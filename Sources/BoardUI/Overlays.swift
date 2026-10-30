import AppKit
import BoardKit
import SwiftUI

/// 设置浮层
public struct SettingsSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject var store: BoardStore

    /// 由 app 层注入（SMAppService 需要在 app target 里调）；toggle 返回是否成功
    public var loginItemState: () -> Bool = { false }
    public var toggleLoginItem: (Bool) -> Bool = { _ in false }
    @State private var loginEnabled = false

    public init(isPresented: Binding<Bool>, loginItemState: @escaping () -> Bool = { false }, toggleLoginItem: @escaping (Bool) -> Bool = { _ in false }) {
        _isPresented = isPresented
        self.loginItemState = loginItemState
        self.toggleLoginItem = toggleLoginItem
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("设置")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Toggle(isOn: $settings.expandOnHover) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("悬停标签自动展开").font(.system(size: 12))
                    Text("鼠标停在边缘标签上 0.35 秒后展开面板")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $settings.collapseOnOutsideClick) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("点击面板外自动收起").font(.system(size: 12))
                    Text("默认开启；鼠标离开面板 2 秒也会自动收起")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: Binding(
                get: { loginEnabled },
                set: { on in
                    if toggleLoginItem(on) { loginEnabled = on }
                }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("登录时自动启动").font(.system(size: 12))
                    Text("提示：app 放入「应用程序」文件夹后此功能最稳定")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("数据目录（AI agent 直接读写）")
                    .font(.system(size: 11, weight: .semibold))
                HStack {
                    Text(store.directory.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("在 Finder 打开") {
                        NSWorkspace.shared.open(store.directory)
                    }
                    .controlSize(.small)
                }
                Text("改数据规则见目录内 README.md · 全局快捷键 ⌘⇧T 显示/隐藏")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 12)
        .onAppear { loginEnabled = loginItemState() }
    }
}
