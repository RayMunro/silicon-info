import Foundation
import Darwin

/// Unified memory (DRAM) usage. Everything here works without admin rights.
struct MemSnap {
    var total = 0.0                 // bytes
    var app = 0.0, wired = 0.0, compressed = 0.0, cached = 0.0, free = 0.0
    var swapUsed = 0.0, swapTotal = 0.0
    var pressure = 1                // 1 normal, 2 warning, 4 critical
    var pageInRate = 0.0, pageOutRate = 0.0   // bytes per second

    /// Same definition Activity Monitor uses for "Memory Used".
    var used: Double { app + wired + compressed }
    var pressureName: String { pressure >= 4 ? "Critical" : pressure >= 2 ? "Warning" : "Normal" }
}

struct MemoryReader {
    private let pageSize: Double
    private let total: Double
    private var lastIn: UInt64 = 0, lastOut: UInt64 = 0
    private var lastTime = Date()

    init() {
        var ps: Int32 = 0; var s = MemoryLayout<Int32>.size
        sysctlbyname("hw.pagesize", &ps, &s, nil, 0)
        pageSize = ps > 0 ? Double(ps) : 16384
        var mem: UInt64 = 0; var m = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &mem, &m, nil, 0)
        total = Double(mem)
    }

    mutating func read() -> MemSnap {
        var snap = MemSnap()
        snap.total = total

        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var vm = vm_statistics64_data_t()
        let ok = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        } == KERN_SUCCESS
        guard ok else { return snap }

        let p = pageSize
        snap.app = max(Double(vm.internal_page_count) - Double(vm.purgeable_count), 0) * p
        snap.wired = Double(vm.wire_count) * p
        snap.compressed = Double(vm.compressor_page_count) * p
        snap.cached = (Double(vm.external_page_count) + Double(vm.purgeable_count)) * p
        snap.free = max(total - snap.used - snap.cached, 0)

        var xsw = xsw_usage(); var xs = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &xsw, &xs, nil, 0) == 0 {
            snap.swapUsed = Double(xsw.xsu_used); snap.swapTotal = Double(xsw.xsu_total)
        }
        var lvl: Int32 = 1; var ls = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &lvl, &ls, nil, 0) == 0 { snap.pressure = Int(lvl) }

        let now = Date(), dt = max(now.timeIntervalSince(lastTime), 0.001)
        if lastIn > 0 || lastOut > 0 {
            snap.pageInRate = Double(vm.pageins &- lastIn) * p / dt
            snap.pageOutRate = Double(vm.pageouts &- lastOut) * p / dt
        }
        lastIn = vm.pageins; lastOut = vm.pageouts; lastTime = now
        return snap
    }

    /// Resident memory per process name, largest first.
    static func topProcesses(_ count: Int = 6) -> [(String, Double)] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Axo", "rss=,comm="]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        var byName: [String: Double] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.drop { $0 == " " }.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let kb = Double(parts[0]) else { continue }
            let name = (String(parts[1]) as NSString).lastPathComponent
            byName[name, default: 0] += kb * 1024
        }
        return byName.sorted { $0.value > $1.value }.prefix(count).map { ($0.key, $0.value) }
    }
}
