import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("PlayStore/graphics")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func tint(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func fill(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func text(_ value: String, _ rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor = tint(0x233B32)) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 2
    (value as NSString).draw(in: rect, withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
        .paragraphStyle: paragraph, .kern: -size * 0.022,
    ])
}
func nativeImage(_ path: String) -> NSImage {
    guard let image = NSImage(contentsOf: root.appendingPathComponent(path)) else { fatalError("Missing original asset: \(path)") }
    return image
}
func draw(_ image: NSImage, _ rect: NSRect, radius: CGFloat = 0) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
               hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
}
func panel(_ image: NSImage, x: CGFloat, y: CGFloat, width: CGFloat) {
    let rect = NSRect(x: x, y: y, width: width, height: width * 16 / 9)
    let cg = NSGraphicsContext.current!.cgContext
    cg.setShadow(offset: CGSize(width: 0, height: 8), blur: 22, color: tint(0x233B32, alpha: 0.14).cgColor)
    fill(rect.insetBy(dx: -1, dy: -1), tint(0xD5DED2), radius: 18)
    cg.setShadow(offset: .zero, blur: 0, color: nil)
    draw(image, rect, radius: 17)
}
func canvas(_ width: Int, _ height: Int, file: String, content: () -> Void) throws {
    let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    cg.translateBy(x: 0, y: CGFloat(height)); cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    fill(NSRect(x: 0, y: 0, width: width, height: height), tint(0xF7F5EF))
    content()
    NSGraphicsContext.restoreGraphicsState()
    let bitmap = NSBitmapImageRep(cgImage: cg.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(file), options: .atomic)
    print("Rendered \(file)")
}

let copies: [(String, String, String, String)] = [
    ("en-US", "Small steps.\nReal progress.", "Habits · Calendar · Your own pace", "Native app · Demo data"),
    ("it-IT", "Piccoli passi.\nProgressi concreti.", "Abitudini · Calendario · Il tuo ritmo", "App nativa · Dati dimostrativi"),
    ("fr-FR", "De petits pas.\nDe vrais progrès.", "Habitudes · Calendrier · À votre rythme", "Application native · Données de démonstration"),
    ("de-DE", "Kleine Schritte.\nEchte Fortschritte.", "Gewohnheiten · Kalender · Dein Rhythmus", "Native App · Beispieldaten"),
    ("es-ES", "Pequeños pasos.\nAvances reales.", "Hábitos · Calendario · A tu ritmo", "App nativa · Datos de demostración"),
]
for (locale, title, subtitle, label) in copies {
    try canvas(1024, 500, file: "\(locale)-feature.png") {
        tint(0xE8EDE2).setFill()
        NSBezierPath(ovalIn: NSRect(x: 604, y: -78, width: 574, height: 574)).fill()
        text("Makeet", NSRect(x: 64, y: 72, width: 430, height: 42), size: 28, weight: .semibold)
        text(title, NSRect(x: 64, y: 163, width: 495, height: 140), size: 48, weight: .semibold)
        text(subtitle, NSRect(x: 64, y: 327, width: 475, height: 50), size: 17, weight: .medium, color: tint(0x68746A))
        text(label, NSRect(x: 64, y: 437, width: 490, height: 24), size: 12, weight: .regular, color: tint(0x68746A))
        panel(nativeImage("PlayStore/screenshots/\(locale)/02-calendar.png"), x: 776, y: 48, width: 194)
        panel(nativeImage("PlayStore/screenshots/\(locale)/01-today.png"), x: 562, y: 82, width: 214)
    }
}
try canvas(512, 512, file: "app-icon.png") {
    draw(nativeImage("App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"), NSRect(x: 0, y: 0, width: 512, height: 512))
}
