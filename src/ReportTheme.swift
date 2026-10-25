import AppKit
import SwiftUI

// Native system surfaces adapt to the Mac's appearance around the vivid storage map.
enum ReportTheme {
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let line = Color.primary.opacity(0.08)
    static let muted = Color.secondary
    static let accent = Color.blue
    static let green = Color.green
    static let orange = Color.orange
    static let ring = Color.blue
    static let gap = Color.orange
    static let shared = Color.purple
    static let available = Color.secondary.opacity(0.2)
    static var background: Color { Color(nsColor: .windowBackgroundColor) }
}
