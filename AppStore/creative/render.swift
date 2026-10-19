import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("artifacts/StoreCreative")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func fill(_ rect: NSRect, _ tint: NSColor, radius: CGFloat = 0) {
    tint.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func text(_ value: String, _ rect: NSRect, size: CGFloat, weight: NSFont.Weight,
          tint: NSColor = color(0x233B32)) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 2
    (value as NSString).draw(in: rect, withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: tint, .paragraphStyle: paragraph, .kern: -size * 0.025,
    ])
}

func image(_ path: String) -> NSImage {
    guard let value = NSImage(contentsOf: root.appendingPathComponent(path)) else {
        fatalError("Missing native capture: \(path)")
    }
    return value
}

func drawImage(_ image: NSImage, _ rect: NSRect, radius: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
               respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
}

func phone(_ capture: NSImage, x: CGFloat, y: CGFloat, angle: CGFloat) {
    let cg = NSGraphicsContext.current!.cgContext
    cg.saveGState()
    cg.translateBy(x: x + 319, y: y + 675)
    cg.rotate(by: angle * .pi / 180)
    cg.translateBy(x: -319, y: -675)
    cg.setShadow(offset: CGSize(width: 0, height: 30), blur: 70,
                 color: color(0x233B32, alpha: 0.16).cgColor)
    fill(NSRect(x: 0, y: 0, width: 638, height: 1350), color(0x233B32), radius: 106)
    cg.setShadow(offset: .zero, blur: 0, color: nil)
    drawImage(capture, NSRect(x: 16, y: 16, width: 606, height: 1318), radius: 90)
    cg.restoreGState()
}

let copies: [(String, String, String, String)] = [
    ("it", "Piccoli passi.", "Giorni tuoi.", "Abitudini · Calendario · Progressi"),
    ("en", "Small steps.", "Your kind of day.", "Habits · Calendar · Progress"),
    ("fr", "Petits pas.", "À votre rythme.", "Habitudes · Calendrier · Progrès"),
    ("de", "Kleine Schritte.", "Dein Rhythmus.", "Gewohnheiten · Kalender · Fortschritte"),
    ("es", "Pequeños pasos.", "A tu ritmo.", "Hábitos · Calendario · Progreso"),
]
let levels = [1, 2, 1, 3, 2, 4, 3, 2, 3, 4, 2, 3, 4, 4,
              1, 3, 2, 4, 4, 3, 4, 2, 3, 4, 3, 4, 4, 4]
let icon = image("App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
for (locale, first, second, features) in copies {
    for placement in ["Header", "Search"] {
        let width = placement == "Header" ? 5244 : 3840
        let height = placement == "Header" ? 2950 : 2560
        let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        fill(NSRect(x: 0, y: 0, width: width, height: height), color(0xF7F5EF))
        color(0xE8EDE2).setFill()
        NSBezierPath(ovalIn: NSRect(x: placement == "Header" ? 3100 : 2300,
                                  y: 100, width: 2700, height: 2700)).fill()
        if placement == "Header" {
            cg.translateBy(x: 1086, y: 816.6)
            cg.scaleBy(x: 0.8, y: 0.8)
        } else {
            cg.translateBy(x: 0, y: 400)
        }
        cg.saveGState()
        cg.translateBy(x: 350, y: 0)
        drawImage(icon, NSRect(x: 120, y: 230, width: 112, height: 112), radius: 27)
        text("Makeet", NSRect(x: 264, y: 229, width: 800, height: 128), size: 94, weight: .semibold)
        text(first + "\n" + second, NSRect(x: 120, y: 432, width: 1920, height: 410),
             size: 158, weight: .semibold)
        text(features, NSRect(x: 120, y: 905, width: 1950, height: 90),
             size: 48, weight: .medium, tint: color(0x68746A))
        for (index, level) in levels.enumerated() {
            let tint = color(0xF7F5EF).blended(withFraction: CGFloat(level) * 0.24, of: color(0x376B50))!
            fill(NSRect(x: 120 + (index % 7) * 58, y: 1090 + (index / 7) * 58,
                        width: 44, height: 44), tint, radius: 11)
        }
        cg.restoreGState()
        phone(image("artifacts/StoreScreens/\(locale)/iphone-medium/02-calendar.png"),
              x: 2880, y: 60, angle: 4)
        phone(image("artifacts/StoreScreens/\(locale)/iphone-medium/01-today.png"),
              x: 2160, y: 190, angle: -4)
        NSGraphicsContext.restoreGraphicsState()
        let target = output.appendingPathComponent("Makeet-\(locale)-\(width)x\(height).png")
        let bitmap = NSBitmapImageRep(cgImage: cg.makeImage()!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: target, options: .atomic)
        print("Rendered \(target.lastPathComponent)")
    }
}
