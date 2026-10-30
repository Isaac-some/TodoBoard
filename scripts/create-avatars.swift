import AppKit
import Foundation
for (name, letter, color) in [("yuki", "Y", NSColor.systemTeal), ("matt", "M", NSColor.systemBlue), ("sofia", "S", NSColor.systemOrange), ("richard", "R", NSColor.systemPurple)] {
    let image = NSImage(size: NSSize(width: 128, height: 128)); image.lockFocus()
    color.setFill(); NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 128, height: 128)).fill()
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 64, weight: .medium), .foregroundColor: NSColor.white]
    let size = (letter as NSString).size(withAttributes: attrs)
    (letter as NSString).draw(at: NSPoint(x: (128-size.width)/2, y: (128-size.height)/2), withAttributes: attrs)
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Sources/BoardUI/Avatars/\(name).png"))
}
