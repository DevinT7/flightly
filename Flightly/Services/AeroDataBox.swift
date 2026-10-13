import Foundation
import Security
import SwiftData

// MARK: - Secret storage

/// The RapidAPI key lives in the Keychain (entered in Settings), never in source or the repo.
/// For local development you can also launch with SIMCTL_CHILD_RAPIDAPI_KEY set.
enum Keychain {
    private static let service = "com.flightly.app"
    private static var fallbackURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".secrets.json")
    }
    private static func fileLoad() -> [String: String] {
        (try? Data(contentsOf: fallbackURL)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }
    private static func fileSave(_ d: [String: String]) {
        guard let data = try? JSONEncoder().encode(d) else { return }
        try? data.write(to: fallbackURL, options: [.atomic, .completeFileProtection])
        var u = fallbackURL; var rv = URLResourceValues(); rv.isExcludedFromBackup = true; try? u.setResourceValues(rv)
    }

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data, let s = String(data: d, encoding: .utf8) { return s }
        return fileLoad()[account]      // fallback used when the Keychain is unavailable (e.g. unsigned dev builds)
    }

    /// Returns where the value ended up, or nil if it could not be stored anywhere.
    @discardableResult
    static func set(_ value: String, account: String) -> String? {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        let status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecSuccess { var f = fileLoad(); f[account] = nil; fileSave(f); return "Keychain" }
        var f = fileLoad(); f[account] = value; fileSave(f)
        return fileLoad()[account] == value ? "protected app storage (Keychain unavailable: \(status))" : nil
    }
    static func delete(_ account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        var f = fileLoad(); f[account] = nil; fileSave(f)
    }
}

// MARK: - Quota

struct ADBQuota: Codable, Equatable {
    var unitsLimit: Int?
    var unitsRemaining: Int?
    var resetAt: Date?
    var requestsRemaining: Int?
    var updated: Date?
    /// Below this we stop automatic refreshes and keep the remaining units for things you ask for.
    static let autoFloor = 60
    static let hardFloor = 8
}

// MARK: - Parsed provider models

struct ADBAirportData {
    var icao: String?
    var iata: String
    var name: String
    var lat: Double
    var lon: Double
    var countryCode: String?
    var tz: String?
}

struct ADBLeg {
    var airport: ADBAirportData?
    var scheduled: Date?
    var revised: Date?
    var runway: Date?
    var terminal: String?
    var gate: String?
    var baggage: String?
    var checkIn: String?
}

struct ADBLocationData {
    var lat: Double
    var lon: Double
    var altFt: Int?
    var speedKts: Int?
    var heading: Double?
}

struct ADBFlight {
    var airlineIata: String
    var airlineName: String
    var number: String
    var status: String
    var dep: ADBLeg
    var arr: ADBLeg
    var reg: String?
    var model: String?
    var modeS: String?
    var location: ADBLocationData?
}

