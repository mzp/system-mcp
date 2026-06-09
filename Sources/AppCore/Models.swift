import EventKit
import Foundation

// MARK: - DTOs
//
// Plain `Codable` value types returned by `EventStoreService`. They are shared by
// the CLI (printed as JSON) and the MCP server (serialized into tool results), so
// neither layer depends on EventKit types directly.

public struct CalendarDTO: Codable, Sendable {
    public let id: String
    public let title: String
    public let type: String
    public let allowsModifications: Bool
    public let color: String?
    public let isDefault: Bool
}

public struct ReminderDTO: Codable, Sendable {
    public let id: String
    public let title: String
    public let notes: String?
    public let list: String
    public let listId: String
    public let completed: Bool
    public let completionDate: Date?
    public let dueDate: Date?
    public let priority: String
    public let url: String?
    public let creationDate: Date?
    public let lastModified: Date?
}

public struct EventDTO: Codable, Sendable {
    public let id: String
    public let title: String
    public let notes: String?
    public let calendar: String
    public let calendarId: String
    public let startDate: Date?
    public let endDate: Date?
    public let isAllDay: Bool
    public let location: String?
    public let url: String?
    public let status: String?
    public let creationDate: Date?
    public let lastModified: Date?
}

public struct AuthorizationStatusDTO: Codable, Sendable {
    public let events: String
    public let reminders: String
}

// MARK: - Reminder priority mapping

/// Maps between EventKit's integer priority and friendly strings.
/// Apple convention: 0 = none, 1 = high, 5 = medium, 9 = low.
public enum ReminderPriority: String, CaseIterable, Sendable {
    case none, high, medium, low

    public var ekValue: Int {
        switch self {
        case .none: return 0
        case .high: return 1
        case .medium: return 5
        case .low: return 9
        }
    }

    public init(ekValue: Int) {
        switch ekValue {
        case 0: self = .none
        case 1...4: self = .high
        case 5: self = .medium
        default: self = .low
        }
    }

    public init?(string: String) {
        self.init(rawValue: string.lowercased())
    }
}

// MARK: - EventKit -> DTO conversions

extension CalendarDTO {
    init(_ calendar: EKCalendar, defaultId: String?) {
        self.id = calendar.calendarIdentifier
        self.title = calendar.title
        self.type = CalendarDTO.typeName(calendar.type)
        self.allowsModifications = calendar.allowsContentModifications
        self.color = calendar.cgColor.flatMap(CalendarDTO.hexString(from:))
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

extension ReminderDTO {
    init(_ reminder: EKReminder) {
        self.id = reminder.calendarItemIdentifier
        self.title = reminder.title ?? ""
        self.notes = reminder.notes
        self.list = reminder.calendar?.title ?? ""
        self.listId = reminder.calendar?.calendarIdentifier ?? ""
        self.completed = reminder.isCompleted
        self.completionDate = reminder.completionDate
        self.dueDate = reminder.dueDateComponents?.date
        self.priority = ReminderPriority(ekValue: reminder.priority).rawValue
        self.url = reminder.url?.absoluteString
        self.creationDate = reminder.creationDate
        self.lastModified = reminder.lastModifiedDate
    }
}

extension EventDTO {
    init(_ event: EKEvent) {
        self.id = event.eventIdentifier ?? ""
        self.title = event.title ?? ""
        self.notes = event.notes
        self.calendar = event.calendar?.title ?? ""
        self.calendarId = event.calendar?.calendarIdentifier ?? ""
        self.startDate = event.startDate
        self.endDate = event.endDate
        self.isAllDay = event.isAllDay
        self.location = event.location
        self.url = event.url?.absoluteString
        self.status = EventDTO.statusName(event.status)
        self.creationDate = event.creationDate
        self.lastModified = event.lastModifiedDate
    }

    private static func statusName(_ status: EKEventStatus) -> String? {
        switch status {
        case .none: return nil
        case .tentative: return "tentative"
        case .confirmed: return "confirmed"
        case .canceled: return "canceled"
        @unknown default: return nil
        }
    }
}
