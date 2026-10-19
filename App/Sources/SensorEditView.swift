import SwiftUI

struct SensorEditView: View {
    @EnvironmentObject var ble: BLEManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("tempUnit") private var unitRaw = TempUnit.celsius.rawValue
    @State private var s: SensorInfo

    init(sensor: SensorInfo) { _s = State(initialValue: sensor) }
    private var unit: TempUnit { TempUnit(rawValue: unitRaw) ?? .celsius }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("\(s.model) \(s.shortTag)", text: Binding(
                        get: { s.customName ?? "" },
                        set: { s.customName = $0 }))
                    LabeledContent("Model", value: s.model)
                    LabeledContent("Bluetooth name", value: s.advertisedName)
                }

                Section {
                    Stepper(value: tempOffsetBinding, in: -10...10, step: 0.1) {
                        LabeledContent("Temperature", value: String(format: "%+.1f%@", unit.convertDelta(s.tempOffsetC), unit.symbol))
                    }
                    Stepper(value: $s.humidityOffset, in: -20...20, step: 0.5) {
                        LabeledContent("Humidity", value: String(format: "%+.1f%%", s.humidityOffset))
                    }
                } header: { Text("Calibration") } footer: {
                    Text("Applied to live readings, the chart and exports. Stored data stays raw, so you can change this any time.")
                }

                Section {
                    Toggle("Alerts", isOn: $s.alerts.enabled)
                    if s.alerts.enabled {
                        thresholdRow("Below", temp: \.lowTempC, default: 18)
                        thresholdRow("Above", temp: \.highTempC, default: 26)
                        humidityRow("Below", \.lowHumidity, default: 30)
                        humidityRow("Above", \.highHumidity, default: 60)
                        Toggle("Low battery", isOn: $s.alerts.lowBattery)
                    }
                } header: { Text("Alerts") } footer: {
                    Text("iOS only hears the sensor while DewPoint is open or recently used. For round-the-clock alerts, use the Apple Home bridge with a Home automation.")
                }
            }
            .navigationTitle("Edit Sensor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if s.alerts.enabled { AlertManager.shared.requestPermission() }
                        ble.update(s)
                        dismiss()
                    }
                }
            }
        }
    }

    private var tempOffsetBinding: Binding<Double> {
        Binding(get: { unit.convertDelta(s.tempOffsetC) },
                set: { s.tempOffsetC = unit.deltaToCelsius($0) })
    }

    @ViewBuilder
    private func thresholdRow(_ label: String, temp kp: WritableKeyPath<AlertConfig, Double?>, default def: Double) -> some View {
        let on = Binding<Bool>(get: { s.alerts[keyPath: kp] != nil },
                               set: { s.alerts[keyPath: kp] = $0 ? def : nil })
        Toggle("Temp \(label.lowercased())", isOn: on)
        if let v = s.alerts[keyPath: kp] {
            Stepper(value: Binding(get: { unit.convert(v) },
                                   set: { s.alerts[keyPath: kp] = unit.toCelsius($0) }),
                    in: unit.convert(-20)...unit.convert(50), step: 0.5) {
                Text("\(label) \(String(format: "%.1f", unit.convert(v)))\(unit.symbol)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func humidityRow(_ label: String, _ kp: WritableKeyPath<AlertConfig, Double?>, default def: Double) -> some View {
        let on = Binding<Bool>(get: { s.alerts[keyPath: kp] != nil },
                               set: { s.alerts[keyPath: kp] = $0 ? def : nil })
        Toggle("Humidity \(label.lowercased())", isOn: on)
        if let v = s.alerts[keyPath: kp] {
            Stepper(value: Binding(get: { v }, set: { s.alerts[keyPath: kp] = $0 }), in: 0...100, step: 1) {
                Text("\(label) \(Int(v))%").foregroundStyle(.secondary)
            }
        }
    }
}
