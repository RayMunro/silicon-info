import Foundation
import IOKit
import Darwin

/// One reading of everything the widget shows.
struct Snapshot {
    var eCores: [Double] = []      // 0...1 per efficiency core
    var pCores: [Double] = []      // 0...1 per performance core
    var gpuUtil: Double = 0        // 0...1
    var gpuRenderer: Double = 0
    var gpuTiler: Double = 0
    var gpuMemUsed: Double = 0     // bytes
    var gpuMemAlloc: Double = 0
    var cpuUser: [Double] = []     // per core, E-cores first (0...1)
    var cpuSys: [Double] = []
    var cpuWatts: Double = 0
    var gpuWatts: Double = 0
    var aneWatts: Double = 0
}

// MARK: - IOReport (private, loaded dynamically; no sudo required)

private final class IOReportSession {
    typealias CopyChannels = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    typealias CreateSub = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> UnsafeRawPointer?
    typealias CreateSamples = @convention(c) (UnsafeRawPointer?, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    typealias CreateDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    typealias GetString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    typealias GetInt = @convention(c) (CFDictionary, Int32) -> Int64

    private var createSamples: CreateSamples
    private var createDelta: CreateDelta
    private var channelName: GetString
    private var unitLabel: GetString
    private var intValue: GetInt
    private var sub: UnsafeRawPointer
    private var subbed: CFMutableDictionary
    private var last: CFDictionary
    private var lastTime: Date

    init?() {
        guard let h = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return nil }
        func sym<T>(_ n: String, _ t: T.Type) -> T? {
            guard let p = dlsym(h, n) else { return nil }
            return unsafeBitCast(p, to: t)
        }
        guard let copy = sym("IOReportCopyChannelsInGroup", CopyChannels.self),
              let create = sym("IOReportCreateSubscription", CreateSub.self),
              let cs = sym("IOReportCreateSamples", CreateSamples.self),
              let cd = sym("IOReportCreateSamplesDelta", CreateDelta.self),
              let cn = sym("IOReportChannelGetChannelName", GetString.self),
              let ul = sym("IOReportChannelGetUnitLabel", GetString.self),
              let iv = sym("IOReportSimpleGetIntegerValue", GetInt.self),
              let chans = copy("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue()
        else { return nil }

        var subbedOut: Unmanaged<CFMutableDictionary>?
        guard let s = create(nil, chans, &subbedOut, 0, nil), let sd = subbedOut?.takeRetainedValue(),
              let first = cs(s, sd, nil)?.takeRetainedValue()
        else { return nil }
        createSamples = cs; createDelta = cd; channelName = cn; unitLabel = ul; intValue = iv
        sub = s; subbed = sd; last = first; lastTime = Date()
    }

    /// Returns (channel name, watts) for each energy channel since the previous call.
    func powerByChannel() -> [(String, Double)] {
        guard let cur = createSamples(sub, subbed, nil)?.takeRetainedValue() else { return [] }
        let now = Date()
        defer { last = cur; lastTime = now }
        let dt = max(now.timeIntervalSince(lastTime), 0.001)
        guard let delta = createDelta(last, cur, nil)?.takeRetainedValue(),
              let items = (delta as NSDictionary)["IOReportChannels"] as? [CFDictionary] else { return [] }
        return items.map { ch in
            let name = channelName(ch)?.takeUnretainedValue() as String? ?? ""
            let unit = unitLabel(ch)?.takeUnretainedValue() as String? ?? ""
            let raw = Double(intValue(ch, 0))
            let joules: Double
            switch unit {
            case "mJ": joules = raw / 1e3
            case "uJ", "µJ": joules = raw / 1e6
            case "nJ": joules = raw / 1e9
            default: joules = raw / 1e6
            }
            return (name, joules / dt)
        }
    }
}

// MARK: - Sampler

final class Sampler: ObservableObject {
    @Published var snap = Snapshot()
    @Published var cpuHistory: [Double] = []
    @Published var gpuHistory: [Double] = []
    @Published var aneHistory: [Double] = []
    /// Raw watts per second, 120 s deep, for the detail views.
    @Published var cpuWHistory: [Double] = []
    @Published var gpuWHistory: [Double] = []
    @Published var aneWHistory: [Double] = []
    /// Energy since the widget launched, in watt-hours.
    @Published var cpuWh = 0.0
    @Published var gpuWh = 0.0
    @Published var aneWh = 0.0
    /// Latest powermetrics sample (frequencies, clusters, processes); nil until authorised.
    @Published var pm: PowerFeed.Sample?
    private var lastSampleID = ""
    /// Unified memory (DRAM) state, a two-minute usage history and the biggest processes.
    @Published var mem = MemSnap()
    @Published var memHistory: [Double] = []
    @Published var topMem: [(String, Double)] = []
    private var memReader = MemoryReader()
    private var memTicks = 0
    /// False until a nonzero reading arrives; some macOS versions report zeros for CPU channels.
    @Published var cpuPowerSeen = false
    @Published var gpuPowerSeen = false

