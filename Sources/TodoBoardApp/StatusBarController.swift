import AppKit
import BoardKit
import BoardUI
import Combine

/// 菜单栏入口：保底的显示/隐藏开关 + 快捷操作
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private weak var panelController: PanelController?
    private weak var store: BoardStore?
    private var cancellables = Set<AnyCancellable>()

    init(panelController: PanelController, store: BoardStore) {
        self.panelController = panelController
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "今日看板")
        }
        rebuildMenu()

    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first?.title = panelController?.expanded == true ? "收起看板" : "展开看板"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let toggleItem = NSMenuItem(
            title: (panelController?.expanded == true) ? "收起看板" : "展开看板",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let dataItem = NSMenuItem(title: "打开数据文件夹", action: #selector(openDataFolder), keyEquivalent: "")
        dataItem.target = self
        menu.addItem(dataItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出看板", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func togglePanel() {
        panelController?.toggle()
    }

    @objc private func openDataFolder() {
        if let store {
            NSWorkspace.shared.open(store.directory)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
