import Foundation
import CoreLocation

/// Live aircraft position from the OpenSky Network (free, no key; anonymous use is rate-limited, so we poll
/// one aircraft at most about once a minute and only while its flight is airborne). Looked up by the Mode-S
/// (ICAO24) address that AeroDataBox reports for the flight's aircraft.
struct LivePosition: Equatable {
    var lat: Double
    var lon: Double
    var altFt: Int?
    var speedKts: Int?
    var heading: Double?
    var onGround: Bool
    var timestamp: Date
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    static func == (l: LivePosition, r: LivePosition) -> Bool { l.lat == r.lat && l.lon == r.lon && l.timestamp == r.timestamp }
}

enum OpenSky {
    enum Result { case position(LivePosition), notFound, failed(String) }

    static func fetch(icao24: String) async -> Result {
        let hex = icao24.lowercased().filter { $0.isHexDigit }
        guard hex.count == 6, let url = URL(string: "https://opensky-network.org/api/states/all?icao24=\(hex)") else { return .failed("bad address") }
        var req = URLRequest(url: url); req.timeoutInterval = 15
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if code == 429 { return .failed("OpenSky rate limit; will retry") }
            guard code == 200 else { return .failed("OpenSky HTTP \(code)") }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let states = json["states"] as? [[Any]], let s = states.first, s.count > 10 else { return .notFound }
            guard let lon = s[5] as? Double, let lat = s[6] as? Double else { return .notFound }
            let alt = (s[7] as? Double) ?? (s.count > 13 ? s[13] as? Double : nil)
            let vel = s[9] as? Double
            let ts = ((s[4] as? Double) ?? (s[3] as? Double)).map { Date(timeIntervalSince1970: $0) } ?? Date()
            return .position(LivePosition(lat: lat, lon: lon, altFt: alt.map { Int($0 * 3.28084) }, speedKts: vel.map { Int($0 * 1.94384) },
                                          heading: s[10] as? Double, onGround: (s[8] as? Bool) ?? false, timestamp: ts))
        } catch { return .failed(error.localizedDescription) }
    }
}

extension AppModel {
    /// Polls OpenSky for airborne real flights (max once per 75 s per aircraft; keyless, so it costs no AeroDataBox units).
    func refreshPositions(_ flights: [Flight]) async {
        await Task { await self.performPositionRefresh(flights) }.value
    }
    private func performPositionRefresh(_ flights: [Flight]) async {
        let now = Date()
        for f in flights where f.isReal && f.ownerName == nil {
            let key = f.uuid.uuidString
            guard let snap = snapshots[key], let hex = snap.modeS, !hex.isEmpty else { continue }
            let s = live(f)
            guard s.phase == .enRoute || s.phase == .taxiingOut else { positions[key] = nil; continue }
            if let t = positionChecked[key], now.timeIntervalSince(t) < 75 { continue }
            positionChecked[key] = now
            switch await OpenSky.fetch(icao24: hex) {
            case .position(let p): positions[key] = p.onGround ? nil : p; positionNote = nil
            case .notFound: positionNote = "No live position for this aircraft right now (not covered by OpenSky receivers?). Showing an estimate."
            case .failed(let m): positionNote = m
            }
        }
    }
}
