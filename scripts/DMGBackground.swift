import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let image = NSImage(size: NSSize(width: 680, height: 440))
image.lockFocus()
let bounds = NSRect(x: 0, y: 0, width: 680, height: 440)
NSGradient(starting: NSColor(calibratedRed: 0.96, green: 0.96, blue: 1, alpha: 1),
           ending: NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.98, alpha: 1))!.draw(in: bounds, angle: -70)

func label(_ text: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (text as NSString).draw(in: NSRect(x: 32, y: y, width: 616, height: size * 1.6), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ])
}

let ink = NSColor(calibratedRed: 0.17, green: 0.19, blue: 0.32, alpha: 1)
label("Disk Assessment", y: 342, size: 32, weight: .bold, color: ink)
label("See what’s taking up space.", y: 310, size: 15, weight: .regular, color: ink.withAlphaComponent(0.7))

let arrow = NSBezierPath()
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 309, y: 220))
arrow.line(to: NSPoint(x: 371, y: 220))
arrow.move(to: NSPoint(x: 359, y: 232))
arrow.line(to: NSPoint(x: 371, y: 220))
arrow.line(to: NSPoint(x: 359, y: 208))
NSColor(calibratedRed: 0.43, green: 0.44, blue: 0.80, alpha: 1).setStroke()
arrow.stroke()

label("Drag Disk Assessment into Applications", y: 62, size: 16, weight: .medium, color: ink)
label("Then open it from Applications to get started.", y: 36, size: 13, weight: .regular, color: ink.withAlphaComponent(0.65))
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
