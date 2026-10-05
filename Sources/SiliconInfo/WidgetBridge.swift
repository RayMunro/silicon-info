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
import WidgetKit

extension Sampler {
    /// Everything the widget needs, in one value.
    func makeWidgetData() -> WidgetData {
        var d = WidgetData()
        d.eCores = snap.eCores; d.pCores = snap.pCores
        d.gpuUtil = snap.gpuUtil; d.gpuRenderer = snap.gpuRenderer; d.gpuTiler = snap.gpuTiler
        d.cpuW = snap.cpuWatts; d.gpuW = snap.gpuWatts; d.aneW = snap.aneWatts
        d.powerKnown = cpuPowerSeen
        d.cpuHist = cpuHistory; d.gpuHist = gpuHistory; d.aneHist = aneHistory
        d.memUsed = mem.used; d.memTotal = max(mem.total, 1)
        d.memApp = mem.app; d.memWired = mem.wired; d.memCompressed = mem.compressed
        d.pressure = mem.pressure
        d.purgeNote = Date().timeIntervalSince(purgeNoteDate) < 60 ? purgeNote : ""
        return d
    }

    /// Writes the shared snapshot and, every so often, asks WidgetKit to redraw.
    func publishToWidget(tick: Int) {
        SharedStore.write(makeWidgetData())
        if tick % 10 == 0 { WidgetCenter.shared.reloadAllTimelines() }
    }
}

/// Renders the widget layouts to PNG files, for the documentation. Used by `--render-widgets <folder>`.
@MainActor
func renderWidgetImages(_ d: WidgetData, to dir: String) {
    func save<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String) {
        let content = view.padding(16).frame(width: width, height: height).background(WidgetBackdrop())
            .foregroundStyle(.white).environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        let r = ImageRenderer(content: content)
        r.scale = 2
        guard let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for c in ComponentChoice.allCases { save(SmallWidgetView(d: d, component: c), width: 170, height: 170, name: "small-\(c.rawValue)") }
    save(MediumWidgetView(d: d), width: 364, height: 170, name: "medium")
    save(LargeWidgetView(d: d), width: 364, height: 382, name: "large")
}
