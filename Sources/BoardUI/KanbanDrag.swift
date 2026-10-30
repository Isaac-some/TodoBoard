import AppKit
import BoardKit
import SwiftUI
import UniformTypeIdentifiers

let boardTaskType = UTType.text

/// Hover only previews an insertion line. Data changes on a real drop, so Escape/cancellation is safe.
struct CardDropDelegate: DropDelegate {
    let status: TaskStatus
    let beforeID: String?
    let store: BoardStore
    @Binding var dragging: String?
    @Binding var highlighted: String?
    func validateDrop(info: DropInfo) -> Bool {
        dragging != nil && info.hasItemsConforming(to: [boardTaskType])
    }
    func dropEntered(info: DropInfo) { highlighted = beforeID ?? "end" }
    func dropExited(info: DropInfo) { if highlighted == (beforeID ?? "end") { highlighted = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil; highlighted = nil }
        guard let id = dragging, store.board.task(withID: id) != nil else { return false }
        if id == beforeID { return true }
        let group = store.board.tasks(in: status).filter { $0.id != id }
        let index = group.firstIndex(where: { $0.id == beforeID }) ?? group.count
        return acceptTask(info.itemProviders(for: [boardTaskType]), id: id) {
            withAnimation(.easeInOut(duration: 0.18)) { store.move(taskID: id, to: status, index: index) }
        }
    }
}

struct TrashTarget: View {
    @EnvironmentObject var store: BoardStore
    @Binding var dragging: String?
    @State private var active = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 16) {
                Image(systemName: active ? "flame" : "trash")
                    .font(.system(size: 30, weight: .light)).symbolRenderingMode(.hierarchical)
                Text(active ? "松手丢弃" : "拖到这里丢弃").font(.system(size: 12))
            }
            .foregroundStyle(active ? Color.red : BoardPalette.muted)
            .frame(maxWidth: .infinity).frame(height: 220)
            .background(active ? Color.red.opacity(0.10) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active ? Color.red.opacity(0.7) : Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(Rectangle())
            .onDrop(of: [boardTaskType], isTargeted: $active, perform: discard)
            .accessibilityLabel("垃圾桶，拖入任意阶段卡片以丢弃")
            if let task = store.lastDiscarded {
                Text("已丢弃：\(task.title)").font(.system(size: 10)).foregroundStyle(BoardPalette.muted).lineLimit(2)
                Button("撤销丢弃", action: store.undoDiscard)
                    .font(.system(size: 11)).foregroundStyle(BoardPalette.violet).buttonStyle(.plain)
            }
            Spacer()
        }
    }
    private func discard(_ providers: [NSItemProvider]) -> Bool {
        guard let id = dragging else { return false }
        dragging = nil
        return acceptTask(providers, id: id) {
            guard store.board.task(withID: id) != nil else { return }
            withAnimation { store.deleteTask(taskID: id) }
        }
    }

}

/// Drop target used by the local agent workspace. A successful drop is deliberately
/// small and deterministic: the task enters the doing column and the workspace
/// keeps its id for the local preview. A real agent adapter can consume that
/// preview later without changing the board drag contract.
struct AgentTaskDropDelegate: DropDelegate {
    let store: BoardStore
    @Binding var dragging: String?
    let onDropTask: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        dragging != nil && info.hasItemsConforming(to: [boardTaskType])
    }

    func dropEntered(info: DropInfo) {}
    func dropExited(info: DropInfo) {}
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func performDrop(info: DropInfo) -> Bool {
        guard let id = dragging, store.board.task(withID: id) != nil else {
            dragging = nil
            return false
        }
        dragging = nil
        return acceptTask(info.itemProviders(for: [boardTaskType]), id: id) {
            store.setStatus(taskID: id, .doing)
            onDropTask(id)
        }
    }
}

/// Read the real drag payload before changing data. A cancelled prior drag cannot
/// cause an unrelated text drop to move or discard a card.
private func acceptTask(_ providers: [NSItemProvider], id: String,
                        action: @escaping @MainActor () -> Void) -> Bool {
    guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
    _ = provider.loadObject(ofClass: NSString.self) { object, error in
        guard error == nil, let value = object as? String, value == id else { return }
        Task { @MainActor in action() }
    }
    return true
}
