import SwiftUI
import WidgetKit
import AppIntents

// Diagnostic controls for the blank Control Center icon problem.
// Probe A: intent lives ONLY in the widget extension (no copy in the app).
// Probe B: intent is shared with the app target (how every real control is built).
// Probe C: no intent work, no app group, no provider: the simplest control iOS allows.

@available(iOS 18.0, *)
struct ProbeExtensionOnlyIntent: AppIntent {
    static var title: LocalizedStringResource = "Probe A"
    static var isDiscoverable = false
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "probeA.lastTap")
        return .result()
    }
}

@available(iOS 18.0, *)
struct ProbeAControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.dewpoint.app.probeA") {
            ControlWidgetButton(action: ProbeExtensionOnlyIntent()) {
                Label("Probe A", systemImage: "star.fill")
            }
        }
        .displayName("Probe A")
        .description("Extension-only intent.")
    }
}

@available(iOS 18.0, *)
struct ProbeBControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.dewpoint.app.probeB") {
            ControlWidgetButton(action: OpenRoomIntent("")) {
                Label("Probe B", systemImage: "heart.fill")
            }
        }
        .displayName("Probe B")
        .description("Intent shared with the app.")
    }
}

@available(iOS 18.0, *)
struct ProbeCControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.dewpoint.app.probeC") {
            ControlWidgetToggle("Probe C", isOn: false, action: ProbeToggleIntent()) { _ in
                Label("Probe C", systemImage: "bolt.fill")
            }
        }
        .displayName("Probe C")
        .description("Toggle with a static value.")
    }
}

@available(iOS 18.0, *)
struct ProbeToggleIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Probe C"
    static var isDiscoverable = false
    @Parameter(title: "On") var value: Bool
    init() {}
    func perform() async throws -> some IntentResult { .result() }
}
