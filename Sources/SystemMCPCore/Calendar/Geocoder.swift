import CoreLocation
import Foundation

/// Forward-geocodes a free-form location string into coordinates so events get a
/// structured (map-backed) location, matching what Calendar.app does on input.
/// Forward geocoding needs network access but no location-services permission.
enum Geocoder {
    static func coordinate(for query: String) async -> (latitude: Double, longitude: Double)? {
        await withCheckedContinuation { continuation in
            // CLPlacemark is not Sendable; reduce to plain doubles inside the
            // callback before resuming (same pattern as fetchReminders).
            CLGeocoder().geocodeAddressString(query) { placemarks, error in
                if let error {
                    log.debug(
                        "geocoding failed",
                        metadata: ["query": .string(query), "error": "\(error)"])
                }
                guard let location = placemarks?.first?.location else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: (location.coordinate.latitude, location.coordinate.longitude))
            }
        }
    }
}
