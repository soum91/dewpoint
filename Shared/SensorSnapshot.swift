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
        let snaps: [Snapshot] = sensors.compactMap { s in
            guard let r = live[s.id] else { return nil }
            return Snapshot(id: s.id.uuidString, name: s.displayName, tempC: s.calibratedTemp(r.tempC),
                            humidity: s.calibratedHumidity(r.humidity), battery: r.battery, at: r.lastSeen)
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
        if let shared = AppGroup.read([Snapshot].self, "sensor-widget.json") { return shared }
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode([Snapshot].self, from: data) else { return [] }
        return s
    }
}
