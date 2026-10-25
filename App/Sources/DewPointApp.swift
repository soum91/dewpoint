import SwiftUI
import WidgetKit

@main
struct DewPointApp: App {
    @StateObject private var route = DewPointRoute.shared
    @StateObject private var ble = BLEManager.shared
    @StateObject private var history = HistoryStore.shared
    @Environment(\.scenePhase) private var phase
    @AppStorage("tempUnit") private var unit = "celsius"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .environmentObject(history)
                .tint(Theme.accent)
                .sheet(isPresented: Binding(get: { route.sensorID != nil }, set: { if !$0 { route.sensorID = nil } })) {
                    if let id = route.sensorID {
                        NavigationStack { SensorDetailView(sensorID: id) }
                            .environmentObject(ble).environmentObject(history)
                    }
                }
                .onAppear {
                    SnapshotStore.save(sensors: ble.sensors, live: ble.live)
                }
        }
        .onChange(of: unit) { _ in SnapshotStore.save(sensors: ble.sensors, live: ble.live) }
        .onChange(of: phase) { p in
            switch p {
            case .active: ble.startScanning()
            case .background: ble.stopScanning()
            default: break
            }
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.98, green: 0.45, blue: 0.20)
    static let humidity = Color(red: 0.22, green: 0.60, blue: 0.98)
    static let dew = Color(red: 0.35, green: 0.80, blue: 0.75)

    static func tempColor(_ c: Double) -> Color {
        switch c {
        case ..<16: return Color(red: 0.30, green: 0.55, blue: 1.0)
        case ..<19: return Color(red: 0.35, green: 0.78, blue: 0.95)
        case ..<24: return Color(red: 0.30, green: 0.80, blue: 0.45)
        case ..<27: return Color(red: 0.98, green: 0.70, blue: 0.20)
        default: return Color(red: 0.95, green: 0.30, blue: 0.25)
        }
    }

    static func batteryIcon(_ pct: Int) -> String {
        switch pct {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            SensorListView()
                .tabItem { Label("Sensors", systemImage: "thermometer.medium") }
            HomeBridgeView()
                .tabItem { Label("Apple Home", systemImage: "homekit") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
