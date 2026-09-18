import Foundation

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected

    var label: String {
        switch self {
        case .disconnected: return "DISCONNECTED"
        case .connecting: return "CONNECTING"
        case .connected: return "CONNECTED"
        }
    }
}

enum AppScreen: Equatable {
    case connecting
    case controller
}