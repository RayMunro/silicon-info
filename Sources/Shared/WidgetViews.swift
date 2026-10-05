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

/// Which part of the chip a small widget shows.
enum ComponentChoice: String, CaseIterable, Codable {
    case cpu, gpu, neuralEngine, memory, power

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .neuralEngine: "NEURAL ENGINE"
        case .memory: "MEMORY"
        case .power: "POWER"
        }
    }
    var tint: Color {
        switch self {
        case .cpu: Palette.cpuP
        case .gpu: Palette.gpu
        case .neuralEngine: Palette.ane
        case .memory: Palette.mem
        case .power: .white
        }
    }
}

/// In the real widget the memory area is a button that frees cached memory. Elsewhere it is plain content.
@ViewBuilder
private func tappable<C: View>(_ content: C) -> some View {
#if WIDGET_EXTENSION
    Button(intent: FreeMemoryIntent()) { content }.buttonStyle(.plain)
#else
    content
#endif
}

private func memoryUsage(_ d: WidgetData) -> String {
    d.purgeNote.isEmpty
        ? "\(String(format: "%.1f", d.memUsed / 1_073_741_824)) / \(String(format: "%.0f", d.memTotal / 1_073_741_824)) GB"
        : d.purgeNote
}

private func watts(_ w: Double, known: Bool) -> String { known ? String(format: "%.1f W", w) : "n/a" }

