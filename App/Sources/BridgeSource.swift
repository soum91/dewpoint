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
