import Combine
import Foundation
import Dispatch
import Darwin

/// 面板顶部横幅消息（如外部数据损坏已恢复）
public struct BannerMessage: Equatable, Sendable {
    public var text: String
    public var kind: Kind
    public enum Kind: Sendable { case warning, error }
    public init(text: String, kind: Kind = .warning) {
        self.text = text
        self.kind = kind
    }
}

/// 数据仓库：唯一真相源是 <directory>/tasks.json。
/// app 与外部（AI agent 直接改文件）双向同步：
/// - app 写入：备份 .bak → 原子写 tmp+rename → 重新生成 board.md 镜像
/// - 外部写入：DispatchSource 监听目录变化 → 防抖后重载；JSON 损坏时回滚 .bak
@MainActor
public final class BoardStore: ObservableObject {
    @Published public private(set) var board = BoardData()
    @Published public var banner: BannerMessage?
    @Published public private(set) var lastDiscarded: BoardTask?

    public let directory: URL
    public var tasksFileURL: URL { directory.appendingPathComponent("tasks.json") }
    public var backupFileURL: URL { directory.appendingPathComponent("tasks.json.bak") }
    public var mirrorFileURL: URL { directory.appendingPathComponent("board.md") }
    public var readmeFileURL: URL { directory.appendingPathComponent("README.md") }
    public var archiveDirectory: URL { directory.appendingPathComponent("archive") }

    /// app 自己保存后的短暂静默窗口，避免监听到自身写入触发无谓重载
    private var suppressReloadUntil = Date.distantPast
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var reloadDebounce: DispatchWorkItem?
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private var savedBoard = BoardData()

    private var lockURL: URL { directory.appendingPathComponent("tasks.lock") }

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: - 启动

