import AppKit

/// Shows the current download/USB progress on the Dock icon so it stays visible when the window is hidden (#6).
@MainActor enum DockProgress {
    private static var active = false
    /// fraction in 0...1, or nil for indeterminate while active.
    static func show(_ fraction: Double?) {
        active = true
        let tile = NSApplication.shared.dockTile
        if let fraction, fraction.isFinite {
            tile.badgeLabel = "\(max(0, min(100, Int(fraction * 100))))%"
        } else {
            tile.badgeLabel = "…"
        }
        tile.display()
    }
    static func clear() {
        guard active else { return }
        active = false
        NSApplication.shared.dockTile.badgeLabel = nil
        NSApplication.shared.dockTile.display()
    }
}
