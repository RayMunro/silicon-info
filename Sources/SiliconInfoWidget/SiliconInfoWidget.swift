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

import WidgetKit
import SwiftUI
import AppIntents

extension ComponentChoice: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Component"
    static let caseDisplayRepresentations: [ComponentChoice: DisplayRepresentation] = [
        .cpu: "CPU", .gpu: "GPU", .neuralEngine: "Neural Engine", .memory: "Memory", .power: "Power",
    ]
}

struct SelectComponentIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Component"
    static let description = IntentDescription("Choose what the small widget shows.")

    @Parameter(title: "Show", default: .cpu)
    var component: ComponentChoice
}

struct Entry: TimelineEntry {
    let date: Date
    let data: WidgetData?          // nil when the app has not shared anything yet
    let component: ComponentChoice
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, data: .sample, component: .cpu)
    }

    func snapshot(for configuration: SelectComponentIntent, in context: Context) async -> Entry {
        Entry(date: .now, data: context.isPreview ? .sample : SharedStore.read(), component: configuration.component)
    }

    func timeline(for configuration: SelectComponentIntent, in context: Context) async -> Timeline<Entry> {
        let entry = Entry(date: .now, data: SharedStore.read(), component: configuration.component)
        // The running app also asks for reloads; this is the fallback when it is not running.
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30)))
    }
}

struct SiliconInfoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        let d = entry.data ?? .sample
        Group {
            switch family {
            case .systemSmall: SmallWidgetView(d: d, component: entry.component)
            case .systemMedium: MediumWidgetView(d: d)
            default: LargeWidgetView(d: d)
            }
        }
        .foregroundStyle(.white)
        .overlay(alignment: .bottom) {
            if entry.data == nil || d.ageSeconds > 90 {
                Text("Open Silicon Info to update")
                    .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.black.opacity(0.5), in: Capsule())
            }
        }
        .containerBackground(for: .widget) { WidgetBackdrop() }
    }
}

@main
struct SiliconInfoWidgetBundle: WidgetBundle {
    var body: some Widget { SiliconInfoWidget() }
}

struct SiliconInfoWidget: Widget {
    let kind = "SiliconInfoWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectComponentIntent.self, provider: Provider()) { entry in
            SiliconInfoWidgetView(entry: entry)
        }
        .configurationDisplayName("Silicon Info")
        .description("CPU, GPU, Neural Engine, memory and power. Keep the Silicon Info app running to keep it fresh.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