    /// 首次运行创建目录、README、初始 tasks.json；已存在则加载
    public func bootstrap() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        writeReadme()
        if !FileManager.default.fileExists(atPath: tasksFileURL.path) {
            board = BoardData()
            persist(triggeredBySelf: false)
        } else {
            loadFromDiskAllowFallback()
        }
        checkRollover()
        writeMirror()
    }

    public func startWatching() {
        watchDirectory()
        watchFile()
    }

    // MARK: - 变更入口（app 内操作统一走这里）

    public func mutate(_ body: (inout BoardData) -> Void) {
        body(&board)
        persist()
    }

    public func addTask(title: String, priority: TaskPriority, status: TaskStatus, tags: [String] = [], notes: String = "") {
        let group = board.tasks.filter { $0.status == status }
        let task = BoardTask(
            title: title,
            priority: priority,
            status: status,
            tags: tags,
            notes: notes,
            order: group.count
        )
        board.tasks.append(task)
        persist()
    }

    public func toggleDone(taskID: String) {
        guard var t = board.task(withID: taskID) else { return }
        if t.status == .done {
            // 撤销完成 → 回到今日末尾
            t.status = .today
            t.doneAt = nil
            t.order = board.todayTasks.count
        } else {
            t.status = .done
            t.doneAt = ISO.isoNow()
            t.order = board.doneTasks.count
        }
        mutate { data in
            if let i = data.tasks.firstIndex(where: { $0.id == taskID }) {
                data.tasks[i] = t
            }
        }
    }

    public func setStatus(taskID: String, _ status: TaskStatus) {
        mutate { data in
            guard let i = data.tasks.firstIndex(where: { $0.id == taskID }) else { return }
            data.tasks[i].status = status
            if status == .done {
                data.tasks[i].doneAt = ISO.isoNow()
            } else {
                data.tasks[i].doneAt = nil
            }
            data.tasks[i].order = data.tasks.filter { $0.status == status }.count
        }
    }

    public func updateTask(_ task: BoardTask) {
        mutate { data in
            guard let i = data.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            data.tasks[i] = task
        }
    }

    public func deleteTask(taskID: String) {
        mutate { data in
            guard let i = data.tasks.firstIndex(where: { $0.id == taskID }), data.tasks[i].status != .trash else { return }
            lastDiscarded = data.tasks[i]
            data.tasks[i].status = .trash
            data.tasks[i].order = data.trashTasks.count

        }
    }

    /// 拖拽落点：把 id 移动到目标组 target 的 index 处（index 是落点在目标组内的插入位置）
    public func move(taskID: String, to target: TaskStatus, index: Int) {
        mutate { data in
            guard let existing = data.task(withID: taskID) else { return }
            var group = data.tasks
                .filter { $0.status == target && $0.id != taskID }
                .sorted { $0.order < $1.order }
            let idx = min(max(index, 0), group.count)
            group.insert(existing, at: idx)
            for (i, v) in group.enumerated() {
                guard let gi = data.tasks.firstIndex(where: { $0.id == v.id }) else { continue }
                data.tasks[gi].order = i
                if v.id == taskID {
                    data.tasks[gi].status = target
                    data.tasks[gi].doneAt = target == .done
                        ? (data.tasks[gi].doneAt ?? ISO.isoNow())
                        : nil
                }
            }
        }
    }

    /// 跨天只更新日期，候选/待办/进行中/完成都原样保留。
    public func checkRollover() {
        guard board.day != ISO.dayToday() else { return }
        board.day = ISO.dayToday()
        persist()
    }

    public func undoDiscard() {
        guard let task = lastDiscarded,
              let index = board.tasks.firstIndex(where: { $0.id == task.id && $0.status == .trash }) else { return }
        board.tasks[index] = task
        lastDiscarded = nil
        move(taskID: task.id, to: task.status, index: task.order)
    }

    // MARK: - 持久化

    private func persist(triggeredBySelf: Bool = true) {
        board.updatedAt = ISO.isoNow()
        board.renumberAndSort()
        guard let authoredData = try? encoder.encode(board),
              let authored = try? JSONSerialization.jsonObject(with: authoredData) as? [String: Any],
              let baseData = try? encoder.encode(savedBoard),
              let base = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any] else { return }
        do {
            try withCrossProcessLock {
                // Merge only fields changed by this UI against the last displayed
                // snapshot. A worker's new cards, refs and results survive stale UI.
                var latest = (try? Data(contentsOf: tasksFileURL))
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                let baseTasks = Dictionary(uniqueKeysWithValues: (base["tasks"] as? [[String: Any]] ?? []).compactMap { item in (item["id"] as? String).map { ($0, item) } })
                var diskTasks = latest["tasks"] as? [[String: Any]] ?? []
                for item in authored["tasks"] as? [[String: Any]] ?? [] {
                    guard let id = item["id"] as? String else { continue }
                    if let index = diskTasks.firstIndex(where: { $0["id"] as? String == id }) {
                        let before = baseTasks[id] ?? [:]
                        for key in Set(item.keys).union(before.keys) {
                            if !NSDictionary(dictionary: ["v": item[key] ?? NSNull()]).isEqual(to: ["v": before[key] ?? NSNull()]) {
                                diskTasks[index][key] = item[key]
                            }
                        }
                    } else { diskTasks.append(item) }
                }
                latest["tasks"] = diskTasks
                for key in ["version", "updatedAt", "day"] { latest[key] = authored[key] }
                let data = try JSONSerialization.data(withJSONObject: latest, options: [.prettyPrinted, .sortedKeys])
                let mergedBoard = try JSONDecoder().decode(BoardData.self, from: data)
                // 原子写：同目录临时文件 + rename
                let tmp = directory.appendingPathComponent(".tasks.json.tmp")
                try data.write(to: tmp)
                if FileManager.default.fileExists(atPath: tasksFileURL.path) {
                    _ = try FileManager.default.replaceItemAt(tasksFileURL, withItemAt: tmp)
                } else {
                    try FileManager.default.moveItem(at: tmp, to: tasksFileURL)
                }
                try data.write(to: backupFileURL, options: .atomic)
                board = mergedBoard; savedBoard = mergedBoard
            }
            if triggeredBySelf {
                suppressReloadUntil = Date().addingTimeInterval(1.2)
            }
            // 写入成功后备份，保证 .bak 永远是最近一版完好的数据

        } catch {
            banner = BannerMessage(text: "保存失败：\(error.localizedDescription)", kind: .error)
            return
        }
        writeMirror()
    }

    private func withCrossProcessLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileNoSuchFile) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw CocoaError(.fileLocking) }
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }

    /// 外部改写 tasks.json 后由监听器调用；force 供测试与明确需要时绕过自写静默窗口
    public func reloadFromDisk(force: Bool = false) {
        guard force || Date() >= suppressReloadUntil else {
            scheduleReload()
            return
        }
        let before = board
        loadFromDiskAllowFallback()
        if board != before {
            // 外部写入已采纳：归一化写回并刷新 .bak，
            // 防止"agent 添加后主文件被写坏"时回滚到过旧备份丢任务
            persist()
        } else {
            // 外部写入者（agent）通常只改 tasks.json，镜像由 app 兜底重新生成
            writeMirror()
        }
        checkRollover()
    }

    private func loadFromDiskAllowFallback() {
        if let data = decodeFile(tasksFileURL) {
            if data != board { board = data }; savedBoard = data
            return
        }
        // Restore only after rechecking under the writer lock.
        do {
            try withCrossProcessLock {
                if let current = decodeFile(tasksFileURL) { board = current; savedBoard = current; return }
                if let data = decodeFile(backupFileURL) {
                    if let corrupt = try? Data(contentsOf: tasksFileURL) {
                        try corrupt.write(to: directory.appendingPathComponent("tasks-corrupt-" + UUID().uuidString + ".json"), options: .atomic)
                    }
                    try Data(contentsOf: backupFileURL).write(to: tasksFileURL, options: .atomic)
                    board = data; savedBoard = data
                    banner = BannerMessage(text: "tasks.json 已从最近备份恢复，损坏文件已保留。", kind: .warning)
                }
            }
            if decodeFile(tasksFileURL) != nil { return }
        } catch { }
        // 主备都坏 → 保持内存态，明确告知
        banner = BannerMessage(
            text: "tasks.json 与备份均无法解析，已保留当前界面数据；请检查数据目录中的 tasks.json",
            kind: .error
        )
    }

    private func decodeFile(_ url: URL) -> BoardData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        guard let data = try? dec.decode(BoardData.self, from: raw) else { return nil }
        var d = data
        d.renumberAndSort()
        return d
    }

    // MARK: - 镜像与 README

    public func writeMirror() {
        let md = MirrorWriter.boardMarkdown(board)
        if (try? String(contentsOf: mirrorFileURL, encoding: .utf8)) != md {
            try? md.write(to: mirrorFileURL, atomically: true, encoding: .utf8)
        }
    }

    public func writeReadme() {
        try? ReadmeAgentContract.readmeMarkdown.write(
            to: readmeFileURL, atomically: true, encoding: .utf8
        )
    }

    public func dismissBanner() { banner = nil }

    // MARK: - 文件监听

    private func watchDirectory() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write],
            queue: DispatchQueue.global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleReload()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        dirSource = src
    }

    private func watchFile() {
        let fd = open(tasksFileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: DispatchQueue.global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleReload()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileSource = src
    }

    /// 原子写（replaceItemAt）会换 inode，旧文件源会失效。
    /// 每次重载（含被静默跳过的）后都重挂文件源，确保始终监听当前文件。
    private func scheduleReload() {
        reloadDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.reloadFromDisk()
                self?.refreshFileWatch()
            }
        }
        reloadDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.4, suppressReloadUntil.timeIntervalSinceNow + 0.05), execute: work)
    }

    private func refreshFileWatch() {
        fileSource?.cancel() // cancel 回调里 close 旧 fd
        fileSource = nil
        let fd = open(tasksFileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        attachFileSource(fd: fd)
    }

    private func attachFileSource(fd: Int32) {
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: DispatchQueue.global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleReload()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileSource = src
    }
}
