import AppKit
import BoardKit
import BoardUI
import Combine
import SwiftUI

/// 边缘停靠面板控制器：NSPanel 的收起/展开、贴边吸附、悬停与点击行为
@MainActor
final class PanelController: ObservableObject {
    enum Edge: String, CaseIterable {
        case left, right, top, bottom
        var ui: TabHandleView.EdgeEdge {
            TabHandleView.EdgeEdge(rawValue: rawValue) ?? .right
        }
    }

    static let tabThickness: CGFloat = 26
    static let collapsedLength: CGFloat = 170
    static let expandedWidth: CGFloat = 1340
    static let expandedHeight: CGFloat = 920

    let store: BoardStore
    let settings: AppSettings
    let agentWorkspace: AgentWorkspaceStore

    @Published private(set) var expanded = false
    @Published private(set) var edge: Edge = .right

    private var panel: NSPanel!
    private var hostingView: NSHostingView<AnyView>!
    private var mouseTimer: Timer?
    private var outsideSince: Date?
    private var interactionActive = false
    private var hoverTask: DispatchWorkItem?
    private var hoverSuppressUntil = Date.distantPast
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(store: BoardStore, settings: AppSettings) {
        self.store = store
        self.agentWorkspace = AgentWorkspaceStore(directory: store.directory)
        self.settings = settings
        edge = Edge(rawValue: settings.edgeRaw) ?? .right
        makePanel()
        observeSettings()
        installMonitors()
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkMouseExit() }
        }
    }

    // MARK: - 面板创建

    private func makePanel() {
        let frame = frameFor(expanded: false)
        let p = BoardPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovable = false
        p.isMovableByWindowBackground = false
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.ignoresMouseEvents = false

        let root = AnyView(
            PanelRootView(controller: self)
                .environmentObject(store)
                .environmentObject(agentWorkspace)
        )
        p.appearance = NSAppearance(named: .darkAqua)
        hostingView = NSHostingView(rootView: root)
        p.contentView = hostingView
        panel = p
    }

    func showPanel() {
        panel.orderFrontRegardless()
    }

    // MARK: - 布局计算

    private var screen: NSScreen {
        let sel = NSScreen.screens.max { a, b in
            intersectionArea(a.frame, panel?.frame ?? a.frame) < intersectionArea(b.frame, panel?.frame ?? b.frame)
        }
        return sel ?? NSScreen.main ?? NSScreen.screens.first!
    }

    private func intersectionArea(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let i = a.intersection(b)
        return i.width * i.height
    }

    /// 沿边缘轴的停靠中心位置（点）；-1 = 尚未设置 → 取屏幕居中
    private var offsetAlongEdge: CGFloat {
        get { CGFloat(settings.offsetAlongEdge) }
        set { settings.offsetAlongEdge = Double(newValue) }
    }

    private func frameFor(expanded: Bool, edge: Edge? = nil, screen: NSScreen? = nil) -> NSRect {
        let edge = edge ?? self.edge
        let scr = screen ?? self.screen
        let vis = scr.visibleFrame
        let t = Self.tabThickness

        var offset = offsetAlongEdge
        if offset < 0 { offset = centeredOffset(edge: edge, vis: vis) }
        offset = clampOffset(offset, edge: edge, vis: vis, expanded: expanded)

        switch edge {
        case .right:
            let w = expanded ? min(Self.expandedWidth, vis.width - 12) : t
            let h = expanded ? min(Self.expandedHeight, vis.height - 12) : Self.collapsedLength
            return NSRect(x: vis.maxX - w, y: offset - h / 2, width: w, height: h)
        case .left:
            let w = expanded ? min(Self.expandedWidth, vis.width - 12) : t
            let h = expanded ? min(Self.expandedHeight, vis.height - 12) : Self.collapsedLength
            return NSRect(x: vis.minX, y: offset - h / 2, width: w, height: h)
        case .top:
            let h = expanded ? min(Self.expandedHeight, vis.height - 12) : t
            let w = expanded ? min(Self.expandedWidth, vis.width - 12) : Self.collapsedLength
            return NSRect(x: offset - w / 2, y: vis.maxY - h, width: w, height: h)
        case .bottom:
            let h = expanded ? min(Self.expandedHeight, vis.height - 12) : t
            let w = expanded ? min(Self.expandedWidth, vis.width - 12) : Self.collapsedLength
            return NSRect(x: offset - w / 2, y: vis.minY, width: w, height: h)
        }
    }

    private func centeredOffset(edge: Edge, vis: NSRect) -> CGFloat {
        switch edge {
        case .left, .right: return vis.midY
        case .top, .bottom: return vis.midX
        }
    }

    private func clampOffset(_ v: CGFloat, edge: Edge, vis: NSRect, expanded: Bool) -> CGFloat {
        let length: CGFloat
        switch edge {
        case .left, .right: length = expanded ? min(Self.expandedHeight, vis.height - 12) : Self.collapsedLength
        case .top, .bottom: length = expanded ? min(Self.expandedWidth, vis.width - 12) : Self.collapsedLength
        }
        let half = length / 2
        let lo: CGFloat, hi: CGFloat
        switch edge {
        case .left, .right: lo = vis.minY + half; hi = vis.maxY - half
        case .top, .bottom: lo = vis.minX + half; hi = vis.maxX - half
        }
        return min(max(v, lo), hi)
    }

    private func applyFrame(_ f: NSRect, animated: Bool) {
        guard panel.frame != f else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(f, display: true)
            }
        } else {
            panel.setFrame(f, display: true)
        }
    }

    /// 从当前窗口位置反算沿边偏移（拖动结束时用）
    private func captureOffset(edge: Edge, frame: NSRect) -> CGFloat {
        switch edge {
        case .left, .right: return frame.midY
        case .top, .bottom: return frame.midX
        }
    }

    // MARK: - 展开 / 收起

    func toggle() { expanded ? collapse() : expand() }

    func expand() {
        guard !expanded else { return }
        hoverTask?.cancel()
        outsideSince = nil
        expanded = true
        store.checkRollover()
        applyFrame(frameFor(expanded: true), animated: true)
        showPanel()
        panel.makeKey()
    }

    func collapse() {
        guard expanded else { return }
        hoverTask?.cancel()
        outsideSince = nil
        expanded = false
        hoverSuppressUntil = Date().addingTimeInterval(0.8)
        applyFrame(frameFor(expanded: false), animated: true)
        showPanel()
    }

    func setInteractionActive(_ active: Bool) {
        interactionActive = active
        outsideSince = nil
    }

    private func checkMouseExit() {
        guard expanded else { outsideSince = nil; return }
        let editingText = panel.firstResponder is NSTextView
        let menuOpen = NSApp.windows.contains { $0.isVisible && $0 != panel && $0.level.rawValue >= NSWindow.Level.popUpMenu.rawValue }
        guard !interactionActive, !editingText, !menuOpen, NSEvent.pressedMouseButtons == 0,
              !panel.frame.contains(NSEvent.mouseLocation) else {
            outsideSince = nil
            return
        }
        if let since = outsideSince {
            if Date().timeIntervalSince(since) >= 2 { collapse() }
        } else { outsideSince = Date() }
    }

    // MARK: - 标签交互回调（来自 TabHandleCatcher）

    func tabClicked() {
        toggle()
    }

    func tabDragEnded() {
        // 找最贴合的边缘并吸附
        let f = panel.frame
        let scr = screen
        let vis = scr.visibleFrame

        let distances: [(Edge, CGFloat)] = [
            (.left, f.minX - vis.minX),
            (.right, vis.maxX - f.maxX),
            (.top, vis.maxY - f.maxY),
            (.bottom, f.minY - vis.minY),
        ]
        let nearest = distances.min { $0.1 < $1.1 }!.0

        edge = nearest
        settings.edgeRaw = nearest.rawValue
        // 用拖动结束位置换算新边上的偏移（以拖动落点投影）
        switch nearest {
        case .left, .right: offsetAlongEdge = f.midY
        case .top, .bottom: offsetAlongEdge = f.midX
        }
        applyFrame(frameFor(expanded: expanded, edge: nearest, screen: scr), animated: true)
    }

    func tabHoverEntered() {
        guard !expanded, settings.expandOnHover, Date() >= hoverSuppressUntil else { return }
        hoverTask?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.expanded else { return }
            self.expand()
        }
        hoverTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func tabHoverExited() {
        hoverTask?.cancel()
    }

    // MARK: - 外部点击 / Esc

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, let self, self.expanded, self.panel.isKeyWindow {
                self.collapse()
                return nil
            }
            return event
        }
        settings.$collapseOnOutsideClick
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.updateOutsideMonitor(enabled: enabled)
            }
            .store(in: &cancellables)
    }

    private func updateOutsideMonitor(enabled: Bool) {
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
        guard enabled else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.expanded, !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.collapse()
            }
        }
    }

    private func observeSettings() {
        // 屏幕参数变化时把面板拉回可见区
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.repositionIfNeeded()
            }
            .store(in: &cancellables)
    }

    @MainActor
    func repositionIfNeeded() {
        applyFrame(frameFor(expanded: expanded), animated: false)
    }
}

