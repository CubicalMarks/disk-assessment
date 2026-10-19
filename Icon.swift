import AppKit

let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
func tile(_ rect: NSRect, _ hex: UInt32, radius: CGFloat) {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255,
        green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
tile(NSRect(x: 35, y: 35, width: 954, height: 954), 0x203B3C, radius: 210)
tile(NSRect(x: 186, y: 200, width: 383, height: 624), 0xD5E3D6, radius: 30)
tile(NSRect(x: 591, y: 517, width: 247, height: 307), 0xD6DDED, radius: 30)
tile(NSRect(x: 591, y: 200, width: 247, height: 295), 0xEFDDCF, radius: 30)
image.unlockFocus()
let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
