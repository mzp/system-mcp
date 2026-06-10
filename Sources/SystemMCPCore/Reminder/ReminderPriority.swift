import Foundation

/// Maps between EventKit's integer priority and friendly strings.
/// Apple convention: 0 = none, 1 = high, 5 = medium, 9 = low.
enum ReminderPriority: String, CaseIterable, Sendable {
    case none, high, medium, low

    var ekValue: Int {
        switch self {
        case .none: return 0
        case .high: return 1
        case .medium: return 5
        case .low: return 9
        }
    }

    init(ekValue: Int) {
        switch ekValue {
        case 0: self = .none
        case 1...4: self = .high
        case 5: self = .medium
        default: self = .low
        }
    }

    init?(string: String) {
        self.init(rawValue: string.lowercased())
    }
}
