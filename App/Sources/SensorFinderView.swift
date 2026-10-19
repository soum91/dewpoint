import SwiftUI

/// Shows every Govee-looking Bluetooth device in range, strongest first, with raw data.
/// Hold your sensor against the phone: yours is the one whose signal jumps to the top.
struct SensorFinderView: View {
    @EnvironmentObject var ble: BLEManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("tempUnit") private var unitRaw = TempUnit.celsius.rawValue
    private var unit: TempUnit { TempUnit(rawValue: unitRaw) ?? .celsius }
    @State private var showAll = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Hold your sensor right against the phone. Yours is the one that jumps to the top with a signal around -40 dBm or stronger. Compare the 4 characters after the underscore with the end of the MAC on the sensor's label or in the Govee app.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("Show every Bluetooth device", isOn: $showAll)
                        .onChange(of: showAll) { ble.captureAll = $0 }
                }

                let items = Array(ble.raw.sorted { $0.value.rssi > $1.value.rssi }.prefix(40))
                if items.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Listening…").foregroundStyle(.secondary)
                    }
                }
                ForEach(items, id: \.key) { item in
                    row(id: item.key, r: item.value)
                }
            }
            .navigationTitle("Find My Sensor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { ble.captureRaw = true }
            .onDisappear { ble.captureAll = false; ble.captureRaw = false }
        }
    }

    @ViewBuilder
    private func row(id: UUID, r: RawAdvert) -> some View {
        let added = ble.sensor(id) != nil
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(r.name.isEmpty ? "(no name)" : r.name).font(.body.weight(.semibold))
                Spacer()
                Text("\(r.rssi) dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(r.rssi > -50 ? Color.green : (r.rssi > -75 ? Color.primary : Color.secondary))
            }
            if let p = r.parsed {
                Text("\(p.model) · \(unit.format(p.tempC)) · \(p.humidity.clean())% · battery \(p.battery)%")
                    .font(.caption)
            } else {
                Text("Not decoded. If this is your sensor, send a screenshot of this row.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !r.services.isEmpty {
                Text("Services: \(r.services)").font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            Text(r.hex)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    (Text(r.lastSeen, style: .relative) + Text(" ago"))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                if added {
                    Button("Remove", role: .destructive) { ble.remove(id) }
                        .buttonStyle(.bordered).controlSize(.small)
                } else if r.parsed != nil {
                    Button("Add") { ble.add(id) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
