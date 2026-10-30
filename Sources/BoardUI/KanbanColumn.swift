import AppKit
import BoardKit
import SwiftUI
import UniformTypeIdentifiers

struct KanbanColumn: View {
    @EnvironmentObject var store: BoardStore
    let status: TaskStatus
    @Binding var dragging: String?
    @Binding var editingTaskID: String?
    @State private var highlighted: String?
    @State private var adding = false
    @State private var title = ""
    @FocusState private var inputFocused: Bool
    private var tasks: [BoardTask] { store.board.tasks(in: status) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(status.label).font(.system(size: 17, weight: .semibold)).foregroundStyle(BoardPalette.color(status))
                Spacer()
                Text("\(tasks.count)").font(.system(size: 13, design: .monospaced)).foregroundStyle(BoardPalette.muted)
            }
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    if status == .backlog {
                        ForEach(store.board.backlogDays, id: \.self) { day in
                            HStack {
                                Text(day == ISO.dayToday() ? "今天 · \(day)" : day)
                                Spacer()
                                Text("\(tasks.filter { $0.arrivalDay == day }.count)")
                            }
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(BoardPalette.muted).padding(.top, 10).padding(.bottom, 6)
                            ForEach(tasks.filter { $0.arrivalDay == day }) { task in card(task) }
                        }
                    } else {
                        ForEach(tasks) { task in card(task) }
                    }
                    insertionLine("end")
                    composer
                    Color.clear.frame(minHeight: 60)
                }
                .padding(4)
                .frame(maxWidth: .infinity, minHeight: 440, alignment: .topLeading)
                .contentShape(Rectangle())
                .onDrop(of: [boardTaskType], delegate: CardDropDelegate(status: status, beforeID: nil, store: store, dragging: $dragging, highlighted: $highlighted))
            }
            .padding(.top, 12)
            .background(highlighted != nil ? Color.white.opacity(0.025) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func card(_ task: BoardTask) -> some View {
        VStack(spacing: 0) {
            insertionLine(task.id)
            KanbanCard(task: task, dragging: $dragging, editingTaskID: $editingTaskID)
        }
        .contentShape(Rectangle())
        .onDrop(of: [boardTaskType], delegate: CardDropDelegate(status: status, beforeID: task.id, store: store, dragging: $dragging, highlighted: $highlighted))
    }

    private func insertionLine(_ id: String) -> some View {
        RoundedRectangle(cornerRadius: 1).fill(highlighted == id ? BoardPalette.violet : .clear)
            .frame(height: 2).padding(.vertical, 4)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if adding {
                TextField("写下这件事…", text: $title, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(2...5).font(.system(size: 13))
                    .focused($inputFocused).padding(12)
                    .background(BoardPalette.violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(BoardPalette.violet))
                    .onSubmit(addTask)
                    .accessibilityLabel("\(status.label)新任务标题")
                HStack {
                    Button("取消") { adding = false; title = "" }
                    Spacer()
                    Button("添加 +", action: addTask).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.font(.system(size: 11))
            } else {
                Button {
                    adding = true
                    inputFocused = true
                } label: {
                    HStack { Text("添加卡片"); Image(systemName: "plus"); Spacer() }
                        .font(.system(size: 12)).foregroundStyle(BoardPalette.muted).padding(.vertical, 10).padding(.horizontal, 8)
                }.buttonStyle(.plain).accessibilityLabel("在\(status.label)添加卡片")
            }
        }
    }
    private func addTask() {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        store.addTask(title: value, priority: .mid, status: status)
        title = ""; adding = false
    }
}
