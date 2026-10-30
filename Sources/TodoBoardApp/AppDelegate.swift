import AppKit
import BoardKit
import BoardUI
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: BoardStore!
    var panelController: PanelController!
    var statusBar: StatusBarController!
    var hotKey: HotKeyManager!
    var rolloverTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dataPath = ProcessInfo.processInfo.environment["TODOBOARD_DATA_DIR"]
            ?? ProcessInfo.processInfo.environment["TODOBOARD_TEST_DATA"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TodoBoard-OpenSource").path
        let dir = URL(fileURLWithPath: dataPath, isDirectory: true)
        let settings = AppSettings.shared
        store = BoardStore(directory: dir)
        store.bootstrap()
        store.startWatching()

        panelController = PanelController(store: store, settings: settings)
        panelController.showPanel()
        #if DEBUG
        if ProcessInfo.processInfo.environment["TODOBOARD_TEST_DATA"] != nil {
            panelController.expand()
        }
        #endif

        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showExistingBoard), name: Notification.Name("io.github.isaac-some.todoboard.show-existing"), object: nil)
        statusBar = StatusBarController(panelController: panelController, store: store)
        hotKey = HotKeyManager { [weak self] in
            self?.panelController.toggle()
        }

        // 每分钟更新展示日期，不改变任务状态
        rolloverTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.store.checkRollover()
            }
        }
    }

    @MainActor @objc private func showExistingBoard() { panelController?.expand() }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.agentWorkspace.cancelPendingDeliveries()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
