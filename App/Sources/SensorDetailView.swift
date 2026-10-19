import SwiftUI
import Charts

enum ChartRange: String, CaseIterable, Identifiable {
    case hour = "1H", day = "24H", week = "7D", twenty = "20D", all = "All"
    var id: String { rawValue }
    var seconds: TimeInterval? {
        switch self {
        case .hour: return 3600
        case .day: return 86400
        case .week: return 7 * 86400
        case .twenty: return 20 * 86400
        case .all: return nil
        }
    }
}

enum Metric: String, CaseIterable, Identifiable {
    case temperature = "Temp", humidity = "Humidity", dewPoint = "Dew point"
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .temperature: return Theme.accent
        case .humidity: return Theme.humidity
        case .dewPoint: return Theme.dew
        }
    }
}

struct ChartPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct SensorDetailView: View {
    let sensorID: UUID
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var history: HistoryStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("tempUnit") private var unitRaw = TempUnit.celsius.rawValue
    @State private var range: ChartRange = .day
    @State private var metric: Metric = .temperature
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var exportFile: ExportFile?

    private var unit: TempUnit { TempUnit(rawValue: unitRaw) ?? .celsius }
    private var sensor: SensorInfo? { ble.sensor(sensorID) }

    var body: some View {
        if let sensor {
            List {
                Section { header(sensor) }
                Section { chartSection(sensor) }
                Section { syncRow(sensor) } footer: {
                    Text("Pulls the up-to-20 days of minute-by-minute data stored on the sensor, so gaps while your phone was away get filled.")
                }
                Section {
                    Button {
                        if let url = history.csv(for: sensorID, sensor: sensor, unit: unit) {
                            exportFile = ExportFile(url: url)
                        }
                    } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                    Button { editing = true } label: { Label("Name, calibration & alerts", systemImage: "slider.horizontal.3") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Remove sensor", systemImage: "trash") }
                }
            }
            .navigationTitle(sensor.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editing) { SensorEditView(sensor: sensor) }
            .sheet(item: $exportFile) { f in ShareSheet(items: [f.url]) }
            .confirmationDialog("Remove \(sensor.displayName) and its history?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    ble.remove(sensorID)
                    dismiss()
                }
            }
        } else {
            Text("Sensor removed").foregroundStyle(.secondary)
        }
    }

    // MARK: Header

    @ViewBuilder
    private func header(_ s: SensorInfo) -> some View {
        if let r = ble.live[sensorID] {
            let t = s.calibratedTemp(r.tempC)
            let h = s.calibratedHumidity(r.humidity)
            let d = Climate.dewPoint(tempC: t, humidity: h)
            let comfort = Climate.comfort(humidity: h)
            VStack(spacing: 14) {
                Text(String(format: "%.1f", unit.convert(t)) + unit.symbol)
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.tempColor(t))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                Text(comfort.label)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(comfort.color.opacity(0.18), in: Capsule())
                    .foregroundStyle(comfort.color)
                HStack {
                    stat("Humidity", "\(h.clean())%", "humidity.fill", Theme.humidity)
                    stat("Dew point", unit.format(d), "drop.fill", Theme.dew)
                    stat("Abs. hum.", "\(Climate.absoluteHumidity(tempC: t, humidity: h).clean()) g/m³", "cloud.fill", .secondary)
                }
                HStack(spacing: 16) {
                    Label("\(r.battery)%", systemImage: Theme.batteryIcon(r.battery))
                        .foregroundStyle(r.battery <= 15 ? .red : .secondary)
                    Label("\(r.rssi) dBm", systemImage: "antenna.radiowaves.left.and.right")
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        Label { Text(r.lastSeen, style: .relative) } icon: { Image(systemName: "clock") }
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } else {
            VStack(spacing: 8) {
                ProgressView()
                Text("Listening for \(s.displayName)…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding()
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Chart

    private func points(_ s: SensorInfo) -> [ChartPoint] {
        _ = history.revision
        let raw: [Reading]
        if let secs = range.seconds {
            raw = history.readings(for: sensorID, since: Date().addingTimeInterval(-secs))
        } else {
            raw = history.readings(for: sensorID)
        }
        guard !raw.isEmpty else { return [] }
        let bucket = max(1, raw.count / 400)
        var out: [ChartPoint] = []
        out.reserveCapacity(raw.count / bucket + 1)
        var i = 0
        while i < raw.count {
            let slice = raw[i..<min(i + bucket, raw.count)]
            let n = Double(slice.count)
            let t = slice.reduce(0) { $0 + s.calibratedTemp($1.tempC) } / n
            let h = slice.reduce(0) { $0 + s.calibratedHumidity($1.humidity) } / n
            let v: Double
            switch metric {
            case .temperature: v = unit.convert(t)
            case .humidity: v = h
            case .dewPoint: v = unit.convert(Climate.dewPoint(tempC: t, humidity: h))
            }
            out.append(ChartPoint(date: slice[slice.startIndex].date, value: v))
            i += bucket
        }
        return out
    }

    @ViewBuilder
    private func chartSection(_ s: SensorInfo) -> some View {
        let pts = points(s)
        VStack(alignment: .leading, spacing: 12) {
            Picker("Metric", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if pts.count < 2 {
                Text("Not enough data for this range yet. Leave the app open for a bit or sync history.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                let vals = pts.map(\.value)
                let lo = vals.min() ?? 0, hi = vals.max() ?? 0
                let avg = vals.reduce(0, +) / Double(vals.count)
                let pad = max(0.5, (hi - lo) * 0.15)
                let suffix = metric == .humidity ? "%" : "°"
                HStack {
                    miniStat("Min", lo, suffix)
                    miniStat("Avg", avg, suffix)
                    miniStat("Max", hi, suffix)
                }
                Chart(pts) { p in
                    AreaMark(x: .value("Time", p.date),
                             yStart: .value("Base", lo - pad),
                             yEnd: .value("Value", p.value))
                        .foregroundStyle(LinearGradient(colors: [metric.color.opacity(0.35), metric.color.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", p.date), y: .value("Value", p.value))
                        .foregroundStyle(metric.color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: (lo - pad)...(hi + pad))
                .frame(height: 220)
            }

            Picker("Range", selection: $range) {
                ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 6)
    }

    private func miniStat(_ title: String, _ v: Double, _ suffix: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(v.clean() + suffix).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Sync

    @ViewBuilder
    private func syncRow(_ s: SensorInfo) -> some View {
        let state = ble.sync[sensorID] ?? .idle
        Button {
            ble.syncHistory(sensorID)
        } label: {
            HStack {
                Label("Sync history from sensor", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                if state.isBusy { ProgressView() }
            }
        }
        .disabled(state.isBusy)

        switch state {
        case .connecting:
            Text("Connecting…").font(.caption).foregroundStyle(.secondary)
        case .downloading(let got, let req):
            ProgressView(value: Double(min(got, req)), total: Double(max(req, 1))) {
                Text("Downloaded \(got) of ~\(req) points").font(.caption)
            }
        case .done(let n, let at):
            Text("Synced \(at.formatted(date: .omitted, time: .shortened)) · \(n) new points")
                .font(.caption).foregroundStyle(.secondary)
        case .failed(let msg):
            Text(msg).font(.caption).foregroundStyle(.red)
        case .idle:
            if let last = s.lastHistorySync {
                Text("Last synced \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
