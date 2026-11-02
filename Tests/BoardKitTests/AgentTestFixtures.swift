import Foundation
@testable import BoardKit
@testable import BoardUI

// Test rosters are explicit; production never creates demonstration agents.
@MainActor private func seedFixtures(_ store: AgentWorkspaceStore) -> AgentWorkspaceStore {
    if store.agents.isEmpty, store.error == nil {
        for option in AgentAvatarOption.allCases {
            try! store.upsert(AgentProfile(name: option.rawValue.capitalized, background: "测试角色", avatar: option.rawValue))
        }
        store.select(store.agents[0].id)
    }
    return store
}
@MainActor func fixtureWorkspace(directory: URL) -> AgentWorkspaceStore {
    seedFixtures(AgentWorkspaceStore(directory: directory))
}
@MainActor func fixtureWorkspace(directory: URL, transport: any CodexHandoffTransport,
    openCodex: @escaping @MainActor (String, Bool) async throws -> Void) -> AgentWorkspaceStore {
    seedFixtures(AgentWorkspaceStore(directory: directory, transport: transport, openCodex: openCodex))
}