    /// Rough full-load ceilings used to turn watts into a 0...1 gauge for the ANE.
    let aneMaxWatts = 8.0
    let historyLength = 60

    let eCount: Int
    let pCount: Int
    private var prevTicks: [[UInt32]] = []
    private let ioreport = IOReportSession()
    private let feed = PowerFeed()
    private var timer: Timer?

    init() {
        func sysctl(_ n: String) -> Int {
            var v: Int32 = 0; var s = MemoryLayout<Int32>.size
            return sysctlbyname(n, &v, &s, nil, 0) == 0 ? Int(v) : 0
        }
        pCount = sysctl("hw.perflevel0.logicalcpu")
        eCount = sysctl("hw.perflevel1.logicalcpu")
        _ = tick()
        feed.start()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
    }

    private func update() {
        var s = tick()
        if let io = ioreport {
            for (name, w) in io.powerByChannel() {
                if name.hasSuffix("CPU Energy") || name == "CPU Energy" { s.cpuWatts += w }
                else if name == "GPU Energy" { s.gpuWatts += w }
                else if name.hasPrefix("ANE") { s.aneWatts += w }
            }
        }
        if let r = feed.read() {   // exact figures from powermetrics override the IOReport ones
            s.cpuWatts = r.cpu; s.gpuWatts = r.gpu; s.aneWatts = r.ane
            cpuPowerSeen = true; gpuPowerSeen = true
            pm = r
            if r.id != lastSampleID {   // the file can be read twice per sample; count each once
                lastSampleID = r.id
                cpuWh += r.cpu * r.elapsed / 3600; gpuWh += r.gpu * r.elapsed / 3600; aneWh += r.ane * r.elapsed / 3600
                push(&cpuWHistory, r.cpu, 120); push(&gpuWHistory, r.gpu, 120); push(&aneWHistory, r.ane, 120)
            }
        }
        if s.cpuWatts > 0 { cpuPowerSeen = true }
        if s.gpuWatts > 0 { gpuPowerSeen = true }
        snap = s
        mem = memReader.read()
        push(&memHistory, mem.used / max(mem.total, 1), 120)
        if memTicks % 5 == 0 {   // ps is comparatively heavy, so refresh the process list every 5 s
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let top = MemoryReader.topProcesses()
                DispatchQueue.main.async { self?.topMem = top }
            }
        }
        memTicks += 1
        let cpu = (s.eCores + s.pCores).reduce(0, +) / Double(max(s.eCores.count + s.pCores.count, 1))
        push(&cpuHistory, cpu); push(&gpuHistory, s.gpuUtil); push(&aneHistory, min(s.aneWatts / aneMaxWatts, 1))
    }

    private func push(_ a: inout [Double], _ v: Double, _ limit: Int? = nil) {
        let n = limit ?? historyLength
        a.append(v); if a.count > n { a.removeFirst(a.count - n) }
    }

    // CPU per-core load from host_processor_info. Apple silicon lists E-cores first.
    private func tick() -> Snapshot {
        var s = Snapshot()
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return s }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)) }

        var loads: [Double] = []
        var users: [Double] = [], syss: [Double] = []
        var ticks: [[UInt32]] = []
        for i in 0..<Int(count) {
            let b = i * Int(CPU_STATE_MAX)
            let t = [UInt32(bitPattern: info[b + Int(CPU_STATE_USER)]), UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)]),
                     UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)]), UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)])]
            ticks.append(t)
            if i < prevTicks.count {
                let p = prevTicks[i]
                let d = (0..<4).map { Double(t[$0] &- p[$0]) }
                let total = d.reduce(0, +)
                loads.append(total > 0 ? (total - d[2]) / total : 0)
                users.append(total > 0 ? (d[0] + d[3]) / total : 0)
                syss.append(total > 0 ? d[1] / total : 0)
            } else { loads.append(0); users.append(0); syss.append(0) }
        }
        prevTicks = ticks
        s.eCores = Array(loads.prefix(eCount))
        s.pCores = Array(loads.dropFirst(eCount))

        s.cpuUser = users; s.cpuSys = syss
        (s.gpuUtil, s.gpuRenderer, s.gpuTiler, s.gpuMemUsed, s.gpuMemAlloc) = Self.gpuStats()
        return s
    }

    private static func gpuStats() -> (Double, Double, Double, Double, Double) {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return (0, 0, 0, 0, 0) }
        defer { IOObjectRelease(it) }
        while case let svc = IOIteratorNext(it), svc != 0 {
            defer { IOObjectRelease(svc) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let d = props?.takeRetainedValue() as? [String: Any],
                  let perf = d["PerformanceStatistics"] as? [String: Any] else { continue }
            func v(_ k: String) -> Double { ((perf[k] as? NSNumber)?.doubleValue ?? 0) / 100 }
            func b(_ k: String) -> Double { (perf[k] as? NSNumber)?.doubleValue ?? 0 }
            return (v("Device Utilization %"), v("Renderer Utilization %"), v("Tiler Utilization %"),
                    b("In use system memory"), b("Alloc system memory"))
        }
        return (0, 0, 0, 0, 0)
    }
}
