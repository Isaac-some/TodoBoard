import AppKit
import BoardKit
import SwiftUI

struct KanbanCard: View {
    @EnvironmentObject var store: BoardStore
    let task: BoardTask
    @Binding var dragging: String?
    @Binding var editingTaskID: String?
    @State private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.title).font(.system(size: 14)).lineSpacing(4)
                .foregroundStyle(BoardPalette.text).fixedSize(horizontal: false, vertical: true)
            if !task.tags.isEmpty || task.priority == .high || !task.notes.isEmpty {
                HStack(spacing: 6) {
                    if task.priority == .high {
                        Text("优先").foregroundStyle(Color.orange.opacity(0.9))
                    }
                    ForEach(Array(task.tags.prefix(2).enumerated()), id: \.offset) { _, tag in
                        Text(tag).foregroundStyle(BoardPalette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !task.notes.isEmpty { Image(systemName: "text.alignleft").foregroundStyle(BoardPalette.muted) }
                }.font(.system(size: 10))
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Color(white: 0.18) : BoardPalette.card, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(hovering ? Color.white.opacity(0.25) : Color.white.opacity(0.13)))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture { editingTaskID = task.id }
        .onHover { hovering = $0 }
        .onDrag {
            dragging = task.id
            let provider = NSItemProvider(object: task.id as NSString)
            return provider
        }
        .contextMenu {
            Button("编辑") { editingTaskID = task.id }
            ForEach(TaskStatus.workflow.filter { $0 != task.status }, id: \.self) { status in
                Button("移到\(status.label)") { store.setStatus(taskID: task.id, status) }
            }
            Divider()
            Button("丢到垃圾桶", role: .destructive) { store.deleteTask(taskID: task.id) }
        }
        .accessibilityLabel("\(task.status.label)：\(task.title)")
        .help("\(task.title)\n点击编辑 · 拖动改变阶段\(task.notes.isEmpty ? "" : "\n" + task.notes)")
    }
}
