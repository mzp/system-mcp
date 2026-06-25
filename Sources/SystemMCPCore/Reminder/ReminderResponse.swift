import EventKit
import Foundation

/// Plain `Codable` reminder model returned by `EventKitService` and shared by the CLI
/// (printed as JSON) and the MCP server (serialized into tool results).
public struct ReminderResponse: Codable, Sendable {
    public let id: String
    public let title: String
    public let notes: String?
    public let list: String
    public let listId: String
    public let completed: Bool
    public let completionDate: Date?
    /// Due date. Encoded with the fixed zone's UTC offset when anchored, or as a zone-less
    /// wall-clock (no offset) when floating. See `ZonedDate`.
    public let dueDate: ZonedDate?
    /// Time zone the due date is anchored to (IANA identifier), or nil when the reminder is
    /// floating (no zone — fires at the local wall-clock time). See docs/eventkit.md.
    public let timeZone: String?
    /// True when the due date is floating: it has no time zone and fires at that wall-clock time
    /// wherever the device is, so the time must not be converted across zones. False when anchored
    /// to a zone or when there is no due date. Mirrors `timeZone == nil` but states it explicitly.
    public let floating: Bool
    public let priority: String
    public let location: String?
    public let latitude: Double?
    public let longitude: Double?
    public let proximity: String?
    public let radius: Double?
    public let url: String?
    public let creationDate: Date?
    public let lastModified: Date?
}

extension ReminderResponse {
    init(_ reminder: EKReminder) {
        self.id = reminder.calendarItemIdentifier
        self.title = reminder.title ?? ""
        self.notes = reminder.notes
        self.list = reminder.calendar?.title ?? ""
        self.listId = reminder.calendar?.calendarIdentifier ?? ""
        self.completed = reminder.isCompleted
        self.completionDate = reminder.completionDate
        let dueComponents = reminder.dueDateComponents
        self.dueDate = dueComponents?.date.map {
            ZonedDate(date: $0, timeZone: dueComponents?.timeZone)
        }
        self.timeZone = dueComponents?.timeZone?.identifier
        self.floating = dueComponents?.date != nil && dueComponents?.timeZone == nil
        self.priority = ReminderPriority(ekValue: reminder.priority).rawValue
        let locationAlarm = reminder.alarms?.first { $0.structuredLocation != nil }
        self.location = locationAlarm?.structuredLocation?.title
        let coordinate = locationAlarm?.structuredLocation?.geoLocation?.coordinate
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
        self.proximity = locationAlarm.flatMap { AlarmProximity(ekValue: $0.proximity)?.rawValue }
        // EKStructuredLocation.radius is 0 when the system default applies.
        self.radius = locationAlarm?.structuredLocation.flatMap { $0.radius > 0 ? $0.radius : nil }
        self.url = reminder.url?.absoluteString
        self.creationDate = reminder.creationDate
        self.lastModified = reminder.lastModifiedDate
    }
}
