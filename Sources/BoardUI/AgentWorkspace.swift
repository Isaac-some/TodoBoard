import AppKit
import BoardKit
import SwiftUI
import UniformTypeIdentifiers

struct AgentWorkspaceView: View {
    @EnvironmentObject private var store: BoardStore
    @EnvironmentObject private var workspace: AgentWorkspaceStore
    @Binding var dragging: String?
    var onCollapse: () -> Void = {}
    @State private var showingAddAgent = false
    @State private var agentName = ""
    @State private var selectedTaskID: String?
    @State private var agentDragID: String?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Label("智能体工作区", systemImage: "sparkles").font(.system(size: 14, weight: .semibold))
                Text("选择角色，再分配任务").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { workspace.chooseWorkspace() } label: {
                    HStack(spacing: 10) {
                        Text(workspace.selectedWorkspaceName).font(.system(size: 10)).lineLimit(1)
                        Image(systemName: "folder")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).frame(minWidth: 110, minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(workspace.selectedWorkspacePath)
                .accessibilityLabel("选择 Codex 工作区：\(workspace.selectedWorkspaceName)")
                Button(action: onCollapse) { Image(systemName: "chevron.down").frame(width: 26, height: 24) }
                    .buttonStyle(.plain).accessibilityLabel("收起智能体工作区")
            }
            HStack(alignment: .top, spacing: 16) {
                agentRail.frame(width: 86)
                Divider()
                taskBoard.frame(width: 340)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    if workspace.setupAgentIDs.contains(workspace.selectedID) {
                        HStack {
                            Text("待配置 · 请在 Codex 中完成创建").font(.caption).foregroundStyle(.orange)
                            Spacer()
                            Button("检查配置") { workspace.finishAgentSetup() }.font(.caption)
                        }
                    }
                    AgentChatPanel()
                }.frame(minWidth: 380, maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.1)))
        .alert("添加智能体", isPresented: $showingAddAgent) {
            TextField("名称", text: $agentName)
            Button("取消", role: .cancel) { agentName = "" }
            Button("交给 Codex 创建") {
                do { try workspace.createAgent(name: agentName); agentName = "" }
                catch { workspace.error = error.localizedDescription }
            }.disabled(agentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { Text("先取名，再到 Codex 配置能力和执行流程。") }
        .alert("智能体工作区", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) {
            Button("知道了") { workspace.error = nil }
        } message: { Text(workspace.error ?? "") }
        .onChange(of: workspace.selectedID) { _ in selectedTaskID = workspace.draft.taskIDs.first }
    }

    private var agentRail: some View {
        VStack(spacing: 10) {
            Text("AGENTS").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 14) {
                ForEach(workspace.agents) { agent in
                    Button { withAnimation(.spring(response: 0.25)) { workspace.select(agent.id) } } label: {
                        VStack(spacing: 5) {
                            AgentAvatar(profile: agent, selected: workspace.selectedID == agent.id).frame(width: 49, height: 49)
                            Text(agent.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                .foregroundStyle(workspace.selectedID == agent.id ? .primary : .secondary)
                        }.frame(width: 72)
                    }
                    .buttonStyle(.plain)
                    .help("\(agent.background)；拖到任务上分配")
                    .onDrag { agentDragID = agent.id; return NSItemProvider(object: "todoboard-agent:\(agent.id)" as NSString) }
                    .onDrop(of: [boardTaskType], delegate: AgentTaskDropDelegate(store: store, dragging: $dragging, onDropTask: { id in
                        workspace.select(agent.id); addTask(id)
                    }))
                }
                }.padding(.vertical, 2)
            }
            Button { showingAddAgent = true } label: {
                VStack(spacing: 4) {
                    Circle().strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .overlay(Image(systemName: "plus").font(.system(size: 22, weight: .light)))
                        .frame(width: 42, height: 42)
                    Text("添加").font(.system(size: 10, weight: .medium))
                }.foregroundStyle(.secondary).frame(width: 72)
            }
            .buttonStyle(.plain).accessibilityLabel("添加智能体")

        }
    }

    private var taskBoard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("分配给 \(workspace.selected?.name ?? "智能体")").font(.system(size: 12, weight: .semibold))
                Spacer()
                Menu {
                    ForEach(store.board.tasks.filter { !workspace.draft.taskIDs.contains($0.id) }) { task in
                        Button(task.title) { store.setStatus(taskID: task.id, .doing); addTask(task.id) }
                    }
                } label: { Label("选择任务", systemImage: "plus") }.fixedSize()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if workspace.draft.taskIDs.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tray.and.arrow.down").font(.system(size: 28, weight: .light))
                            Text("把任务拖到这里").font(.system(size: 14, weight: .medium))
                            Text("也可拖到左侧头像，直接分配\n拖入后任务进入「进行中」")
                                .font(.system(size: 11)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    ForEach(workspace.draft.taskIDs, id: \.self) { id in
                        if let task = store.board.task(withID: id) { taskCard(task) }
                        else {
                            HStack { Text("任务已移除：\(id)"); Spacer(); Button("移出") { removeTask(id) } }.font(.caption)
                        }
                    }
                }.padding(10).frame(maxWidth: .infinity)
            }
            .background(BoardPalette.violet.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BoardPalette.violet.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .onDrop(of: [boardTaskType], delegate: AgentTaskDropDelegate(store: store, dragging: $dragging, onDropTask: addTask))
            Text("可把其他智能体头像拖到任务卡片，转交任务").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func taskCard(_ task: BoardTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Button { selectedTaskID = task.id } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title).font(.system(size: 12, weight: .medium)).multilineTextAlignment(.leading)
                        Text("\(task.id) · \(task.status.label)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                Button { removeTask(task.id) } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).help("移出本次任务")
            }

        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selectedTaskID == task.id ? BoardPalette.violet.opacity(0.7) : .clear))
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            guard let agentID = agentDragID, let provider = providers.first else { return false }
            agentDragID = nil
            let sourceID = workspace.selectedID
            _ = provider.loadObject(ofClass: NSString.self) { object, error in
                guard error == nil, object as? String == "todoboard-agent:\(agentID)" else { return }
                Task { @MainActor in
                    workspace.select(sourceID)
                    let hint = workspace.draft.ovHints[task.id]
                    workspace.updateDraft { $0.taskIDs.removeAll { $0 == task.id } }
                    workspace.select(agentID); addTask(task.id)
                    if let hint { workspace.updateDraft { $0.ovHints[task.id] = hint } }
                }
            }
            return true
        }
    }

    private func addTask(_ id: String) {
        workspace.updateDraft { if !$0.taskIDs.contains(id) { $0.taskIDs.append(id) } }
        selectedTaskID = id
    }
    private func removeTask(_ id: String) {
        workspace.updateDraft { $0.taskIDs.removeAll { $0 == id }; $0.ovHints.removeValue(forKey: id) }
    }

}

