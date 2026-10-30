import AppKit
import SwiftUI
import XCTest
@testable import BoardKit
@testable import BoardUI

final class AgentEditorTests: XCTestCase {
    @MainActor func testNativeComposerLayoutAndWorkspacePreview() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BoardStore(directory: folder); store.bootstrap()
        let agents = AgentWorkspaceStore(directory: folder)
        let view = AgentWorkspaceView(dragging: .constant(nil))
            .environmentObject(store).environmentObject(agents)
            .frame(width: 1300, height: 340).padding(16)
            .background(Color(red: 0.075, green: 0.075, blue: 0.085))
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1332, height: 372), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func editors(_ view: NSView) -> [PlaceholderTextView] {
            (view as? PlaceholderTextView).map { [$0] } ?? view.subviews.flatMap(editors)
        }
        let editor = try XCTUnwrap(editors(host).first)
        XCTAssertGreaterThan(editor.bounds.width, 200)
        XCTAssertEqual(editor.textContainerInset, NSSize(width: 9, height: 9))
        XCTAssertTrue(editor.string.isEmpty)
        editor.layoutManager?.ensureLayout(for: try XCTUnwrap(editor.textContainer))
        let emptyLine = try XCTUnwrap(editor.layoutManager).extraLineFragmentRect
        XCTAssertGreaterThan(emptyLine.height, 0)
        editor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        editor.insertText("中", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertEqual(editor.string, "中")
        let container = try XCTUnwrap(editor.textContainer)
        let layout = try XCTUnwrap(editor.layoutManager)
        layout.ensureLayout(for: container)
        let glyph = layout.boundingRect(forGlyphRange: NSRange(location: 0, length: 1), in: container)
        XCTAssertEqual(glyph.minX, container.lineFragmentPadding, accuracy: 0.5)
        XCTAssertEqual(glyph.minY, 0, accuracy: 0.5)
        XCTAssertEqual(glyph.height, emptyLine.height, accuracy: 1)
        editor.string = "中文输入测试\n第二行"
        editor.layoutManager?.ensureLayout(for: try XCTUnwrap(editor.textContainer))
        XCTAssertGreaterThan(editor.layoutManager?.numberOfGlyphs ?? 0, 5)
        editor.string = ""
        if let path = ProcessInfo.processInfo.environment["TODOBOARD_UI_SNAPSHOT"] {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
        window.contentView = nil
    }
}