private struct Header: View {
    let title: String, tint: Color, trailing: String
    var size: CGFloat = 10
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(title).font(.system(size: size, weight: .semibold)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Text(trailing).font(.system(size: size, weight: .medium, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

// MARK: - Small: one component

struct SmallWidgetView: View {
    let d: WidgetData
    let component: ComponentChoice

    var body: some View {
        VStack(spacing: 6) {
            Header(title: component.title, tint: component.tint, trailing: trailing)
            Spacer(minLength: 0)
            if component == .memory { tappable(body_) } else { body_ }
        }
    }

    private var body_: some View {
        VStack(spacing: 6) {
            ring
            Text(footnote).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private var trailing: String {
        switch component {
        case .cpu: watts(d.cpuW, known: d.powerKnown)
        case .gpu: watts(d.gpuW, known: d.powerKnown)
        case .neuralEngine: watts(d.aneW, known: d.powerKnown)
        case .memory: ""
        case .power: ""
        }
    }

    @ViewBuilder private var ring: some View {
        switch component {
        case .cpu:
            Ring(value: d.cpuLoad, color: Palette.cpuP, label: pct(d.cpuLoad), sub: "LOAD", line: 8, labelSize: 18).frame(width: 78, height: 78)
        case .gpu:
            Ring(value: d.gpuUtil, color: Palette.gpu, label: pct(d.gpuUtil), sub: "DEVICE", line: 8, labelSize: 18).frame(width: 78, height: 78)
        case .neuralEngine:
            Ring(value: min(d.aneW / WidgetData.aneMaxWatts, 1), color: Palette.ane, label: String(format: "%.1f", d.aneW),
                 sub: "WATTS", line: 8, labelSize: 18).frame(width: 78, height: 78)
        case .memory:
            Ring(value: d.memUsed / max(d.memTotal, 1), color: Palette.mem, label: String(format: "%.1f", d.memUsed / 1_073_741_824),
                 sub: "GB USED", line: 8, labelSize: 18).frame(width: 78, height: 78)
        case .power:
            Ring(value: min(d.totalW / 40, 1), color: .white, label: String(format: "%.1f", d.totalW), sub: "WATTS", line: 8, labelSize: 18)
                .frame(width: 78, height: 78)
        }
    }

    private var footnote: String {
        switch component {
        case .cpu: "P \(pct(avg(d.pCores)))  ·  E \(pct(avg(d.eCores)))"
        case .gpu: "Render \(pct(d.gpuRenderer))  ·  Tiler \(pct(d.gpuTiler))"
        case .neuralEngine: d.aneW > 0.05 ? "Active" : "Idle"
        case .memory: d.purgeNote.isEmpty ? "of \(String(format: "%.0f", d.memTotal / 1_073_741_824)) GB  ·  Tap to free" : d.purgeNote
        case .power: "CPU \(String(format: "%.1f", d.cpuW))  GPU \(String(format: "%.1f", d.gpuW))  ANE \(String(format: "%.1f", d.aneW))"
        }
    }
}

// MARK: - Medium: CPU, GPU and Neural Engine side by side

struct MediumWidgetView: View {
    let d: WidgetData

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Header(title: "CPU", tint: Palette.cpuP, trailing: watts(d.cpuW, known: d.powerKnown))
                    Text("PERFORMANCE \(pct(avg(d.pCores)))").font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.cpuP)
                    CoreBars(loads: d.pCores, color: Palette.cpuP, height: 20, spacing: 2)
                    Text("EFFICIENCY \(pct(avg(d.eCores)))").font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.cpuE)
                    CoreBars(loads: d.eCores, color: Palette.cpuE, height: 20, spacing: 2)
                }.frame(maxWidth: .infinity)
                VStack(spacing: 4) {
                    Header(title: "GPU", tint: Palette.gpu, trailing: watts(d.gpuW, known: d.powerKnown))
                    Ring(value: d.gpuUtil, color: Palette.gpu, label: pct(d.gpuUtil), sub: "DEVICE", line: 6, labelSize: 14, subSize: 7)
                        .frame(width: 64, height: 64)
                }.frame(width: 84)
                VStack(spacing: 4) {
                    Header(title: "ANE", tint: Palette.ane, trailing: watts(d.aneW, known: d.powerKnown))
                    Ring(value: min(d.aneW / WidgetData.aneMaxWatts, 1), color: Palette.ane, label: String(format: "%.1f", d.aneW),
                         sub: "WATTS", line: 6, labelSize: 14, subSize: 7).frame(width: 64, height: 64)
                }.frame(width: 84)
            }
            Spacer(minLength: 0)
            tappable(HStack(spacing: 8) {
                Text("MEM").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(Palette.mem)
                StackedBar(parts: [(d.memApp / max(d.memTotal, 1), Palette.mem), (d.memWired / max(d.memTotal, 1), Palette.mem.opacity(0.6)),
                                   (d.memCompressed / max(d.memTotal, 1), Palette.mem.opacity(0.35))], height: 6)
                Text(memoryUsage(d)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }.contentShape(Rectangle()))
            HStack(spacing: 8) {
                Text("PWR").font(.system(size: 8.5, weight: .semibold))
                let t = max(d.totalW, 0.001)
                StackedBar(parts: [(d.cpuW / t, Palette.cpuP), (d.gpuW / t, Palette.gpu), (d.aneW / t, Palette.ane)], height: 6)
                Text(watts(d.totalW, known: d.powerKnown)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Large: everything

struct LargeWidgetView: View {
    let d: WidgetData

    var body: some View {
        VStack(spacing: 7) {
            panel {
                Header(title: "CPU", tint: Palette.cpuP, trailing: watts(d.cpuW, known: d.powerKnown), size: 11)
                Text("PERFORMANCE · \(d.pCores.count)   \(pct(avg(d.pCores)))").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(Palette.cpuP)
                CoreBars(loads: d.pCores, color: Palette.cpuP, height: 18)
                Text("EFFICIENCY · \(d.eCores.count)   \(pct(avg(d.eCores)))").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(Palette.cpuE)
                CoreBars(loads: d.eCores, color: Palette.cpuE, height: 18)
            }
            HStack(spacing: 7) {
                panel {
                    Header(title: "GPU", tint: Palette.gpu, trailing: watts(d.gpuW, known: d.powerKnown), size: 11)
                    Ring(value: d.gpuUtil, color: Palette.gpu, label: pct(d.gpuUtil), sub: "DEVICE", line: 6, labelSize: 14)
                        .frame(width: 54, height: 54).frame(maxWidth: .infinity)
                }
                panel {
                    Header(title: "NEURAL ENGINE", tint: Palette.ane, trailing: watts(d.aneW, known: d.powerKnown), size: 11)
                    Ring(value: min(d.aneW / WidgetData.aneMaxWatts, 1), color: Palette.ane, label: String(format: "%.1f", d.aneW),
                         sub: "WATTS", line: 6, labelSize: 14).frame(width: 54, height: 54).frame(maxWidth: .infinity)
                }
            }
            tappable(panel {
                Header(title: d.purgeNote.isEmpty ? "MEMORY  ·  TAP TO FREE" : "MEMORY", tint: Palette.mem, trailing: memoryUsage(d), size: 11)
                StackedBar(parts: [(d.memApp / max(d.memTotal, 1), Palette.mem), (d.memWired / max(d.memTotal, 1), Palette.mem.opacity(0.6)),
                                   (d.memCompressed / max(d.memTotal, 1), Palette.mem.opacity(0.35))], height: 7)
            }.contentShape(Rectangle()))
            panel {
                let t = max(d.totalW, 0.001)
                Header(title: "POWER", tint: .white, trailing: watts(d.totalW, known: d.powerKnown), size: 11)
                StackedBar(parts: [(d.cpuW / t, Palette.cpuP), (d.gpuW / t, Palette.gpu), (d.aneW / t, Palette.ane)], height: 7)
            }
        }
    }

    private func panel<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) { content() }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.06)))
    }
}

/// Dark backdrop shared by the real widget and the PNG renders used for documentation.
struct WidgetBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.13, green: 0.14, blue: 0.22), Color(red: 0.04, green: 0.04, blue: 0.09)],
                       startPoint: .top, endPoint: .bottom)
    }
}
