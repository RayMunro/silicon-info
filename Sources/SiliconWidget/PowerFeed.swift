import Foundation

/// Exact CPU/GPU/ANE power, per-core frequency and per-process usage from `powermetrics`, which needs root.
/// The widget asks for admin rights once per launch via the standard macOS password dialog; a root loop
/// writes one sample per second to a file that we parse, and exits when the widget quits.
final class PowerFeed {
    struct FreqStep { var mhz: Int; var pct: Double }
    struct Cluster { var name: String; var freq: Double = 0; var active: Double = 0; var steps: [FreqStep] = [] }
    struct TaskUsage { var name: String; var cpuMs: Double; var gpuMs: Double }

    struct Sample {
        var id = ""                      // timestamp line; changes once per sample
        var elapsed = 1.0                // seconds covered by the sample
        var cpu = 0.0, gpu = 0.0, ane = 0.0
        var coreFreq: [Double] = []      // MHz, indexed by CPU number (E-cores first)
        var coreActive: [Double] = []    // 0...1
        var clusters: [Cluster] = []     // E, P0, P1
        var gpuFreq = 0.0
        var gpuActive = 0.0              // 0...1
        var gpuSteps: [FreqStep] = []
        var tasks: [TaskUsage] = []
    }

    private let path = "/private/tmp/siliconwidget-powermetrics.txt"
    private(set) var started = false

    func start() {
        guard !started else { return }
        started = true
        // A root loop from a previous launch is still running (it outlives us by a moment): reuse it, no prompt.
        if let m = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(m) < 3 { return }
        let loop = "rm -f \(path) \(path).tmp; while pgrep -x SiliconWidget > /dev/null; do "
            + "/usr/bin/powermetrics --samplers cpu_power,gpu_power,ane_power,tasks --show-process-gpu -i 1000 -n 1 > \(path).tmp 2>/dev/null "
            + "&& mv \(path).tmp \(path) || sleep 2; done"
        let shell = "sh -c '\(loop)' > /dev/null 2>&1 &"
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with prompt \"SiliconWidget needs admin rights to read CPU, GPU and Neural Engine power.\" with administrator privileges"
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            try? p.run()
            p.waitUntilExit()
        }
    }

    /// Latest sample, or nil if the feed isn't running (not authorised yet, or declined).
    func read() -> Sample? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return Self.parse(text)
    }

    // MARK: parsing

    private static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
        }
    }

    private static func steps(_ s: String) -> [FreqStep] {
        guard let re = try? NSRegularExpression(pattern: #"(\d+) MHz:\s*([\d.]*)%"#) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            guard let a = Range(m.range(at: 1), in: s), let b = Range(m.range(at: 2), in: s), let mhz = Int(s[a]) else { return nil }
            return FreqStep(mhz: mhz, pct: Double(s[b]) ?? 0)
        }
    }

    static func parse(_ text: String) -> Sample? {
        var s = Sample()
        var clusters: [String: Cluster] = [:]
        var freq: [Int: Double] = [:], active: [Int: Double] = [:]
        var inTasks = false
        var tasks: [String: TaskUsage] = [:]
        var sawCPU = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if line.hasPrefix("*** Sampled system activity") {
                s.id = line
                if let m = match(#"\(([\d.]+)ms elapsed\)"#, line), let ms = Double(m[0]) { s.elapsed = ms / 1000 }
                continue
            }
            if line.hasPrefix("*** Running tasks") { inTasks = true; continue }
            if line.hasPrefix("****") { inTasks = false; continue }

            if inTasks {
                // Name  ID  CPU ms/s  User%  ...  GPU ms/s   (names may contain spaces)
                guard let m = match(#"^(.+?)\s{2,}(-?\d+)\s+([\d.]+)\s+.*?([\d.]+)\s*$"#, line),
                      let cpu = Double(m[2]), let gpu = Double(m[3]),
                      m[0] != "ALL_TASKS", m[0] != "DEAD_TASKS", m[0] != "powermetrics", m[0] != "Name" else { continue }
                var t = tasks[m[0]] ?? TaskUsage(name: m[0], cpuMs: 0, gpuMs: 0)
                t.cpuMs += cpu; t.gpuMs += gpu
                tasks[m[0]] = t
                continue
            }

            if let m = match(#"^(CPU|GPU|ANE) Power: (\d+) mW"#, line), let mw = Double(m[1]) {
                if m[0] == "CPU" { s.cpu = mw / 1000; sawCPU = true }
                else if m[0] == "GPU", s.gpu == 0 { s.gpu = mw / 1000 }
                else if m[0] == "ANE" { s.ane = mw / 1000 }
            } else if let m = match(#"^(E|P\d)-Cluster HW active frequency: (\d+) MHz"#, line) {
                clusters[m[0], default: Cluster(name: m[0])].freq = Double(m[1]) ?? 0
            } else if let m = match(#"^(E|P\d)-Cluster HW active residency:\s*([\d.]+)%(.*)"#, line) {
                clusters[m[0], default: Cluster(name: m[0])].active = (Double(m[1]) ?? 0) / 100
                clusters[m[0]]?.steps = steps(m[2])
            } else if let m = match(#"^CPU (\d+) frequency: (\d+) MHz"#, line), let i = Int(m[0]) {
                freq[i] = Double(m[1])
            } else if let m = match(#"^CPU (\d+) active residency:\s*([\d.]+)%"#, line), let i = Int(m[0]) {
                active[i] = (Double(m[1]) ?? 0) / 100
            } else if let m = match(#"^GPU HW active frequency: (\d+) MHz"#, line) {
                s.gpuFreq = Double(m[0]) ?? 0
            } else if let m = match(#"^GPU HW active residency:\s*([\d.]+)%(.*)"#, line) {
                s.gpuActive = (Double(m[0]) ?? 0) / 100
                s.gpuSteps = steps(m[1])
            }
        }
        guard sawCPU else { return nil }
        let n = (freq.keys.max() ?? -1) + 1
        s.coreFreq = (0..<n).map { freq[$0] ?? 0 }
        s.coreActive = (0..<n).map { active[$0] ?? 0 }
        s.clusters = ["E", "P0", "P1"].compactMap { clusters[$0] }
        s.tasks = Array(tasks.values)
        return s
    }
}
