import Foundation

/// 生成 board.md（给 AI agent 与人直接阅读的镜像，由 app 在每次数据变化后重写）
public enum MirrorWriter {
    public static func boardMarkdown(_ board: BoardData) -> String {
        var lines: [String] = []
        lines.append("<!--")
        lines.append("  此文件由 TodoBoard app 自动生成，请勿手改。")
        lines.append("  AI agent 读取看板请用本文件；修改数据请编辑 tasks.json（规则见同目录 README.md）。")
        lines.append("-->")
        lines.append("")
        lines.append("# TodoBoard · \(board.day) 周\(weekdayShort(board.day))")
        lines.append("")

        for status in TaskStatus.workflow {
            lines.append("## \(status.label)（从上到下即手动顺序）")
            let tasks = board.tasks(in: status)
            if tasks.isEmpty { lines.append("_（空）_") }
            if status == .backlog {
                for day in board.backlogDays {
                    lines.append("### \(day)")
                    for task in tasks.filter({ $0.arrivalDay == day }) {
                        lines.append("- \(rowTitle(task))")
                        lines.append(contentsOf: notesLines(task, indent: "  "))
                    }
                }
            } else {
                for (index, task) in tasks.enumerated() {
                    lines.append("\(index + 1). \(rowTitle(task))")
                    lines.append(contentsOf: notesLines(task, indent: "   "))
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func rowTitle(_ t: BoardTask) -> String {
        "**\(escape(t.title))** \(meta(t))"
    }

    private static func meta(_ t: BoardTask) -> String {
        var parts: [String] = ["`\(t.priority.label)`"]
        for tag in t.tags where !tag.isEmpty {
            parts.append("`\(tag)`")
        }
        return parts.joined(separator: " ")
    }

    private static func notesLines(_ t: BoardTask, indent: String) -> [String] {
        guard !t.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let noteLines = t.notes
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        return ([indent + "> " + noteLines[0]] + noteLines.dropFirst().map { indent + "> " + $0 })
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|")
    }

    /// 周几的短中文（"五"），失败返回空
    private static func weekdayShort(_ day: String) -> String {
        let full = ISO.weekdayCN(ofDay: day) // "星期五" / "周五"
        guard full.count >= 2 else { return full }
        return String(full.suffix(1))
    }
}

/// 生成 archive/<day>.md（每日完成归档）
public enum Archiver {
    public static func archiveMarkdown(day: String, doneTasks: [BoardTask]) -> String {
        var lines: [String] = []
        lines.append("<!-- TodoBoard 每日归档，由 app 生成。AI agent 可回读用户当天完成了什么。 -->")
        lines.append("")
        lines.append("# \(day) 完成清单")
        if doneTasks.isEmpty {
            lines.append("_当天无已完成任务_")
        } else {
            for t in doneTasks {
                let time = ISO.shortTime(t.doneAt)
                let tags = t.tags.filter { !$0.isEmpty }.map { "`\($0)`" }.joined(separator: " ")
                var line = "- **\(t.title)** `\(t.priority.label)`"
                if !tags.isEmpty { line += " \(tags)" }
                if !time.isEmpty { line += "（\(time) 完成）" }
                lines.append(line)
                let note = t.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty {
                    lines.append("  > \(note.replacingOccurrences(of: "\n", with: " "))")
                }
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
