import AppKit
import BoardKit
import SwiftUI

struct AgentDraft: Codable {
    var taskIDs: [String] = []
    var instruction = ""
    var ovHints: [String: String] = [:]
}
struct CodexWorkspace: Identifiable, Hashable {
    let path: String
    let name: String
    var id: String { path }
}
private struct AgentWorkspaceData: Codable {
    var agents: [AgentProfile]
    var selectedID: String
    var drafts: [String: AgentDraft] = [:]
    var workspacePaths: [String: String] = [:]
    var workspaceBookmarks: [String: Data] = [:]
    var setupAgentIDs: Set<String> = []
    private enum CodingKeys: String, CodingKey { case agents, selectedID, drafts, workspacePaths, workspaceBookmarks, setupAgentIDs }
    init(agents: [AgentProfile], selectedID: String, drafts: [String: AgentDraft],
         workspacePaths: [String: String], workspaceBookmarks: [String: Data], setupAgentIDs: Set<String>) {
        self.agents = agents; self.selectedID = selectedID; self.drafts = drafts
        self.workspacePaths = workspacePaths; self.workspaceBookmarks = workspaceBookmarks; self.setupAgentIDs = setupAgentIDs
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        agents = try values.decode([AgentProfile].self, forKey: .agents)
        selectedID = try values.decode(String.self, forKey: .selectedID)
        drafts = try values.decodeIfPresent([String: AgentDraft].self, forKey: .drafts) ?? [:]
        workspacePaths = try values.decodeIfPresent([String: String].self, forKey: .workspacePaths) ?? [:]
        setupAgentIDs = try values.decodeIfPresent(Set<String>.self, forKey: .setupAgentIDs) ?? []
        workspaceBookmarks = try values.decodeIfPresent([String: Data].self, forKey: .workspaceBookmarks) ?? [:]
    }
}