enum ADBParse {
    private static let utc: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd HH:mm'Z'"; return f
    }()
    private static func date(_ v: Any?) -> Date? { ((v as? [String: Any])?["utc"] as? String).flatMap { utc.date(from: $0) } }
    private static func str(_ v: Any?) -> String? { let s = (v as? String)?.trimmingCharacters(in: .whitespaces); return (s?.isEmpty ?? true) ? nil : s }

    static func airport(_ v: Any?) -> ADBAirportData? {
        guard let d = v as? [String: Any], let iata = str(d["iata"]) else { return nil }
        let loc = d["location"] as? [String: Any]
        return ADBAirportData(icao: str(d["icao"]), iata: iata.uppercased(), name: str(d["name"]) ?? str(d["shortName"]) ?? iata,
                              lat: (loc?["lat"] as? Double) ?? 0, lon: (loc?["lon"] as? Double) ?? 0, countryCode: str(d["countryCode"]), tz: str(d["timeZone"]))
    }
    static func leg(_ v: Any?) -> ADBLeg {
        let d = v as? [String: Any] ?? [:]
        return ADBLeg(airport: airport(d["airport"]), scheduled: date(d["scheduledTime"]), revised: date(d["revisedTime"]) ?? date(d["predictedTime"]),
                      runway: date(d["runwayTime"]), terminal: str(d["terminal"]), gate: str(d["gate"]), baggage: str(d["baggageBelt"]), checkIn: str(d["checkInDesk"]))
    }
    static func location(_ v: Any?) -> ADBLocationData? {
        guard let d = v as? [String: Any] else { return nil }
        let inner = d["location"] as? [String: Any]
        guard let lat = (inner?["lat"] as? Double) ?? (d["lat"] as? Double), let lon = (inner?["lon"] as? Double) ?? (d["lon"] as? Double) else { return nil }
        let alt = ((d["pressureAltitude"] as? [String: Any])?["feet"] as? Double).map(Int.init) ?? (d["altitude"] as? [String: Any])?["feet"].flatMap { ($0 as? Double).map(Int.init) }
        let spd = ((d["groundSpeed"] as? [String: Any])?["kt"] as? Double).map(Int.init)
        let hdg = (d["trueTrack"] as? [String: Any])?["deg"] as? Double
        return ADBLocationData(lat: lat, lon: lon, altFt: alt, speedKts: spd, heading: hdg)
    }
    static func flight(_ d: [String: Any]) -> ADBFlight? {
        guard let rawNumber = str(d["number"]) else { return nil }
        let al = d["airline"] as? [String: Any]
        let airlineIata = (str(al?["iata"]) ?? String(rawNumber.prefix(2))).uppercased()
        let compact = rawNumber.replacingOccurrences(of: " ", with: "")
        let number = compact.hasPrefix(airlineIata) ? String(compact.dropFirst(airlineIata.count)) : compact
        let ac = d["aircraft"] as? [String: Any]
        return ADBFlight(airlineIata: airlineIata, airlineName: str(al?["name"]) ?? airlineIata, number: number, status: str(d["status"]) ?? "Unknown",
                         dep: leg(d["departure"]), arr: leg(d["arrival"]), reg: str(ac?["reg"]), model: str(ac?["model"]), modeS: str(ac?["modeS"])?.lowercased(), location: location(d["location"]))
    }
    static func flights(_ data: Data) -> [ADBFlight] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let arr = json as? [[String: Any]] { return arr.compactMap(flight) }
        if let obj = json as? [String: Any] {
            let list = ((obj["departures"] as? [[String: Any]]) ?? []) + ((obj["arrivals"] as? [[String: Any]]) ?? [])
            return list.compactMap(flight)
        }
        return []
    }
}

// MARK: - Snapshot (what we remember about a real flight; persisted to save quota)

struct RealSnapshot: Codable, Equatable {
    var status: String
    var depSched: Date?
    var depRevised: Date?
    var depRunway: Date?
    var arrSched: Date?
    var arrRevised: Date?
    var arrRunway: Date?
    var depTerminal: String?
    var depGate: String?
    var depCheckIn: String?
    var arrTerminal: String?
    var arrGate: String?
    var baggage: String?
    var reg: String?
    var model: String?
    var modeS: String?
    var lat: Double?
    var lon: Double?
    var altFt: Int?
    var speedKts: Int?
    var heading: Double?
    var fetchedAt: Date
    var nextFetch: Date

    init(_ f: ADBFlight, fetchedAt: Date = Date(), nextFetch: Date = Date()) {
        status = f.status
        depSched = f.dep.scheduled; depRevised = f.dep.revised; depRunway = f.dep.runway
        arrSched = f.arr.scheduled; arrRevised = f.arr.revised; arrRunway = f.arr.runway
        depTerminal = f.dep.terminal; depGate = f.dep.gate; depCheckIn = f.dep.checkIn
        arrTerminal = f.arr.terminal; arrGate = f.arr.gate; baggage = f.arr.baggage
        reg = f.reg; model = f.model; modeS = f.modeS
        lat = f.location?.lat; lon = f.location?.lon; altFt = f.location?.altFt; speedKts = f.location?.speedKts; heading = f.location?.heading
        self.fetchedAt = fetchedAt; self.nextFetch = nextFetch
    }
}

