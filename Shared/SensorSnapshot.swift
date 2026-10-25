import Foundation
import WidgetKit
enum SnapshotStore {
    struct Snapshot: Codable {
        var id: String = ""
        let name: String
        let tempC: Double
        let humidity: Double
        let battery: Int
        let at: Date
    }

    private static let key = "dewpoint.snapshot.v1"

    #if !WIDGET_EXTENSION
    static func save(sensors: [SensorInfo], live: [UUID: LiveReading]) {
        let previous = load()
        let snaps: [Snapshot] = sensors.compactMap { sensor in
            if let reading = live[sensor.id] {
                return Snapshot(id: sensor.id.uuidString, name: sensor.displayName,
                                tempC: sensor.calibratedTemp(reading.tempC),
                                humidity: sensor.calibratedHumidity(reading.humidity),
                                battery: reading.battery, at: reading.lastSeen)
            }

            // Reuse a saved reading when the sensor isn't nearby. On a fresh
            // App Group container, recover a reading from the app's private
            // history instead of replacing the widget with "--".
            let old = previous.first {
                $0.id == sensor.id.uuidString || ($0.id.isEmpty && $0.name == sensor.displayName)
            }
            if let last = HistoryStore.shared.readings(for: sensor.id).last,
               last.date > (old?.at ?? .distantPast) {
                return Snapshot(id: sensor.id.uuidString, name: sensor.displayName,
                                tempC: sensor.calibratedTemp(last.tempC),
                                humidity: sensor.calibratedHumidity(last.humidity),
                                battery: old?.battery ?? -1, at: last.date)
            }
            guard let old else { return nil }
            return Snapshot(id: sensor.id.uuidString, name: sensor.displayName,
                            tempC: old.tempC, humidity: old.humidity,
                            battery: old.battery, at: old.at)
        }
        guard let data = try? JSONEncoder().encode(snaps) else { return }
        UserDefaults.standard.set(data, forKey: key)
        AppGroup.write(snaps, "sensor-widget.json")
        AppGroup.write(UserDefaults.standard.string(forKey: "tempUnit") ?? "celsius", "unit.json")
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
    }

    #endif
    static func load() -> [Snapshot] {
        let shared = AppGroup.read([Snapshot].self, "sensor-widget.json")
        let local: [Snapshot]? = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([Snapshot].self, from: $0) }
        // A re-signed installation may get a newly created (empty) App Group.
        // Keep the app's last private snapshots until they can be republished.
        if let shared, !shared.isEmpty { return shared }
        return local ?? shared ?? []
    }
}

// Preserve pre-widget private snapshots whose payload did not yet contain a sensor ID.
extension SnapshotStore.Snapshot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decode(String.self, forKey: .name)
        tempC = try c.decode(Double.self, forKey: .tempC)
        humidity = try c.decode(Double.self, forKey: .humidity)
        battery = try c.decode(Int.self, forKey: .battery)
        at = try c.decode(Date.self, forKey: .at)
    }
}
