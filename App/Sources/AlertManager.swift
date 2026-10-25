import Foundation
import UserNotifications

/// Local notifications when a sensor leaves its comfort range.
/// Note: iOS only delivers Govee advertisements while the app is open (or recently backgrounded),
/// so for 24/7 alerts use the Apple Home bridge and a Home automation.
final class AlertManager {
    static let shared = AlertManager()
    private var lastFired: [String: Date] = [:]
    private let cooldown: TimeInterval = 30 * 60

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func evaluate(sensor: SensorInfo, reading: LiveReading) {
        let cfg = sensor.alerts
        guard cfg.enabled else { return }
        let t = sensor.calibratedTemp(reading.tempC)
        let h = sensor.calibratedHumidity(reading.humidity)
        let unit = TempUnit(rawValue: UserDefaults.standard.string(forKey: "tempUnit") ?? "") ?? .celsius

        if let lo = cfg.lowTempC, t < lo {
            fire(sensor, kind: "lowT", title: "\(sensor.displayName) is cold",
                 body: "Temperature is \(unit.format(t)) (below \(unit.format(lo))).")
        }
        if let hi = cfg.highTempC, t > hi {
            fire(sensor, kind: "highT", title: "\(sensor.displayName) is warm",
                 body: "Temperature is \(unit.format(t)) (above \(unit.format(hi))).")
        }
        if let lo = cfg.lowHumidity, h < lo {
            fire(sensor, kind: "lowH", title: "\(sensor.displayName) is dry",
                 body: "Humidity is \(h.clean())% (below \(lo.clean(0))%).")
        }
        if let hi = cfg.highHumidity, h > hi {
            fire(sensor, kind: "highH", title: "\(sensor.displayName) is humid",
                 body: "Humidity is \(h.clean())% (above \(hi.clean(0))%).")
        }
        if cfg.lowBattery, reading.battery > 0, reading.battery <= 15 {
            fire(sensor, kind: "batt", title: "\(sensor.displayName) battery low",
                 body: "Battery is at \(reading.battery)%. Swap the AAA cells soon.", cooldown: 24 * 3600)
        }
    }

    private func fire(_ s: SensorInfo, kind: String, title: String, body: String, cooldown: TimeInterval? = nil) {
        let key = "\(s.id.uuidString)-\(kind)"
        if let last = lastFired[key], Date().timeIntervalSince(last) < (cooldown ?? self.cooldown) { return }
        lastFired[key] = Date()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: key + "-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
