import BoardKit
import SwiftUI

struct AgentCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar: AgentAvatarOption
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    let create: (String, String) throws -> Void

    init(initialAvatar: AgentAvatarOption, create: @escaping (String, String) throws -> Void) {
        _avatar = State(initialValue: initialAvatar)
        self.create = create
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("添加智能体").font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text("名称").font(.system(size: 12, weight: .medium))
                TextField("给智能体取个名字", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .accessibilityLabel("智能体名称")
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("选择头像").font(.system(size: 12, weight: .medium))
                HStack(spacing: 18) {
                    ForEach(AgentAvatarOption.allCases) { option in
                        Button { avatar = option } label: {
                            AgentPortrait(avatar: option.rawValue, fallback: "")
                                .frame(width: 64, height: 64)
                                .overlay(Circle().strokeBorder(avatar == option ? BoardPalette.violet : .clear, lineWidth: 3))
                                .overlay(alignment: .bottomTrailing) {
                                    if avatar == option {
                                        Image(systemName: "checkmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, BoardPalette.violet)
                                            .font(.system(size: 18))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.label)
                        .accessibilityValue(avatar == option ? "已选择" : "未选择")
                        .accessibilityAddTraits(avatar == option ? .isSelected : [])
                        .help(option.label)
                    }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .accessibilityLabel("创建失败：" + error)
            }
            Text("取名和选头像 → Codex 逐题访谈 → 你确认职能 → 创建与试跑。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("去 Codex 开始访谈", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 400)
        .onAppear { nameFocused = true }
        .onChange(of: name) { _ in error = nil }
        .onChange(of: avatar) { _ in error = nil }
    }

    private func submit() {
        do {
            try create(name, avatar.rawValue)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
