import Foundation

// MARK: - 枚举

public enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case high, mid, low

    public var label: String {
        switch self {
        case .high: return "高"
        case .mid: return "中"
        case .low: return "低"
        }
    }

    /// 未知值兜底：外部（AI agent）写入的字符串不在枚举内时使用
    public static func fallback(for raw: String?) -> TaskPriority {
        switch raw {
        case "high": return .high
        case "mid": return .mid
        case "low": return .low
        default: return .mid
        }
    }
}

public enum TaskStatus: String, Codable, Sendable {
    case today, backlog, doing, done, trash

    /// 未知值兜底：按 agent 契约，无法识别的状态一律按积压处理（不进入今日，由人来决策）
    public var label: String {
        switch self {
        case .backlog: return "候选"
        case .today: return "待办"
        case .doing: return "进行中"
        case .done: return "已完成"
        case .trash: return "垃圾桶"
        }
    }

    public static let workflow: [TaskStatus] = [.backlog, .today, .doing, .done]

    public static func fallback(for raw: String?) -> TaskStatus {
        switch raw {
        case "today": return .today
        case "backlog": return .backlog
        case "doing": return .doing
        case "trash": return .trash
        case "done": return .done
        default: return .backlog
        }
    }
}

/// A pointer to material retained by the background pipeline. The board keeps
/// provenance, never a second copy of the source body.
public struct TaskSourceReference: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var kind: String
    public var title: String
    public var uri: String
    public var observedAt: String?
    public var contentHash: String?
    public var locator: String?

    public init(id: String = UUID().uuidString, kind: String, title: String,
                uri: String, observedAt: String? = nil,
                contentHash: String? = nil, locator: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.uri = uri
        self.observedAt = observedAt; self.contentHash = contentHash; self.locator = locator
    }
}

public enum ExecutionState: String, Codable, Sendable {
    case none, queued, running, needsInput, result, failed
}

public struct TaskExecutionRecord: Codable, Equatable, Hashable, Sendable {
    public var state: ExecutionState
    public var agentID: String?
    public var adapter: String?
    public var summary: String?
    public var evidence: [String]
    public var updatedAt: String

    public init(state: ExecutionState = .none, agentID: String? = nil,
                adapter: String? = nil, summary: String? = nil,
                evidence: [String] = [], updatedAt: String = ISO.isoNow()) {
        self.state = state; self.agentID = agentID; self.adapter = adapter
        self.summary = summary; self.evidence = evidence; self.updatedAt = updatedAt
    }
}

// MARK: - 任务

public struct BoardTask: Codable, Identifiable, Equatable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var priority: TaskPriority
    public var status: TaskStatus
    public var tags: [String]
    /// Markdown 自由文本，给 AI agent 的上下文（仓库路径、验收标准、链接等）
    public var notes: String
    /// 所在状态组内的排序，0 起，小在前。由 app 维护，agent 不应改动
    public var order: Int
    /// ISO8601
    public var createdAt: String
    /// ISO8601，未完成为 nil
    public var doneAt: String?
    /// 后台资料位置；卡片不复制会议、对话或文档正文。
    public var sourceRefs: [TaskSourceReference]
    /// Agent 回传结果。queued/result 不等于用户已完成。
    public var execution: TaskExecutionRecord?

    public init(
        id: String = BoardTask.newID(),
        title: String,
        priority: TaskPriority = .mid,
        status: TaskStatus = .backlog,
        tags: [String] = [],
        notes: String = "",
        order: Int = 0,
        createdAt: String = ISO.isoNow(),
        doneAt: String? = nil,
        sourceRefs: [TaskSourceReference] = [],
        execution: TaskExecutionRecord? = nil
    ) {
        self.id = id
        self.title = title
        self.priority = priority
        self.status = status
        self.tags = tags
        self.notes = notes
        self.order = order
        self.createdAt = createdAt
        self.doneAt = status == .done ? (doneAt ?? ISO.isoNow()) : doneAt
        self.sourceRefs = sourceRefs
        self.execution = execution
    }

    // 容错解码：字段缺失或值非法时落到安全默认值，保证 agent 手写的 JSON 不至于让 app 崩溃
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? BoardTask.newID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "(无标题)"
        priority = TaskPriority.fallback(for: try c.decodeIfPresent(String.self, forKey: .priority))
        status = TaskStatus.fallback(for: try c.decodeIfPresent(String.self, forKey: .status))
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ISO.isoNow()
        doneAt = try c.decodeIfPresent(String.self, forKey: .doneAt)
        sourceRefs = try c.decodeIfPresent([TaskSourceReference].self, forKey: .sourceRefs) ?? []
        execution = try c.decodeIfPresent(TaskExecutionRecord.self, forKey: .execution)
        if status == .done && doneAt == nil {
            doneAt = ISO.isoNow()
        }
        if status != .done && status != .trash {
            doneAt = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(priority, forKey: .priority)
        try c.encode(status, forKey: .status)
        try c.encode(tags, forKey: .tags)
        try c.encode(notes, forKey: .notes)
        try c.encode(order, forKey: .order)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(doneAt, forKey: .doneAt)
        try c.encode(sourceRefs, forKey: .sourceRefs)
        try c.encodeIfPresent(execution, forKey: .execution)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, priority, status, tags, notes, order, createdAt, doneAt, sourceRefs, execution
    }

    /// 按来源时间的本地日期分组；非法时间单独分组，不伪装成今天。
    public var arrivalDay: String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = ISO.parse(createdAt) ?? parser.date(from: createdAt) else { return "日期未知" }
        return ISO.dayString(date)
    }

    /// 生成 agent 兼容格式的短 id：t-xxxxxx（小写字母数字）
    public static func newID() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        var s = ""
        for _ in 0..<6 { s.append(chars.randomElement()!) }
        return "t-\(s)"
    }
}

