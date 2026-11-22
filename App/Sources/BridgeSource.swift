import Foundation
import Network
import SwiftUI

/// Finds the Keystone Bridge on the home Wi-Fi (Bonjour) and keeps DewPoint's reading fresh from it
/// whenever the phone can't hear the Govee itself.
@MainActor
final class BridgeSource: ObservableObject {
    static let shared = BridgeSource()

    @Published var host: BridgeFeed.Host? = BridgeFeed.host
    @Published var room: BridgeRoom?
    @Published var searching = false
    @Published var status = ""

    private var browser: NWBrowser?
    private var timer: Timer?
    @Published private(set) var feedAttempts = 0
    @Published private(set) var lastFeedAttempt: Date?
    private var lastForwarded = Date.distantPast
    private var feedSequence: UInt32 = 0
    private var pendingFeeds: [UUID: NWConnection] = [:]  // retain UDP sends until completion

    /// DewPoint is the iOS app. Only genuine CoreBluetooth observations get forwarded:
    /// readings fetched FROM Keystone must never be echoed back to the ESP32.
    /// iOS does not guarantee continuous background advertisement scanning.
    func forward(sensor: SensorInfo, reading: LiveReading) {
        guard let h = host, !h.host.isEmpty else { return }
        let name = sensor.advertisedName
        guard !name.isEmpty, name.count < 32,
              (name.hasPrefix("GV") || name.hasPrefix("Govee")),
              name.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) ||
                                      ($0 >= 97 && $0 <= 122) || $0 == 95 || $0 == 45 }) else { return }
        // One paired sensor only: otherwise use Keystone's currently selected Govee name.
        if let paired = room?.name, !paired.isEmpty,
           paired.caseInsensitiveCompare(name) != .orderedSame { return }
        if room == nil, BLEManager.shared.sensors.first?.id != sensor.id { return }
        let age = Date().timeIntervalSince(reading.lastSeen)
        guard (0...120).contains(age), (-40...100).contains(reading.tempC),
              (0...100).contains(reading.humidity), (0...100).contains(reading.battery),
              Date().timeIntervalSince(lastForwarded) >= 12 else { return }

        feedSequence &+= 1
        lastForwarded = Date()
        lastFeedAttempt = lastForwarded
        feedAttempts += 1
        let packet = String(format: "DPG2,%@,%.2f,%.2f,%d,%u,%u",
                            name, reading.tempC, reading.humidity, reading.battery,
                            UInt32(age * 1000), feedSequence)
        guard let data = packet.data(using: .utf8),
              let port = NWEndpoint.Port(rawValue: 8092) else { return }
        let parameters = NWParameters.udp
        parameters.requiredInterfaceType = .wifi  // never use a cellular data route
        let connection = NWConnection(host: NWEndpoint.Host(h.host), port: port, using: parameters)
        let id = UUID()
        pendingFeeds[id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .ready:
                connection?.send(content: data, completion: .contentProcessed { _ in
                    connection?.cancel()
                    Task { @MainActor in self?.pendingFeeds[id] = nil }
                })
            case .failed, .cancelled:
                connection?.cancel()
                Task { @MainActor in self?.pendingFeeds[id] = nil }
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue.global(qos: .utility))
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            self?.pendingFeeds.removeValue(forKey: id)?.cancel()
        }
    }


    func start() {
        poll()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        if host == nil { find() }
    }

    func stop() { timer?.invalidate(); timer = nil; browser?.cancel(); browser = nil }

    func poll() {
        Task {
            if let h = host, let r = await BridgeFeed.fetch(h) {
                room = r
                status = "Bridge heard it \(Int(Date().timeIntervalSince(r.at))) s ago"
                BLEManager.shared.applyBridge(r)
            } else if host != nil {
                status = "Bridge not reachable (or it hasn't heard the Govee yet)"
                if !searching { find() }   // its address may have changed
            }
        }
    }

    func setManual(_ ip: String) {
        let h = BridgeFeed.Host(host: ip.trimmingCharacters(in: .whitespaces), port: 8080)
        host = h; BridgeFeed.host = h; poll()
    }

    func find() {
        browser?.cancel()
        searching = true
        let b = NWBrowser(for: .bonjour(type: "_afterglow._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            for r in results { Task { await self?.resolve(r.endpoint) } }
        }
        b.start(queue: .main)
        browser = b
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            searching = false
            browser?.cancel(); browser = nil
        }
    }

    private func resolve(_ endpoint: NWEndpoint) async {
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let c = NWConnection(to: endpoint, using: params)
        let result: (String, Int)? = await withCheckedContinuation { cont in
            let once = Once()
            c.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let h, let p)? = c.currentPath?.remoteEndpoint, once.fire() {
                        var host = "\(h)"
                        if let pct = host.firstIndex(of: "%") { host = String(host[..<pct]) }
                        cont.resume(returning: (host, Int(p.rawValue)))
                    } else if once.fire() { cont.resume(returning: nil) }
                    c.cancel()
                case .failed, .cancelled:
                    if once.fire() { cont.resume(returning: nil) }
                default: break
                }
            }
            c.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                if once.fire() { cont.resume(returning: nil); c.cancel() }
            }
        }
        guard let r = result else { return }
        let h = BridgeFeed.Host(host: r.0, port: r.1)
        host = h; BridgeFeed.host = h
        searching = false
        poll()
    }
}

private final class Once: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func fire() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}
