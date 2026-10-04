import SwiftUI

// MARK: - helpers

/// Scrolls only when the content is taller than the screen allows; otherwise it hugs the content.
struct FitScroll<C: View>: View {
    @State private var h: CGFloat = 400
    @ViewBuilder var content: C
    var body: some View {
        let maxH = (NSScreen.main?.visibleFrame.height ?? 800) - 140
        ScrollView(.vertical, showsIndicators: false) {
            content.background(GeometryReader { g in
                Color.clear
                    .onAppear { h = g.size.height }
                    .onChange(of: g.size.height) { _, new in h = new }
            })
        }
        .frame(height: min(h, maxH))
    }
}

func norm(_ a: [Double]) -> [Double] { let m = max(a.max() ?? 1, 0.0001); return a.map { $0 / m } }
func mhz(_ v: Double) -> String { v >= 1000 ? String(format: "%.2f GHz", v / 1000) : "\(Int(v)) MHz" }
func gb(_ bytes: Double) -> String { String(format: "%.2f GB", bytes / 1_073_741_824) }
func watts(_ w: Double) -> String { String(format: "%.2f W", w) }

struct NeedsAccess: View {
    var body: some View {
        Text("Frequency and per-process data come from powermetrics. Approve the admin prompt (relaunch the widget to be asked again).")
            .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct Block<Content: View>: View {
    let title: String
    var trailing: String = ""
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                Spacer()
                Text(trailing).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
    }
}

struct Stat: View {
    let label: String, value: String
    var color: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Time spent at each frequency step, lowest clock on the left.
struct FreqHistogram: View {
    let steps: [PowerFeed.FreqStep]
    let color: Color
    var body: some View {
        let sorted = steps.sorted { $0.mhz < $1.mhz }
        let top = max(sorted.map(\.pct).max() ?? 1, 0.01)
        VStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(sorted.enumerated()), id: \.offset) { _, s in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1.5).fill(color.opacity(0.12))
                        RoundedRectangle(cornerRadius: 1.5).fill(color).frame(height: max(1.5, 26 * s.pct / top))
                    }.frame(height: 26)
                }
            }
            HStack {
                Text(sorted.first.map { mhz(Double($0.mhz)) } ?? "").font(.system(size: 8)).foregroundStyle(.secondary)
                Spacer()
                Text(sorted.last.map { mhz(Double($0.mhz)) } ?? "").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
    }
}

struct StackedBar: View {
    let parts: [(Double, Color)]   // fractions of the full width
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    Rectangle().fill(p.1).frame(width: g.size.width * CGFloat(min(max(p.0, 0), 1)))
                }
                Spacer(minLength: 0)
            }
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }.frame(height: height)
    }
}

