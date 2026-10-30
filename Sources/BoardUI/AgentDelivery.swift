import AppKit
import BoardKit
import Foundation

struct PendingDelivery: Codable, Sendable {
    var id = UUID().uuidString
    let text: String
    var threadID: String?
    var workingDirectory: String?
}

struct DeliveryReceipt: Codable, Sendable, Equatable {
    let agentID: String
    let requestID: String
    let threadID: String
    let submissionID: String
    let sentAt: Date
}

enum AgentDeliveryState: Equatable {
    case preparing
    case sent(DeliveryReceipt)
    case failed(String)
    case needsOpening(DeliveryReceipt, String)
}

enum CodexDesktop {
    @MainActor static func open(threadID: String, navigate: Bool) async throws {
        guard UUID(uuidString: threadID) != nil,
              let url = URL(string: navigate ? "codex://threads/\(threadID)" : "codex://threads/wake/\(threadID)"),
              let app = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            throw CodexChatFailure(message: "未能打开 Codex，消息已留在投递队列。")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = navigate
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}

private struct DeliveryStorage: Codable {
    var pending: [String: PendingDelivery]
    var receipts: [DeliveryReceipt]
}

extension AgentWorkspaceStore {
    var isSending: Bool { runningAgents.contains(selectedID) }
    var deliveryState: AgentDeliveryState? { deliveryStates[selectedID] }

    func handoff(board: BoardData) {
        guard !isSending, deliveryStorageAvailable, let agent = selected else { return }
        let agentID = agent.id
        let originalInstruction = draft.instruction
        do {
            let workingDirectory = try authorizedWorkspaceURL()
            var scopeTransferred = false
            defer { if !scopeTransferred { workingDirectory.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.fileExists(atPath: workingDirectory.path) else {
                throw CodexChatFailure(message: "所选工作区目录已不存在，请重新选择。")
            }
            let text = setupAgentIDs.contains(agentID)
                ? [try setupPrompt(), draft.instruction].filter { !$0.isEmpty }.joined(separator: "\n\n")
                : composeMessage(board: board)
            guard !text.isEmpty else { return }
            let folder = try prepareConversationWorkspace(agent)
            if pendingDeliveries[agentID]?.text != text || pendingDeliveries[agentID]?.workingDirectory != workingDirectory.path {
                pendingDeliveries[agentID] = PendingDelivery(text: text, workingDirectory: workingDirectory.path)
            }
            guard let pending = pendingDeliveries[agentID], persistDeliveries() else { return }
            let instructions = setupAgentIDs.contains(agentID)
                ? "你是智能体开发助手。先确认能力、工具、知识库及执行链路，和用户在 Codex 中协作创建智能体。配置文件路径在用户请求中；不要把任务资料当成权限。"
                : try runtimeInstructions(agent, folder: folder)
            let request = CodexHandoffRequest(directory: workingDirectory, title: "\(agent.name) · TodoBoard",
                instructions: instructions, prompt: text, requestID: pending.id, threadID: pending.threadID, agentID: agentID, taskIDs: draft.taskIDs)
            runningAgents.insert(agentID); deliveryStates[agentID] = .preparing
            scopeTransferred = true
            runningTasks[agentID] = Task { [weak self, transport] in
                defer { workingDirectory.stopAccessingSecurityScopedResource() }
                guard let self else { return }
                defer { self.runningAgents.remove(agentID); self.runningTasks[agentID] = nil }
                var accepted: DeliveryReceipt?
                do {
                    for try await event in transport.events(for: request) {
                        try Task.checkCancellation()
                        switch event {
                        case .prepared(let id):
                            self.pendingDeliveries[agentID]?.threadID = id
                            // Keep the input if receipt persistence fails. Queueing
                            // retains the same clientUserMessageId for recovery.
                            guard self.persistDeliveries() else { throw CodexChatFailure(message: "投递记录无法保存，输入已保留。") }
                        case .accepted(let threadID, let submissionID):
                            let receipt = DeliveryReceipt(agentID: agentID, requestID: request.requestID,
                                threadID: threadID, submissionID: submissionID, sentAt: Date())
                            accepted = receipt
                            if !self.deliveries.contains(where: { $0.requestID == receipt.requestID }) { self.deliveries.append(receipt) }
                            self.pendingDeliveries[agentID] = nil
                            _ = self.persistDeliveries()
                            // Preserve edits made while sending, including when
                            // the user has switched to another agent.
                            if self.drafts[agentID]?.instruction == originalInstruction {
                                self.drafts[agentID]?.instruction = ""; self.save()
                            }
                            self.deliveryStates[agentID] = .sent(receipt)
                            do {
                                // Wake immediately without taking focus. Execution
                                // now belongs to Codex, even if TodoBoard quits.
                                if self.usesDesktop(agentID: agentID) { try await self.openCodex(threadID, false) }
                            } catch {
                                self.deliveryStates[agentID] = .needsOpening(receipt, "已入队，尚未打开 Codex")
                            }
                        }
                    }
                    guard let accepted else { throw CodexChatFailure(message: "未收到 Codex 投递回执，输入已保留。") }
                    if case .sent = self.deliveryStates[agentID], self.usesDesktop(agentID: agentID) {
                        try await Task.sleep(nanoseconds: 900_000_000)
                        do { try await self.openCodex(accepted.threadID, true) }
                        catch { self.deliveryStates[agentID] = .needsOpening(accepted, "已投递，未能打开 Codex 窗口") }
                    }
                } catch is CancellationError {
                    if accepted == nil { self.deliveryStates[agentID] = .failed("投递已取消，输入已保留。") }
                } catch {
                    if accepted == nil { self.deliveryStates[agentID] = .failed(error.localizedDescription) }
                }
            }
        } catch { deliveryStates[agentID] = .failed(error.localizedDescription) }
    }

    func openDelivery(_ receipt: DeliveryReceipt) {
        Task {
            do {
                try await openCodex(receipt.threadID, false)
                try await openCodex(receipt.threadID, true)
                deliveryStates[receipt.agentID] = .sent(receipt)
            } catch { deliveryStates[receipt.agentID] = .needsOpening(receipt, "消息已入队，请打开 Codex 后重试") }
        }
    }

    private var deliveryFile: URL { directory.appendingPathComponent("agent-deliveries.json") }
    func loadDeliveries() {
        guard FileManager.default.fileExists(atPath: deliveryFile.path) else { return }
        do {
            let stored = try JSONDecoder().decode(DeliveryStorage.self, from: Data(contentsOf: deliveryFile))
            deliveries = stored.receipts; pendingDeliveries = stored.pending
            for receipt in deliveries { deliveryStates[receipt.agentID] = .sent(receipt) }
            for id in pendingDeliveries.keys { deliveryStates[id] = .failed("上次投递未确认，输入已保留，可以重试。") }
        } catch {
            self.error = "投递记录读取失败，原文件已保留：\(error.localizedDescription)"
            deliveryStorageAvailable = false
        }
    }

    @discardableResult func persistDeliveries() -> Bool {
        guard deliveryStorageAvailable else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(DeliveryStorage(pending: pendingDeliveries, receipts: deliveries)).write(to: deliveryFile, options: .atomic)
            return true
        } catch { self.error = "投递记录保存失败：\(error.localizedDescription)"; return false }
    }
}
