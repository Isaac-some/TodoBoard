import XCTest
@testable import BoardKit

@MainActor
final class BoardKitTests: XCTestCase {
    var dir: URL!
    var store: BoardStore!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("todoboard-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = BoardStore(directory: dir)
        store.bootstrap()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: 基础

    func testBootstrapCreatesFiles() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.tasksFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.readmeFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.mirrorFileURL.path))
        let readme = try! String(contentsOf: store.readmeFileURL, encoding: .utf8)
        XCTAssertTrue(readme.contains("backlog"))
        XCTAssertTrue(readme.contains("tasks.json"))
    }

    func testSaveLoadRoundtripAndBackup() {
        store.addTask(title: "任务A", priority: .high, status: .today, tags: ["工作"])
        store.addTask(title: "任务B", priority: .low, status: .backlog)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backupFileURL.path))

        let raw = try! String(contentsOf: store.tasksFileURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("任务A"))

        let store2 = BoardStore(directory: dir)
        store2.bootstrap()
        XCTAssertEqual(store2.board.tasks.count, 2)
        XCTAssertEqual(store2.board.todayTasks.first?.title, "任务A")
    }

    func testOrderRenumberOnPersist() {
        store.addTask(title: "A", priority: .mid, status: .today)
        store.addTask(title: "B", priority: .mid, status: .today)
        store.addTask(title: "C", priority: .mid, status: .backlog)
        XCTAssertEqual(store.board.todayTasks.map(\.title), ["A", "B"])
        XCTAssertEqual(store.board.todayTasks.map(\.order), [0, 1])
        XCTAssertEqual(store.board.backlogTasks.map(\.order), [0])
    }

    // MARK: 外部（agent）写入

    func testExternalAppendAdoptedOnReload() throws {
        store.addTask(title: "既有任务", priority: .mid, status: .today)

        // 模拟 agent：读文件 → append → 写回
        let raw = try String(contentsOf: store.tasksFileURL, encoding: .utf8)
        var obj = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
        var tasks = obj["tasks"] as! [[String: Any]]
        tasks.append([
            "id": "t-agent1",
            "title": "agent 新增任务",
            "priority": "high",
            "status": "backlog",
            "tags": ["ai"],
            "notes": "来自 codex",
            "createdAt": ISO.isoNow(),
        ] as [String: Any])
        obj["tasks"] = tasks
        let data = try JSONSerialization.data(withJSONObject: obj)
        try data.write(to: store.tasksFileURL)

        store.reloadFromDisk(force: true)
        XCTAssertEqual(store.board.backlogTasks.first?.title, "agent 新增任务")
        XCTAssertEqual(store.board.backlogTasks.first?.id, "t-agent1")
        XCTAssertEqual(store.board.todayTasks.count, 1)
        // 镜像同步重新生成
        let mirror = try String(contentsOf: store.mirrorFileURL, encoding: .utf8)
        XCTAssertTrue(mirror.contains("agent 新增任务"))
        XCTAssertTrue(mirror.contains("候选"))
        // 外部写入被采纳后，.bak 也应刷新到包含新任务（防写坏回滚丢数据）
        let bak = try String(contentsOf: store.backupFileURL, encoding: .utf8)
        XCTAssertTrue(bak.contains("agent 新增任务"))
    }

    func testCorruptedJSONRollsBackToBackup() throws {
        store.addTask(title: "好任务", priority: .mid, status: .today)
        XCTAssertEqual(store.board.tasks.count, 1)

        // agent 写坏 JSON
        try Data("{ broken json !!!".utf8).write(to: store.tasksFileURL)

        store.reloadFromDisk(force: true)
        XCTAssertEqual(store.board.tasks.count, 1) // 从 .bak 恢复
        XCTAssertEqual(store.board.todayTasks.first?.title, "好任务")
        XCTAssertNotNil(store.banner)
        XCTAssertEqual(store.banner?.kind, .warning)
        // 主文件已被回滚修复
        let raw = try String(contentsOf: store.tasksFileURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("好任务"))
    }

    func testTolerantDecodingOfForeignFields() throws {
        let foreign = """
        {
          "version": 1,
          "updatedAt": "2026-10-24T01:00:00Z",
          "day": "2026-10-24",
          "tasks": [
            {"id":"t-x1","title":"未知优先级","priority":"urgent","status":"whenever"},
            {"id":"t-x2"}
          ]
        }
        """
        try Data(foreign.utf8).write(to: store.tasksFileURL)
        store.reloadFromDisk(force: true)
        XCTAssertEqual(store.board.tasks.count, 2)
        XCTAssertEqual(store.board.tasks[0].priority, .mid)   // 未知优先级 → 中
        XCTAssertEqual(store.board.tasks[0].status, .backlog) // 未知状态 → 积压
        XCTAssertEqual(store.board.tasks[1].title, "(无标题)")
    }

    // MARK: 交互操作

    func testToggleDoneAndUndo() {
        store.addTask(title: "A", priority: .mid, status: .today)
        let id = store.board.todayTasks[0].id
        store.toggleDone(taskID: id)
        XCTAssertEqual(store.board.doneTasks.first?.title, "A")
        XCTAssertNotNil(store.board.doneTasks.first?.doneAt)
        store.toggleDone(taskID: id) // 撤销 → 回今日
        XCTAssertEqual(store.board.todayTasks.first?.title, "A")
        XCTAssertNil(store.board.todayTasks.first?.doneAt)
    }

    func testMoveBetweenGroups() {
        store.addTask(title: "A", priority: .mid, status: .backlog)
        store.addTask(title: "B", priority: .mid, status: .today)
        store.addTask(title: "C", priority: .mid, status: .today)
        store.move(taskID: store.board.backlogTasks[0].id, to: .today, index: 0)
        XCTAssertEqual(store.board.todayTasks.map(\.title), ["A", "B", "C"])
        XCTAssertTrue(store.board.backlogTasks.isEmpty)
        // 今日内部重排：C 到最前
        store.move(taskID: store.board.todayTasks[2].id, to: .today, index: 0)
        XCTAssertEqual(store.board.todayTasks.map(\.title), ["C", "A", "B"])
    }

    func testNewDayPreservesEveryStageAndOrder() throws {
        for status in TaskStatus.workflow {
            store.addTask(title: "\(status.rawValue)-A", priority: .mid, status: status)
            store.addTask(title: "\(status.rawValue)-B", priority: .low, status: status)
        }
        let original = store.board.tasks
        store.mutate { $0.day = "2000-01-01" }
        store.checkRollover()
        XCTAssertEqual(store.board.day, ISO.dayToday())
        XCTAssertEqual(store.board.tasks, original)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: store.archiveDirectory.path).isEmpty)
        let reopened = BoardStore(directory: dir)
        reopened.bootstrap()
        XCTAssertEqual(reopened.board.tasks, original)
    }

    func testDiscardFromEveryStageAndUndoRestoresPosition() {
        for status in TaskStatus.workflow {
            store.addTask(title: "A", priority: .high, status: status)
            store.addTask(title: "B", priority: .mid, status: status)
            let original = store.board.tasks(in: status)
            store.deleteTask(taskID: original[0].id)
            XCTAssertEqual(store.board.tasks(in: status).map(\.id), [original[1].id])
            XCTAssertTrue(store.board.trashTasks.contains { $0.id == original[0].id })
            store.undoDiscard()
            XCTAssertEqual(store.board.tasks(in: status).map(\.id), original.map(\.id))
            XCTAssertNil(store.lastDiscarded)
        }
    }

    func testDoingDoneAndTrashSurviveReloadWithManualOrder() {
        store.addTask(title: "A", priority: .mid, status: .backlog)
        store.addTask(title: "B", priority: .mid, status: .backlog)
        let ids = store.board.backlogTasks.map(\.id)
        store.move(taskID: ids[0], to: .doing, index: 0)
        store.move(taskID: ids[0], to: .done, index: 0)
        store.move(taskID: ids[1], to: .done, index: 0)
        XCTAssertEqual(store.board.doneTasks.map(\.title), ["B", "A"])
        store.deleteTask(taskID: ids[0])
        let reopened = BoardStore(directory: dir)
        reopened.bootstrap()
        XCTAssertEqual(reopened.board.doneTasks.map(\.title), ["B"])
        XCTAssertEqual(reopened.board.trashTasks.map(\.title), ["A"])
    }

    func testCandidateDateGroupsAreLocalAndRetainedWhenMoving() {
        let a = BoardTask(title: "yesterday", createdAt: "2026-10-27T12:00:00+08:00")
        let b = BoardTask(title: "today", createdAt: "2026-10-28T12:00:00.123+08:00")
        let unknown = BoardTask(title: "unknown", createdAt: "invalid")
        store.mutate { $0.tasks = [a, b, unknown] }
        XCTAssertEqual(a.arrivalDay, ISO.dayString(ISO.parse(a.createdAt)!))
        XCTAssertNotEqual(a.arrivalDay, b.arrivalDay)
        XCTAssertEqual(unknown.arrivalDay, "日期未知")
        XCTAssertEqual(Set(store.board.backlogDays).count, 3)
        store.move(taskID: a.id, to: .doing, index: 0)
        store.move(taskID: a.id, to: .backlog, index: 0)
        XCTAssertEqual(store.board.task(withID: a.id)?.createdAt, a.createdAt)
    }

    // MARK: 镜像

    func testMirrorContent() {
        store.addTask(title: "重要事", priority: .high, status: .today, tags: ["工作"], notes: "上下文第一行\n第二行")
        store.addTask(title: "池中事", priority: .low, status: .backlog)
        let mirror = try! String(contentsOf: store.mirrorFileURL, encoding: .utf8)
        XCTAssertTrue(mirror.contains("待办"))
        XCTAssertTrue(mirror.contains("1. **重要事** `高` `工作`"))
        XCTAssertTrue(mirror.contains("> 上下文第一行"))
        XCTAssertTrue(mirror.contains("候选"))
        XCTAssertTrue(mirror.contains("池中事"))
        XCTAssertTrue(mirror.contains("请勿手改"))
    }

    func testExternalAppendDuringSaveWindowEventuallyReloads() async throws {
        store.startWatching()
        store.addTask(title: "app task", priority: .mid, status: .today)
        var data = try JSONDecoder().decode(BoardData.self, from: Data(contentsOf: store.tasksFileURL))
        data.tasks.append(BoardTask(id: "t-watch1", title: "external candidate", status: .backlog))
        try JSONEncoder().encode(data).write(to: store.tasksFileURL, options: .atomic)
        try await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertEqual(store.board.backlogTasks.first?.id, "t-watch1")
        XCTAssertTrue(try String(contentsOf: store.mirrorFileURL).contains("external candidate"))
    }

    func testSelfWriteSuppression() {
        store.addTask(title: "A", priority: .mid, status: .today)
        // app 自己刚写完（静默窗口内），外部重载应被跳过，不产生 banner
        try? Data("garbage".utf8).write(to: store.tasksFileURL)
        store.reloadFromDisk()
        XCTAssertEqual(store.board.tasks.count, 1)
        XCTAssertNil(store.banner)
    }
    func testStaleUISavePreservesWorkerResultsAndUnknownFields() throws {
        store.addTask(title: "Original", priority: .mid, status: .today)
        var edited = store.board.tasks[0]
        var raw = try JSONSerialization.jsonObject(with: Data(contentsOf: store.tasksFileURL)) as! [String: Any]
        var tasks = raw["tasks"] as! [[String: Any]]
        tasks[0]["execution"] = ["state": "result", "summary": "Background result", "evidence": ["synthetic evidence"], "updatedAt": ISO.isoNow()]
        tasks[0]["providerExtension"] = "keep"
        let another = BoardTask(title: "Worker candidate", status: .backlog)
        tasks.append(try JSONSerialization.jsonObject(with: JSONEncoder().encode(another)) as! [String: Any])
        raw["tasks"] = tasks; raw["rootExtension"] = true
        try JSONSerialization.data(withJSONObject: raw).write(to: store.tasksFileURL, options: .atomic)
        edited.notes = "UI edit while worker wrote"
        store.updateTask(edited)
        let persisted = try JSONSerialization.jsonObject(with: Data(contentsOf: store.tasksFileURL)) as! [String: Any]
        let merged = persisted["tasks"] as! [[String: Any]]
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?["providerExtension"] as? String, "keep")
        XCTAssertEqual((merged.first?["execution"] as? [String: Any])?["summary"] as? String, "Background result")
        XCTAssertEqual(merged.first?["notes"] as? String, edited.notes)
        XCTAssertEqual(persisted["rootExtension"] as? Bool, true)
    }

}
