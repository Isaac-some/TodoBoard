import XCTest
@testable import BoardKit
@testable import BoardUI

private struct MockHandoff: CodexHandoffTransport {
    var fail = false
    var omitReceipt = false
    func events(for request: CodexHandoffRequest) -> AsyncThrowingStream<CodexHandoffEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.prepared(threadID: "01a1874a-0cee-7c73-914c-b996f00225ca"))
            if fail { continuation.finish(throwing: CodexChatFailure(message: "模拟连接失败")); return }
            if !omitReceipt { continuation.yield(.accepted(threadID: "01a1874a-0cee-7c73-914c-b996f00225ca", submissionID: request.requestID)) }
            continuation.finish()
        }
    }
}

final class CodexHandoffTests: XCTestCase {
    @MainActor func testAcceptedHandoffClearsOnlySentDraftAndPersistsReceipt() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var opens: [Bool] = []
        let workspace = AgentWorkspaceStore(directory: folder, transport: MockHandoff(), openCodex: { _, navigate in opens.append(navigate) })
        let id = workspace.selectedID
        workspace.updateDraft { $0.instruction = "请交给 Codex" }
        workspace.handoff(board: BoardData())
        await workspace.runningTasks[id]?.value
        XCTAssertEqual(opens, [false, true])
        XCTAssertFalse(workspace.isSending)
        XCTAssertEqual(workspace.draft.instruction, "")
        XCTAssertEqual(workspace.deliveries.count, 1)
        XCTAssertTrue(workspace.pendingDeliveries.isEmpty)
        guard case .sent = workspace.deliveryState else { return XCTFail("Require a durable receipt") }
        let restored = AgentWorkspaceStore(directory: folder)
        XCTAssertEqual(restored.deliveries, workspace.deliveries)
        XCTAssertTrue(restored.pendingDeliveries.isEmpty)
        let role = try restored.prepareConversationWorkspace(try XCTUnwrap(restored.selected))
        try "custom role".write(to: role.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        _ = try restored.prepareConversationWorkspace(try XCTUnwrap(restored.selected))
        XCTAssertEqual(try String(contentsOf: role.appendingPathComponent("AGENTS.md")), "custom role")
    }

