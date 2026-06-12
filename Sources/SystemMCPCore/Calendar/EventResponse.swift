import EventKit
import Foundation

/// Plain `Codable` event model returned by `EventKitService` and shared by the CLI
/// (printed as JSON) and the MCP server (serialized into tool results).
public struct EventResponse: Codable, Sendable {
    public let id: String
    public let title: String
    public let notes: String?
    public let calendar: String
    public let calendarId: String
    public let startDate: Date?
    public let endDate: Date?
    public let isAllDay: Bool
    public let timeZone: String?
    public let location: String?
    public let latitude: Double?
    public let longitude: Double?
    public let url: String?
    public let status: String?
    public let creationDate: Date?
    public let lastModified: Date?
}

extension EventResponse {
    init(_ event: EKEvent) {
        self.id = event.eventIdentifier ?? ""
        self.title = event.title ?? ""
        self.notes = event.notes
        self.calendar = event.calendar?.title ?? ""
        self.calendarId = event.calendar?.calendarIdentifier ?? ""
        self.startDate = event.startDate
        self.endDate = event.endDate
        self.isAllDay = event.isAllDay
        self.timeZone = event.timeZone?.identifier
        self.location = event.location
        let coordinate = event.structuredLocation?.geoLocation?.coordinate
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
        self.url = event.url?.absoluteString
        self.status = EventResponse.statusName(event.status)
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
