import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - 全局快捷键（⌘⇧T）

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private final class Box {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
    }
    private var box: Box?

    convenience init(keyCode: UInt32 = UInt32(kVK_ANSI_T),
                     modifiers: UInt32 = UInt32(cmdKey | shiftKey),
                     action: @escaping () -> Void) {
        self.init()
        register(keyCode: keyCode, modifiers: modifiers, action: action)
    }

    /// keyCode: kVK_ANSI_T；modifiers: cmdKey|shiftKey
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_T),
                  modifiers: UInt32 = UInt32(cmdKey | shiftKey),
                  action: @escaping () -> Void) {
        let box = Box(action)
        self.box = box

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            let box = Unmanaged<Box>.fromOpaque(userData).takeUnretainedValue()
            // 回到主线程执行
            DispatchQueue.main.async { box.action() }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &spec,
            Unmanaged.passRetained(box).toOpaque(),
            &eventHandler
        )

        let id = EventHotKeyID(signature: OSType(0x5442_4F44), id: 1) // 'TBOD'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

// MARK: - 开机自启（SMAppService，macOS 13+）

enum AutoLauncher {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