extension RealSnapshot {
    /// Placeholder before the first successful fetch for a real flight: schedule from the flight record, nothing else.
    init(emptyFor f: Flight) {
        status = "Expected"; depSched = f.schedDep; arrSched = f.schedArr
        fetchedAt = .distantPast; nextFetch = Date()
    }
}

// MARK: - Mapping provider data -> app models

enum ADBMap {
    static func register(_ a: ADBAirportData) {
        guard AirportDB.airport(a.iata) == nil else { return }
        let country = a.countryCode.flatMap { Locale.current.localizedString(forRegionCode: $0.uppercased()) } ?? (a.countryCode ?? "")
        AirportDB.register(Airport(iata: a.iata, name: a.name, city: a.name.replacingOccurrences(of: " International", with: "").replacingOccurrences(of: " Airport", with: ""),
                                   country: country, lat: a.lat, lon: a.lon, tz: a.tz ?? "UTC", icaoCode: a.icao))
    }

    /// Creates a Flight (marked real) from a provider record. Returns nil if the route or times are missing.
    static func makeFlight(_ f: ADBFlight) -> Flight? {
        guard let da = f.dep.airport, let aa = f.arr.airport, let sd = f.dep.scheduled, let sa = f.arr.scheduled else { return nil }
        register(da); register(aa)
        AirportDB.register(Airline(code: f.airlineIata, name: f.airlineName))
        let fl = Flight(airlineCode: f.airlineIata, number: f.number, dep: da.iata, arr: aa.iata, schedDep: sd, schedArr: sa, source: .search)
        fl.isReal = true
        apply(f, to: fl)
        return fl
    }

    /// Copies provider details onto the flight; returns human-readable change notes (for the Record of Changes).
    @discardableResult
    static func apply(_ f: ADBFlight, to fl: Flight) -> [String] {
        var notes: [String] = []
        func set(_ keyPath: ReferenceWritableKeyPath<Flight, String>, _ new: String?, _ label: String) {
            let v = new ?? "—"
            if fl[keyPath: keyPath] != v {
                let old = fl[keyPath: keyPath]
                fl[keyPath: keyPath] = v
                if fl.isReal, old != "—", !old.isEmpty, v != "—", !fl.createdIsFresh { notes.append("\(label) changed \(old) → \(v)") }
            }
        }
        set(\.depTerminal, f.dep.terminal, "Departure terminal"); set(\.depGate, f.dep.gate, "Departure gate")
        set(\.arrTerminal, f.arr.terminal, "Arrival terminal"); set(\.arrGate, f.arr.gate, "Arrival gate")
        set(\.baggage, f.arr.baggage, "Baggage claim")
        if let r = f.reg {
            if fl.tail != r { if !fl.tail.isEmpty, fl.tail != "—", !fl.createdIsFresh { notes.append("Aircraft changed \(fl.tail) → \(r)") }; fl.tail = r }
        } else if fl.createdIsFresh { fl.tail = "" }
        if let m = f.model { fl.aircraft = m } else if fl.createdIsFresh { fl.aircraft = "" }
        if let sd = f.dep.scheduled, abs(sd.timeIntervalSince(fl.schedDep)) > 60 { notes.append("Departure rescheduled to \(sd.formatted(date: .abbreviated, time: .shortened))"); fl.schedDep = sd }
        if let sa = f.arr.scheduled, abs(sa.timeIntervalSince(fl.schedArr)) > 60 { fl.schedArr = sa }
        return notes
    }
}

extension Flight {
    /// True for ~1 minute after creation, so the first fill from the provider isn't logged as a "change".
    var createdIsFresh: Bool { Date().timeIntervalSince(createdAt) < 90 }
}

// MARK: - Client

enum ADBError: LocalizedError {
    case noKey, unauthorized, rateLimited, lowQuota(Int), http(Int), network(String)
    var errorDescription: String? {
        switch self {
        case .noKey: "No AeroDataBox key. Add one in Settings → Data sources."
        case .unauthorized: "AeroDataBox rejected the key (check it, and that you're subscribed to the API)."
        case .rateLimited: "AeroDataBox rate limit or monthly quota reached."
        case .lowQuota(let n): "Only \(n) API units left this month; keeping them in reserve."
        case .http(let c): "AeroDataBox returned HTTP \(c)."
        case .network(let m): m
        }
    }
}