@MainActor
public final class AgentWorkspaceStore: ObservableObject {
    @Published var agents: [AgentProfile] = []
    @Published var selectedID = ""
    @Published var drafts: [String: AgentDraft] = [:]
    @Published var workspacePaths: [String: String] = [:]
    @Published var workspaceNames: [String: String] = [:]
    @Published var workspaceBookmarks: [String: Data] = [:]
    @Published var setupAgentIDs: Set<String> = []
    @Published var error: String?
    @Published var runningAgents: Set<String> = []
    @Published var deliveryStates: [String: AgentDeliveryState] = [:]
    var runningTasks: [String: Task<Void, Never>] = [:]
    var pendingDeliveries: [String: PendingDelivery] = [:]
    var deliveries: [DeliveryReceipt] = []
    let transport: any CodexHandoffTransport
    let openCodex: @MainActor (String, Bool) async throws -> Void
    let directory: URL
    var deliveryStorageAvailable = true
    private var canSave = true
    private var file: URL { directory.appendingPathComponent("agent-workspace.json") }
    var selected: AgentProfile? { agents.first { $0.id == selectedID } }
    var selectedWorkspacePath: String {
        workspacePaths[selectedID] ?? defaultAgentDirectory(selectedID).path
    }
    var selectedWorkspaceName: String {
        workspaceNames[selectedID] ?? (workspacePaths[selectedID].map { URL(fileURLWithPath: $0).lastPathComponent } ?? "\(selected?.name ?? "智能体") 工作区")
    }
    var draft: AgentDraft { drafts[selectedID] ?? AgentDraft() }
    public convenience init(directory: URL) {
        self.init(directory: directory, transport: RuntimeHandoffClient(dataDirectory: directory))
    }
    init(directory: URL, transport: any CodexHandoffTransport,
         openCodex: @escaping @MainActor (String, Bool) async throws -> Void = CodexDesktop.open) {
        self.transport = transport
        self.openCodex = openCodex
        self.directory = directory
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let data = try JSONDecoder().decode(AgentWorkspaceData.self, from: Data(contentsOf: file))
                for profile in data.agents { try profile.validate() }
                guard !data.agents.isEmpty, Set(data.agents.map(\.id)).count == data.agents.count else {
                    throw AgentProtocolError.invalid("角色列表为空或 ID 重复")
                }
                agents = data.agents; selectedID = data.selectedID; drafts = data.drafts; workspacePaths = data.workspacePaths; workspaceBookmarks = data.workspaceBookmarks; setupAgentIDs = data.setupAgentIDs
                if selected == nil { selectedID = agents[0].id }
            } catch { self.error = "智能体配置读取失败，原文件已保留：\(error.localizedDescription)"; canSave = false }
        }
        if agents.isEmpty {
            agents = [("Yuki", "产品研究与需求梳理", "yuki"), ("Matt", "工程实现与验证", "matt"), ("Sofia", "知识整理与文档", "sofia"), ("Richard", "任务复盘与分析", "richard")].map {
                AgentProfile(name: $0.0, background: $0.1, avatar: $0.2)
            }
            selectedID = agents[0].id
        }
        loadDeliveries()
    }
    func usesDesktop(agentID: String) -> Bool {
        guard let bytes = try? Data(contentsOf: directory.appendingPathComponent("config.json")),
              let config = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return true }
        let agents = config["agents"] as? [String: [String: Any]]
        let fallback = config["defaultAgent"] as? [String: Any]
        return (agents?[agentID]?["adapter"] as? String ?? fallback?["adapter"] as? String ?? "codex-gui") == "codex-gui"
    }
    public func cancelPendingDeliveries() {
        for task in runningTasks.values { task.cancel() }
    }
    func select(_ id: String) { selectedID = id; save() }
    func updateDraft(_ change: (inout AgentDraft) -> Void) {
        var value = draft; change(&value); drafts[selectedID] = value; save()
    }
    func upsert(_ profile: AgentProfile) throws {
        try profile.validate()
        if let i = agents.firstIndex(where: { $0.id == profile.id }) { agents[i] = profile }
        else { agents.append(profile) }
        selectedID = profile.id; save()
    }
    func save() {
        guard canSave else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(AgentWorkspaceData(agents: agents, selectedID: selectedID, drafts: drafts,
                workspacePaths: workspacePaths, workspaceBookmarks: workspaceBookmarks, setupAgentIDs: setupAgentIDs)).write(to: file, options: .atomic)
        } catch { self.error = "保存智能体工作区失败：\(error.localizedDescription)" }
    }
    func packet(board: BoardData) -> AgentWorkPacket? {
        guard let selected else { return nil }
        return AgentWorkPacket(agent: selected, tasks: draft.taskIDs.compactMap { id in
            board.task(withID: id).map { AgentTaskContext(task: $0, ovHints: draft.ovHints[id] ?? "") }
        }, instruction: draft.instruction)
    }
    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "选择 Codex 工作区"
        panel.message = "选择 Agent 要使用的项目文件夹"
        panel.prompt = "使用此工作区"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: selectedWorkspacePath, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            workspacePaths[selectedID] = url.path
            workspaceNames[selectedID] = url.lastPathComponent
            workspaceBookmarks[selectedID] = bookmark
            save()
        } catch { self.error = "无法保存工作区授权：\(error.localizedDescription)" }
    }
    func authorizedWorkspaceURL() throws -> URL {
        if let bookmark = workspaceBookmarks[selectedID] {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard url.startAccessingSecurityScopedResource() else {
                throw CodexChatFailure(message: "macOS 未授予所选工作区访问权限，请重新选择。")
            }
            do {
                if stale {
                    workspaceBookmarks[selectedID] = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                }
                let pathChanged = workspacePaths[selectedID] != url.path
                workspacePaths[selectedID] = url.path
                workspaceNames[selectedID] = url.lastPathComponent
                if stale || pathChanged { save() }
                return url
            } catch {
                url.stopAccessingSecurityScopedResource()
                throw error
            }
        }
        let url = URL(fileURLWithPath: selectedWorkspacePath, isDirectory: true)
        if workspacePaths[selectedID] == nil {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
}
