import XCTest
@testable import BoardKit
@testable import BoardUI

final class AgentWorkspaceTests: XCTestCase {
    @MainActor func testDraftsSurviveReconstructionAndStayWithTheirAgent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = AgentWorkspaceStore(directory: folder)
        let first = workspace.selectedID
        workspace.updateDraft { $0.taskIDs = ["t-alpha"]; $0.instruction = "保留这段说明"; $0.ovHints["t-alpha"] = "历史决策" }
        workspace.select(workspace.agents[1].id)
        XCTAssertTrue(workspace.draft.taskIDs.isEmpty)
        let restored = AgentWorkspaceStore(directory: folder)
        restored.select(first)
        XCTAssertEqual(restored.draft.taskIDs, ["t-alpha"])
        XCTAssertEqual(restored.draft.instruction, "保留这段说明")
        XCTAssertEqual(restored.draft.ovHints["t-alpha"], "历史决策")
    }
    @MainActor func testVisibleMessageContainsFullTaskContext() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = AgentWorkspaceStore(directory: folder)
        let task = BoardTask(title: "测试任务", priority: .mid, status: .doing, notes: String(repeating: "长备注", count: 500))
        workspace.updateDraft { $0.taskIDs = [task.id, "deleted"]; $0.ovHints[task.id] = "OV 线索"; $0.instruction = "请给方案" }
        let text = workspace.composeMessage(board: BoardData(tasks: [task]))
        XCTAssertTrue(text.contains(task.notes))
        XCTAssertTrue(text.contains(task.createdAt))
        XCTAssertTrue(text.contains("相似会议、事件"))
        XCTAssertTrue(text.contains("OV 线索"))
        XCTAssertTrue(text.hasSuffix("请给方案"))
        XCTAssertFalse(text.contains("deleted"))
        XCTAssertFalse(text.contains("System prompt"))
    }
    @MainActor func testImportRejectsUnknownVersionAndUpdatesSameIdentity() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = AgentWorkspaceStore(directory: folder)
        var profile = workspace.agents[0]
        profile.version = 2
        XCTAssertThrowsError(try workspace.upsert(profile))
        profile.version = 1; profile.name = "改名"
        try workspace.upsert(profile)
        XCTAssertEqual(workspace.agents.count, 4)
        XCTAssertEqual(workspace.selected?.name, "改名")
    }
    @MainActor func testCorruptWorkspaceIsPreserved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("agent-workspace.json")
        try "broken".write(to: file, atomically: true, encoding: .utf8)
        let workspace = AgentWorkspaceStore(directory: folder)
        XCTAssertNotNil(workspace.error)
        workspace.updateDraft { $0.instruction = "不可覆盖坏文件" }
        XCTAssertEqual(try String(contentsOf: file), "broken")
    }
}