// MARK: - 看板数据（tasks.json 根结构）

public struct BoardData: Codable, Equatable, Sendable {
    public var version: Int
    /// ISO8601，最后一次写入时间
    public var updatedAt: String
    /// 当前展示日期，yyyy-MM-dd（本地时区）。跨天不改变任务状态
    public var day: String
    public var tasks: [BoardTask]

    public init(version: Int = 1, updatedAt: String = ISO.isoNow(), day: String = ISO.dayToday(), tasks: [BoardTask] = []) {
        self.version = version
        self.updatedAt = updatedAt
        self.day = day
        self.tasks = tasks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ISO.isoNow()
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ISO.dayToday()
        tasks = try c.decodeIfPresent([BoardTask].self, forKey: .tasks) ?? []
    }

    // MARK: 派生视图

    public var todayTasks: [BoardTask] { tasks.filter { $0.status == .today }.sorted { $0.order < $1.order } }
    public var backlogTasks: [BoardTask] { tasks.filter { $0.status == .backlog }.sorted { $0.order < $1.order } }
    public var doingTasks: [BoardTask] { tasks(in: .doing) }
    public var doneTasks: [BoardTask] { tasks(in: .done) }
    public var trashTasks: [BoardTask] { tasks(in: .trash) }
    public func tasks(in status: TaskStatus) -> [BoardTask] {
        tasks.filter { $0.status == status }.sorted { $0.order < $1.order }
    }
    public var backlogDays: [String] { Array(Set(backlogTasks.map(\.arrivalDay))).sorted(by: >) }


    /// 状态组内重新编号 order（0..n），并按 今日 → 积压 → 完成 排列主数组
    public mutating func renumberAndSort() {
        var out: [BoardTask] = []
        for group in [TaskStatus.backlog, .today, .doing, .done, .trash] {
            var arr = tasks.filter { $0.status == group }.sorted { $0.order < $1.order }
            for i in arr.indices { arr[i].order = i }
            out.append(contentsOf: arr)
        }
        tasks = out
    }

    public func task(withID id: String) -> BoardTask? { tasks.first { $0.id == id } }
}

// MARK: - 时间工具

public enum ISO {
    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f
    }()

    public static func isoNow() -> String { isoFormatter.string(from: Date()) }

    public static func dayToday() -> String { dayFormatter.string(from: Date()) }
    public static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }

    public static func parse(_ iso: String) -> Date? { isoFormatter.date(from: iso) }

    /// "14:32"（解析失败返回原串）
    public static func shortTime(_ iso: String?) -> String {
        guard let iso, let d = parse(iso) else { return "" }
        return timeFormatter.string(from: d)
    }

    /// "周五"
    public static func weekdayCN(ofDay day: String) -> String {
        guard let d = dayFormatter.date(from: day) else { return "" }
        return weekdayFormatter.string(from: d)
    }
}
