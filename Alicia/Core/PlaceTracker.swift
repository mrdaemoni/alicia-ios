import CoreLocation
import Foundation
import Observation

/// Where Hector is, at the resolution that is actually useful to Alicia.
///
/// He asked for this on 2026-09-18: *"I also don't mind giving the Alicia iOS
/// permission to get my location. I think that's important so you know where I
/// am, especially to know where I'm traveling … since I travel a lot between
/// here, Palo Alto, and Seattle. So when I'm in the office or at home, all of
/// those signals, I want Alicia to also capture so she becomes aware of where
/// I am."*
///
/// The first version sent only a city. He asked for more on the same day:
/// *"I want to have more precise location if possible. I can give the
/// permission. I'm the only one using this app, so it's fine."*
///
/// So it now resolves a **named place within a city** — the neighbourhood or
/// district, and the point of interest when there is one — while still never
/// sending a coordinate. "Palo Alto · Professorville" is a different answer
/// from "Palo Alto", and it is the answer that lets Alicia tell a day at his
/// desk from a day out. A latitude is not, and adding one would buy nothing
/// she can reason with.
///
/// Consequences, held deliberately:
///
///   * Coordinates never leave this class. Reverse geocoding happens on the
///     phone; only names are published.
///   * Significant-change monitoring keeps working in the background for the
///     "he flew somewhere" case. While the app is in front it also takes
///     ordinary updates, so arriving at the office registers within the hour
///     rather than at the next city boundary.
///   * A refused or restricted permission is a normal state, not an error. The
///     app works exactly as before and says nothing about where he is.
@MainActor @Observable final class PlaceTracker: NSObject, CLLocationManagerDelegate {
    static let shared = PlaceTracker()

    /// The named places he described. Matched by locality, so "the office" is
    /// whichever address in Palo Alto he works from rather than a fence drawn
    /// around a building he might move out of.
    enum Named: String {
        case home, office, travelling, unknown
    }

    private(set) var locality = ""        // "Palo Alto"
    private(set) var district = ""        // "Professorville" — sub-locality
    private(set) var spot = ""            // a named point of interest, if any
    private(set) var region = ""          // "California"
    private(set) var country = ""         // "United States"
    private(set) var named: Named = .unknown
    private(set) var updatedAt: Date?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var resolving = false

    /// Which locality counts as which place, from Hector directly on
    /// 2026-09-18: *"My home is in Palo Alto. My office is in Seattle."*
    /// Stated rather than guessed — Alicia should not infer "this is his
    /// office" from how long he stands in a building.
    private let homeLocalities = ["Palo Alto"]
    private let officeLocalities = ["Seattle"]

    private override init() {
        super.init()
        manager.delegate = self
        // He asked for precision and granted it. This resolves a street and a
        // neighbourhood; what is *published* is still only names, so the
        // accuracy buys a better name rather than a finer coordinate.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorization = manager.authorizationStatus
    }

    /// Ask once, when he can see why. Called from the Body/Us surface rather
    /// than at launch, so the system prompt arrives attached to a reason.
    func requestAccess() {
        guard manager.authorizationStatus == .notDetermined else {
            begin()
            return
        }
        manager.requestWhenInUseAuthorization()
    }

    func begin() {
        guard [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) else { return }
        // Two cadences. Significant-change survives a launch and catches the
        // flight without the app in front; ordinary updates while he is
        // actually using the app catch arriving at the office. The second is
        // stopped the moment the app leaves the foreground — precision he
        // granted is not a licence to follow him around all day.
        manager.startMonitoringSignificantLocationChanges()
        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    /// Foreground-only precision. Significant-change monitoring continues.
    func pauseForegroundUpdates() {
        manager.stopUpdatingLocation()
    }

    func stop() {
        manager.stopMonitoringSignificantLocationChanges()
    }

    /// What Alicia is told. Empty until a place actually resolves — she is
    /// never handed a guess, and "unknown" is a real answer.
    var wire: [String: String]? {
        guard !locality.isEmpty else { return nil }
        var out = ["locality": locality, "region": region, "country": country,
                   "named": named.rawValue,
                   "as_of": updatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""]
        if !district.isEmpty { out["district"] = district }
        if !spot.isEmpty { out["spot"] = spot }
        return out
    }

    /// One line for a surface that wants to show him what she knows.
    var summary: String {
        guard !locality.isEmpty else {
            switch authorization {
            case .denied, .restricted: return "Location is off. Alicia doesn't know where you are."
            case .notDetermined:       return "Alicia doesn't know where you are yet."
            default:                   return "Finding where you are…"
            }
        }
        var place = locality
        if !district.isEmpty { place += " · " + district }
        else if !region.isEmpty { place += ", " + region }
        if !spot.isEmpty { place += " · " + spot }
        switch named {
        case .home:       return place + " · home"
        case .office:     return place + " · the office"
        case .travelling: return place + " · away"
        case .unknown:    return place
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if [.authorizedWhenInUse, .authorizedAlways].contains(status) { self.begin() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        Task { @MainActor in self.resolve(newest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Not knowing where he is is an ordinary state. Nothing is surfaced and
        // the last known place is kept until a better one arrives.
    }

    // MARK: resolving

    private func resolve(_ location: CLLocation) {
        guard !resolving else { return }
        resolving = true
        geocoder.reverseGeocodeLocation(location) { [weak self] marks, _ in
            Task { @MainActor in
                guard let self else { return }
                self.resolving = false
                guard let mark = marks?.first, let city = mark.locality, !city.isEmpty else { return }
                self.locality = city
                self.district = mark.subLocality ?? ""
                // A point of interest, never a street address: "Stanford
                // Libraries" is something she can reason about; a house number
                // is a thing to be careful with for no gain.
                self.spot = (mark.areasOfInterest?.first).map { $0 } ?? ""
                self.region = mark.administrativeArea ?? ""
                self.country = mark.country ?? ""
                self.named = self.classify(city)
                self.updatedAt = .now
                self.report()
            }
        }
    }

    private func classify(_ city: String) -> Named {
        if homeLocalities.contains(city) { return .home }
        if officeLocalities.contains(city) { return .office }
        return .travelling
    }

    /// Alicia learns about a place through the same telemetry channel as the
    /// rest of his presence — one event when it changes, never a stream.
    private func report() {
        guard let wire else { return }
        PresenceTracker.shared.place(wire)
    }
}