    @MainActor func testFailuresAndMissingReceiptPreserveInputAndRetryIdentity() async throws {
        for transport in [MockHandoff(fail: true), MockHandoff(omitReceipt: true)] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let workspace = AgentWorkspaceStore(directory: folder, transport: transport, openCodex: { _, _ in XCTFail("Do not open on failed delivery") })
            workspace.updateDraft { $0.instruction = "保留输入" }
            workspace.handoff(board: BoardData())
            await workspace.runningTasks[workspace.selectedID]?.value
            XCTAssertEqual(workspace.draft.instruction, "保留输入")
            XCTAssertTrue(workspace.deliveries.isEmpty)
            let pending = try XCTUnwrap(workspace.pendingDeliveries[workspace.selectedID])
            guard case .failed = workspace.deliveryState else { return XCTFail("No fake success") }
            let restored = AgentWorkspaceStore(directory: folder)
            XCTAssertEqual(restored.pendingDeliveries[restored.selectedID]?.id, pending.id)
            XCTAssertEqual(restored.pendingDeliveries[restored.selectedID]?.threadID, pending.threadID)
            workspace.handoff(board: BoardData())
            await workspace.runningTasks[workspace.selectedID]?.value
            XCTAssertEqual(workspace.pendingDeliveries[workspace.selectedID]?.id, pending.id)
        }
    }

    @MainActor func testEditsAndAgentSwitchDuringHandoffArePreserved() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = AgentWorkspaceStore(directory: folder, transport: MockHandoff(), openCodex: { _, _ in })
        let first = workspace.selectedID
        workspace.updateDraft { $0.instruction = "已经发送的" }
        workspace.handoff(board: BoardData())
        workspace.updateDraft { $0.instruction = "下一条草稿" }
        workspace.select(workspace.agents[1].id)
        workspace.updateDraft { $0.instruction = "另一个角色的草稿" }
        await workspace.runningTasks[first]?.value
        XCTAssertEqual(workspace.draft.instruction, "另一个角色的草稿")
        workspace.select(first)
        XCTAssertEqual(workspace.draft.instruction, "下一条草稿")
    }

    @MainActor func testOpenFailureKeepsReceiptAndDoesNotAskToResend() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = AgentWorkspaceStore(directory: folder, transport: MockHandoff(), openCodex: { _, _ in throw CodexChatFailure(message: "打不开") })
        workspace.updateDraft { $0.instruction = "任务" }
        workspace.handoff(board: BoardData())
        await workspace.runningTasks[workspace.selectedID]?.value
        XCTAssertEqual(workspace.deliveries.count, 1)
        XCTAssertEqual(workspace.draft.instruction, "")
        guard case .needsOpening = workspace.deliveryState else { return XCTFail("Distinguish delivery from opening") }
    }

    func testQueueUsesSeparateUnloadedServerAndFullUnicodeStdin() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let executable = folder.appendingPathComponent("fake-codex")
        let script = """
        #!/usr/bin/python3
        import sys,json,os
        from pathlib import Path
        loaded=False
        for line in sys.stdin:
            r=json.loads(line);m=r['method'];v=r.get('params',{});result={}
            if m=='initialized':continue
            if m=='thread/start':
                loaded=True
                Path('creator.txt').write_text(str(os.getpid()))
                result={'thread':{'id':'01a1874a-0cee-7c73-914c-b996f00225ca'}}
            if m=='thread/queue/add':
                if loaded:sys.exit(9)
                Path('queued.txt').write_text(v['input'][0]['text'])
                result={'queuedSubmission':{'id':'queue-id','clientUserMessageId':v['clientUserMessageId']}}
            raw=(json.dumps({'id':r['id'],'result':result},ensure_ascii=False)+'\\n').encode()
            for byte in raw:sys.stdout.buffer.write(bytes([byte]));sys.stdout.buffer.flush()
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let text = String(repeating: "长任务上下文中文 `literal` $(literal)\n", count: 6000)
        let request = CodexHandoffRequest(directory: folder, title: "Example Agent", instructions: "Provide a factual result", prompt: text, requestID: "request-id", threadID: nil)
        var events: [CodexHandoffEvent] = []
        for try await event in CodexHandoffClient(executableOverride: executable).events(for: request) { events.append(event) }
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.last, .accepted(threadID: "01a1874a-0cee-7c73-914c-b996f00225ca", submissionID: "queue-id"))
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("queued.txt")), text)
    }

    func testRetryRecognizesQueuedOrConsumedMessageWithoutAddingItAgain() async throws {
        for consumed in [false, true] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let executable = folder.appendingPathComponent("fake-codex")
            let script = """
            #!/usr/bin/python3
            import sys,json
            consumed=\(consumed ? "True" : "False")
            for line in sys.stdin:
                r=json.loads(line);m=r['method'];result={}
                if m=='initialized':continue
                if m in ['thread/start','thread/resume','thread/queue/add']:sys.exit(9)
                if m=='thread/queue/list':
                    result={'data':[] if consumed else [{'id':'existing','clientUserMessageId':'request-id'}]}
                if m=='thread/read':
                    result={'thread':{'turns':[{'items':[{'type':'userMessage','id':'existing','clientId':'request-id'}]}]}}
                print(json.dumps({'id':r['id'],'result':result}),flush=True)
            """
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            let request = CodexHandoffRequest(directory: folder, title: "Example Agent", instructions: "", prompt: "已投递的消息",
                requestID: "request-id", threadID: "01a1874a-0cee-7c73-914c-b996f00225ca")
            var events: [CodexHandoffEvent] = []
            for try await event in CodexHandoffClient(executableOverride: executable).events(for: request) { events.append(event) }
            XCTAssertEqual(events, [.accepted(threadID: request.threadID!, submissionID: "existing")])
        }
    }
}
