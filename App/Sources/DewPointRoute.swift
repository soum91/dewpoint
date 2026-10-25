import SwiftUI
@MainActor final class DewPointRoute: ObservableObject {
    static let shared = DewPointRoute()
    @Published var sensorID: UUID?
}