struct ProcessList: View {
    let rows: [(String, Double)]   // name, percent of one core / of the GPU
    let color: Color
    let empty: String
    var body: some View {
        if rows.isEmpty {
            Text(empty).font(.system(size: 10)).foregroundStyle(.secondary)
        } else {
            let top = max(rows.map(\.1).max() ?? 1, 1)
            VStack(spacing: 5) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 8) {
                        Text(r.0).font(.system(size: 10.5)).lineLimit(1).frame(width: 130, alignment: .leading)
                        GeometryReader { g in
                            Capsule().fill(color).frame(width: max(2, g.size.width * CGFloat(r.1 / top)))
                        }.frame(height: 5)
                        Text(String(format: "%.0f%%", r.1)).font(.system(size: 10, design: .monospaced)).frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }
}

/// Three series drawn as cumulative areas, so the top edge is the total.
struct StackedHistory: View {
    let a: [Double], b: [Double], c: [Double]   // bottom, middle, top
    let colors: [Color]
    var body: some View {
        let n = min(a.count, b.count, c.count)
        let tot = (0..<n).map { a[$0] + b[$0] + c[$0] }
        let m = max(tot.max() ?? 1, 0.01)
        GeometryReader { g in
            ZStack {
                layer(g, (0..<n).map { tot[$0] / m }, colors[2])
                layer(g, (0..<n).map { (a[$0] + b[$0]) / m }, colors[1])
                layer(g, (0..<n).map { a[$0] / m }, colors[0])
            }
        }
    }
    private func layer(_ g: GeometryProxy, _ v: [Double], _ color: Color) -> some View {
        Path { p in
            guard v.count > 1 else { return }
            p.move(to: CGPoint(x: 0, y: g.size.height))
            for (i, x) in v.enumerated() {
                p.addLine(to: CGPoint(x: g.size.width * CGFloat(i) / CGFloat(v.count - 1), y: g.size.height * (1 - CGFloat(x))))
            }
            p.addLine(to: CGPoint(x: g.size.width, y: g.size.height)); p.closeSubpath()
        }.fill(color.opacity(0.85))
    }
}

func topProcesses(_ pm: PowerFeed.Sample?, gpu: Bool, count: Int = 6) -> [(String, Double)] {
    guard let pm else { return [] }
    return pm.tasks
        .map { ($0.name, (gpu ? $0.gpuMs : $0.cpuMs) / 10) }   // ms of work per second -> % of one core / of the GPU
        .filter { $0.1 >= 0.5 }
        .sorted { $0.1 > $1.1 }
        .prefix(count).map { $0 }
}

// MARK: - CPU

struct CPUDetail: View {
    @ObservedObject var sampler: Sampler
    var body: some View {
        let s = sampler.snap, pm = sampler.pm
        let names = ["E": "Efficiency", "P0": "Performance 0", "P1": "Performance 1"]
        VStack(spacing: 10) {
            Block(title: "CLUSTERS", trailing: "freq · active") {
                if let pm {
                    ForEach(pm.clusters, id: \.name) { c in
                        VStack(spacing: 4) {
                            HStack {
                                Circle().fill(c.name == "E" ? Palette.cpuE : Palette.cpuP).frame(width: 6, height: 6)
                                Text(names[c.name] ?? c.name).font(.system(size: 11, weight: .medium))
                                Spacer()
                                Text("\(mhz(c.freq))  ·  \(pct(c.active))").font(.system(size: 10.5, design: .monospaced))
                            }
                            FreqHistogram(steps: c.steps, color: c.name == "E" ? Palette.cpuE : Palette.cpuP)
                        }
                    }
                } else { NeedsAccess() }
            }
            Block(title: "CORES", trailing: "user ▮ system ▮") {
                VStack(spacing: 4) {
                    ForEach(Array((s.cpuUser.indices)), id: \.self) { i in
                        let isE = i < sampler.eCount
                        let label = isE ? "E\(i + 1)" : "P\(i - sampler.eCount + 1)"
                        let u = s.cpuUser[i], y = s.cpuSys[i]
                        HStack(spacing: 8) {
                            Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(isE ? Palette.cpuE : Palette.cpuP).frame(width: 26, alignment: .leading)
                            StackedBar(parts: [(u, isE ? Palette.cpuE : Palette.cpuP), (y, .red.opacity(0.85))], height: 7)
                            Text(pm.flatMap { i < $0.coreFreq.count ? mhz($0.coreFreq[i]) : nil } ?? "n/a")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 66, alignment: .trailing)
                            Text(pct(u + y)).font(.system(size: 10, design: .monospaced)).frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            }
            Block(title: "TOP PROCESSES", trailing: "% of one core") {
                ProcessList(rows: topProcesses(pm, gpu: false), color: Palette.cpuP, empty: pm == nil ? "Needs admin access." : "Nothing busy.")
            }
            Block(title: "POWER · LAST 2 MIN", trailing: powerSummary(sampler.cpuWHistory)) {
                Sparkline(values: norm(sampler.cpuWHistory), color: Palette.cpuP).frame(height: 44)
                Text("Per-cluster power isn't exposed by macOS on this chip; only the CPU total is.")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
}

func powerSummary(_ h: [Double]) -> String {
    guard !h.isEmpty else { return "" }
    return String(format: "avg %.1f · peak %.1f W", h.reduce(0, +) / Double(h.count), h.max() ?? 0)
}

// MARK: - GPU

struct GPUDetail: View {
    @ObservedObject var sampler: Sampler
    var body: some View {
        let s = sampler.snap, pm = sampler.pm
        VStack(spacing: 10) {
            Block(title: "OVERVIEW", trailing: watts(s.gpuWatts)) {
                HStack(spacing: 16) {
                    Ring(value: s.gpuUtil, color: Palette.gpu, label: pct(s.gpuUtil), sub: "DEVICE").frame(width: 84, height: 84)
                    VStack(spacing: 10) {
                        HStack {
                            Stat(label: "FREQUENCY", value: pm.map { mhz($0.gpuFreq) } ?? "n/a", color: Palette.gpu)
                            Stat(label: "ACTIVE", value: pm.map { pct($0.gpuActive) } ?? "n/a")
                        }
                        HStack {
                            Stat(label: "MAX CLOCK", value: pm?.gpuSteps.map(\.mhz).max().map { mhz(Double($0)) } ?? "n/a")
                            Stat(label: "IDLE", value: pm.map { pct(1 - $0.gpuActive) } ?? "n/a")
                        }
                    }
                }
            }
            Block(title: "FREQUENCY RESIDENCY", trailing: "time at each clock") {
                if let pm { FreqHistogram(steps: pm.gpuSteps, color: Palette.gpu) } else { NeedsAccess() }
            }
            Block(title: "ENGINES") {
                VStack(spacing: 5) {
                    MiniBar(label: "Device", value: s.gpuUtil, color: Palette.gpu)
                    MiniBar(label: "Render", value: s.gpuRenderer, color: Palette.gpu)
                    MiniBar(label: "Tiler", value: s.gpuTiler, color: Palette.gpu)
                }
            }
            Block(title: "MEMORY", trailing: "shared with the system") {
                let alloc = max(s.gpuMemAlloc, 1)
                HStack {
                    Stat(label: "IN USE", value: gb(s.gpuMemUsed), color: Palette.gpu)
                    Stat(label: "ALLOCATED", value: gb(s.gpuMemAlloc))
                }
                StackedBar(parts: [(s.gpuMemUsed / alloc, Palette.gpu)], height: 6)
            }
            Block(title: "TOP GPU PROCESSES", trailing: "% of GPU time") {
                ProcessList(rows: topProcesses(pm, gpu: true), color: Palette.gpu,
                            empty: pm == nil ? "Needs admin access." : "No process is using the GPU right now.")
            }
            Block(title: "LAST MINUTE", trailing: "utilization") {
                Sparkline(values: sampler.gpuHistory, color: Palette.gpu).frame(height: 40)
            }
        }
    }
}

// MARK: - Neural Engine

struct ANEDetail: View {
    @ObservedObject var sampler: Sampler
    var body: some View {
        let w = sampler.snap.aneWatts, h = sampler.aneWHistory
        let active = w > 0.05
        VStack(spacing: 10) {
            Block(title: "OVERVIEW", trailing: active ? "ACTIVE" : "IDLE") {
                HStack(spacing: 16) {
                    Ring(value: min(w / sampler.aneMaxWatts, 1), color: Palette.ane, label: String(format: "%.2f", w), sub: "WATTS")
                        .frame(width: 84, height: 84)
                    VStack(spacing: 10) {
                        HStack {
                            Stat(label: "AVG · 2 MIN", value: watts(h.isEmpty ? 0 : h.reduce(0, +) / Double(h.count)), color: Palette.ane)
                            Stat(label: "PEAK · 2 MIN", value: watts(h.max() ?? 0))
                        }
                        HStack {
                            Stat(label: "SESSION", value: String(format: "%.2f mWh", sampler.aneWh * 1000))
                            Stat(label: "LOAD", value: pct(min(w / sampler.aneMaxWatts, 1)))
                        }
                    }
                }
            }
            Block(title: "POWER · LAST 2 MIN", trailing: "scaled to peak") {
                Sparkline(values: norm(h), color: Palette.ane).frame(height: 70)
            }
            Block(title: "ABOUT THIS READING") {
                Text("macOS doesn't expose Neural Engine utilization, frequency or per-process use, only its power draw. Load is power as a share of an assumed \(Int(sampler.aneMaxWatts)) W ceiling. Idle reads 0 W.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Power split

struct PowerDetail: View {
    @ObservedObject var sampler: Sampler
    var body: some View {
        let s = sampler.snap
        let total = max(s.cpuWatts + s.gpuWatts + s.aneWatts, 0.001)
        let rows: [(String, Color, Double, [Double], Double)] = [
            ("CPU", Palette.cpuP, s.cpuWatts, sampler.cpuWHistory, sampler.cpuWh),
            ("GPU", Palette.gpu, s.gpuWatts, sampler.gpuWHistory, sampler.gpuWh),
            ("Neural Engine", Palette.ane, s.aneWatts, sampler.aneWHistory, sampler.aneWh),
        ]
        VStack(spacing: 10) {
            Block(title: "RIGHT NOW", trailing: watts(total)) {
                StackedBar(parts: rows.map { ($0.2 / total, $0.1) }, height: 12)
                ForEach(rows, id: \.0) { r in
                    HStack {
                        Circle().fill(r.1).frame(width: 7, height: 7)
                        Text(r.0).font(.system(size: 11))
                        Spacer()
                        Text(String(format: "%.2f W  ·  %d%%", r.2, Int((r.2 / total * 100).rounded())))
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
            }
            Block(title: "LAST 2 MIN", trailing: "stacked") {
                StackedHistory(a: sampler.cpuWHistory, b: sampler.gpuWHistory, c: sampler.aneWHistory,
                               colors: [Palette.cpuP, Palette.gpu, Palette.ane]).frame(height: 70)
            }
            Block(title: "AVERAGE, PEAK AND ENERGY") {
                ForEach(rows, id: \.0) { r in
                    HStack {
                        Text(r.0).font(.system(size: 11)).foregroundStyle(r.1)
                        Spacer()
                        Text(String(format: "avg %.2f · peak %.2f W · %.2f mWh", r.3.isEmpty ? 0 : r.3.reduce(0, +) / Double(r.3.count), r.3.max() ?? 0, r.4 * 1000))
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                Text("Energy is since the widget launched. DRAM and media-engine power aren't readable on this chip.")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Memory (DRAM)

struct MemoryDetail: View {
    @ObservedObject var sampler: Sampler
    var body: some View {
        let m = sampler.mem, t = max(m.total, 1)
        let pressureColor: Color = m.pressure >= 4 ? .red : m.pressure >= 2 ? .yellow : .green
        let parts: [(String, Double, Color)] = [
            ("App memory", m.app, Palette.mem),
            ("Wired", m.wired, Palette.mem.opacity(0.6)),
            ("Compressed", m.compressed, Palette.mem.opacity(0.35)),
            ("Cached files", m.cached, .gray.opacity(0.55)),
            ("Free", m.free, .gray.opacity(0.2)),
        ]
        VStack(spacing: 10) {
            Block(title: "UNIFIED MEMORY", trailing: "shared by CPU, GPU and Neural Engine") {
                HStack {
                    Stat(label: "USED", value: gb(m.used), color: Palette.mem)
                    Stat(label: "AVAILABLE", value: gb(m.total - m.used))
                    Stat(label: "TOTAL", value: gb(m.total))
                }
                StackedBar(parts: parts.map { ($0.1 / t, $0.2) }, height: 10)
                ForEach(parts, id: \.0) { r in
                    HStack {
                        Circle().fill(r.2).frame(width: 7, height: 7)
                        Text(r.0).font(.system(size: 11))
                        Spacer()
                        Text("\(gb(r.1))  \u{00B7}  \(pct(r.1 / t))").font(.system(size: 10.5, design: .monospaced))
                    }
                }
            }
            Block(title: "PRESSURE AND SWAP") {
                HStack {
                    Stat(label: "PRESSURE", value: m.pressureName, color: pressureColor)
                    Stat(label: "SWAP USED", value: gb(m.swapUsed))
                    Stat(label: "SWAP SIZE", value: gb(m.swapTotal))
                }
                HStack {
                    Stat(label: "PAGED IN", value: rate(m.pageInRate))
                    Stat(label: "PAGED OUT", value: rate(m.pageOutRate))
                    Spacer().frame(maxWidth: .infinity)
                }
            }
            Block(title: "TOP PROCESSES", trailing: "resident memory") {
                let top = max(sampler.topMem.first?.1 ?? 1, 1)
                if sampler.topMem.isEmpty {
                    Text("Reading processes...").font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 5) {
                        ForEach(Array(sampler.topMem.enumerated()), id: \.offset) { _, r in
                            HStack(spacing: 8) {
                                Text(r.0).font(.system(size: 10.5)).lineLimit(1).frame(width: 130, alignment: .leading)
                                GeometryReader { g in
                                    Capsule().fill(Palette.mem).frame(width: max(2, g.size.width * CGFloat(r.1 / top)))
                                }.frame(height: 5)
                                Text(gb(r.1)).font(.system(size: 10, design: .monospaced)).frame(width: 64, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            Block(title: "LAST 2 MIN", trailing: "memory used") {
                Sparkline(values: sampler.memHistory, color: Palette.mem).frame(height: 44)
                Text("DRAM bandwidth and DRAM power are not readable on this chip, even with admin rights.")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }

    private func rate(_ bytesPerSec: Double) -> String { String(format: "%.1f MB/s", bytesPerSec / 1_048_576) }
}
