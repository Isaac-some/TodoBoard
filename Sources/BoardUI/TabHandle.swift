import AppKit
import SwiftUI

// MARK: - 事件捕获层（AppKit）

/// 边缘标签的事件层：处理 点击（切换展开）、拖动（移动/换边）、悬停（自动展开）。
/// 叠在 SwiftUI 视觉层之上，透明。
public final class TabHandleCatcher: NSView {
    public var onClick: (() -> Void)?
    public var onDragEnd: (() -> Void)?
    public var onHoverEntered: (() -> Void)?
    public var onHoverExited: (() -> Void)?

    private var initialScreenPoint: NSPoint?
    private var initialWindowOrigin: NSPoint?
    private var dragged = false

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }

    public override func mouseDown(with event: NSEvent) {
        dragged = false
        if let window {
            initialScreenPoint = window.convertToScreen(CGRect(origin: event.locationInWindow, size: .zero)).origin
            initialWindowOrigin = window.frame.origin
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let window, let startPt = initialScreenPoint, let startOrigin = initialWindowOrigin else { return }
        let cur = window.convertToScreen(CGRect(origin: event.locationInWindow, size: .zero)).origin
        let dx = cur.x - startPt.x, dy = cur.y - startPt.y
        if abs(dx) > 3 || abs(dy) > 3 { dragged = true }
        guard dragged else { return }
        window.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    public override func mouseUp(with event: NSEvent) {
        if dragged {
            onDragEnd?()
        } else {
            onClick?()
        }
        initialScreenPoint = nil
        initialWindowOrigin = nil
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let ta = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
    }

    public override func mouseEntered(with event: NSEvent) { onHoverEntered?() }
    public override func mouseExited(with event: NSEvent) { onHoverExited?() }
}

public struct TabHandleCatcherRepresentable: NSViewRepresentable {
    public let configure: (TabHandleCatcher) -> Void

    public init(configure: @escaping (TabHandleCatcher) -> Void) {
        self.configure = configure
    }

    public func makeNSView(context: Context) -> TabHandleCatcher {
        let v = TabHandleCatcher()
        configure(v)
        return v
    }

    public func updateNSView(_ nsView: TabHandleCatcher, context: Context) {
        configure(nsView)
    }
}

// MARK: - 视觉层（SwiftUI）

/// 收起时的贴边竖条 / 展开后的面板把手。厚度固定 26pt。
public struct TabHandleView: View {
    public let edge: EdgeEdge
    public let todayCount: Int
    public let collapsed: Bool

    public init(edge: EdgeEdge, todayCount: Int, collapsed: Bool) {
        self.edge = edge
        self.todayCount = todayCount
        self.collapsed = collapsed
    }

    public enum EdgeEdge: String, Sendable { case left, right, top, bottom }

    public var body: some View {
        let vertical = edge == .left || edge == .right
        ZStack {
            Color(red: 0.075, green: 0.075, blue: 0.085)
            content(vertical: vertical)
        }
        .clipShape(InnerRoundedRectangle(edge: edge, radius: collapsed ? 9 : 0))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func content(vertical: Bool) -> some View {
        if vertical {
            VStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Rectangle().fill(Color.primary.opacity(0.18)).frame(width: 12, height: 1)
                Text("\(todayCount)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(todayCount == 0 ? Color.secondary : Color.primary)
                chevron
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(todayCount)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                chevron
            }
        }
    }

    @ViewBuilder
    private var chevron: some View {
        // 指示可拉动方向（朝屏幕内侧）
        switch edge {
        case .right: Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
        case .left: Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
        case .top: Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
        case .bottom: Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
        }
    }

    private func roundedShape(vertical: Bool) -> some Shape {
        InnerRoundedRectangle(edge: edge, radius: 9)
    }
}

/// 靠屏幕边缘为圆角，朝屏幕内侧为直角。
public struct InnerRoundedRectangle: Shape {
    public let edge: TabHandleView.EdgeEdge
    public let radius: CGFloat

    public init(edge: TabHandleView.EdgeEdge, radius: CGFloat) {
        self.edge = edge
        self.radius = radius
    }

    public func path(in rect: CGRect) -> Path {
        // The free edge facing into the screen is square; the attached edge is rounded.
        let r = min(radius, min(rect.width, rect.height) / 2)
        let tl = edge == .left || edge == .top ? r : 0
        let tr = edge == .right || edge == .top ? r : 0
        let bl = edge == .left || edge == .bottom ? r : 0
        let br = edge == .right || edge == .bottom ? r : 0
        let x = rect.minX, y = rect.minY, w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: x + tl, y: y))
        p.addLine(to: CGPoint(x: x + w - tr, y: y))
        p.addQuadCurve(to: CGPoint(x: x + w, y: y + tr), control: CGPoint(x: x + w, y: y))
        p.addLine(to: CGPoint(x: x + w, y: y + h - br))
        p.addQuadCurve(to: CGPoint(x: x + w - br, y: y + h), control: CGPoint(x: x + w, y: y + h))
        p.addLine(to: CGPoint(x: x + bl, y: y + h))
        p.addQuadCurve(to: CGPoint(x: x, y: y + h - bl), control: CGPoint(x: x, y: y + h))
        p.addLine(to: CGPoint(x: x, y: y + tl))
        p.addQuadCurve(to: CGPoint(x: x + tl, y: y), control: CGPoint(x: x, y: y))
        p.closeSubpath()
        return p
    }
}
