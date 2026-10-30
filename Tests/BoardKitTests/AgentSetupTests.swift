import XCTest
@testable import BoardKit
@testable import BoardUI

private actor SetupCapture { var requests: [CodexHandoffRequest] = []; func append(_ r: CodexHandoffRequest) { requests.append(r) } }
private struct SetupTransport: CodexHandoffTransport {
    let capture: SetupCapture
    func events(for request: CodexHandoffRequest) -> AsyncThrowingStream<CodexHandoffEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await capture.append(request)
                continuation.yield(.accepted(threadID: "01a1874a-0cee-7c73-914c-b996f00225ca", submissionID: request.requestID))
                continuation.finish()
            }
        }
    }
}
private struct CaptureFailureTransport: CodexHandoffTransport {
    let capture: SetupCapture
    func events(for request: CodexHandoffRequest) -> AsyncThrowingStream<CodexHandoffEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await capture.append(request)
                continuation.yield(.prepared(threadID: "01a1874a-0cee-7c73-914c-b996f00225ca"))
                continuation.finish(throwing: CodexChatFailure(message: "模拟投递失败"))
            }
        }
    }
}
final class AgentSetupTests: XCTestCase {
    @MainActor func testNamingCreatesRealSetupRequestAndRequiresReturnedConfiguration() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let capture = SetupCapture()
        let store = AgentWorkspaceStore(directory: folder, transport: SetupTransport(capture: capture), openCodex: { _, _ in })
        let count = store.agents.count
        XCTAssertThrowsError(try store.createAgent(name: "  \n"))
        XCTAssertEqual(store.agents.count, count)
        try store.createAgent(name: "  研究助手  ")
        let id = store.selectedID
        await store.runningTasks[id]?.value
        let requests = await capture.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].directory, store.defaultAgentDirectory(id))
        XCTAssertTrue(requests[0].prompt.contains("execution.md"))
        XCTAssertTrue(store.setupAgentIDs.contains(id), "Queue receipt is not completion")
        XCTAssertThrowsError(try store.createAgent(name: "研究助手"))
        let restored = AgentWorkspaceStore(directory: folder, transport: SetupTransport(capture: capture), openCodex: { _, _ in })
        XCTAssertTrue(restored.setupAgentIDs.contains(id))
        let configDirectory = try restored.configurationDirectory(try XCTUnwrap(restored.selected))
        let configFile = configDirectory.appendingPathComponent("agent.json")
        let originalConfig = try Data(contentsOf: configFile)
        restored.finishAgentSetup()
        XCTAssertTrue(restored.setupAgentIDs.contains(id))
        XCTAssertEqual(try Data(contentsOf: configFile), originalConfig)
        var profile = try XCTUnwrap(store.selected)
        profile.systemPrompt = "验证后执行研究任务"; profile.skills = ["research"]
        let config = try store.prepareConversationWorkspace(profile)
        try JSONEncoder().encode(profile).write(to: config.appendingPathComponent("agent.json"))
        try "执行入口与人工验收".write(to: config.appendingPathComponent("execution.md"), atomically: true, encoding: .utf8)
        restored.finishAgentSetup()
        XCTAssertFalse(restored.setupAgentIDs.contains(id))
        XCTAssertEqual(restored.selected?.skills, ["research"])
        XCTAssertEqual(restored.selected?.systemPrompt, profile.systemPrompt)
        restored.updateDraft { $0.instruction = "开始研究" }
        restored.handoff(board: BoardData())
        await restored.runningTasks[id]?.value
        let executionRequests = await capture.requests
        XCTAssertEqual(executionRequests.count, 2)
        XCTAssertTrue(try XCTUnwrap(executionRequests.last).instructions.contains(profile.systemPrompt))
        XCTAssertTrue(try XCTUnwrap(executionRequests.last).instructions.contains("research"))
    }
    @MainActor func testMissingSelectedProjectIsNotRecreatedDuringHandoff() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let capture = SetupCapture()
        let store = AgentWorkspaceStore(directory: folder, transport: SetupTransport(capture: capture), openCodex: { _, _ in })
        let missing = folder.appendingPathComponent("deleted-project")
        store.workspacePaths[store.selectedID] = missing.path
        store.updateDraft { $0.instruction = "请验证" }
        store.handoff(board: BoardData())
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertEqual(store.draft.instruction, "请验证")
        guard case .failed = store.deliveryState else { return XCTFail("Missing folder must fail before writes") }
        let requests = await capture.requests
        XCTAssertTrue(requests.isEmpty)
    }
    @MainActor func testInvalidBookmarkFailsBeforeWritingSelectedProject() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let capture = SetupCapture()
        let store = AgentWorkspaceStore(directory: folder, transport: SetupTransport(capture: capture), openCodex: { _, _ in })
        let project = folder.appendingPathComponent("selected-project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        store.workspacePaths[store.selectedID] = project.path
        store.workspaceBookmarks[store.selectedID] = Data("invalid bookmark".utf8)
        store.updateDraft { $0.instruction = "保留这段输入" }
        store.handoff(board: BoardData())
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent(".todoboard").path))
        XCTAssertEqual(store.draft.instruction, "保留这段输入")
        guard case .failed = store.deliveryState else { return XCTFail("Invalid access must stop handoff before writes") }
        let requests = await capture.requests
        XCTAssertTrue(requests.isEmpty)
    }
    @MainActor func testSelectedWorkspaceBookmarkSurvivesRestartAndHandoff() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = folder.appendingPathComponent("selected-project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let store = AgentWorkspaceStore(directory: folder)
        store.workspacePaths[store.selectedID] = project.path
        store.workspaceBookmarks[store.selectedID] = try project.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        store.updateDraft { $0.instruction = "验证所选工作区" }
        let capture = SetupCapture()
        let restored = AgentWorkspaceStore(directory: folder, transport: SetupTransport(capture: capture), openCodex: { _, _ in })
        restored.handoff(board: BoardData())
        await restored.runningTasks[restored.selectedID]?.value
        let requests = await capture.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.directory.resolvingSymlinksInPath().path, project.resolvingSymlinksInPath().path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.appendingPathComponent(".todoboard").path))
        XCTAssertEqual(restored.workspaceNames[restored.selectedID], "selected-project")
        guard case .sent = restored.deliveryState else { return XCTFail("Expect delivery after bookmark resolution") }
    }
    @MainActor func testWorkspaceChangeDoesNotRetryIntoPreviousThread() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let capture = SetupCapture()
        let store = AgentWorkspaceStore(directory: folder, transport: CaptureFailureTransport(capture: capture), openCodex: { _, _ in })
        store.updateDraft { $0.instruction = "相同任务" }
        store.handoff(board: BoardData()); await store.runningTasks[store.selectedID]?.value
        let next = folder.appendingPathComponent("other-project")
        try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
        store.workspacePaths[store.selectedID] = next.path
        store.handoff(board: BoardData()); await store.runningTasks[store.selectedID]?.value
        let requests = await capture.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].directory.path, next.path)
        XCTAssertNil(requests[1].threadID)
        XCTAssertNotEqual(requests[0].requestID, requests[1].requestID)
        XCTAssertEqual(store.draft.instruction, "相同任务")
    }
    @MainActor func testImplicitDirectoriesAreSeparateAndPersistedWorkspaceIsRespected() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AgentWorkspaceStore(directory: folder)
        let first = try store.authorizedWorkspaceURL()
        XCTAssertNotEqual(first, folder)
        store.select(store.agents[1].id)
        XCTAssertNotEqual(first, try store.authorizedWorkspaceURL())
        store.workspacePaths[store.selectedID] = "/tmp"
        store.save()
        let restored = AgentWorkspaceStore(directory: folder)
        XCTAssertEqual(try restored.authorizedWorkspaceURL().path, "/tmp")
    }
}
