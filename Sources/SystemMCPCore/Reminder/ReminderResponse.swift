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
    public let dueDate: Date?
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
        self.dueDate = reminder.dueDateComponents?.date
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
