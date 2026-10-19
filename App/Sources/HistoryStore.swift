import Foundation

/// Per-sensor reading history, stored as JSON in Application Support. One reading per minute max.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    /// Keep this much history on the phone.
    static let retention: TimeInterval = 180 * 24 * 3600

    @Published private(set) var revision = 0   // bumps whenever any history changes
    private var cache: [UUID: [Reading]] = [:]
    private var dirty: Set<UUID> = []
    private var saveWork: DispatchWorkItem?
    private let io = DispatchQueue(label: "dewpoint.history.io")

    private var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("history", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func url(for id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).json") }

    func readings(for id: UUID) -> [Reading] {
        if let c = cache[id] { return c }
        var loaded: [Reading] = []
        if let data = try? Data(contentsOf: url(for: id)),
           let decoded = try? JSONDecoder().decode([Reading].self, from: data) {
            loaded = decoded
        }
        cache[id] = loaded
        return loaded
    }

    func readings(for id: UUID, since: Date) -> [Reading] {
        let all = readings(for: id)
        // binary search for first index >= since
        var lo = 0, hi = all.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if all[mid].date < since { lo = mid + 1 } else { hi = mid }
        }
        return Array(all[lo...])
    }

    /// Adds a live advertisement reading, at most one per minute.
    func addLive(_ r: Reading, for id: UUID) {
        var all = readings(for: id)
        let minute = r.date.flooredToMinute
        if let last = all.last, last.date >= minute { return }
        all.append(Reading(date: minute, tempC: r.tempC, humidity: r.humidity))
        cache[id] = all
        markDirty(id)
    }

    /// Merges a batch (e.g. downloaded device history). Device data wins over live data for the same minute.
    @discardableResult
    func merge(_ batch: [Reading], for id: UUID) -> Int {
        guard !batch.isEmpty else { return 0 }
        var byMinute: [TimeInterval: Reading] = [:]
        for r in readings(for: id) { byMinute[r.date.timeIntervalSince1970] = r }
        let before = byMinute.count
        for r in batch {
            let m = r.date.flooredToMinute
            byMinute[m.timeIntervalSince1970] = Reading(date: m, tempC: r.tempC, humidity: r.humidity)
        }
        let cutoff = Date().addingTimeInterval(-Self.retention)
        let merged = byMinute.values.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        cache[id] = merged
        markDirty(id)
        return max(0, byMinute.count - before)
    }

    func delete(_ id: UUID) {
        cache[id] = nil
        try? FileManager.default.removeItem(at: url(for: id))
        revision += 1
    }

    func csv(for id: UUID, sensor: SensorInfo, unit: TempUnit) -> URL? {
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        var lines = ["timestamp,temperature_\(unit == .celsius ? "c" : "f"),humidity_pct,dew_point_\(unit == .celsius ? "c" : "f")"]
        for r in readings(for: id) {
            let t = sensor.calibratedTemp(r.tempC)
            let h = sensor.calibratedHumidity(r.humidity)
            let d = Climate.dewPoint(tempC: t, humidity: h)
            lines.append("\(iso.string(from: r.date)),\(unit.convert(t).clean()),\(h.clean()),\(unit.convert(d).clean())")
        }
        let safe = sensor.displayName.replacingOccurrences(of: "/", with: "-")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe) history.csv")
        do {
            try lines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
            return out
        } catch { return nil }
    }

    private func markDirty(_ id: UUID) {
        dirty.insert(id)
        revision += 1
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func flush() {
        let ids = dirty
        dirty.removeAll()
        for id in ids {
            guard let data = try? JSONEncoder().encode(cache[id] ?? []) else { continue }
            let target = url(for: id)
            io.async { try? data.write(to: target, options: .atomic) }
        }
    }
}
