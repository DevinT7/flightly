import Foundation
import CoreLocation

/// Everything the detail screen needs to show about a flight "right now".
enum FlightPhase: String {
    case scheduled = "Scheduled", boarding = "Boarding", taxiingOut = "Taxiing", enRoute = "In the air"
    case landed = "Landed", arrived = "Arrived", canceled = "Canceled"
}

struct InboundLeg: Identifiable {
    let id = UUID()
    let from: String, to: String
    let schedDep: Date, schedArr: Date
    let estArr: Date
    var delay: Int { Int(estArr.timeIntervalSince(schedArr) / 60) }
    let landed: Bool
}

struct WeatherInfo {
    let condition: String, symbol: String, tempC: Int, windKts: Int, visibilityMi: Int
    let metar: String
}

struct ForecastBucket: Identifiable { let id: String; let label: String; let pct: Double }

struct LiveState {
    var phase: FlightPhase
    var depDelay: Int
    var arrDelay: Int
    var estDep: Date, estArr: Date
    var actDep: Date?, actArr: Date?
    var progress: Double
    var position: CLLocationCoordinate2D?
    var heading: Double
    var altitudeFt: Int, speedKts: Int
    var delayReason: String?
    var prediction: String
    var depGate: String, arrGate: String, baggage: String
    var taxiOutMin: Int, taxiInMin: Int
    var inbound: [InboundLeg]
    var forecast: [ForecastBucket]
    var routeOnTimePct: Double, routeAvgDelay: Int
    var depWeather: WeatherInfo, arrWeather: WeatherInfo
    var trend: [Double]          // predicted delay by hour (min), for Delay Trend
    var canceledRisk: Double
    var minutesToBoarding: Int
    var weatherLive = false          // true when depWeather/arrWeather come from real METARs
    var faaDep: FAAStatus? = nil     // real FAA programs at the airports (US only)
    var faaArr: FAAStatus? = nil
    // Provenance. For real flights the simulator-only sections (inbound chain, forecast, trend) are left empty.
    var isReal = false
    var wheelsUp: Date? = nil
    var wheelsDown: Date? = nil
    var updatedAt: Date? = nil
}

/// Protocol so a real data source (AeroAPI, AeroDataBox, ...) can replace the simulator.
protocol FlightDataProvider {
    func state(for flight: Flight, at now: Date) -> LiveState
    func lookup(airlineCode: String, number: String, date: Date) -> Flight?
    func routeSearch(from: String, to: String, date: Date) -> [Flight]
}

struct SimulatedProvider: FlightDataProvider {
    static let shared = SimulatedProvider()

    // MARK: lookup
    func lookup(airlineCode: String, number: String, date: Date) -> Flight? {
        let code = airlineCode.uppercased()
        guard AirportDB.airline(code) != nil, let n = Int(number), n > 0 else { return nil }
        var r = Seed(key: "route\(code)\(n)").rng
        let a = AirportDB.all[r.int(AirportDB.all.count)]
        var b = AirportDB.all[r.int(AirportDB.all.count)]
        if b == a { b = AirportDB.all[(AirportDB.all.firstIndex(of: a)! + 7) % AirportDB.all.count] }
        return build(code, String(n), a, b, date, &r)
    }

    func routeSearch(from: String, to: String, date: Date) -> [Flight] {
        guard let a = AirportDB.airport(from), let b = AirportDB.airport(to), a != b else { return [] }
        var r = Seed(key: "rs\(from)\(to)").rng
        let carriers = AirportDB.airlines.shuffledStable(&r).prefix(6)
        return carriers.enumerated().map { i, al in
            var fr = Seed(key: "rsf\(from)\(to)\(al.code)").rng
            var d = date
            d = Calendar.current.date(bySettingHour: 6 + i * 2, minute: [0, 15, 30, 45][fr.int(4)], second: 0, of: d) ?? d
            return build(al.code, String(100 + fr.int(2800)), a, b, d, &fr, fixedDeparture: true)
        }
    }

