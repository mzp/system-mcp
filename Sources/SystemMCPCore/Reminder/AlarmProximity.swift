import EventKit

/// Proximity trigger for location-based reminder alarms
/// (enter = notify on arrival, leave = notify on departure).
public enum AlarmProximity: String, CaseIterable, Sendable {
    case enter
    case leave

    public init?(string: String) {
        self.init(rawValue: string.lowercased())
    }

    /// Returns `nil` for `.none` (alarm without a proximity trigger).
    public init?(ekValue: EKAlarmProximity) {
        switch ekValue {
        case .enter: self = .enter
        case .leave: self = .leave
        case .none: return nil
        @unknown default: return nil
        }
    }

    public var ekValue: EKAlarmProximity {
        switch self {
        case .enter: return .enter
        case .leave: return .leave
        }
    }
}