enum ADB {
    static let host = "aerodatabox.p.rapidapi.com"
    static var apiKey: String? {
        if let k = ProcessInfo.processInfo.environment["RAPIDAPI_KEY"], !k.isEmpty { return k }
        return Keychain.get("rapidapi-key")
    }
    static var hasKey: Bool { apiKey?.isEmpty == false }

    struct Response { var data: Data?; var quota: ADBQuota }

    /// One GET. 204 → data nil. Parses quota headers on every response.
    static func get(_ path: String, current: ADBQuota) async throws -> Response {
        guard let key = apiKey, !key.isEmpty else { throw ADBError.noKey }
        if let rem = current.unitsRemaining, rem < ADBQuota.hardFloor { throw ADBError.lowQuota(rem) }
        guard let url = URL(string: "https://\(host)\(path)") else { throw ADBError.network("bad URL") }
        var req = URLRequest(url: url); req.timeoutInterval = 25
        req.setValue(key, forHTTPHeaderField: "X-RapidAPI-Key"); req.setValue(host, forHTTPHeaderField: "X-RapidAPI-Host")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            var q = current
            func hdr(_ n: String) -> Int? { http?.value(forHTTPHeaderField: n).flatMap { Int($0) } }
            if let r = hdr("x-ratelimit-api-units-remaining") { q.unitsRemaining = r }
            if let l = hdr("x-ratelimit-api-units-limit") { q.unitsLimit = l }
            if let rs = hdr("x-ratelimit-api-units-reset") { q.resetAt = Date().addingTimeInterval(TimeInterval(rs)) }
            if let rq = hdr("x-ratelimit-requests-remaining") { q.requestsRemaining = rq }
            q.updated = Date()
            switch http?.statusCode ?? -1 {
            case 200: return Response(data: data, quota: q)
            case 204: return Response(data: nil, quota: q)
            case 401, 403: throw ADBError.unauthorized
            case 429: throw ADBError.rateLimited
            case let c: throw ADBError.http(c)
            }
        } catch let e as ADBError { throw e }
        catch { throw ADBError.network(error.localizedDescription) }
    }

    static func flightPath(code: String, number: String, dateLocal: String) -> String {
        "/flights/number/\(code)\(number)/\(dateLocal)?withAircraftImage=false&withLocation=true&dateLocalRole=Both"
    }
    static func boardPath(iata: String, from: String, to: String, direction: String) -> String {
        "/flights/airports/iata/\(iata)/\(from)/\(to)?withLeg=true&direction=\(direction)&withCancelled=true&withCodeshared=false&withCargo=false&withPrivate=false"
    }
}

// MARK: - AppModel: fetching, persistence, refresh policy

