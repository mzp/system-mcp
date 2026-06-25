import Foundation

/// How a reminder due date or calendar event is anchored in time, parsed from the single optional
/// `timezone` argument. Floating is modeled as one of the time-zone choices ("no zone") rather than
/// a separate flag: "fix to a zone" and "make it floating" can't be requested at once, so the
/// contradiction is impossible by construction. It also mirrors Calendar's time-zone picker, where
/// "None" is the floating option. See docs/eventkit.md.
public enum TimeAnchor: Sendable, Equatable {
    /// No `timezone` given: anchor to the device's local zone (a concrete moment). The default.
    case local
    /// `timezone: floating` (or `none`): no zone — fires at this wall-clock time wherever the device is.
    case floating
    /// An explicit zone (`America/New_York`, `EST`, …): fixed to that zone's absolute moment.
    case fixed(TimeZone)

    /// The sentinel `timezone` values that select floating, matched case-insensitively.
    public static let floatingNames: Set<String> = ["floating", "none"]

    /// Zone in which to interpret an input date string that carries no offset of its own. Local and
    /// floating both read the wall-clock in the device's zone; fixed reads it in its own zone.
    public var parseZone: TimeZone {
        switch self {
        case .local, .floating: .current
        case .fixed(let zone): zone
        }
    }

    /// Zone to anchor a reminder's due components to, or nil for floating. (Events apply the anchor
    /// by switching on the case, since they distinguish "leave existing" from "set local".)
    public var dueZone: TimeZone? {
        switch self {
        case .local: .current
        case .floating: nil
        case .fixed(let zone): zone
        }
    }
}