struct AgentAvatar: View {
    let profile: AgentProfile
    let selected: Bool
    private var avatar: NSImage? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Avatars/\(profile.avatar).png")
        if let url = bundled, let image = NSImage(contentsOf: url) { return image }
        let development = Bundle.module.url(forResource: profile.avatar, withExtension: "png", subdirectory: "Avatars")
        return development.flatMap { NSImage(contentsOf: $0) }
    }
    var body: some View {
        GeometryReader { geo in
            Group {
                if let avatar { Image(nsImage: avatar).resizable().scaledToFill() }
                else { Circle().fill(.cyan.opacity(0.3)).overlay(Text(String(profile.name.prefix(1)))) }
            }
            .frame(width: geo.size.width, height: geo.size.height).clipShape(Circle())
            .saturation(selected ? 1 : 0).opacity(selected ? 1 : 0.45)
            .overlay(alignment: .bottomTrailing) {
                if !selected {
                    Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 17, height: 17).background(.white, in: Circle()).offset(x: 1, y: 1)
                }
            }
        }
    }
}

struct AgentWorkspaceCollapsedBar: View {
    let onExpand: () -> Void
    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 9) {
                Label("智能体工作区", systemImage: "sparkles").font(.system(size: 12, weight: .semibold))
                Text("选择角色 · 分配任务 · 带上需要的上下文").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(); Image(systemName: "chevron.up"); Text("展开").font(.system(size: 10))
            }.foregroundStyle(BoardPalette.violet).padding(.horizontal, 13).frame(height: 42)
                .background(BoardPalette.card.opacity(0.82), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityLabel("展开智能体工作区")
    }
}
