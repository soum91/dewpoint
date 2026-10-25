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
        let snaps: [Snapshot] = sensors.compactMap { s in
            guard let r = live[s.id] else {
                guard let old = previous.first(where: { $0.id == s.id.uuidString || ($0.id.isEmpty && $0.name == s.displayName) }) else { return nil }
                return Snapshot(id: s.id.uuidString, name: s.displayName, tempC: old.tempC, humidity: old.humidity, battery: old.battery, at: old.at)
            }
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
