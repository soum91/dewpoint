import SwiftUI
import WidgetKit
import AppIntents

@main struct DewPointWidgets: WidgetBundle {
    var body: some Widget {
        LegacyRoomWidget()
        CompactTemperatureWidget()
        if #available(iOS 17.0, *) { RoomWidget() }
        if #available(iOS 18.0, *) { RoomTemperatureControl(); RoomHumidityControl(); ProbeAControl(); ProbeBControl(); ProbeCControl() }
    }
}
struct RoomEntry: TimelineEntry {
    var date: Date
    var sensor: SnapshotStore.Snapshot?
    var temperature: String {
        guard let s = sensor else { return "--" }
        let f = AppGroup.read(String.self, "unit.json") == "fahrenheit"
        return String(format: "%.1f%@", f ? s.tempC * 9 / 5 + 32 : s.tempC, f ? "°F" : "°C")
    }
    var humidity: String { sensor.map { String(format: "%.0f%%", $0.humidity) } ?? "--" }
    static func make(_ id: String? = nil) -> RoomEntry {
        let list = SnapshotStore.load()
        let sensor = id.flatMap { chosen in list.first { $0.id == chosen } } ?? list.first
        return .init(date: .now, sensor: sensor)
    }
}
struct LegacyRoomProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoomEntry { .make() }
    func getSnapshot(in context: Context, completion: @escaping (RoomEntry) -> Void) { completion(.make()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RoomEntry>) -> Void) {
        completion(Timeline(entries: [.make()], policy: .after(.now.addingTimeInterval(900))))
    }
}
@available(iOS 17.0, *) struct RoomProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RoomEntry { .make() }
    func snapshot(for configuration: RoomWidgetConfiguration, in context: Context) async -> RoomEntry { .make(configuration.sensor?.id) }
    func timeline(for configuration: RoomWidgetConfiguration, in context: Context) async -> Timeline<RoomEntry> {
        Timeline(entries: [.make(configuration.sensor?.id)], policy: .after(.now.addingTimeInterval(900)))
    }
}
struct LegacyRoomWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DewPointRoom", provider: LegacyRoomProvider()) { RoomView(entry: $0) }
            .configurationDisplayName("Room temperature & humidity").description("Latest room reading and measurement time.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
// Dedicated, read-only 1x1 Lock Screen temperature. Intentionally minimal:
// no button, accessory background, or dynamic layout that can clip in a circle.
struct CompactTemperatureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DewPointLockTemperatureV2", provider: LegacyRoomProvider()) { entry in
            Group {
                if #available(iOS 17.0, *) {
                    CompactTemperatureView(entry: entry)
                        .containerBackground(for: .widget) { Color.clear }
                } else {
                    CompactTemperatureView(entry: entry)
                }
            }
        }
        .configurationDisplayName("Temperature 1x1")
        .description("A compact thermometer and your latest saved Govee temperature.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
struct CompactTemperatureView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RoomEntry

    var body: some View {
        Group {
            if family == .accessoryCircular {
                VStack(spacing: 1) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 16, weight: .semibold))
                    Text(entry.temperature)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.medium")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.sensor?.name ?? "DewPoint")
                            .font(.caption2).lineLimit(1)
                        Text(entry.temperature).font(.headline).lineLimit(1)
                    }
                }
            }
        }
    }
}
@available(iOS 17.0, *) struct RoomWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DewPointSelectedRoom", intent: RoomWidgetConfiguration.self, provider: RoomProvider()) { RoomView(entry: $0) }
            .configurationDisplayName("Choose a room").description("Select a sensor for each widget.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
struct RoomView: View {
    @Environment(\.widgetFamily) var family
    let entry: RoomEntry
    @ViewBuilder var content: some View {
        if family == .accessoryInline {
            Text("\(entry.sensor?.name ?? "DewPoint") \(entry.temperature) · \(entry.humidity)")
        } else if family == .accessoryCircular {
            ZStack { AccessoryWidgetBackground(); VStack(spacing: 1) {
                Image(systemName: "thermometer.medium")
                Text(entry.temperature).font(.caption.bold()).minimumScaleFactor(0.6)
            } }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Label(entry.sensor?.name ?? "DewPoint", systemImage: "thermometer.medium").font(.caption.bold()).lineLimit(1)
                Text("\(entry.temperature) · \(entry.humidity)").font(family == .systemSmall ? .title3.bold() : .headline).minimumScaleFactor(0.6)
                if let s = entry.sensor {
                    Text("\(s.humidity < 30 ? "Dry" : s.humidity < 60 ? "Comfortable" : "Humid")" + (s.battery >= 0 ? " · \(s.battery)% battery" : "")).font(.caption2)
                    Text("Updated \(s.at, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
                } else { Text("Open DewPoint near your sensor").font(.caption2) }
            }
        }
    }
    var body: some View {
        Group {
            if #available(iOS 17.0, *) { content.containerBackground(for: .widget) { Color.clear } }
            else { content.padding(4) }
        }
    }
}
@available(iOS 18.0, *) struct RoomControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: RoomControlConfiguration) -> RoomEntry { .make(configuration.sensor?.id) }
    func currentValue(configuration: RoomControlConfiguration) async throws -> RoomEntry { .make(configuration.sensor?.id) }
}
@available(iOS 18.0, *) struct RoomTemperatureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.dewpoint.app.temperature", provider: RoomControlProvider()) { entry in
            ControlWidgetButton(action: OpenRoomIntent(entry.sensor?.id ?? "")) {
                Image(systemName: "thermometer.medium")
                    .controlWidgetActionHint("Open DewPoint to refresh room temperature")
            }
        }.displayName("Room temperature").description("Latest saved temperature. Opens the sensor to refresh over Bluetooth.")
    }
}
@available(iOS 18.0, *) struct RoomHumidityControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.dewpoint.app.humidity", provider: RoomControlProvider()) { entry in
            ControlWidgetButton(action: OpenRoomIntent(entry.sensor?.id ?? "")) {
                Label("\(entry.sensor?.name ?? "Room") · \(entry.humidity)", systemImage: "humidity.fill")
            }
        }.displayName("Room humidity").description("Latest saved humidity. Opens the sensor to refresh over Bluetooth.")
    }
}
