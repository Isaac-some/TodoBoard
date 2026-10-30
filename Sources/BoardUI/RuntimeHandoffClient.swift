import Foundation

/// The app sends a packet. Durable delivery and result tracking belong to the worker.
struct RuntimeHandoffClient: CodexHandoffTransport {
    let dataDirectory: URL
    func events(for request: CodexHandoffRequest) -> AsyncThrowingStream<CodexHandoffEvent, Error> {
        AsyncThrowingStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let install = self.dataDirectory.appendingPathComponent("runtime-install.json")
                    guard let config = try JSONSerialization.jsonObject(with: Data(contentsOf: install)) as? [String: String],
                          let python = config["python"], let modulePath = config["modulePath"] else {
                        throw CodexChatFailure(message: "请先按快速开始安装 TodoBoard 后台（runtime-install.json 缺失）。")
                    }
                    let folder = self.dataDirectory.appendingPathComponent("outbox", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let packet = folder.appendingPathComponent(request.requestID + ".json")
                    let body: [String: Any] = ["version": 1, "requestID": request.requestID, "agentID": request.agentID ?? "",
                        "taskIDs": request.taskIDs, "cwd": request.directory.path, "title": request.title,
                        "instructions": request.instructions, "prompt": request.prompt]
                    try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys]).write(to: packet, options: .atomic)
                    let process = Process(); let output = Pipe(); let error = Pipe()
                    process.executableURL = URL(fileURLWithPath: python)
                    process.arguments = ["-m", "todoboard.cli", "--data-dir", self.dataDirectory.path, "handoff", "--packet-file", packet.path]
                    process.standardOutput = output; process.standardError = error
                    var env = ProcessInfo.processInfo.environment
                    env["PYTHONPATH"] = modulePath
                    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                    process.environment = env
                    try process.run()
                    let result = output.fileHandleForReading.readDataToEndOfFile()
                    let failure = error.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0,
                          let receipt = try? JSONSerialization.jsonObject(with: result) as? [String: Any],
                          let id = receipt["submissionID"] as? String else {
                        throw CodexChatFailure(message: "后台投递未确认，任务已保留。" + (String(data: failure, encoding: .utf8) ?? ""))
                    }
                    let thread = receipt["threadID"] as? String ?? request.requestID
                    continuation.yield(.accepted(threadID: thread, submissionID: id))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }
}
