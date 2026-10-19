import AppIntents
import Foundation

private func ageText(_ d: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f.localizedString(for: d, relativeTo: Date())
}

struct GetTemperatureIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Room Temperature"
    static var description = IntentDescription("Latest temperature from your first Govee sensor, in your chosen unit.")

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        guard let s = SnapshotStore.load().first else {
            return .result(value: .nan, dialog: IntentDialog(stringLiteral: "No reading yet. Open DewPoint near the sensor first."))
        }
        let unit = TempUnit(rawValue: UserDefaults.standard.string(forKey: "tempUnit") ?? "") ?? .celsius
        let v = (unit.convert(s.tempC) * 10).rounded() / 10
        return .result(value: v, dialog: IntentDialog(stringLiteral: "\(s.name) is \(unit.format(s.tempC)), updated \(ageText(s.at))."))
    }
}

struct GetHumidityIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Room Humidity"
    static var description = IntentDescription("Latest relative humidity from your first Govee sensor.")

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        guard let s = SnapshotStore.load().first else {
            return .result(value: .nan, dialog: IntentDialog(stringLiteral: "No reading yet. Open DewPoint near the sensor first."))
        }
        let v = (s.humidity * 10).rounded() / 10
        return .result(value: v, dialog: IntentDialog(stringLiteral: "\(s.name) humidity is \(v.clean())%, updated \(ageText(s.at))."))
    }
}

struct DewPointShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetTemperatureIntent(), phrases: ["What's the temperature in \(.applicationName)"])
        AppShortcut(intent: GetHumidityIntent(), phrases: ["What's the humidity in \(.applicationName)"])
    }
}
