import Foundation
import SwiftUI

// MARK: - Readings

/// One stored measurement. Values are RAW (uncalibrated); offsets are applied at display time
/// so changing a calibration later fixes the whole history too.
struct Reading: Codable, Hashable, Identifiable {
    var id: Date { date }
    let date: Date
    let tempC: Double
    let humidity: Double
}

/// Latest advertisement from a sensor. Not persisted.
struct LiveReading: Equatable {
    var tempC: Double
    var humidity: Double
    var battery: Int
    var rssi: Int
    var lastSeen: Date
    var model: String
    var name: String
}

// MARK: - Sensors

struct AlertConfig: Codable, Hashable {
    var enabled: Bool = false
    var lowTempC: Double? = nil
    var highTempC: Double? = nil
    var lowHumidity: Double? = nil
    var highHumidity: Double? = nil
    var lowBattery: Bool = true
}

struct SensorInfo: Codable, Identifiable, Hashable {
    let id: UUID                 // CoreBluetooth peripheral identifier (stable per phone)
    var model: String            // e.g. "H5102"
    var advertisedName: String   // e.g. "GVH5102_9A4C"
    var customName: String?
    var tempOffsetC: Double = 0
    var humidityOffset: Double = 0
    var lastHistorySync: Date?
    var alerts = AlertConfig()

    var shortTag: String {
        if let r = advertisedName.range(of: "_", options: .backwards) {
            return String(advertisedName[r.upperBound...])
        }
        return String(id.uuidString.prefix(4))
    }

    var displayName: String {
        if let c = customName?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        return "\(model) \(shortTag)"
    }

    func calibratedTemp(_ raw: Double) -> Double { raw + tempOffsetC }
    func calibratedHumidity(_ raw: Double) -> Double { min(100, max(0, raw + humidityOffset)) }
}

// MARK: - Units & climate math

enum TempUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var symbol: String { self == .celsius ? "°C" : "°F" }

    func convert(_ c: Double) -> Double { self == .celsius ? c : c * 9 / 5 + 32 }
    /// Convert a delta (offsets) rather than an absolute temperature.
    func convertDelta(_ c: Double) -> Double { self == .celsius ? c : c * 9 / 5 }
    func toCelsius(_ v: Double) -> Double { self == .celsius ? v : (v - 32) * 5 / 9 }
    func deltaToCelsius(_ v: Double) -> Double { self == .celsius ? v : v * 5 / 9 }

    func format(_ c: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f%@", convert(c), symbol)
    }
}

enum Climate {
    /// Magnus–Tetens dew point, °C.
    static func dewPoint(tempC t: Double, humidity rh: Double) -> Double {
        let h = max(rh, 0.1)
        let a = 17.62, b = 243.12
        let g = log(h / 100) + a * t / (b + t)
        return b * g / (a - g)
    }

    /// Absolute humidity in g/m³.
    static func absoluteHumidity(tempC t: Double, humidity rh: Double) -> Double {
        let es = 6.112 * exp(17.67 * t / (t + 243.5))
        return es * rh * 2.1674 / (273.15 + t)
    }

    static func comfort(humidity rh: Double) -> (label: String, color: Color) {
        switch rh {
        case ..<30: return ("Dry", .orange)
        case ..<60: return ("Comfortable", .green)
        case ..<70: return ("Humid", .yellow)
        default: return ("Very humid", .red)
        }
    }
}

extension Date {
    var flooredToMinute: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 / 60).rounded(.down) * 60)
    }
}

extension Double {
    func clean(_ decimals: Int = 1) -> String { String(format: "%.\(decimals)f", self) }
}
