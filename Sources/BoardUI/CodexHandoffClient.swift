import Foundation

struct CodexHandoffRequest: Sendable {
    let directory: URL
    let title: String
    let instructions: String
    let prompt: String
    let requestID: String
    let threadID: String?
    var agentID: String? = nil
    var taskIDs: [String] = []
}

enum CodexHandoffEvent: Sendable, Equatable {
    case prepared(threadID: String)
    case accepted(threadID: String, submissionID: String)
}

protocol CodexHandoffTransport: Sendable {
    func events(for request: CodexHandoffRequest) -> AsyncThrowingStream<CodexHandoffEvent, Error>
}

/// Creates a durable conversation, then deposits the message without loading it.
/// Codex desktop owns execution after receiving the wake deep link.
struct CodexHandoffClient: CodexHandoffTransport {
    var executableOverride: URL?

    func events(for request: CodexHandoffRequest) -> AsyncThrowingStream<CodexHandoffEvent, Error> {
        let worker = HandoffWorker()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { reason in
                if case .cancelled = reason { worker.cancel() }
            }
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard let executable = executableOverride ?? CodexInstallation.locateExecutable() else {
                        throw CodexChatFailure(message: "未找到 Codex，请先安装并登录。")
                    }
                    try worker.deliver(request, executable: executable, continuation: continuation)
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }
}

private final class HandoffWorker: @unchecked Sendable {
    private let lock = NSLock()
    private var current: HandoffRPC?
    private var cancelled = false

    func cancel() {
        lock.lock(); cancelled = true; let rpc = current; lock.unlock()
        rpc?.stop()
    }

    private func session<T>(executable: URL, directory: URL, body: (HandoffRPC) throws -> T) throws -> T {
        let rpc = HandoffRPC()
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        current = rpc
        lock.unlock()
        defer {
            rpc.stop()
            lock.lock(); current = nil; lock.unlock()
        }
        try rpc.start(executable: executable, directory: directory)
        return try body(rpc)
    }

    func deliver(_ request: CodexHandoffRequest, executable: URL,
                 continuation: AsyncThrowingStream<CodexHandoffEvent, Error>.Continuation) throws {
        let threadID: String
        if let existing = request.threadID { threadID = existing }
        else {
            // Separate lifetimes are essential. queue/add on a loaded thread may
            // start a turn in this temporary server and interrupt it at shutdown.
            threadID = try session(executable: executable, directory: request.directory) { rpc in
                let result = try rpc.call("thread/start", [
                    "cwd": request.directory.path, "ephemeral": false,
                    "approvalPolicy": "on-request", "sandbox": "workspace-write",
                    "developerInstructions": request.instructions
                ])
                guard let thread = result["thread"] as? [String: Any], let id = thread["id"] as? String,
                      UUID(uuidString: id) != nil else { throw HandoffRPC.invalidResponse() }
                continuation.yield(.prepared(threadID: id))
                _ = try rpc.call("thread/name/set", ["threadId": id, "name": request.title])
                return id
            }
        }
        let submissionID = try session(executable: executable, directory: request.directory) { rpc in
            if request.threadID != nil {
                // clientUserMessageId is correlation metadata, not a server-side
                // uniqueness constraint. Check both queued and consumed input.
                var cursor: String?
                repeat {
                    var params: [String: Any] = ["threadId": threadID, "limit": 100]
                    if let cursor { params["cursor"] = cursor }
                    let page = try rpc.call("thread/queue/list", params)
                    for item in page["data"] as? [[String: Any]] ?? [] {
                        if item["clientUserMessageId"] as? String == request.requestID, let id = item["id"] as? String { return id }
                    }
                    cursor = page["nextCursor"] as? String
                } while cursor != nil
                let history = try rpc.call("thread/read", ["threadId": threadID, "includeTurns": true])
                let thread = history["thread"] as? [String: Any]
                for turn in thread?["turns"] as? [[String: Any]] ?? [] {
                    for item in turn["items"] as? [[String: Any]] ?? [] {
                        if item["type"] as? String == "userMessage", item["clientId"] as? String == request.requestID,
                           let id = item["id"] as? String { return id }
                    }
                }
            }
            // Never resume/start the thread here. Disk reads do not load it.
            let result = try rpc.call("thread/queue/add", [
                "threadId": threadID, "clientUserMessageId": request.requestID,
                "input": [["type": "text", "text": request.prompt]]
            ])
            guard let queued = result["queuedSubmission"] as? [String: Any],
                  let id = queued["id"] as? String,
                  queued["clientUserMessageId"] as? String == request.requestID else {
                throw HandoffRPC.invalidResponse()
            }
            return id
        }
        continuation.yield(.accepted(threadID: threadID, submissionID: submissionID))
    }
}

private final class HandoffRPC: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private var buffer = Data()
    private var nextID = 0
    private let lock = NSLock()
    private var stopped = false
    private var timeout: DispatchWorkItem?

    static func invalidResponse() -> CodexChatFailure { CodexChatFailure(message: "Codex 没有返回投递回执，输入已保留。") }

    func start(executable: URL, directory: URL) throws {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { throw CancellationError() }
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.currentDirectoryURL = directory
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", environment["PATH"] ?? ""].joined(separator: ":")
        process.environment = environment
        try process.run()
        // This is a local connection timeout, independent of model execution.
        let deadline = DispatchWorkItem { [weak self] in self?.stop() }
        timeout = deadline
        DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: deadline)
        // Do not keep the startup lock while waiting for a response.
        lock.unlock()
        defer { lock.lock() }
        _ = try call("initialize", ["clientInfo": ["name": "todoboard", "version": "1.3.0"],
                                     "capabilities": ["experimentalApi": true]])
        try write(["method": "initialized"])
    }

    func call(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        nextID += 1; let id = nextID
        try write(["id": id, "method": method, "params": params])
        while true {
            let object = try read()
            guard object["id"] as? Int == id else { continue }
            if let error = object["error"] as? [String: Any] {
                throw CodexChatFailure(message: "投递失败：" + (error["message"] as? String ?? "Codex 连接异常"))
            }
            guard let result = object["result"] as? [String: Any] else { throw Self.invalidResponse() }
            return result
        }
    }

    private func write(_ value: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: value); data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func read() throws -> [String: Any] {
        while true {
            if let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                guard let result = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw Self.invalidResponse() }
                return result
            }
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { throw CodexChatFailure(message: "Codex 连接已断开，输入已保留。") }
            buffer.append(chunk)
            guard buffer.count <= 16 * 1024 * 1024 else { throw Self.invalidResponse() }
        }
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return }
        stopped = true; timeout?.cancel()
        try? input.fileHandleForWriting.close()
        // There is no model turn in either temporary server. Wait for its full
        // shutdown before queueing, so the next process cannot auto-dispatch it.
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? output.fileHandleForReading.close()
    }
}
