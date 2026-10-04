import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let sampler = Sampler()
    private var top: CGFloat = 0     // y of the window's top edge; kept fixed when the content resizes

    func applicationDidFinishLaunching(_ n: Notification) {
        let host = NSHostingController(rootView: WidgetView(sampler: sampler))
        host.sizingOptions = [.preferredContentSize]   // window follows the content when a card expands
        window = NSWindow(contentRect: NSRect(origin: .zero, size: host.view.fittingSize),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = host
        window.delegate = self
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let d = UserDefaults.standard
        let vis = NSScreen.main?.visibleFrame ?? .zero
        var x = vis.maxX - window.frame.width - 24
        top = vis.maxY - 24
        if d.object(forKey: "x") != nil {
            let sx = CGFloat(d.double(forKey: "x")), st = CGFloat(d.double(forKey: "top"))
            if vis.insetBy(dx: -50, dy: -50).contains(NSPoint(x: sx + 40, y: st - 40)) { x = sx; top = st }
        }
        window.setFrameOrigin(NSPoint(x: x, y: top - window.frame.height))
        window.makeKeyAndOrderFront(nil)
    }

    private var adjusting = false

    func windowDidMove(_ n: Notification) {
        if adjusting { return }
        top = window.frame.maxY
        UserDefaults.standard.set(Double(window.frame.minX), forKey: "x")
        UserDefaults.standard.set(Double(top), forKey: "top")
    }

    func windowDidResize(_ n: Notification) {
        var y = top - window.frame.height
        var x = window.frame.minX
        if let vis = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {   // never hang off the screen
            if y < vis.minY + 8 { y = vis.minY + 8 }
            if x + window.frame.width > vis.maxX - 8 { x = vis.maxX - 8 - window.frame.width }
            if x < vis.minX + 8 { x = vis.minX + 8 }
        }
        if window.frame.minY != y || window.frame.minX != x {
            adjusting = true; window.setFrameOrigin(NSPoint(x: x, y: y)); adjusting = false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
