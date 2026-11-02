import AppKit
import SwiftUI

struct AgentPortrait: View {
    let avatar: String
    let fallback: String
    private var image: NSImage? {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Avatars/\(avatar).png"),
           let image = NSImage(contentsOf: url) { return image }
        return Bundle.module.url(forResource: avatar, withExtension: "png", subdirectory: "Avatars")
            .flatMap { NSImage(contentsOf: $0) }
    }
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Circle().fill(.cyan.opacity(0.3)).overlay(Text(String(fallback.prefix(1)))) }
        }.clipShape(Circle())
    }
}
