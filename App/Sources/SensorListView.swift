import SwiftUI
import CoreBluetooth

struct SensorListView: View {
    @EnvironmentObject var ble: BLEManager
    @AppStorage("tempUnit") private var unitRaw = TempUnit.celsius.rawValue
    private var unit: TempUnit { TempUnit(rawValue: unitRaw) ?? .celsius }

    var body: some View {
        NavigationStack {
            List {
                if ble.bluetoothState != .poweredOn && ble.bluetoothState != .unknown {
                    Section {
                        Label(bluetoothMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if ble.sensors.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No sensors yet").font(.headline)
                            Text("Keep your H5102 within a few metres. It shows up under Nearby within a few seconds. Tap Add.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    Section {
                        ForEach(ble.sensors) { s in
                            NavigationLink(value: s.id) {
                                SensorCard(sensor: s, reading: ble.live[s.id], unit: unit)
                            }
                        }
                        .onMove { ble.move(from: $0, to: $1) }
                    }
                }

                let nearby = ble.nearby.sorted { $0.value.rssi > $1.value.rssi }
                Section {
                    if nearby.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Scanning for Govee sensors…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(nearby, id: \.key) { item in
                        let id = item.key
                        let r = item.value
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name.isEmpty ? r.model : r.name).font(.body.weight(.medium))
                                Text("\(unit.format(r.tempC)) · \(r.humidity.clean())% · \(r.rssi) dBm")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") {
                                withAnimation { ble.add(id) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Text("Nearby")
                } footer: {
                    Text("Only sensors you add are logged. Neighbours' sensors stay out of your history.")
                }
            }
            .navigationTitle("DewPoint")
            .navigationDestination(for: UUID.self) { id in
                SensorDetailView(sensorID: id)
            }
            .toolbar {
                if !ble.sensors.isEmpty { EditButton() }
            }
        }
    }

    private var bluetoothMessage: String {
        switch ble.bluetoothState {
        case .poweredOff: return "Bluetooth is off. Turn it on in Control Center."
        case .unauthorized: return "Bluetooth permission denied. Enable it in Settings > DewPoint."
        case .unsupported: return "This device doesn't support Bluetooth LE."
        default: return "Bluetooth isn't ready."
        }
    }
}

struct SensorCard: View {
    let sensor: SensorInfo
    let reading: LiveReading?
    let unit: TempUnit

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let r = reading {
                let t = sensor.calibratedTemp(r.tempC)
                let h = sensor.calibratedHumidity(r.humidity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(sensor.displayName).font(.headline)
                    HStack(spacing: 10) {
                        Label("\(h.clean())%", systemImage: "humidity.fill")
                            .foregroundStyle(Theme.humidity)
                        Label("\(r.battery)%", systemImage: Theme.batteryIcon(r.battery))
                            .foregroundStyle(r.battery <= 15 ? .red : .secondary)
                    }
                    .font(.caption)
                    TimelineView(.periodic(from: .now, by: 15)) { _ in
                        Text(r.lastSeen, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                        + Text(" ago").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Text(String(format: "%.1f°", unit.convert(t)))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.tempColor(t))
                    .monospacedDigit()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sensor.displayName).font(.headline)
                    Text("Waiting for a reading…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("--°")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}
