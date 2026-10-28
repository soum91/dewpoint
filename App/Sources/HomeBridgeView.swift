import SwiftUI

struct HomeBridgeView: View {
    @EnvironmentObject var ble: BLEManager
    @Environment(\.openURL) private var openURL
    private let installer = URL(string: "https://soum91.github.io/afterglow/")!

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "homekit").font(.largeTitle).foregroundStyle(Theme.accent)
                        Text("Your Govee reaches Apple Home through the Keystone Bridge, the same ESP32 that carries your lights, TV, purifier, sound bar and AC. It listens to the H5102 over Bluetooth and shows it in Home as a temperature, humidity and battery sensor.")
                            .font(.subheadline)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    Button { openURL(URL(string: "keystone://")!) } label: {
                        Label("Open Keystone", systemImage: "cpu")
                    }
                } footer: {
                    Text("Keystone shows what the bridge hears from the Govee (Home tab › Room), and Bridge › Pick a different Govee sensor if it locked onto the wrong one.")
                }

                Section("What you get in Apple Home") {
                    Label("Temperature, humidity and battery tiles", systemImage: "thermometer.medium")
                    Label("Automations, e.g. AC on above 25°C", systemImage: "wand.and.stars")
                    Label("Smart Auto on the AC uses this reading", systemImage: "air.conditioner.horizontal")
                    Label("Siri: \"What's the temperature in the bedroom?\"", systemImage: "waveform")
                }

                Section {
                    step(1, "Flash the bridge", "On a computer, open the installer page in Chrome, plug the ESP32 in and click Connect and install.")
                    step(2, "Join its Wi-Fi", "On your phone, join the open \"Keystone-Setup\" network. The setup page pops up: pick your 2.4 GHz Wi-Fi.")
                    step(3, "Add to Home", "Home app › + › Add Accessory › More options › \"Keystone Bridge\", code 466-37-726.")
                    step(4, "Pair Keystone", "Keystone finds the bridge on your Wi-Fi. The Govee shows up on its own.")
                } header: { Text("Setting up a new bridge") } footer: {
                    Text("On first start the bridge locks onto the strongest Govee sensor it hears for 30 seconds, so keep it close to the right one. Then it listens in short bursts every couple of minutes.")
                }

                Section {
                    Link(destination: installer) { Label("Bridge installer", systemImage: "arrow.down.circle") }
                }

                if !ble.sensors.isEmpty {
                    Section("Your sensors' Bluetooth names") {
                        ForEach(ble.sensors) { s in
                            LabeledContent(s.displayName, value: s.advertisedName)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Text("Apple Home only reaches accessories away from home through a home hub (HomePod or Apple TV). Without one, open Keystone instead: it reaches the bridge from anywhere.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Apple Home")
        }
    }

    private func step(_ n: Int, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.headline).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SettingsView: View {
    @EnvironmentObject var ble: BLEManager
    @AppStorage("tempUnit") private var unitRaw = TempUnit.celsius.rawValue
    @State private var lastPublished: Date?

    private var sharedSnapshots: [SnapshotStore.Snapshot] {
        AppGroup.read([SnapshotStore.Snapshot].self, "sensor-widget.json") ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Temperature", selection: $unitRaw) {
                        Text("Celsius").tag(TempUnit.celsius.rawValue)
                        Text("Fahrenheit").tag(TempUnit.fahrenheit.rawValue)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Text("Ask Siri \"What's the temperature in DewPoint\", or use the Get Room Temperature / Humidity actions in the Shortcuts app.")
                        .font(.footnote)
                } header: { Text("Shortcuts & Siri") }
                Section("Lock Screen widget diagnostics") {
                    LabeledContent("Shared container", value: AppGroup.isShared ? "Connected" : "Unavailable")
                    LabeledContent("Group", value: AppGroup.activeGroup ?? "No shared group")
                        .font(.caption)
                    LabeledContent("Added sensors", value: "\(ble.sensors.count)")
                    LabeledContent("Live readings", value: "\(ble.live.count)")
                    LabeledContent("Shared snapshots", value: "\(sharedSnapshots.count)")
                    if let s = sharedSnapshots.first {
                        LabeledContent("Saved temperature", value: String(format: "%.1f°C", s.tempC))
                        LabeledContent("Reading age", value: s.at.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("Publish widget reading now") {
                        SnapshotStore.save(sensors: ble.sensors, live: ble.live)
                        lastPublished = .now
                    }
                    if let lastPublished {
                        Text("Last publish: \(lastPublished, style: .time)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Only sensors added on the Sensors tab are sent to the widget. If shared snapshots stay at 0 while live readings are available, send a screenshot of this section.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Sensors", value: "\(ble.sensors.count)")
                    Text("No account, no cloud, no ads. Everything stays on this phone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
