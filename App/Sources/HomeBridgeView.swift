import SwiftUI

struct HomeBridgeView: View {
    @EnvironmentObject var ble: BLEManager
    private let repo = URL(string: "https://github.com/soum91/dewpoint/tree/main/Bridge")!
    private let flasher = URL(string: "https://espressif.github.io/esptool-js/")!

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "homekit").font(.largeTitle).foregroundStyle(Theme.accent)
                        Text("Govee sensors don't speak HomeKit, and Apple doesn't let an iPhone app invent Home accessories. The fix is a tiny always-on bridge: a ~$10 ESP32 board that listens to your H5102 over Bluetooth and shows it in the Home app as a real temperature + humidity sensor.")
                            .font(.subheadline)
                    }
                    .padding(.vertical, 6)
                }

                Section("What you get in Apple Home") {
                    Label("Temperature, humidity and battery tiles", systemImage: "thermometer.medium")
                    Label("Automations, e.g. AC on above 25°C", systemImage: "wand.and.stars")
                    Label("Works 24/7 with your phone anywhere (via a home hub)", systemImage: "appletv")
                    Label("Siri: \"What's the temperature in the bedroom?\"", systemImage: "waveform")
                }

                Section {
                    step(1, "Get an ESP32 board", "Any ESP32, ESP32-S3 or ESP32-C3 dev board with USB. Plug it in near the sensor.")
                    step(2, "Flash the firmware", "Grab the .bin for your chip from the repo's Bridge page, open the web flasher in Chrome on a computer, connect, and write it at address 0x0.")
                    step(3, "Join its Wi-Fi", "Join the \"HomeSpan-Setup\" network (password homespan), enter your 2.4 GHz Wi-Fi and a setup code.")
                    step(4, "Add to Home", "Home app > + > Add Accessory > More options, pick \"DewPoint Bridge\" and enter the setup code (default 466-37-726).")
                } header: { Text("Setup") } footer: {
                    Text("On first boot the bridge locks onto the strongest Govee sensor it hears in 30 seconds, so keep it close to the right one.")
                }

                Section {
                    Link(destination: repo) { Label("Bridge firmware & guide", systemImage: "arrow.down.circle") }
                    Link(destination: flasher) { Label("ESP web flasher", systemImage: "bolt.horizontal.circle") }
                }

                if !ble.sensors.isEmpty {
                    Section("Your sensors' Bluetooth names") {
                        ForEach(ble.sensors) { s in
                            LabeledContent(s.displayName, value: s.advertisedName)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("No ESP32?") {
                    Text("If you run Homebridge on a Raspberry Pi or a computer with Bluetooth, the homebridge-govee plugin can expose the H5102 too. The ESP32 is cheaper and needs no maintenance.")
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
