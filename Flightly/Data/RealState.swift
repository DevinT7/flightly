import Foundation
import CoreLocation

/// Builds the app's LiveState for a real flight from the provider snapshot. Anything the provider doesn't supply
/// is left empty (never invented): no inbound chain, forecast or trend, and unknown gate/taxi data shows as "—".
enum RealState {
    static func make(_ f: Flight, _ snap: RealSnapshot, now: Date, live: LivePosition? = nil) -> LiveState {
        let sched = (dep: snap.depSched ?? f.schedDep, arr: snap.arrSched ?? f.schedArr)
        let estDep = snap.depRevised ?? sched.dep
        let estArr = snap.arrRevised ?? sched.arr
        let depDelay = Int(estDep.timeIntervalSince(sched.dep) / 60)
        let arrDelay = Int(estArr.timeIntervalSince(sched.arr) / 60)

        let status = snap.status
        let phase: FlightPhase = {
            if status.hasPrefix("Canceled") { return .canceled }
            if status == "Arrived" { return .arrived }
            if let r = snap.arrRunway, now >= r { return now >= r.addingTimeInterval(15 * 60) ? .arrived : .landed }
            if ["EnRoute", "Approaching", "Diverted"].contains(status) { return .enRoute }
            if let r = snap.depRunway, now >= r { return .enRoute }
            if status == "Departed" { return .taxiingOut }
            if ["Boarding", "GateClosed"].contains(status) { return .boarding }
            return .scheduled
        }()

        let airborneStart = snap.depRunway ?? (phase == .enRoute ? estDep : nil)
        var progress = 0.0
        switch phase {
        case .arrived, .landed: progress = 1
        case .enRoute:
            if let start = airborneStart { progress = now.timeIntervalSince(start) / max(60, estArr.timeIntervalSince(start)) }
            else { progress = 0.05 }
        default: progress = 0
        }
        progress = min(1, max(0, progress))

        var position: CLLocationCoordinate2D?
        var heading = snap.heading ?? 0
        var livePos = false
        if let lp = live, phase == .enRoute || phase == .taxiingOut, let a = f.depAirport, let b = f.arrAirport {
            // Progress from the real position: share of the remaining+flown great-circle distance already covered.
            let here = CLLocation(latitude: lp.lat, longitude: lp.lon)
            let flown = CLLocation(latitude: a.lat, longitude: a.lon).distance(from: here)
            let left = CLLocation(latitude: b.lat, longitude: b.lon).distance(from: here)
            let routeLen = CLLocation(latitude: a.lat, longitude: a.lon).distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
            // Trust the position only if it lies near the planned route (guards against a swapped aircraft or a stale/wrong ID).
            if flown + left > 0, flown + left < routeLen * 1.5 + 150_000 {
                progress = min(1, max(0, flown / (flown + left)))
                position = lp.coordinate; heading = lp.heading ?? heading; livePos = true
            }
        }
        if livePos {}
        else if let lat = snap.lat, let lon = snap.lon, phase == .enRoute { position = .init(latitude: lat, longitude: lon) }
        else if let a = f.depAirport, let b = f.arrAirport {
            if phase == .enRoute { position = Geo.interpolate(a, b, progress)   // estimated along the great circle
                heading = Geo.bearing(position!, Geo.interpolate(a, b, min(1, progress + 0.01))) }
            else if phase == .landed || phase == .arrived { position = b.coordinate }
            else { position = a.coordinate; heading = Geo.bearing(a.coordinate, b.coordinate) }
        }

        let late = depDelay >= 15
        let prediction: String = {
            switch phase {
            case .canceled: return "This flight has been canceled."
            case .arrived, .landed: return arrDelay >= 15 ? "Arrived \(arrDelay) min late." : (arrDelay <= -5 ? "Arrived \(-arrDelay) min early." : "Arrived on time.")
            case .enRoute: return arrDelay >= 15 ? "Running \(arrDelay) min behind schedule." : "On schedule."
            default: return late ? "Departure is running \(depDelay) min late." : "On schedule."
            }
        }()

        let nowSim = SimulatedProvider.shared   // only for placeholder weather until live METAR overlays it
        var s = LiveState(
            phase: phase, depDelay: depDelay, arrDelay: phase == .canceled ? 0 : arrDelay, estDep: estDep, estArr: estArr,
            actDep: snap.depRunway, actArr: snap.arrRunway, progress: progress, position: position, heading: heading,
            altitudeFt: live?.altFt ?? snap.altFt ?? 0, speedKts: live?.speedKts ?? snap.speedKts ?? 0, delayReason: nil, prediction: prediction,
            depGate: snap.depGate ?? "—", arrGate: snap.arrGate ?? "—", baggage: snap.baggage ?? "—",
            taxiOutMin: snap.depRunway.map { max(0, Int($0.timeIntervalSince(estDep) / 60)) } ?? 0,
            taxiInMin: (snap.arrRunway != nil) ? max(0, Int(estArr.timeIntervalSince(snap.arrRunway!) / 60)) : 0,
            inbound: [], forecast: [], routeOnTimePct: 0, routeAvgDelay: 0,
            depWeather: nowSim.weather(f.dep, now), arrWeather: nowSim.weather(f.arr, now), trend: [], canceledRisk: 0,
            minutesToBoarding: Int(estDep.addingTimeInterval(-40 * 60).timeIntervalSince(now) / 60))
        s.isReal = true
        s.positionLive = livePos
        s.positionTime = live?.timestamp
        s.wheelsUp = snap.depRunway; s.wheelsDown = snap.arrRunway; s.updatedAt = snap.fetchedAt
        return s
    }

    /// How long to wait before spending quota on this flight again. nil = never (finished or canceled).
    static func nextInterval(_ f: Flight, status: String, now: Date, remainingUnits: Int?) -> TimeInterval? {
        if status.hasPrefix("Canceled") { return nil }
        if status == "Arrived", now > f.schedArr.addingTimeInterval(2 * 3600) { return nil }
        if now > f.schedArr.addingTimeInterval(6 * 3600) { return nil }
        let hrsToDep = f.schedDep.timeIntervalSince(now) / 3600
        var base: TimeInterval
        if now >= f.schedDep.addingTimeInterval(-0.5 * 3600) {                       // gate area / in the air
            let hrsToArr = f.schedArr.timeIntervalSince(now) / 3600
            base = hrsToArr < 1 ? 20 * 60 : 45 * 60
        } else if hrsToDep < 3 { base = 45 * 60 }
        else if hrsToDep < 12 { base = 2 * 3600 }
        else if hrsToDep < 48 { base = 6 * 3600 }
        else { base = 24 * 3600 }
        if let r = remainingUnits, r < 150 { base *= 2 }                              // stretch the remaining budget
        return base
    }
}
