import Foundation
import AppIntents

@available(iOS 17.0, *)
struct RoomSensorEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Room sensor"
    static var defaultQuery = RoomSensorQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
}
@available(iOS 17.0, *)
struct RoomSensorQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RoomSensorEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [RoomSensorEntity] {
        SnapshotStore.load().map { .init(id: $0.id, name: $0.name) }
    }
}
@available(iOS 17.0, *)
struct RoomWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Room readings"
    @Parameter(title: "Sensor") var sensor: RoomSensorEntity?
}
@available(iOS 18.0, *)
struct RoomControlConfiguration: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Room readings"
    @Parameter(title: "Sensor") var sensor: RoomSensorEntity?
}
@available(iOS 17.0, *)
struct OpenRoomIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Room Readings"
    static var openAppWhenRun = true
    @Parameter(title: "Sensor ID") var sensorID: String
    init() { sensorID = "" }
    init(_ id: String) { sensorID = id }
    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        DewPointRoute.shared.sensorID = UUID(uuidString: sensorID)
        BLEManager.shared.startScanning()
        #endif
        return .result()
    }
}
