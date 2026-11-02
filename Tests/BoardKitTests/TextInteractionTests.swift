import AppKit
import SwiftUI
import XCTest
@testable import BoardKit
@testable import BoardUI

@MainActor
final class TextInteractionTests: XCTestCase {
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    }

    private func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
    }

    private func panel<V: View>(_ view: V) -> (NSPanel, NSHostingView<V>) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let panel = KeyPanel(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 500),
                             styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.makeKeyAndOrderFront(nil)
        settle()
        host.layoutSubtreeIfNeeded()
        return (panel, host)
    }

    private func command(_ character: String, keyCode: UInt16, in window: NSWindow,
                         modifiers: NSEvent.ModifierFlags = .command) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                    characters: character, charactersIgnoringModifiers: character,
                                    isARepeat: false, keyCode: keyCode)!
        NSApp.sendEvent(event)
        settle()
    }

    func testEditingShortcutsRouteToNativeTextControls() throws {
        let originalMenu = NSApplication.shared.mainMenu
        let clipboard = NSPasteboard.general
        let originalItems = (clipboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            NSApp.mainMenu = originalMenu
            clipboard.clearContents()
            let items = originalItems.map { representations in
                let item = NSPasteboardItem()
                for (type, data) in representations { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { clipboard.writeObjects(items) }
        }
        NSApp.mainMenu = BoardApplicationMenu.makeMainMenu()
        let (window, _) = panel(Text("native responder chain"))
        defer { window.close() }
        let editor = NSTextView(frame: window.contentView!.bounds)
        editor.isRichText = false; editor.allowsUndo = true
        window.contentView = editor; window.makeFirstResponder(editor)
        clipboard.clearContents(); clipboard.setString("中文\nsecond line 🧪", forType: .string)
        command("v", keyCode: 9, in: window)
        XCTAssertEqual(editor.string, "中文\nsecond line 🧪")
        command("a", keyCode: 0, in: window)
        XCTAssertEqual(editor.selectedRange().length, editor.string.utf16.count)
        command("c", keyCode: 8, in: window)
        XCTAssertEqual(clipboard.string(forType: .string), editor.string)
        command("x", keyCode: 7, in: window)
        XCTAssertEqual(editor.string, "")
        command("z", keyCode: 6, in: window)
        XCTAssertEqual(editor.string, "中文\nsecond line 🧪")
        command("z", keyCode: 6, in: window, modifiers: [.command, .shift])
        XCTAssertEqual(editor.string, "")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        window.contentView = field; window.makeFirstResponder(field)
        clipboard.clearContents(); clipboard.setString("标题 🧪", forType: .string)
        command("v", keyCode: 9, in: window)
        XCTAssertEqual(field.stringValue, "标题 🧪")
        command("a", keyCode: 0, in: window)
        command("x", keyCode: 7, in: window)
        XCTAssertEqual(field.stringValue, "")
        command("z", keyCode: 6, in: window)
        XCTAssertEqual(field.stringValue, "标题 🧪")
    }

    func testComposerSupportsUndoAndKeepsItsDraftInSync() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let board = BoardStore(directory: folder); board.bootstrap()
        let workspace = fixtureWorkspace(directory: folder)
        let (window, host) = panel(AgentWorkspaceView(dragging: .constant(nil))
            .environmentObject(board).environmentObject(workspace))
        defer { window.close() }
        let editor = try XCTUnwrap(descendants(host, of: PlaceholderTextView.self).first)
        XCTAssertTrue(editor.allowsUndo, "Task instructions must support native Undo/Redo")
        window.makeFirstResponder(editor)
        editor.insertText("第一行\nsecond line 🧪", replacementRange: NSRange(location: NSNotFound, length: 0))
        settle()
        XCTAssertEqual(workspace.draft.instruction, editor.string)
        XCTAssertTrue(editor.undoManager?.canUndo == true)
        editor.undoManager?.undo(); settle()
        XCTAssertEqual(editor.string, "")
        XCTAssertEqual(workspace.draft.instruction, "")
        editor.undoManager?.redo(); settle()
        XCTAssertEqual(workspace.draft.instruction, "第一行\nsecond line 🧪")
    }

    func testComposerKeepsFocusBeforeFirstKeystrokeDuringWorkspaceUpdates() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let board = BoardStore(directory: folder); board.bootstrap()
        let workspace = fixtureWorkspace(directory: folder)
        let (window, host) = panel(AgentWorkspaceView(dragging: .constant(nil))
            .environmentObject(board).environmentObject(workspace))
        defer { window.close() }
        let editor = try XCTUnwrap(descendants(host, of: PlaceholderTextView.self).first)
        window.makeFirstResponder(editor); settle()
        workspace.updateDraft { $0.taskIDs = ["synthetic-task"] }; settle()
        XCTAssertTrue(window.firstResponder === editor, "Workspace refresh must not steal input focus")
    }

    func testInputMethodSurvivesUnrelatedWorkspaceRefreshAndCommitsChinese() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let board = BoardStore(directory: folder); board.bootstrap()
        let workspace = fixtureWorkspace(directory: folder)
        let (window, host) = panel(AgentWorkspaceView(dragging: .constant(nil))
            .environmentObject(board).environmentObject(workspace))
        defer { window.close() }
        let editor = try XCTUnwrap(descendants(host, of: PlaceholderTextView.self).first)
        window.makeFirstResponder(editor)
        editor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        workspace.updateDraft { $0.taskIDs = ["synthetic-task"] }; settle()
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(editor.string, "zhong")
        editor.insertText("中", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertEqual(workspace.draft.instruction, "中")
    }

    func testSwitchingAgentsCannotUndoIntoAnotherAgentsDraft() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let board = BoardStore(directory: folder); board.bootstrap()
        let workspace = fixtureWorkspace(directory: folder)
        let firstID = workspace.selectedID
        let (window, host) = panel(AgentWorkspaceView(dragging: .constant(nil))
            .environmentObject(board).environmentObject(workspace))
        defer { window.close() }
        var editor = try XCTUnwrap(descendants(host, of: PlaceholderTextView.self).first)
        window.makeFirstResponder(editor)
        editor.insertText("第一个角色的草稿", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
        workspace.select(workspace.agents[1].id); settle()
        editor = try XCTUnwrap(descendants(host, of: PlaceholderTextView.self).first)
        XCTAssertEqual(editor.string, "")
        window.makeFirstResponder(editor)
        editor.insertText("第二个角色的草稿", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
        editor.undoManager?.undo(); settle()
        XCTAssertEqual(workspace.draft.instruction, "")
        XCTAssertEqual(workspace.drafts[firstID]?.instruction, "第一个角色的草稿")
        workspace.select(firstID); settle()
        editor = try XCTUnwrap(descendants(host, of: PlaceholderTextView.self).first)
        XCTAssertEqual(editor.string, "第一个角色的草稿")
        XCTAssertFalse(editor.undoManager?.canUndo == true)
        XCTAssertEqual(fixtureWorkspace(directory: folder).draft.instruction, "第一个角色的草稿")
    }

    func testCollapsingDetailPreservesEditedNotes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let board = BoardStore(directory: folder); board.bootstrap()
        board.addTask(title: "任务", priority: .mid, status: .today)
        let task = try XCTUnwrap(board.board.todayTasks.first)
        var presented = true
        let detail = TaskDetailSheet(task: task,
            isPresented: Binding(get: { presented }, set: { presented = $0 })).environmentObject(board)
        let (window, host) = panel(AnyView(detail))
        defer { window.close() }
        let editor = try XCTUnwrap(descendants(host, of: NSTextView.self).first { !$0.isFieldEditor })
        window.makeFirstResponder(editor)
        editor.insertText("收起时保留\n中文 🧪", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
        host.rootView = AnyView(Text("collapsed")); settle()
        XCTAssertEqual(board.board.task(withID: task.id)?.notes, "收起时保留\n中文 🧪")
        XCTAssertEqual(board.board.task(withID: task.id)?.status, .today)
    }
}
