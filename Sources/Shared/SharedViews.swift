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
    var line: CGFloat = 9
    var labelSize: CGFloat = 19
    var subSize: CGFloat = 9
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: line)
            Circle().trim(from: 0, to: CGFloat(min(max(value, 0.001), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: value)
            VStack(spacing: 0) {
                Text(label).font(.system(size: labelSize, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(sub).font(.system(size: subSize, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }
}

struct CoreBars: View {
    let loads: [Double]
    let color: Color
    var height: CGFloat = 34
    var spacing: CGFloat = 3
    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(loads.enumerated()), id: \.offset) { _, l in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2.5).fill(color.opacity(0.16))
                    RoundedRectangle(cornerRadius: 2.5).fill(color)
                        .frame(height: max(3, height * CGFloat(l)))
                        .animation(.easeOut(duration: 0.5), value: l)
                }.frame(height: height)
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

func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
func avg(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
func norm(_ a: [Double]) -> [Double] { let m = max(a.max() ?? 1, 0.0001); return a.map { $0 / m } }
func gb(_ bytes: Double) -> String { String(format: "%.2f GB", bytes / 1_073_741_824) }
