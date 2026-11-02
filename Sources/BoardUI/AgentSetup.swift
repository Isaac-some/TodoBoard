import BoardKit
import Foundation

extension AgentWorkspaceStore {
    func defaultAgentDirectory(_ id: String) -> URL {
        let key = Data(id.utf8).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("agent-projects/\(key)", isDirectory: true)
    }

    var suggestedAvatar: AgentAvatarOption {
        AgentAvatarOption.allCases.first { option in !agents.contains { $0.avatar == option.rawValue } } ?? .yuki
    }

    func createAgent(name: String, avatar: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AgentProtocolError.invalid("请先给智能体取名") }
        guard !agents.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            throw AgentProtocolError.invalid("已有同名智能体，请换个名字")
        }
        // Fail before creating a placeholder if the required interview resources are missing.
        _ = try AgentSetupInterview.instructions()
        let agent = AgentProfile(name: name, background: "等待在 Codex 中访谈确定职能", avatar: avatar)
        try agent.validate()
        let project = defaultAgentDirectory(agent.id)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        _ = try prepareConversationWorkspace(agent)
        setupAgentIDs.insert(agent.id)
        try upsert(agent)
        // Existing durable transport handles retries and opening the Codex chat.
        handoff(board: BoardData())
    }

    func setupPrompt() throws -> String {
        guard let agent = selected else { return "" }
        let folder = try configurationDirectory(agent)
        return """
        请与我一起创建名为「\(agent.name)」的个人智能体。这是配置请求，不是执行待办。
        独立工作区：\(selectedWorkspacePath)
        请先运行 /grill-me（即 /grilling）访谈，完整遵守创建指令中的两份技能原文。
        每次只问一个问题，给出推荐答案并等待我的回答；能查到的事实自己查，关键决定交给我。
        逐步确定工作职能与边界，形成职能说明，直到我明确确认理解一致后才开始配置、实现与试跑。
        不得把本次点击创建、取名或选头像当成职能确认；确认前不要执行待办。
        配置目录：\(folder.path)
        我确认后，在该目录保存 interview.md，包含已确认的职能说明、我的确认原话及对话位置。
        然后实现相应执行链路并验证；不要仅创建一个名字或声称能力引用已经加载。
        配置保存至：\(folder.appendingPathComponent("agent.json").path)
        保留已有 JSON 字段、version=1、id=\(agent.id)、name=\(agent.name)、avatar=\(agent.avatar)，更新 background、systemPrompt、skills、toolGroups、mcpServers、knowledge 等字段。
        将角色指令保存至同目录 AGENTS.md；把执行入口、依赖、验证结果、人工介入点写入 execution.md。
        TodoBoard 管理候选与分发；独立后台负责资料留存、知识库与执行回传。执行入口由 Agent 适配器配置。
        执行完成后先请我验收，再由我回 TodoBoard 点击「检查配置」。不要自动修改正式待办状态。
        """
    }

    func finishAgentSetup() {
        do {
            guard let agent = selected, setupAgentIDs.contains(agent.id) else { return }
            let workingDirectory = try authorizedWorkspaceURL()
            defer { workingDirectory.stopAccessingSecurityScopedResource() }
            let folder = try configurationDirectory(agent)
            let profile = try JSONDecoder().decode(AgentProfile.self, from: Data(contentsOf: folder.appendingPathComponent("agent.json")))
            try profile.validate()
            let execution = try String(contentsOf: folder.appendingPathComponent("execution.md"), encoding: .utf8)
            let interviewFile = folder.appendingPathComponent("interview.md")
            guard FileManager.default.fileExists(atPath: interviewFile.path),
                  let interview = try? String(contentsOf: interviewFile, encoding: .utf8),
                  !interview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgentProtocolError.invalid("缺少访谈职能说明，请先在 Codex 完成访谈、确认职能并保存 interview.md")
            }
            guard profile.id == agent.id, profile.name == agent.name, profile.avatar == agent.avatar,
                  !profile.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !execution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgentProtocolError.invalid("配置尚未完成，请先在 Codex 中补齐角色指令和执行说明")
            }
            try upsert(profile)
            setupAgentIDs.remove(agent.id); save()
        } catch { self.error = "配置检查未通过：\(error.localizedDescription)" }
    }
}
