import BoardKit
import SwiftUI

/// One composer. The real conversation and all replies live in Codex desktop.
struct AgentChatPanel: View {
    @EnvironmentObject private var workspace: AgentWorkspaceStore
    @EnvironmentObject private var board: BoardStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composing: Bool
    @State private var acknowledging = false
    @State private var flying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "paperplane").foregroundStyle(BoardPalette.violet)
                Text("交给 \(workspace.selected?.name ?? "智能体")").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("在 Codex 中继续").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ZStack(alignment: .topLeading) {
                AgentInstructionEditor(text: Binding(get: { workspace.draft.instruction }, set: { text in
                    workspace.updateDraft { $0.instruction = text }
                    acknowledging = false
                }), isFocused: $composing)
                .accessibilityLabel("给 Codex 的任务说明")
                if acknowledging {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().fill(BoardPalette.violet.opacity(0.14)).frame(width: 52, height: 52)
                                .scaleEffect(flying ? 1.15 : 0.7).opacity(flying ? 1 : 0)
                            Image(systemName: "paperplane.fill").font(.system(size: 24))
                                .foregroundStyle(BoardPalette.violet)
                                .offset(x: flying ? 25 : -20, y: flying ? -18 : 15)
                                .opacity(flying ? 0 : 1)
                            Image(systemName: "checkmark").font(.system(size: 23, weight: .semibold))
                                .foregroundStyle(BoardPalette.violet).opacity(flying ? 1 : 0)
                                .scaleEffect(flying ? 1 : 0.5)
                        }
                        Text("已发送给 Codex").font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BoardPalette.background.opacity(0.97))
                    .allowsHitTesting(false)
                    .accessibilityLabel("已发送给 Codex")
                }
            }
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08)))
            HStack(spacing: 8) {
                status
                Spacer(minLength: 4)
                Button {
                    acknowledging = false
                    workspace.handoff(board: board.board); composing = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right")
                        Text("发送给 Codex")
                    }.font(.system(size: 11, weight: .medium)).padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent).tint(BoardPalette.violet)
                .keyboardShortcut(.return, modifiers: .command)
                .help("发送 · ⌘Enter").accessibilityLabel("发送给 Codex")
                .disabled(workspace.isSending || (!workspace.setupAgentIDs.contains(workspace.selectedID) && workspace.composeMessage(board: board.board).isEmpty) || !workspace.deliveryStorageAvailable)
            }
        }
        .onChange(of: workspace.deliveryState) { state in
            guard case .sent = state, !composing else { return }
            acknowledging = true; flying = false
        }
        .task(id: acknowledging) {
            guard acknowledging else { return }
            // Insert the plane at its starting position before animating it.
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.65)) { flying = true }
        }
        .onChange(of: workspace.selectedID) { _ in acknowledging = false }
        .onChange(of: composing) { focused in if focused { acknowledging = false } }
    }

    @ViewBuilder private var status: some View {
        switch workspace.deliveryState {
        case .preparing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("正在交给 Codex…").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2).help(message)
        case .needsOpening(let receipt, let message):
            Button(message + " · 重试打开") { workspace.openDelivery(receipt) }
                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.orange)
        case .sent(let receipt):
            Button("在 Codex 中打开 ↗") { workspace.openDelivery(receipt) }
                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
        case nil:
            Text(workspace.draft.taskIDs.isEmpty ? "⌘Enter 发送" : "附带 \(workspace.draft.taskIDs.count) 项任务上下文")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
