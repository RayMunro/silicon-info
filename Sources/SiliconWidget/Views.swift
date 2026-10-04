import SwiftUI

enum Palette {
    static let cpuE = Color(red: 0.36, green: 0.84, blue: 0.62)   // efficiency cores
    static let cpuP = Color(red: 0.30, green: 0.60, blue: 1.00)   // performance cores
    static let gpu  = Color(red: 1.00, green: 0.55, blue: 0.25)
    static let ane  = Color(red: 0.75, green: 0.45, blue: 1.00)
    static let mem  = Color(red: 0.95, green: 0.40, blue: 0.62)   // unified memory (DRAM)
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { g in
            let n = max(values.count, 2)
            let pts = values.enumerated().map { CGPoint(x: g.size.width * CGFloat($0.offset) / CGFloat(n - 1),
                                                       y: g.size.height * (1 - CGFloat(min(max($0.element, 0), 1)))) }
            ZStack {
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: CGPoint(x: f.x, y: g.size.height)); p.addLine(to: f)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height)); p.closeSubpath()
                }.fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f); pts.dropFirst().forEach { p.addLine(to: $0) }
                }.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }
}

struct Ring: View {
    let value: Double
    let color: Color
    let label: String
    let sub: String
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 9)
            Circle().trim(from: 0, to: CGFloat(min(max(value, 0.001), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: value)
            VStack(spacing: 0) {
                Text(label).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(sub).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }
}

struct CoreBars: View {
    let loads: [Double]
    let color: Color
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(loads.enumerated()), id: \.offset) { _, l in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2.5).fill(color.opacity(0.16))
                    RoundedRectangle(cornerRadius: 2.5).fill(color)
                        .frame(height: max(3, 34 * CGFloat(l)))
                        .animation(.easeOut(duration: 0.5), value: l)
                }.frame(height: 34)
            }
        }
    }
}

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

func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
func avg(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }

enum Panel: String { case cpu = "CPU", gpu = "GPU", ane = "NEURAL ENGINE", power = "POWER", mem = "MEMORY" }

struct WidgetView: View {
    @ObservedObject var sampler: Sampler
    @State private var open: Panel? = {
        // `--open cpu|gpu|ane|power` starts with a detail view showing (handy for screenshots)
        guard let i = CommandLine.arguments.firstIndex(of: "--open"), i + 1 < CommandLine.arguments.count else { return nil }
        switch CommandLine.arguments[i + 1] { case "cpu": return .cpu; case "gpu": return .gpu; case "ane": return .ane; case "power": return .power; case "mem": return .mem; default: return nil }
    }()

    var body: some View {
        Group {
            if let open { detail(open) } else { overview }
        }
        .padding(14)
        .frame(width: 400)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12)))
        .preferredColorScheme(.dark)
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
            Text("Silicon Info  ·  © 2026 Ray Munro")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 4)
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
