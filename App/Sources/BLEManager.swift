import Foundation
import CoreBluetooth
import Combine

struct RawAdvert: Equatable {
    let name: String
    let rssi: Int
    let hex: String
    var services: String = ""
    let parsed: GoveeAdvert?
    let lastSeen: Date
}

enum SyncState: Equatable {
    case idle
    case connecting
    case downloading(received: Int, requested: Int)
    case done(newPoints: Int, at: Date)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .connecting, .downloading: return true
        default: return false
        }
    }
}

/// Govee's GATT history protocol ("INTELLI_ROCKS"), as documented by GoveeBTTempLogger.
private enum GoveeGATT {
    static let command = CBUUID(string: "494e5445-4c4c-495f-524f-434b535f2011")
    static let request = CBUUID(string: "494e5445-4c4c-495f-524f-434b535f2012")
    static let data    = CBUUID(string: "494e5445-4c4c-495f-524f-434b535f2013")
    static let encryptedMarker = CBUUID(string: "00010203-0405-0607-0809-0a0b0c0d2b10")

    /// Device keeps ~20 days of minute data.
    static let maxPoints = 20 * 24 * 60

    static func packet(_ head: [UInt8]) -> Data {
        var b = [UInt8](repeating: 0, count: 20)
        for (i, v) in head.enumerated() where i < 19 { b[i] = v }
        b[19] = b[0..<19].reduce(0, ^)
        return Data(b)
    }
}

private final class SyncSession {
    let sensorID: UUID
    let peripheral: CBPeripheral
    var chars: [CBUUID: CBCharacteristic] = [:]
    var pendingServices = 0
    var requested = 0
    var startedAt = Date().flooredToMinute
    var records: [Reading] = []
    var lastPacket = Date()
    var requestSent = false

    init(sensorID: UUID, peripheral: CBPeripheral) {
        self.sensorID = sensorID
        self.peripheral = peripheral
    }
}