// MARK: - 面板根视图（把手 + 内容的组合）

struct PanelRootView: View {
    @ObservedObject var controller: PanelController
    @EnvironmentObject var store: BoardStore
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Group {
            switch controller.edge {
            case .right:
                HStack(spacing: 0) { content; handle }
            case .left:
                HStack(spacing: 0) { handle; content }
            case .top:
                VStack(spacing: 0) { handle; content }
            case .bottom:
                VStack(spacing: 0) { content; handle }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(controller.expanded ? Color(red: 0.075, green: 0.075, blue: 0.085) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: controller.expanded ? 16 : 0))
        .overlay {
            if controller.expanded {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.09))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if controller.expanded {
            BoardContentView(
                settings: settings,
                edge: controller.edge.ui,
                onCollapse: { controller.collapse() },
                onInteractionChanged: { controller.setInteractionActive($0) },
                loginItemState: { AutoLauncher.isEnabled },
                toggleLoginItem: { on in
                    do {
                        try AutoLauncher.setEnabled(on)
                        return true
                    } catch {
                        return false
                    }
                }
            )
            .transition(.opacity)
        } else {
            Color.clear
        }
    }

    private var handle: some View {
        let vertical = controller.edge == .left || controller.edge == .right
        return ZStack {
            TabHandleView(
                edge: controller.edge.ui,
                todayCount: store.board.todayTasks.count,
                collapsed: !controller.expanded
            )
            TabHandleCatcherRepresentable { v in
                v.onClick = { [weak controller] in controller?.tabClicked() }
                v.onDragEnd = { [weak controller] in controller?.tabDragEnded() }
                v.onHoverEntered = { [weak controller] in controller?.tabHoverEntered() }
                v.onHoverExited = { [weak controller] in controller?.tabHoverExited() }
            }
        }
        .frame(width: vertical ? PanelController.tabThickness : nil,
               height: vertical ? nil : PanelController.tabThickness)
        .frame(maxWidth: vertical ? nil : .infinity,
               maxHeight: vertical ? .infinity : nil)
    }
}

/// Borderless panels need an explicit key-window policy for text editing.
private final class BoardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
