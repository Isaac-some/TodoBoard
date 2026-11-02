import AppKit
import BoardKit
import SwiftUI

// MARK: - 任务详情编辑

public struct TaskDetailSheet: View {
    @EnvironmentObject var store: BoardStore
    let task: BoardTask
    @Binding var isPresented: Bool

    @State private var title: String = ""
    @State private var priority: TaskPriority = .mid
    @State private var status: TaskStatus = .today
    @State private var tagsText: String = ""
    @State private var notes: String = ""
    @State private var finished = false
    private var hasTitle: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.6).onTapGesture { saveAndClose() }
            detail.frame(width: 500).padding(20)
        }
        .onExitCommand { saveAndClose() }
        .onDisappear {
            // Collapsing the panel destroys this view too. Preserve the edit
            // just as closing the detail does, without resurrecting discarded tasks.
            if !finished { saveAndClose() }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("任务详情")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    saveAndClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("保存并关闭")
            }

            TextField("标题", text: $title)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("任务标题")
            if !hasTitle {
                Text("请填写任务标题").font(.caption).foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Picker("优先级", selection: $priority) {
                    Text("高").tag(TaskPriority.high)
                    Text("中").tag(TaskPriority.mid)
                    Text("低").tag(TaskPriority.low)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Picker("所在", selection: $status) {
                    ForEach(TaskStatus.workflow, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }

            TextField("标签（空格分隔）", text: $tagsText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("任务标签")

            VStack(alignment: .leading, spacing: 4) {
                Text("备注与来源")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                TextEditor(text: $notes)
                    .accessibilityLabel("任务备注")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 110)
                    .scrollContentBackground(.hidden)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.1))
                    )
            }

            if !task.sourceRefs.isEmpty {
                Text("资料引用").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(task.sourceRefs, id: \.id) { ref in
                            Text(ref.title).font(.caption.bold())
                            Text(ref.uri).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            if let time = ref.observedAt { Text("原始记录：" + time).font(.caption2) }
                            if let locator = ref.locator { Text(locator).font(.caption).textSelection(.enabled) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 90)
            }
            if let result = task.execution, result.state != .none {
                Text("执行：" + result.state.rawValue + " · 等待人工验收").font(.caption.bold())
                ScrollView {
                    VStack(alignment: .leading) {
                        Text(result.summary ?? "尚无结果摘要").textSelection(.enabled)
                        ForEach(result.evidence, id: \.self) { Text($0).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.font(.caption).frame(maxHeight: 100)
            }
            HStack {
                Button(role: .destructive) {
                    finished = true
                    store.deleteTask(taskID: task.id)
                    isPresented = false
                } label: {
                    Label("丢弃", systemImage: "trash")
                        .font(.system(size: 12))
                }
                .controlSize(.small)
                Spacer()
                if task.status == .done {
                    Button("撤销完成") { saveAndClose(status: .today) }
                        .controlSize(.small)
                        .disabled(!hasTitle)
                } else {
                    Button("完成") { saveAndClose(status: .done) }
                        .controlSize(.small)
                        .disabled(!hasTitle)
                }
                Button("保存") { saveAndClose() }
                    .controlSize(.small)
                    .disabled(!hasTitle)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(14)
        .background(BoardPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 12)
        .onAppear {
            title = task.title
            priority = task.priority
            status = task.status
            tagsText = task.tags.joined(separator: " ")
            notes = task.notes
        }
    }

    private func saveAndClose(status overrideStatus: TaskStatus? = nil) {
        guard hasTitle, var updated = store.board.task(withID: task.id) else { return }
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.priority = priority
        updated.notes = notes
        updated.tags = tagsText
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "，" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let destination = overrideStatus ?? status
        if destination != updated.status {
            store.updateTask(updated)
            store.setStatus(taskID: task.id, destination)
        } else {
            store.updateTask(updated)
        }
        finished = true
        isPresented = false
    }
}
