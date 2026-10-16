import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let directory = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(red: 0.14, green: 0.25, blue: 0.19, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
let style = NSMutableParagraphStyle()
style.alignment = .center
let font = NSFont.systemFont(ofSize: 660, weight: .semibold)
("a" as NSString).draw(in: NSRect(x: 0, y: 100, width: 1024, height: 850), withAttributes: [
    .font: font, .foregroundColor: NSColor(red: 0.96, green: 0.95, blue: 0.90, alpha: 1), .paragraphStyle: style
])
for (index, alpha) in [0.3, 0.6, 1.0].enumerated() {
    NSColor(red: 0.75, green: 0.84, blue: 0.55, alpha: alpha).setFill()
    NSBezierPath(roundedRect: NSRect(x: 418 + index * 68, y: 150, width: 46, height: 46), xRadius: 12, yRadius: 12).fill()
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("AppIcon.png"))
let contents = """
{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
"""
try contents.write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