final class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()

    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var sensors: [SensorInfo] = []
    @Published private(set) var live: [UUID: LiveReading] = [:]
    @Published private(set) var nearby: [UUID: LiveReading] = [:]   // seen but not added
    @Published private(set) var sync: [UUID: SyncState] = [:]
    /// Every Govee-looking advert, parsed or not. Only filled while the finder sheet is open.
    @Published private(set) var raw: [UUID: RawAdvert] = [:]
    var captureRaw = false {
        didSet { if !captureRaw { raw = [:] } }
    }
    /// Finder: include every Bluetooth device, not just Govee-looking ones.
    var captureAll = false {
        didSet { raw = [:] }
    }

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var session: SyncSession?
    private var watchdog: Timer?
    private let history = HistoryStore.shared
    private let sensorsKey = "dewpoint.sensors.v1"

    private override init() {
        super.init()
        loadSensors()
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: Sensor list

    private func loadSensors() {
        if let data = UserDefaults.standard.data(forKey: sensorsKey),
           let s = try? JSONDecoder().decode([SensorInfo].self, from: data) {
            sensors = s
        }
    }

    private func saveSensors() {
        if let data = try? JSONEncoder().encode(sensors) {
            UserDefaults.standard.set(data, forKey: sensorsKey)
        }
        SnapshotStore.save(sensors: sensors, live: live)
    }

    func sensor(_ id: UUID) -> SensorInfo? { sensors.first { $0.id == id } }

    func add(_ id: UUID) {
        guard sensor(id) == nil, let r = nearby[id] ?? raw[id].flatMap({ ra in
            ra.parsed.map { LiveReading(tempC: $0.tempC, humidity: $0.humidity, battery: $0.battery,
                                        rssi: ra.rssi, lastSeen: ra.lastSeen, model: $0.model, name: ra.name) }
        }) else { return }
        sensors.append(SensorInfo(id: id, model: r.model, advertisedName: r.name))
        live[id] = r
        nearby[id] = nil
        saveSensors()
    }

    func update(_ s: SensorInfo) {
        guard let i = sensors.firstIndex(where: { $0.id == s.id }) else { return }
        sensors[i] = s
        saveSensors()
    }

    func remove(at offsets: IndexSet) {
        for id in offsets.map({ sensors[$0].id }) { remove(id) }
    }

    func remove(_ id: UUID) {
        sensors.removeAll { $0.id == id }
        live[id] = nil
        history.delete(id)
        saveSensors()
    }

    func move(from: IndexSet, to: Int) {
        sensors.move(fromOffsets: from, toOffset: to)
        saveSensors()
    }

    // MARK: Scanning

    func startScanning() {
        guard central.state == .poweredOn, !central.isScanning else { return }
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScanning() {
        if central.isScanning { central.stopScan() }
        history.flush()
    }

    private var lastSnapshotSave = Date.distantPast

    private func handle(_ adv: GoveeAdvert, id: UUID, name: String, rssi: Int) {
        let reading = LiveReading(tempC: adv.tempC, humidity: adv.humidity, battery: adv.battery,
                                  rssi: rssi, lastSeen: Date(), model: adv.model, name: name)
        guard let idx = sensors.firstIndex(where: { $0.id == id }) else {
            nearby[id] = reading
            return
        }
        live[id] = reading
        if sensors[idx].advertisedName != name, !name.isEmpty {
            sensors[idx].advertisedName = name
        }
        history.addLive(Reading(date: Date(), tempC: adv.tempC, humidity: adv.humidity), for: id)
        AlertManager.shared.evaluate(sensor: sensors[idx], reading: reading)
        if Date().timeIntervalSince(lastSnapshotSave) > 30 {
            lastSnapshotSave = Date()
            SnapshotStore.save(sensors: sensors, live: live)
        }
    }

    // MARK: History download

    func syncHistory(_ id: UUID) {
        guard session == nil else { return }
        guard central.state == .poweredOn else {
            sync[id] = .failed("Bluetooth is off.")
            return
        }
        guard let p = peripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else {
            sync[id] = .failed("Sensor not seen yet. Get closer and try again.")
            return
        }
        let s = SyncSession(sensorID: id, peripheral: p)
        session = s
        sync[id] = .connecting
        p.delegate = self
        central.connect(p, options: nil)
        startWatchdog()
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let s = self.session else { return }
            let idle = Date().timeIntervalSince(s.lastPacket)
            if !s.requestSent && idle > 20 {
                self.finish(error: "Couldn't connect. Make sure the sensor is close and the Govee app is closed.")
            } else if s.requestSent && idle > 8 {
                // Device went quiet: treat whatever arrived as the full download.
                self.finish(error: nil)
            }
        }
    }

    private func sendRequest(_ s: SyncSession) {
        guard let req = s.chars[GoveeGATT.request] else { return }
        let since = sensor(s.sensorID)?.lastHistorySync
        var points = GoveeGATT.maxPoints
        if let since {
            points = Int(Date().timeIntervalSince(since) / 60) + 5
        }
        points = min(GoveeGATT.maxPoints, max(7, points))
        s.requested = points
        s.startedAt = Date().flooredToMinute
        s.lastPacket = Date()
        s.requestSent = true
        let cmd = GoveeGATT.packet([0x33, 0x01, UInt8(points >> 8), UInt8(points & 0xFF), 0x00, 0x01])
        write(cmd, to: req, on: s.peripheral)
        sync[s.sensorID] = .downloading(received: 0, requested: points)
    }

    private func write(_ data: Data, to c: CBCharacteristic, on p: CBPeripheral) {
        let type: CBCharacteristicWriteType = c.properties.contains(.write) ? .withResponse : .withoutResponse
        p.writeValue(data, for: c, type: type)
    }

    private func handleHistoryPacket(_ bytes: [UInt8], _ s: SyncSession) {
        guard bytes.count >= 5 else { return }
        s.lastPacket = Date()
        var offset = Int(bytes[0]) << 8 | Int(bytes[1])
        if offset < 7 { finishSoon() }
        if offset % 450 < 6, let req = s.chars[GoveeGATT.request] {
            write(GoveeGATT.packet([0xAA, 0x01]), to: req, on: s.peripheral) // keep-alive
        }
        var i = 2
        while i + 2 < bytes.count, offset > 0 {
            if let (t, h) = GoveeParser.decodePacked(bytes[i], bytes[i + 1], bytes[i + 2]),
               (-40...100).contains(t), (0...100).contains(h) {
                let date = s.startedAt.addingTimeInterval(-60 * Double(offset))
                s.records.append(Reading(date: date, tempC: t, humidity: h))
            }
            offset -= 1
            i += 3
        }
        sync[s.sensorID] = .downloading(received: s.records.count, requested: s.requested)
    }

    private var finishScheduled = false
    private func finishSoon() {
        guard !finishScheduled else { return }
        finishScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.finishScheduled = false
            self?.finish(error: nil)
        }
    }

    private func finish(error: String?) {
        guard let s = session else { return }
        session = nil
        watchdog?.invalidate()
        watchdog = nil
        central.cancelPeripheralConnection(s.peripheral)
        if let error, s.records.isEmpty {
            sync[s.sensorID] = .failed(error)
            return
        }
        let added = history.merge(s.records, for: s.sensorID)
        if var info = sensor(s.sensorID), s.requestSent {
            info.lastHistorySync = s.startedAt
            update(info)
        }
        sync[s.sensorID] = .done(newPoints: added, at: Date())
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        if central.state == .poweredOn { startScanning() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let md = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let adv = GoveeParser.parse(name: name, manufacturerData: md)
        if captureRaw, captureAll || adv != nil || GoveeParser.looksLikeGovee(name: name) || GoveeParser.looksLikeGovee(manufacturerData: md),
           Date().timeIntervalSince(raw[peripheral.identifier]?.lastSeen ?? .distantPast) > 1 {
            raw[peripheral.identifier] = RawAdvert(name: name, rssi: RSSI.intValue,
                                                   hex: md.map { $0.map { String(format: "%02X", $0) }.joined(separator: " ") } ?? "(no manufacturer data)",
                                                   services: ((advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? [])
                                                       .map(\.uuidString).joined(separator: ", "),
                                                   parsed: adv, lastSeen: Date())
        }
        guard let adv else { return }
        peripherals[peripheral.identifier] = peripheral
        handle(adv, id: peripheral.identifier, name: name, rssi: RSSI.intValue)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let s = session, s.peripheral.identifier == peripheral.identifier else { return }
        s.lastPacket = Date()
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard session?.peripheral.identifier == peripheral.identifier else { return }
        finish(error: error?.localizedDescription ?? "Connection failed.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard session?.peripheral.identifier == peripheral.identifier else { return }
        finish(error: "Sensor disconnected.")
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = session else { return }
        let services = peripheral.services ?? []
        if services.isEmpty { finish(error: "No services found on sensor."); return }
        s.pendingServices = services.count
        for svc in services { peripheral.discoverCharacteristics(nil, for: svc) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let s = session else { return }
        for c in service.characteristics ?? [] { s.chars[c.uuid] = c }
        s.pendingServices -= 1
        guard s.pendingServices <= 0 else { return }

        if s.chars[GoveeGATT.encryptedMarker] != nil && s.chars[GoveeGATT.data] == nil {
            finish(error: "This sensor's firmware uses encrypted history, which isn't supported yet.")
            return
        }
        guard s.chars[GoveeGATT.request] != nil, let dataChar = s.chars[GoveeGATT.data] else {
            finish(error: "History service not found on this sensor.")
            return
        }
        for uuid in [GoveeGATT.command, GoveeGATT.request] {
            if let c = s.chars[uuid], c.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: c)
            }
        }
        peripheral.setNotifyValue(true, for: dataChar)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let s = session, characteristic.uuid == GoveeGATT.data, !s.requestSent else { return }
        if let error {
            finish(error: error.localizedDescription)
            return
        }
        sendRequest(s)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let s = session, let value = characteristic.value else { return }
        let bytes = [UInt8](value)
        switch characteristic.uuid {
        case GoveeGATT.data:
            handleHistoryPacket(bytes, s)
        case GoveeGATT.request:
            s.lastPacket = Date()
            if bytes.count >= 2, bytes[0] == 0xEE, bytes[1] == 0x01 { finishSoon() }
        default:
            break
        }
    }
}
