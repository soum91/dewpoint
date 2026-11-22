import SwiftUI

struct HomeBridgeView: View {
    @EnvironmentObject var ble: BLEManager
    @StateObject private var feed = BridgeSource.shared
    @State private var manualIP = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "homekit").font(.largeTitle).foregroundStyle(Theme.accent)
                        Text("DewPoint reads the Govee on this iPhone and forwards fresh readings to the Keystone ESP32 while the app is running. The Keystone iOS app manages the bridge and its firmware; the bridge sends temperature, humidity and battery status to Apple Home. When the iPhone cannot report, the bridge uses its own Bluetooth fallback.")
                            .font(.subheadline)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    LabeledContent("Bridge", value: feed.host?.host ?? (feed.searching ? "Searching…" : "Not found"))
                    if let r = feed.room {
                        LabeledContent("Its reading", value: String(format: "%.1f° · %.0f%%", r.tempC, r.humidity))
                    }
                    if !feed.status.isEmpty { Text(feed.status).font(.footnote).foregroundStyle(.secondary) }
                    Button("Search again") { feed.find() }
                    HStack {
                        TextField("Or type its IP", text: $manualIP).keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                        Button("Use") { feed.setManual(manualIP) }.disabled(manualIP.isEmpty)
                    }
                    LabeledContent("Feed attempts", value: "\(feed.feedAttempts)")
                    if let last = feed.lastFeedAttempt {
                        LabeledContent("Last feed attempt", value: last.formatted(date: .omitted, time: .standard))
                    }
                } header: { Text("Govee feed to Keystone") } footer: {
                    Text("DewPoint can forward only while iOS delivers Bluetooth observations. Background or suspended scanning is not guaranteed; Keystone's BLE fallback remains enabled. View the actual received-packet count in the Keystone app under Bridge › Thermometer.")
                }

                Section {
                    Button { openURL(URL(string: "keystone://")!) } label: {
                        Label("Open Keystone", systemImage: "cpu")
                    }
                } footer: {
                    Text("Open the Keystone iOS app to manage the bridge, install its firmware, inspect DewPoint feed status, and choose the Govee sensor.")
                }

                Section("What you get in Apple Home") {
                    Label("Temperature, humidity and battery tiles", systemImage: "thermometer.medium")
                    Label("Automations, e.g. AC on above 25°C", systemImage: "wand.and.stars")
                    Label("Smart Auto on the AC uses this reading", systemImage: "air.conditioner.horizontal")
                    Label("Check it from anywhere in Keystone (remote access)", systemImage: "globe")
                    Label("Siri: \"What's the temperature in the bedroom?\"", systemImage: "waveform")
                }

                Section {
                    step(1, "Open Keystone", "Use the Keystone iOS app to pair and manage the ESP32 bridge, including its firmware.")
                    step(2, "Stay on home Wi-Fi", "Open DewPoint near your Govee sensor. Its fresh readings are sent to the bridge when available.")
                    step(3, "Add in Apple Home", "The Keystone bridge exposes the thermometer, humidity and battery service.")
                } header: { Text("How the apps work together") } footer: {
                    Text("There is no DewPoint firmware to flash. Keystone is the only firmware project. Both apps can read status from the same bridge.")
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
                    Text("Away from home, Keystone reaches the bridge through its encrypted relay, so the reading (and everything else on the bridge) works from anywhere. The Apple Home app itself only works away from home with a home hub (HomePod or Apple TV).")
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
