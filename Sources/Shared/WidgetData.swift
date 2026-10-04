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

import Foundation
import os

/// What the app shares with the widget. The widget is sandboxed and cannot sample hardware itself,
/// so the app writes this to the shared App Group container and the widget reads it.
struct WidgetData: Codable {
    var date = Date()
    var eCores: [Double] = []
    var pCores: [Double] = []
    var gpuUtil = 0.0, gpuRenderer = 0.0, gpuTiler = 0.0
    var cpuW = 0.0, gpuW = 0.0, aneW = 0.0
    var powerKnown = false              // false until the administrator-powered feed is running
    var cpuHist: [Double] = [], gpuHist: [Double] = [], aneHist: [Double] = []   // 0...1, newest last
    var memUsed = 0.0, memTotal = 1.0, memApp = 0.0, memWired = 0.0, memCompressed = 0.0   // bytes
    var pressure = 1                    // 1 normal, 2 warning, 4 critical

    static let aneMaxWatts = 8.0

    var cpuLoad: Double { avg(pCores + eCores) }
    var totalW: Double { cpuW + gpuW + aneW }
    var pressureName: String { pressure >= 4 ? "Critical" : pressure >= 2 ? "Warning" : "Normal" }
    var ageSeconds: TimeInterval { Date().timeIntervalSince(date) }

    /// Plausible values for the widget gallery and for previews.
    static let sample = WidgetData(
        eCores: [0.7, 0.65, 0.5, 0.4], pCores: [0.3, 0.2, 0.15, 0.1, 0.1, 0.05, 0.05, 0.02, 0.02, 0.01],
        gpuUtil: 0.22, gpuRenderer: 0.22, gpuTiler: 0.1, cpuW: 3.8, gpuW: 0.6, aneW: 0, powerKnown: true,
        cpuHist: (0..<40).map { 0.2 + 0.1 * sin(Double($0) / 4) }, gpuHist: (0..<40).map { 0.2 + 0.05 * sin(Double($0) / 3) },
        aneHist: Array(repeating: 0, count: 40),
        memUsed: 17.4 * 1_073_741_824, memTotal: 36 * 1_073_741_824, memApp: 11 * 1_073_741_824, memWired: 3.4 * 1_073_741_824, memCompressed: 3 * 1_073_741_824)
}

enum SharedStore {
    static let groupID = "875N49PYZ9.com.raymondmunro.siliconinfo"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("snapshot.json")
    }

    static func write(_ data: WidgetData) {
        let log = Logger(subsystem: "com.raymondmunro.siliconinfo", category: "store")
        guard let url = fileURL else { log.error("shared container unavailable"); return }
        do {
            try JSONEncoder().encode(data).write(to: url, options: .atomic)
        } catch {
            log.error("could not write snapshot: \(String(describing: error), privacy: .public)")
        }
    }

    static func read() -> WidgetData? {
        guard let url = fileURL, let bytes = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: bytes)
    }
}
