import AppKit
import Darwin

// One lock for both installed and development builds. It is released by the OS
// on exit, including a force quit; a stale file never prevents the next launch.
let instanceDirectory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TODOBOARD_DATA_DIR"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TodoBoard-OpenSource").path)
try FileManager.default.createDirectory(at: instanceDirectory, withIntermediateDirectories: true)
let instanceFD = open(instanceDirectory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
guard instanceFD >= 0 else { fatalError("无法创建 TodoBoard 单实例锁") }
if flock(instanceFD, LOCK_EX | LOCK_NB) != 0 {
    close(instanceFD)
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("io.github.isaac-some.todoboard.show-existing"), object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

// SPM 可执行入口：手动装配 NSApplication（打包成 .app 见 scripts/build-app.sh）
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 无 Dock 图标，仅菜单栏 + 面板
app.run()
