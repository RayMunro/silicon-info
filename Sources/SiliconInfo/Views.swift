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

struct Card<Content: View>: View {
    let title: String
    let tint: Color
    let power: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(title).font(.system(size: 11, weight: .semibold)).tracking(0.6)
                Spacer()
                Text(power).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            }
            content
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
    }
}


enum Panel: String { case cpu = "CPU", gpu = "GPU", ane = "NEURAL ENGINE", power = "POWER", mem = "MEMORY" }

struct WidgetView: View {
    @ObservedObject var sampler: Sampler
    @State private var open: Panel? = {
        // `--open cpu|gpu|ane|power` starts with a detail view showing (handy for screenshots)
        guard let i = CommandLine.arguments.firstIndex(of: "--open"), i + 1 < CommandLine.arguments.count else { return nil }
        switch CommandLine.arguments[i + 1] { case "cpu": return .cpu; case "gpu": return .gpu; case "ane": return .ane; case "power": return .power; case "mem": return .mem; default: return nil }
    }()

    var body: some View {
        VStack(spacing: 8) {
            titleBar
            Group {
                if let open { detail(open) } else { overview }
            }
        }
        .padding(14)
        .frame(width: 400)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12)))
        .preferredColorScheme(.dark)
        .contextMenu {
            Button("Hide Panel") { NotificationCenter.default.post(name: .hidePanel, object: nil) }
            Button("Quit Silicon Info") { NSApp.terminate(nil) }
        }
    }

    /// Close button, copyright and the area you drag to move the panel.
    private var titleBar: some View {
        HStack(spacing: 8) {
            Button { NotificationCenter.default.post(name: .hidePanel, object: nil) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close panel (Silicon Info keeps running in the menu bar)")
            Spacer()
            Text("Silicon Info  \u{00B7}  \u{00A9} 2026 Ray Munro")
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            Spacer()
            Color.clear.frame(width: 14, height: 14)   // balances the close button so the text stays centred
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .background(WindowDragHandle())
    }

    private func tint(_ p: Panel) -> Color {
        switch p { case .cpu: Palette.cpuP; case .gpu: Palette.gpu; case .ane: Palette.ane; case .power: .white; case .mem: Palette.mem }
    }

    private func detail(_ p: Panel) -> some View {
        let s = sampler.snap
        let w: Double = { switch p { case .cpu: s.cpuWatts; case .gpu: s.gpuWatts; case .ane: s.aneWatts; case .power: s.cpuWatts + s.gpuWatts + s.aneWatts; case .mem: 0 } }()
        return VStack(spacing: 10) {
            HStack {
                Button { withAnimation(.easeOut(duration: 0.2)) { open = nil } } label: {
                    HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold)); Text("Back") }
                        .font(.system(size: 11, weight: .medium))
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(tint(p)).frame(width: 7, height: 7)
                Text(p.rawValue).font(.system(size: 11, weight: .semibold)).tracking(0.6)
                Spacer()
                Text(p == .mem ? "\(gb(sampler.mem.used)) / \(gb(sampler.mem.total))" : String(format: "%.1f W", w))
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(.horizontal, 4)
            FitScroll {
                switch p {
                case .cpu: CPUDetail(sampler: sampler)
                case .gpu: GPUDetail(sampler: sampler)
                case .ane: ANEDetail(sampler: sampler)
                case .power: PowerDetail(sampler: sampler)
                case .mem: MemoryDetail(sampler: sampler)
                }
            }
        }
    }

    private var overview: some View {
        let s = sampler.snap
        let watts: (Double, Bool) -> String = { w, ok in ok ? String(format: "%.1f W", w) : "n/a" }
        let total = max(s.cpuWatts + s.gpuWatts + s.aneWatts, 0.001)
        return VStack(spacing: 10) {
            Card(title: "CPU", tint: Palette.cpuP, power: watts(s.cpuWatts, sampler.cpuPowerSeen)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("PERFORMANCE · \(s.pCores.count)").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.cpuP)
                        Spacer(); Text(pct(avg(s.pCores))).font(.system(size: 10, design: .monospaced)) }
                    CoreBars(loads: s.pCores, color: Palette.cpuP)
                    HStack { Text("EFFICIENCY · \(s.eCores.count)").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.cpuE)
                        Spacer(); Text(pct(avg(s.eCores))).font(.system(size: 10, design: .monospaced)) }.padding(.top, 4)
                    CoreBars(loads: s.eCores, color: Palette.cpuE)
                }
                Sparkline(values: sampler.cpuHistory, color: Palette.cpuP).frame(height: 26)
            }
            .contentShape(Rectangle()).onTapGesture { withAnimation(.easeOut(duration: 0.2)) { open = .cpu } }
            HStack(spacing: 10) {
                Card(title: "GPU", tint: Palette.gpu, power: watts(s.gpuWatts, sampler.gpuPowerSeen)) {
                    Ring(value: s.gpuUtil, color: Palette.gpu, label: pct(s.gpuUtil), sub: "DEVICE").frame(width: 84, height: 84).frame(maxWidth: .infinity)
                    VStack(spacing: 3) {
                        MiniBar(label: "Render", value: s.gpuRenderer, color: Palette.gpu)
                        MiniBar(label: "Tiler", value: s.gpuTiler, color: Palette.gpu)
                    }
                    Sparkline(values: sampler.gpuHistory, color: Palette.gpu).frame(height: 22)
                }
                .contentShape(Rectangle()).onTapGesture { withAnimation(.easeOut(duration: 0.2)) { open = .gpu } }
                Card(title: "NEURAL ENGINE", tint: Palette.ane, power: String(format: "%.1f W", s.aneWatts)) {
                    Ring(value: min(s.aneWatts / sampler.aneMaxWatts, 1), color: Palette.ane,
                         label: String(format: "%.1f", s.aneWatts), sub: "WATTS").frame(width: 84, height: 84).frame(maxWidth: .infinity)
                    Text("Load shown as power; macOS exposes no ANE utilization counter.")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Sparkline(values: sampler.aneHistory, color: Palette.ane).frame(height: 22)
                }
                .contentShape(Rectangle()).onTapGesture { withAnimation(.easeOut(duration: 0.2)) { open = .ane } }
            }
            Card(title: "MEMORY", tint: Palette.mem, power: "\(gb(sampler.mem.used)) / \(gb(sampler.mem.total))") {
                let m = sampler.mem, t = max(m.total, 1)
                StackedBar(parts: [(m.app / t, Palette.mem), (m.wired / t, Palette.mem.opacity(0.6)), (m.compressed / t, Palette.mem.opacity(0.35))], height: 8)
                Text("Pressure: \(m.pressureName)").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle()).onTapGesture { withAnimation(.easeOut(duration: 0.2)) { open = .mem } }
            Card(title: "POWER", tint: .white, power: String(format: "%.1f W", s.cpuWatts + s.gpuWatts + s.aneWatts)) {
                StackedBar(parts: [(s.cpuWatts / total, Palette.cpuP), (s.gpuWatts / total, Palette.gpu), (s.aneWatts / total, Palette.ane)], height: 8)
            }
            .contentShape(Rectangle()).onTapGesture { withAnimation(.easeOut(duration: 0.2)) { open = .power } }
        }
    }
}

struct MiniBar: View {
    let label: String; let value: Double; let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.16))
                    Capsule().fill(color).frame(width: max(3, g.size.width * CGFloat(value)))
                        .animation(.easeOut(duration: 0.5), value: value)
                }
            }.frame(height: 5)
            Text(pct(value)).font(.system(size: 9, design: .monospaced)).frame(width: 30, alignment: .trailing)
        }
    }
}

/// An area that moves the window when dragged. Cards react to clicks, so the panel needs a dedicated handle.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
