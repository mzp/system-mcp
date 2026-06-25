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
    /// Start/end. Encoded with the event's time-zone offset when anchored, or as a zone-less
    /// wall-clock (no offset) when floating. See `ZonedDate`.
    public let startDate: ZonedDate?
    public let endDate: ZonedDate?
    public let isAllDay: Bool
    public let timeZone: String?
    /// True when the event is floating: it has no time zone and occurs at that wall-clock time
    /// wherever the device is, so the time must not be converted across zones. False when anchored
    /// to a zone or when there is no start date. Mirrors `timeZone == nil` but states it explicitly.
    public let floating: Bool
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
        self.startDate = event.startDate.map { ZonedDate(date: $0, timeZone: event.timeZone) }
        self.endDate = event.endDate.map { ZonedDate(date: $0, timeZone: event.timeZone) }
        self.isAllDay = event.isAllDay
        self.timeZone = event.timeZone?.identifier
        self.floating = event.startDate != nil && event.timeZone == nil
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
