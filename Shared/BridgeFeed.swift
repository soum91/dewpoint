import Foundation

/// The Govee reading as the Keystone Bridge hears it. The sensor only broadcasts, so any number of
/// listeners can hear it; the bridge is plugged in and listening all day, the phone is not. iOS gives an
/// app no Bluetooth scanning in the background, so the widget reads the bridge instead.
struct BridgeRoom: Equatable {
    var name: String
    var tempC: Double
    var humidity: Double
    var battery: Int
    var at: Date
}

enum BridgeFeed {
    struct Host: Codable, Equatable { var host: String; var port: Int }

    static var host: Host? {
        get { AppGroup.read(Host.self, "bridge-host.json") }
        set { if let newValue { AppGroup.write(newValue, "bridge-host.json") } else { AppGroup.remove("bridge-host.json") } }
    }

    /// Asks the bridge (home Wi-Fi only) for its Govee reading. Nil when it can't be reached or hasn't heard the sensor.
    static func fetch(_ h: Host? = BridgeFeed.host, timeout: TimeInterval = 4) async -> BridgeRoom? {
        guard let h, let u = URL(string: "http://\(h.host):\(h.port)/api/info?lite=1") else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["app"] as? String == "afterglow-bridge",
              let g = obj["govee"] as? [String: Any],
              let t = (g["temp"] as? NSNumber)?.doubleValue,
              let hum = (g["humidity"] as? NSNumber)?.doubleValue else { return nil }
        let ago = (g["heardAgo"] as? NSNumber)?.doubleValue ?? 0
        return BridgeRoom(name: (g["name"] as? String) ?? "", tempC: t, humidity: hum,
                          battery: (g["battery"] as? NSNumber)?.intValue ?? -1,
                          at: Date().addingTimeInterval(-max(0, ago)))
    }
}

extension SnapshotStore.Snapshot {
    /// This snapshot with the bridge's newer reading in it (the sensor's calibration still applies).
    func withBridge(_ r: BridgeRoom) -> SnapshotStore.Snapshot {
        var s = self
        s.tempC = r.tempC + tOff
        s.humidity = min(100, max(0, r.humidity + hOff))
        if r.battery >= 0 { s.battery = r.battery }
        s.at = r.at
        return s
    }

    func matches(_ r: BridgeRoom, onlyOne: Bool) -> Bool {
        if let a = adv, !a.isEmpty, !r.name.isEmpty { return a.caseInsensitiveCompare(r.name) == .orderedSame }
        return onlyOne
    }
}
