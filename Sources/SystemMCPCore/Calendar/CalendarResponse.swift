import EventKit
import Foundation

/// A calendar (event calendar) or reminder list. Returned by both tools, so it lives
/// in the shared core. Plain `Codable` value type: neither the CLI nor the MCP layer
/// depends on EventKit types directly.
public struct CalendarResponse: Codable, Sendable {
    public let id: String
    public let title: String
    public let type: String
    public let allowsModifications: Bool
    public let color: String?
    public let isDefault: Bool
}

// MARK: - EventKit -> response conversion

extension CalendarResponse {
    public init(_ calendar: EKCalendar, defaultId: String?) {
        self.id = calendar.calendarIdentifier
        self.title = calendar.title
        self.type = CalendarResponse.typeName(calendar.type)
        self.allowsModifications = calendar.allowsContentModifications
        self.color = calendar.cgColor.flatMap(CalendarResponse.hexString(from:))
        self.isDefault = (defaultId != nil && defaultId == calendar.calendarIdentifier)
    }

    private static func typeName(_ type: EKCalendarType) -> String {
        switch type {
        case .local: return "local"
        case .calDAV: return "calDAV"
        case .exchange: return "exchange"
        case .subscription: return "subscription"
        case .birthday: return "birthday"
        @unknown default: return "unknown"
        }
    }

    private static func hexString(from color: CGColor) -> String? {
        guard let comps = color.components, comps.count >= 3 else { return nil }
        let r = Int((comps[0] * 255).rounded())
        let g = Int((comps[1] * 255).rounded())
        let b = Int((comps[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
