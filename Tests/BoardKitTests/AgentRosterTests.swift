import XCTest
@testable import BoardKit
@testable import BoardUI

private struct RosterTransport: CodexHandoffTransport {
    func events(for request: CodexHandoffRequest) -> AsyncThrowingStream<CodexHandoffEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: CodexChatFailure(message: "离线测试")) }
    }
}

final class AgentRosterTests: XCTestCase {
    @MainActor func testEmptyRosterStaysEmptyAcrossRestart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AgentWorkspaceStore(directory: folder)
        XCTAssertTrue(store.agents.isEmpty)
        XCTAssertNil(store.selected)
        store.select("removed-agent")
        store.updateDraft { $0.instruction = "无角色时不能创建草稿" }
        XCTAssertTrue(store.selectedID.isEmpty)
        XCTAssertTrue(store.drafts.isEmpty)
        store.save()
        let restored = AgentWorkspaceStore(directory: folder)
        XCTAssertNil(restored.error)
        XCTAssertTrue(restored.agents.isEmpty)
        XCTAssertNil(restored.selected)
    }

    @MainActor func testOnlySavedRealAgentReturnsWithItsConfiguration() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AgentWorkspaceStore(directory: folder)
        var profile = AgentProfile(name: "Writeman", background: "真实角色", avatar: "matt")
        profile.systemPrompt = "保留完整配置"
        profile.skills = ["writing"]
        try store.upsert(profile)
        store.updateDraft { $0.instruction = "待发送草稿" }
        let restored = AgentWorkspaceStore(directory: folder)
        XCTAssertEqual(restored.agents.count, 1)
        XCTAssertEqual(restored.agents[0], profile)
        XCTAssertEqual(restored.selectedID, profile.id)
        XCTAssertEqual(restored.draft.instruction, "待发送草稿")
        XCTAssertEqual(restored.suggestedAvatar, .yuki)
    }

    @MainActor func testEveryPortraitCanBeChosenAndSurvivesSetupAndRestart() async throws {
        XCTAssertEqual(AgentAvatarOption.allCases.count, 4)
        for option in AgentAvatarOption.allCases {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let store = AgentWorkspaceStore(directory: folder, transport: RosterTransport(), openCodex: { _, _ in XCTFail("离线测试不能打开 Codex") })
            try store.createAgent(name: "  中文名字 🖋  ", avatar: option.rawValue)
            await store.runningTasks[store.selectedID]?.value
            let profile = try XCTUnwrap(store.selected)
            XCTAssertEqual(profile.name, "中文名字 🖋")
            XCTAssertEqual(profile.avatar, option.rawValue)
            let config = try store.configurationDirectory(profile)
            var returned = try JSONDecoder().decode(AgentProfile.self, from: Data(contentsOf: config.appendingPathComponent("agent.json")))
            XCTAssertEqual(returned.avatar, option.rawValue)
            returned.systemPrompt = "实际能力配置"
            try JSONEncoder().encode(returned).write(to: config.appendingPathComponent("agent.json"))
            try "实际执行入口".write(to: config.appendingPathComponent("execution.md"), atomically: true, encoding: .utf8)
            try "职能确认记录".write(to: config.appendingPathComponent("interview.md"), atomically: true, encoding: .utf8)
            store.finishAgentSetup()
            XCTAssertFalse(store.setupAgentIDs.contains(profile.id))
            let restored = AgentWorkspaceStore(directory: folder)
            XCTAssertEqual(restored.agents.count, 1)
            XCTAssertEqual(restored.selected?.avatar, option.rawValue)
            XCTAssertEqual(restored.selected?.systemPrompt, "实际能力配置")
        }
    }

    @MainActor func testInvalidPortraitDoesNotCreateFilesOrAgent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AgentWorkspaceStore(directory: folder)
        XCTAssertThrowsError(try store.createAgent(name: "测试角色", avatar: "missing-avatar"))
        XCTAssertTrue(store.agents.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
}
