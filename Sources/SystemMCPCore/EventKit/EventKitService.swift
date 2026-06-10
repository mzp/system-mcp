import EventKit
import Foundation
import Logging

/// Thin actor wrapper around `EKEventStore`. All EventKit access is funnelled through
/// here so the CLI and MCP layers only ever see Sendable response models.
///
/// This core type holds only the shared infrastructure (the store, authorization, and
/// calendar lookup). Each tool adds its domain methods via `extension EventKitService`
/// in its own target (`AppleReminder` / `AppleCalendar`), using the `package`-visible
/// members below.
public actor EventKitService {
    package let store = EKEventStore()

    public init() {}

    // MARK: - Authorization

    /// The authorization status for a single entity type, as a friendly string.
    public func authorizationStatus(for entity: EKEntityType) -> StatusResponse {
        StatusResponse(
            entity: Self.entityName(entity),
            status: Self.statusName(EKEventStore.authorizationStatus(for: entity)))
    }

    /// Requests access to one entity type (triggers the TCC prompt on first run) and
    /// returns the resulting status.
    @discardableResult
    public func requestAccess(to entity: EKEntityType) async -> StatusResponse {
        if EKEventStore.authorizationStatus(for: entity) == .notDetermined {
            switch entity {
            case .event: _ = try? await store.requestFullAccessToEvents()
            case .reminder: _ = try? await store.requestFullAccessToReminders()
            @unknown default: break
            }
        }
        let status = authorizationStatus(for: entity)
        log.info(
            "authorization",
            metadata: ["entity": .string(status.entity), "status": .string(status.status)])
        return status
    }

    /// Ensures the process has full access to `entity`, requesting it once if undetermined.
    package func ensureAccess(to entity: EKEntityType, label: String) async throws {
        switch EKEventStore.authorizationStatus(for: entity) {
        case .fullAccess:
            return
        case .notDetermined:
            let granted: Bool
            switch entity {
            case .event: granted = (try? await store.requestFullAccessToEvents()) ?? false
            case .reminder: granted = (try? await store.requestFullAccessToReminders()) ?? false
            @unknown default: granted = false
            }
            if !granted { throw EventKitError.accessDenied(entity: label) }
        default:
            log.warning(
                "\(label) access denied",
                metadata: ["status": "\(EKEventStore.authorizationStatus(for: entity).rawValue)"])
            throw EventKitError.accessDenied(entity: label)
        }
    }

    private static func entityName(_ entity: EKEntityType) -> String {
        switch entity {
        case .event: return "calendar"
        case .reminder: return "reminders"
        @unknown default: return "unknown"
        }
    }

    private static func statusName(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .fullAccess: return "fullAccess"
        case .writeOnly: return "writeOnly"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Calendar lookup

    /// Resolve a calendar/reminder list by identifier or title within an entity type.
    package func calendar(idOrName: String, entity: EKEntityType, label: String) throws -> EKCalendar {
        let calendars = store.calendars(for: entity)
        if let byId = calendars.first(where: { $0.calendarIdentifier == idOrName }) {
            return byId
        }
        if let byName = calendars.first(where: { $0.title == idOrName }) {
            return byName
        }
        throw EventKitError.notFound("\(label) '\(idOrName)'")
    }
}