extension AppModel {
    private var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("adb-state.json")
    }
    private struct Persisted: Codable { var snapshots: [String: RealSnapshot]; var quota: ADBQuota }

    func loadPersistedADB() {
        guard let d = try? Data(contentsOf: storeURL), let p = try? JSONDecoder().decode(Persisted.self, from: d) else { return }
        snapshots = p.snapshots; quota = p.quota
    }
    func persistADB() {
        if let d = try? JSONEncoder().encode(Persisted(snapshots: snapshots, quota: quota)) { try? d.write(to: storeURL, options: .atomic) }
    }

    private func call(_ path: String) async throws -> Data? {
        let r = try await ADB.get(path, current: quota)
        quota = r.quota; persistADB()
        return r.data
    }

    // MARK: Lookups (user-initiated)

    /// Real flights for a flight number on a local date, or [] if the provider has none.
    func lookupRealFlights(code: String, number: String, date: Date) async throws -> [Flight] {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.locale = Locale(identifier: "en_US_POSIX")
        guard let data = try await call(ADB.flightPath(code: code, number: number, dateLocal: df.string(from: date))) else { return [] }
        adbError = nil
        var out: [Flight] = []
        for item in ADBParse.flights(data) {
            guard let fl = ADBMap.makeFlight(item) else { continue }
            pendingSnapshots[fl.uuid.uuidString] = RealSnapshot(item, nextFetch: Date().addingTimeInterval(3600))
            out.append(fl)
        }
        return out
    }

    /// Called when the user adds a looked-up flight: keep its first snapshot.
    func adopt(_ f: Flight) {
        if let snap = pendingSnapshots.removeValue(forKey: f.uuid.uuidString) { snapshots[f.uuid.uuidString] = snap; persistADB() }
    }

    // MARK: Board (airport detail)

    func realBoard(iata: String, departures: Bool) async throws -> [SimulatedProvider.BoardRow] {
        guard let tz = AirportDB.airport(iata)?.timeZone else { return [] }
        var cal = Calendar.current; cal.timeZone = tz
        let df = DateFormatter(); df.calendar = cal; df.timeZone = tz; df.dateFormat = "yyyy-MM-dd'T'HH:mm"; df.locale = Locale(identifier: "en_US_POSIX")
        let from = Date().addingTimeInterval(-30 * 60), to = Date().addingTimeInterval(2.5 * 3600)
        let path = ADB.boardPath(iata: iata, from: df.string(from: from), to: df.string(from: to), direction: departures ? "Departure" : "Arrival")
        guard let data = try await call(path) else { return [] }
        return ADBParse.flights(data).compactMap { f in
            let here = departures ? f.dep : f.arr, other = departures ? f.arr : f.dep
            guard let t = here.revised ?? here.scheduled, let o = other.airport?.iata else { return nil }
            let delay = max(0, Int(((here.revised ?? here.scheduled ?? t).timeIntervalSince(here.scheduled ?? t)) / 60))
            return SimulatedProvider.BoardRow(code: f.airlineIata + f.number, other: o, time: t, status: f.status, gate: here.gate ?? "—", delay: delay)
        }.sorted { $0.time < $1.time }
    }

    // MARK: Background-ish refresh of tracked real flights (budget-aware)

    /// Unstructured so a SwiftUI `.task` restart can't cancel an in-flight (quota-spending) request.
    func refreshRealFlights(_ flights: [Flight], context: ModelContext, force: Flight? = nil) async {
        await Task { await self.performRefreshReal(flights, context: context, force: force) }.value
    }

    private func performRefreshReal(_ flights: [Flight], context: ModelContext, force: Flight?) async {
        guard ADB.hasKey, !adbBusy else { return }
        if force == nil, !adbAuto { return }
        if force == nil, let r = quota.unitsRemaining, r < ADBQuota.autoFloor { return }
        adbBusy = true; defer { adbBusy = false }
        let now = Date()
        var due = flights.filter { $0.isReal && $0.ownerName == nil }
        if let force { due = [force] }
        else { due = due.filter { f in (snapshots[f.uuid.uuidString]?.nextFetch ?? .distantPast) <= now && RealState.nextInterval(f, status: snapshots[f.uuid.uuidString]?.status ?? "Expected", now: now, remainingUnits: quota.unitsRemaining) != nil } }
        for f in due.prefix(3) {
            let dayDF = DateFormatter(); dayDF.timeZone = f.depAirport?.timeZone ?? .current; dayDF.dateFormat = "yyyy-MM-dd"; dayDF.locale = Locale(identifier: "en_US_POSIX")
            do {
                let data = try await call(ADB.flightPath(code: f.airlineCode, number: f.number, dateLocal: dayDF.string(from: f.schedDep)))
                let items = data.map { ADBParse.flights($0) } ?? []
                guard let item = items.first(where: { $0.dep.airport?.iata == f.dep && $0.arr.airport?.iata == f.arr }) ?? items.first else {
                    var s = snapshots[f.uuid.uuidString] ?? RealSnapshot(emptyFor: f); s.nextFetch = now.addingTimeInterval(6 * 3600); snapshots[f.uuid.uuidString] = s; continue
                }
                let notes = ADBMap.apply(item, to: f)
                notes.forEach { f.record($0) }
                let interval = RealState.nextInterval(f, status: item.status, now: now, remainingUnits: quota.unitsRemaining) ?? 24 * 3600 * 7
                snapshots[f.uuid.uuidString] = RealSnapshot(item, fetchedAt: now, nextFetch: now.addingTimeInterval(interval))
                adbError = nil
            } catch {
                adbError = error.localizedDescription
                if case ADBError.unauthorized = error { break }
                if case ADBError.rateLimited = error { break }
            }
        }
        try? context.save(); persistADB()
    }
}

