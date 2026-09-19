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
/// So the thing being captured is **a place, not a position**. Alicia is told
/// "San Francisco" or "Seattle", and "home", "office" or "away" — never a
/// coordinate. That is what he asked for and it is all the question needs:
/// knowing he is in Seattle changes what she should say; knowing which block
/// of Seattle does not, and would be a record neither of us should be keeping.
///
/// Consequences of that choice, held deliberately:
///
///   * Coordinates never leave this class. Reverse geocoding happens on the
///     phone and only the locality, region and place name are published.
///   * Significant-change monitoring, not continuous updates — it is the API
///     that exists for "he moved city", costs almost no battery, and wakes the
///     app for a flight without following him down a street.
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

    private(set) var locality = ""        // "San Francisco"
    private(set) var region = ""          // "California"
    private(set) var country = ""         // "United States"
    private(set) var named: Named = .unknown
    private(set) var updatedAt: Date?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var resolving = false

    /// Which locality counts as which place. Editable here rather than guessed:
    /// Alicia should not infer "this is his office" from how long he stands in
    /// a building.
    private let homeLocalities = ["San Francisco"]
    private let officeLocalities = ["Palo Alto"]

    private override init() {
        super.init()
        manager.delegate = self
        // The coarsest accuracy that still resolves a city. We are not asking
        // for precision we would then have to justify keeping.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
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
        // Significant-change monitoring is the "he changed city" API. It keeps
        // working across a launch and does not need the app in front.
        manager.startMonitoringSignificantLocationChanges()
        manager.requestLocation()
    }

    func stop() {
        manager.stopMonitoringSignificantLocationChanges()
    }

    /// What Alicia is told. Empty until a place actually resolves — she is
    /// never handed a guess, and "unknown" is a real answer.
    var wire: [String: String]? {
        guard !locality.isEmpty else { return nil }
        return ["locality": locality, "region": region, "country": country,
                "named": named.rawValue,
                "as_of": updatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""]
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
        let place = region.isEmpty ? locality : locality + ", " + region
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
