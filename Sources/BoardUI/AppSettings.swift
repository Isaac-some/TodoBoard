import AppKit
import BoardKit
import Combine
import Foundation
import SwiftUI

/// app 偏好设置（UserDefaults 持久化）。数据存放在独立数据目录，这里只存界面行为
@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let d = UserDefaults.standard

    @Published public var expandOnHover: Bool {
        didSet { d.set(expandOnHover, forKey: "expandOnHover") }
    }
    @Published public var collapseOnOutsideClick: Bool {
        didSet { d.set(collapseOnOutsideClick, forKey: "collapseOnOutsideClick") }
    }
    /// 边缘停靠方向：left / right / top / bottom
    @Published public var edgeRaw: String {
        didSet { d.set(edgeRaw, forKey: "edgeRaw") }
    }
    /// 停靠位置沿边缘轴的中心点（点数，相对所在屏幕 visibleFrame）
    @Published public var offsetAlongEdge: Double {
        didSet { d.set(offsetAlongEdge, forKey: "offsetAlongEdge") }
    }
    /// 新任务默认投放组（记忆上次选择）
    @Published public var newTaskStatusRaw: String {
        didSet { d.set(newTaskStatusRaw, forKey: "newTaskStatusRaw") }
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "expandOnHover": true,
            "collapseOnOutsideClick": true,
            "edgeRaw": "right",
            "offsetAlongEdge": -1, // -1 表示尚未初始化（取屏幕居中）
            "newTaskStatusRaw": TaskStatus.today.rawValue,
        ])
        if !d.bool(forKey: "blurt110AutoCollapseMigrated") {
            d.set(true, forKey: "collapseOnOutsideClick")
            d.set(true, forKey: "blurt110AutoCollapseMigrated")
        }
        expandOnHover = d.bool(forKey: "expandOnHover")
        collapseOnOutsideClick = d.bool(forKey: "collapseOnOutsideClick")
        edgeRaw = d.string(forKey: "edgeRaw") ?? "right"
        offsetAlongEdge = d.double(forKey: "offsetAlongEdge")
        newTaskStatusRaw = d.string(forKey: "newTaskStatusRaw") ?? TaskStatus.today.rawValue
    }
}

// MARK: - 通用小组件

public struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    public init(material: NSVisualEffectView.Material = .underWindowBackground) {
        self.material = material
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

public extension TaskPriority {
    var color: Color {
        switch self {
        case .high: return Color(red: 0.85, green: 0.25, blue: 0.25)
        case .mid: return Color(red: 0.90, green: 0.65, blue: 0.15)
        case .low: return Color(white: 0.62)
        }
    }
}