#if DEBUG
/// Debug-only: load real flights from a saved AeroDataBox board response (e.g. `.probe/airport_fids.json`) so the
/// live-data UI can be exercised without spending quota. Launch with SIMCTL_CHILD_FLIGHTLY_FIXTURE=<path>.
extension AppModel {
    func loadFixture(path: String, hereAirportInfo: String, context: ModelContext) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let infoData = try? Data(contentsOf: URL(fileURLWithPath: hereAirportInfo)),
              let info = try? JSONSerialization.jsonObject(with: infoData) as? [String: Any],
              let here = ADBParse.airport(info) else { return }
        let existing = (try? context.fetch(FetchDescriptor<Flight>())) ?? []
        let liveTest = ProcessInfo.processInfo.environment["FLIGHTLY_FIXTURE_MODES"] != nil
        if liveTest { guard !existing.contains(where: { $0.notes == "fixture-live" }) else { return } }
        else { guard !existing.contains(where: { $0.isReal }) else { return } }
        var picks: [ADBFlight] = []
        let all = ADBParse.flights(data)
        if liveTest, let one = all.first(where: { $0.status == "Departed" && $0.arr.airport != nil && $0.reg != nil }) {
            var f = one; f.dep.airport = here
            if let fl = ADBMap.makeFlight(f) {
                fl.notes = "fixture-live"
                var snap = RealSnapshot(f, fetchedAt: Date().addingTimeInterval(-60), nextFetch: Date().addingTimeInterval(6 * 3600))
                snap.modeS = ProcessInfo.processInfo.environment["FLIGHTLY_FIXTURE_MODES"]; snap.status = "EnRoute"
                snap.depRunway = Date().addingTimeInterval(-3600); snap.arrRunway = nil
                snap.depSched = Date().addingTimeInterval(-3900); snap.depRevised = snap.depSched
                snap.arrSched = Date().addingTimeInterval(7200); snap.arrRevised = snap.arrSched
                fl.schedDep = snap.depSched!; fl.schedArr = snap.arrSched!
                snapshots[fl.uuid.uuidString] = snap
                context.insert(fl); try? context.save(); persistADB()
            }
            return
        }
        for status in ["Departed", "Expected", "Canceled"] {
            if let f = all.first(where: { $0.status == status && $0.arr.airport != nil && $0.dep.gate != nil && $0.reg != nil }) { picks.append(f) }
        }
        for var f in picks {
            f.dep.airport = here
            guard let fl = ADBMap.makeFlight(f) else { continue }
            var snap = RealSnapshot(f, fetchedAt: Date().addingTimeInterval(-300), nextFetch: Date().addingTimeInterval(6 * 3600))
            if ["Expected", "Departed"].contains(f.status), let hex = ProcessInfo.processInfo.environment["FLIGHTLY_FIXTURE_MODES"] {
                // Pretend this flight is airborne, flown by the aircraft with this Mode-S address (tests the OpenSky path).
                snap.modeS = hex; snap.status = "EnRoute"; snap.depRunway = Date().addingTimeInterval(-3600); snap.arrRunway = nil
                snap.depSched = Date().addingTimeInterval(-3900); snap.depRevised = snap.depSched; snap.arrSched = Date().addingTimeInterval(7200); snap.arrRevised = snap.arrSched
            }
            snapshots[fl.uuid.uuidString] = snap
            context.insert(fl)
        }
        try? context.save(); persistADB()
    }
}
#endif
