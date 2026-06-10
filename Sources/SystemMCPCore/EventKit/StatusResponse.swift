import Foundation

/// Authorization status for a single EventKit entity, returned by each tool's `status`.
public struct StatusResponse: Codable, Sendable {
    public let entity: String
    public let status: String

    public init(entity: String, status: String) {
        self.entity = entity
        self.status = status
    }
}