    private func build(_ code: String, _ num: String, _ a: Airport, _ b: Airport, _ date: Date,
                       _ r: inout SeededRNG, fixedDeparture: Bool = false) -> Flight {
        let miles = Geo.distanceMiles(a, b)
        let hours = miles / 480 + 0.6
        var cal = Calendar.current; cal.timeZone = a.timeZone
        let hour = fixedDeparture ? cal.component(.hour, from: date) : 6 + r.int(15)
        let minute = fixedDeparture ? cal.component(.minute, from: date) : [0, 10, 25, 40, 55][r.int(5)]
        let dayStart = fixedDeparture ? cal.startOfDay(for: date) : cal.startOfDay(for: date)
        let dep = cal.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart) ?? date
        let arr = dep.addingTimeInterval(hours * 3600)
        return Flight(airlineCode: code, number: num, dep: a.iata, arr: b.iata, schedDep: dep, schedArr: arr, source: .search)
    }

    // MARK: live state
    func state(for f: Flight, at now: Date) -> LiveState {
        let dayKey = Int(f.schedDep.timeIntervalSince1970 / 86400)
        var r = Seed(key: "\(f.code)\(f.dep)\(f.arr)\(dayKey)").rng
        let depA = f.depAirport, arrA = f.arrAirport

        // Final delay outcome for this flight
        let roll = r.double()
        var finalDelay = 0
        var reason: String? = nil
        if roll < 0.55 { finalDelay = Int(r.range(-8, 8)) }
        else if roll < 0.80 { finalDelay = Int(r.range(12, 35)) }
        else if roll < 0.95 { finalDelay = Int(r.range(35, 95)) }
        else { finalDelay = Int(r.range(95, 220)) }
        let canceled = r.double() < 0.012
        let reasons = ["Late-arriving aircraft", "Weather at \(f.dep)", "Weather at \(f.arr)", "Air traffic control volume", "Crew availability", "Maintenance check", "Ground stop at \(f.arr)"]
        if finalDelay >= 15 { reason = reasons[r.int(reasons.count)] }

        // Inbound aircraft chain for the 25-hour "where's my plane"
        let others = AirportDB.all
        var chain: [InboundLeg] = []
        var prev = f.dep
        var t = f.schedDep.addingTimeInterval(-3600 * 1.0)
        let inboundDelayTarget = reason == "Late-arriving aircraft" ? finalDelay + 40 : Int(r.range(-5, 10))
        for i in 0..<3 {
            var o = others[r.int(others.count)]
            if o.iata == prev { o = others[(others.firstIndex(of: o)! + 3) % others.count] }
            let dur = max(1.2, Geo.distanceMiles(o, AirportDB.airport(prev) ?? o) / 480 + 0.6) * 3600
            let sArr = t, sDep = t.addingTimeInterval(-dur)
            let d = i == 0 ? inboundDelayTarget : Int(r.range(-5, 20))
            let est = sArr.addingTimeInterval(Double(d) * 60)
            chain.insert(InboundLeg(from: o.iata, to: prev, schedDep: sDep, schedArr: sArr, estArr: est, landed: est < now), at: 0)
            prev = o.iata
            t = sDep.addingTimeInterval(-3600 * 1.5)
        }
        // chain currently ordered oldest → newest; last = inbound leg
        let turnaround = 45.0 * 60
        if let last = chain.last, reason == "Late-arriving aircraft" {
            let needed = last.estArr.addingTimeInterval(turnaround).timeIntervalSince(f.schedDep) / 60
            finalDelay = max(finalDelay, Int(needed))
        }

        // Delay evolves as departure approaches (visible only gradually)
        let hrsToDep = f.schedDep.timeIntervalSince(now) / 3600
        let ramp = min(1, max(0, 1 - hrsToDep / 24))
        let shown = Int(Double(finalDelay) * ramp)
        let depDelay = canceled ? 0 : (now >= f.schedDep ? finalDelay : shown)
        let taxiOut = 8 + r.int(18), taxiIn = 5 + r.int(12)
        let estDep = f.schedDep.addingTimeInterval(Double(depDelay) * 60)
        let airborneSecs = f.schedArr.timeIntervalSince(f.schedDep) - Double(taxiOut + taxiIn) * 60
        let wheelsUp = estDep.addingTimeInterval(Double(taxiOut) * 60)
        let airDelayAdj = Int(r.range(-12, 6))
        let wheelsDown = wheelsUp.addingTimeInterval(airborneSecs + Double(airDelayAdj) * 60)
        let estArr = wheelsDown.addingTimeInterval(Double(taxiIn) * 60)
        let arrDelay = Int(estArr.timeIntervalSince(f.schedArr) / 60)

        // Phase / position
        var phase: FlightPhase = .scheduled
        var progress = 0.0
        if canceled { phase = .canceled }
        else if now >= estArr.addingTimeInterval(600) { phase = .arrived; progress = 1 }
        else if now >= wheelsDown { phase = .landed; progress = 1 }
        else if now >= wheelsUp { phase = .enRoute; progress = now.timeIntervalSince(wheelsUp) / wheelsDown.timeIntervalSince(wheelsUp) }
        else if now >= estDep { phase = .taxiingOut }
        else if now >= estDep.addingTimeInterval(-40 * 60) { phase = .boarding }
        progress = min(1, max(0, progress))

        var pos: CLLocationCoordinate2D? = nil
        var heading = 0.0
        if let a = depA, let b = arrA {
            if phase == .enRoute {
                pos = Geo.interpolate(a, b, progress)
                heading = Geo.bearing(pos!, Geo.interpolate(a, b, min(1, progress + 0.01)))
            } else if phase == .landed || phase == .arrived { pos = b.coordinate }
            else { pos = a.coordinate; heading = Geo.bearing(a.coordinate, b.coordinate) }
        }
        let altitude: Int, speed: Int
        if phase == .enRoute {
            let climb = min(1, min(progress / 0.12, (1 - progress) / 0.12))
            altitude = Int(37000 * max(0.02, climb)); speed = Int(120 + 330 * max(0.1, climb))
        } else { altitude = 0; speed = phase == .taxiingOut ? 15 : 0 }

        // Gate changes get decided deterministically ~2h before departure
        var depGate = f.depGate, arrGate = f.arrGate
        if hrsToDep < 2, r.double() < 0.35 { depGate = "\(["A","B","C","D"][r.int(4)])\(1 + r.int(40))" }
        if hrsToDep < 1, r.double() < 0.3 { arrGate = "\(["A","B","C","D"][r.int(4)])\(1 + r.int(40))" }

        // Route stats ("arrival forecast")
        var fr = Seed(key: "fc\(f.dep)\(f.arr)\(f.airlineCode)").rng
        let onTime = fr.range(58, 90)
        let l1 = fr.range(4, 14), l2 = fr.range(2, 9), l3 = fr.range(1, 5)
        let canc = fr.range(0.3, 2.5)
        let early = fr.range(8, 22)
        let total = onTime + l1 + l2 + l3 + canc
        let scale = 100 / total
        let forecast = [
            ForecastBucket(id: "early", label: "Early", pct: early * scale * 0.5),
            ForecastBucket(id: "ontime", label: "On time", pct: onTime * scale - early * scale * 0.5),
            ForecastBucket(id: "l15", label: "15–30m", pct: l1 * scale),
            ForecastBucket(id: "l30", label: "30–60m", pct: l2 * scale),
            ForecastBucket(id: "l60", label: "60m+", pct: l3 * scale),
            ForecastBucket(id: "canc", label: "Canceled", pct: canc * scale),
        ]
        let avgDelay = Int(fr.range(4, 22))

        // Delay trend (when delays start/ease) for the departure airport
        var tr = Seed(key: "trend\(f.dep)\(dayKey)").rng
        let peak = tr.range(8, 18), amp = tr.range(8, 45)
        let trend = (0..<24).map { h in max(0, amp * exp(-pow((Double(h) - peak) / 4.0, 2)) + tr.range(0, 4)) }

        let prediction: String
        switch phase {
        case .canceled: prediction = "This flight has been canceled."
        case .arrived, .landed: prediction = arrDelay > 15 ? "Arrived \(arrDelay) min late." : (arrDelay < -5 ? "Arrived \(-arrDelay) min early." : "Arrived on time.")
        default:
            if finalDelay >= 15 && hrsToDep > 0 && shown < 15 { prediction = "Delay predicted: about \(finalDelay) min." }
            else if depDelay >= 15 { prediction = "Departure is running \(depDelay) min late." }
            else { prediction = "Currently expected on time." }
        }

        var st = LiveState(
            phase: phase, depDelay: depDelay, arrDelay: canceled ? 0 : arrDelay,
            estDep: estDep, estArr: estArr,
            actDep: now >= wheelsUp ? wheelsUp : nil, actArr: now >= wheelsDown ? wheelsDown : nil,
            progress: progress, position: pos, heading: heading, altitudeFt: altitude, speedKts: speed,
            delayReason: reason, prediction: prediction, depGate: depGate, arrGate: arrGate, baggage: f.baggage,
            taxiOutMin: taxiOut, taxiInMin: taxiIn, inbound: chain, forecast: forecast,
            routeOnTimePct: forecast[0].pct + forecast[1].pct, routeAvgDelay: avgDelay,
            depWeather: weather(f.dep, now), arrWeather: weather(f.arr, now), trend: trend,
            canceledRisk: canc * scale, minutesToBoarding: Int(estDep.addingTimeInterval(-40 * 60).timeIntervalSince(now) / 60))
        st.wheelsUp = wheelsUp; st.wheelsDown = wheelsDown
        return st
    }

    // MARK: weather & airports
    func weather(_ iata: String, _ now: Date) -> WeatherInfo {
        let hourKey = Int(now.timeIntervalSince1970 / 10800)
        var r = Seed(key: "wx\(iata)\(hourKey)").rng
        let conds: [(String, String)] = [("Clear", "sun.max.fill"), ("Partly cloudy", "cloud.sun.fill"), ("Overcast", "cloud.fill"),
                                         ("Rain", "cloud.rain.fill"), ("Thunderstorms", "cloud.bolt.rain.fill"), ("Fog", "cloud.fog.fill"), ("Snow", "snowflake")]
        let weights = [30, 25, 15, 12, 5, 6, 7]
        var pick = r.int(weights.reduce(0, +)), idx = 0
        for (i, w) in weights.enumerated() { if pick < w { idx = i; break }; pick -= w }
        let lat = abs(AirportDB.airport(iata)?.lat ?? 30)
        let temp = Int(30 - lat * 0.4 + r.range(-8, 8))
        let wind = 4 + r.int(22)
        let vis = [5, 6, 3, 2, 6, 1, 1][idx] + r.int(3)
        let day = Calendar.current.component(.day, from: now), hr = Calendar.current.component(.hour, from: now)
        let metar = "K\(iata) \(String(format: "%02d", day))\(String(format: "%02d", hr))53Z \(String(format: "%03d", r.int(36) * 10))\(String(format: "%02d", wind))KT \(vis)SM \(conds[idx].0.uppercased().prefix(3)) \(temp)/\(max(-9, temp - 6)) A\(2980 + r.int(50))"
        return WeatherInfo(condition: conds[idx].0, symbol: conds[idx].1, tempC: temp, windKts: wind, visibilityMi: vis, metar: metar)
    }

    struct AirportStatus {
        let airport: Airport
        let severity: Int      // 0 normal, 1 minor, 2 moderate, 3 severe
        let avgDelay: Int
        let reason: String
        let weather: WeatherInfo
    }
    func status(_ a: Airport, _ now: Date) -> AirportStatus {
        let w = weather(a.iata, now)
        var r = Seed(key: "st\(a.iata)\(Int(now.timeIntervalSince1970 / 3600))").rng
        var sev = r.double() < 0.7 ? 0 : (r.double() < 0.6 ? 1 : (r.double() < 0.7 ? 2 : 3))
        if ["Thunderstorms", "Snow", "Fog"].contains(w.condition) { sev = max(sev, 2) }
        let avg = [r.int(8), 15 + r.int(15), 30 + r.int(25), 60 + r.int(60)][sev]
        let reason: String
        switch (sev, w.condition) {
        case (0, _): reason = "No significant delays"
        case (_, "Thunderstorms"): reason = "Thunderstorms in the area"
        case (_, "Snow"): reason = "Snow and de-icing"
        case (_, "Fog"): reason = "Low visibility"
        default: reason = ["High traffic volume", "Runway construction", "Ground delay program", "Staffing"][r.int(4)]
        }
        return AirportStatus(airport: a, severity: sev, avgDelay: avg, reason: reason, weather: w)
    }

    struct BoardRow: Identifiable { let id = UUID(); let code: String, other: String, time: Date, status: String, gate: String, delay: Int }
    func board(_ a: Airport, departures: Bool, now: Date) -> [BoardRow] {
        var r = Seed(key: "bd\(a.iata)\(departures)\(Int(now.timeIntervalSince1970 / 3600))").rng
        return (0..<14).map { i in
            let al = AirportDB.airlines[r.int(AirportDB.airlines.count)]
            var o = AirportDB.all[r.int(AirportDB.all.count)]; if o == a { o = AirportDB.all[(AirportDB.all.firstIndex(of: o)! + 1) % AirportDB.all.count] }
            let d = r.double() < 0.7 ? 0 : Int(r.range(10, 80))
            let t = now.addingTimeInterval(Double(i * 11 - 20 + r.int(8)) * 60)
            let st = t < now.addingTimeInterval(-30 * 60) ? (departures ? "Departed" : "Landed") : (d > 14 ? "Delayed" : "On time")
            return BoardRow(code: al.code + String(100 + r.int(2800)), other: o.iata, time: t, status: st, gate: "\(["A","B","C"][r.int(3)])\(1 + r.int(30))", delay: d)
        }.sorted { $0.time < $1.time }
    }

    func hourlyPerformance(_ a: Airport, _ now: Date) -> [(hour: Int, onTime: Double)] {
        var r = Seed(key: "hp\(a.iata)\(Int(now.timeIntervalSince1970 / 86400))").rng
        return (5..<24).map { h in (h, max(40, min(99, 95 - Double(max(0, h - 10)) * r.range(1.5, 3.2) + r.range(-4, 4)))) }
    }

    func runwayRegulars(_ a: Airport) -> [(name: String, flights: Int)] {
        var r = Seed(key: "rr\(a.iata)").rng
        let names = ["Maya R.", "Jonas K.", "Priya S.", "Diego M.", "Aiko T.", "Sam W.", "Lena F.", "Omar H."]
        return (0..<3).map { i in (names[r.int(names.count)], 120 - i * 22 - r.int(15)) }
    }
}

extension Array {
    func shuffledStable(_ r: inout SeededRNG) -> [Element] {
        var a = self
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, r.int(i + 1)) }
        return a
    }
}
