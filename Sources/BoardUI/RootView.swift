import AppKit
import BoardKit
import SwiftUI

public struct BoardContentView: View {
    @EnvironmentObject public var store: BoardStore
    @ObservedObject public var settings: AppSettings
    public let edge: TabHandleView.EdgeEdge
    public let onCollapse: () -> Void
    public var onInteractionChanged: (Bool) -> Void = { _ in }
    public var loginItemState: () -> Bool
    public var toggleLoginItem: (Bool) -> Bool
    @State private var dragging: String?
    @State private var editingTaskID: String?
    @State private var showSettings = false
    @AppStorage("showAgentWorkspace") private var showAgentWorkspace = false

    public init(settings: AppSettings, edge: TabHandleView.EdgeEdge, onCollapse: @escaping () -> Void,
                onInteractionChanged: @escaping (Bool) -> Void = { _ in },
                loginItemState: @escaping () -> Bool = { false }, toggleLoginItem: @escaping (Bool) -> Bool = { _ in false }) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TODOBOARD_AGENT_PREVIEW"] == "1" {
            UserDefaults.standard.set(true, forKey: "showAgentWorkspace")
        }
        #endif
        self.onInteractionChanged = onInteractionChanged
        self.settings = settings
        self.edge = edge
        self.onCollapse = onCollapse
        self.loginItemState = loginItemState
        self.toggleLoginItem = toggleLoginItem
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            if let banner = store.banner {
                HStack {
                    Label(banner.text, systemImage: "exclamationmark.triangle")
                    Spacer()
                    Button("关闭") { store.dismissBanner() }
                }
                .font(.system(size: 12)).foregroundStyle(.orange).padding(12)
            }
            GeometryReader { geo in
                let columnWidth = max(205, (geo.size.width - 210) / 4)
                HStack(alignment: .top, spacing: 16) {
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(TaskStatus.workflow, id: \.self) { status in
                                KanbanColumn(status: status, dragging: $dragging, editingTaskID: $editingTaskID)
                                    .frame(width: columnWidth)
                            }
                        }
                        .frame(height: geo.size.height)
                    }
                    TrashTarget(dragging: $dragging)
                        .frame(width: 144)
                }
            }
            .padding(.horizontal, 28).padding(.top, 18)
            .frame(minHeight: 380, maxHeight: .infinity)

            if showAgentWorkspace {
                AgentWorkspaceView(
                    dragging: $dragging,
                    onCollapse: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAgentWorkspace = false
                        }
                    }
                )
                .frame(height: 300)
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                AgentWorkspaceCollapsedBar {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAgentWorkspace = true
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

        }
        .background(BoardPalette.background)

        .overlay {
            if let task = store.board.task(withID: editingTaskID ?? "") {
                Color.black.opacity(0.6).onTapGesture { editingTaskID = nil }
                TaskDetailSheet(task: task, isPresented: Binding(get: { editingTaskID != nil }, set: { if !$0 { editingTaskID = nil } }))
                    .frame(width: 500).padding(20)
            }
            if showSettings {
                Color.black.opacity(0.6).onTapGesture { showSettings = false }
                SettingsSheet(isPresented: $showSettings, loginItemState: loginItemState, toggleLoginItem: toggleLoginItem)
                    .frame(width: 460).padding(20)
            }
        }
        .onChange(of: editingTaskID) { _ in reportInteraction() }
        .onChange(of: showSettings) { _ in reportInteraction() }
        .onChange(of: dragging) { _ in reportInteraction() }
        .onDisappear { onInteractionChanged(false) }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.split.2x2").font(.system(size: 19)).foregroundStyle(BoardPalette.violet)
            Text("TodoBoard").font(.system(size: 21, weight: .semibold))
            Spacer()
            Text(store.board.day.replacingOccurrences(of: "-", with: "."))
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(BoardPalette.muted)
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .help("设置").accessibilityLabel("设置")
            Button(action: onCollapse) { Image(systemName: "arrow.right.to.line") }
                .help("收起看板 · ⌘⇧T").accessibilityLabel("收起看板")
        }
        .buttonStyle(.plain).foregroundStyle(BoardPalette.text)
        .padding(.horizontal, 28).padding(.vertical, 16)
    }

    private func reportInteraction() {
        onInteractionChanged(editingTaskID != nil || showSettings)
    }

}

enum BoardPalette {
    static let background = Color(red: 0.075, green: 0.075, blue: 0.085)
    static let card = Color(red: 0.14, green: 0.14, blue: 0.155)
    static let text = Color(white: 0.92)
    static let muted = Color(white: 0.48)
    static let violet = Color(red: 0.68, green: 0.58, blue: 0.98)
    static func color(_ status: TaskStatus) -> Color {
        switch status {
        case .backlog: return Color(white: 0.58)
        case .today: return Color(red: 0.95, green: 0.85, blue: 0.42)
        case .doing: return Color(red: 0.57, green: 0.74, blue: 0.96)
        case .done: return Color(red: 0.52, green: 0.85, blue: 0.71)
        case .trash: return .red
        }
    }
}
