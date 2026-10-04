// Silicon Info
// Copyright (C) 2026 Ray Munro
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import SwiftUI
import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    var window: NSWindow!
    let sampler = Sampler()
    private var statusItem: NSStatusItem!
    private var cpuSubscription: AnyCancellable?
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
        setupStatusItem()

        // `--render-widgets <folder>` saves PNGs of the widget layouts after a short warm-up, then quits.
        if let i = CommandLine.arguments.firstIndex(of: "--render-widgets"), i + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [self] in
                renderWidgetImages(sampler.makeWidgetData(), to: dir)
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Silicon Info")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.toolTip = "Silicon Info"
        }
        // Live CPU load next to the icon. Monospaced digits stop the item from jittering as the value changes.
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        cpuSubscription = sampler.$snap.receive(on: DispatchQueue.main).sink { [weak self] snap in
            let load = avg(snap.pCores + snap.eCores)
            self?.statusItem.button?.attributedTitle = NSAttributedString(string: " \(pct(load))", attributes: [.font: font])
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Rebuilt each time the menu opens so the readings are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = sampler.snap
        func w(_ v: Double) -> String { sampler.cpuPowerSeen ? String(format: "%.1f W", v) : "n/a" }
        func info(_ text: String) {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        info("CPU  \(pct(avg(s.pCores + s.eCores)))  \u{00B7}  \(w(s.cpuWatts))")
        info("GPU  \(pct(s.gpuUtil))  \u{00B7}  \(w(s.gpuWatts))")
        info("Neural Engine  \(w(s.aneWatts))")
        info("Memory  \(gb(sampler.mem.used)) of \(gb(sampler.mem.total))")
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: window.isVisible ? "Hide Panel" : "Show Panel", action: #selector(togglePanel), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Silicon Info", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func togglePanel() {
        if window.isVisible { window.orderOut(nil) } else { window.orderFrontRegardless() }
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
