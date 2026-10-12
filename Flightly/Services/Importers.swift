import Foundation
import EventKit
import SwiftData

/// Turns free text (confirmation emails, calendar events, ICS entries) into flights.
enum TextFlightParser {
    static func parse(_ text: String, fallbackDate: Date = Date(), source: FlightSource) -> [Flight] {
        var out: [Flight] = []
        // Split into blocks so a multi-leg itinerary yields multiple flights.
        let blocks = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for block in (blocks.isEmpty ? [text] : blocks) {
            if let f = parseBlock(block, fallbackDate: fallbackDate, source: source) { out.append(f) }
        }
        return out
    }

    private static let codeRegex = try! NSRegularExpression(pattern: #"\b([A-Z][A-Z0-9]|[A-Z0-9][A-Z])\s?-?(\d{1,4})\b"#)
    private static let parenRegex = try! NSRegularExpression(pattern: #"\(([A-Z]{3})\)"#)
    private static let pairRegex = try! NSRegularExpression(pattern: #"\b([A-Z]{3})\s*(?:to|→|->|–|-|—)\s*([A-Z]{3})\b"#)

    static func parseBlock(_ block: String, fallbackDate: Date, source: FlightSource) -> Flight? {
        let ns = block as NSString
        let full = NSRange(location: 0, length: ns.length)
        var airline: String?, number: String?
        for m in codeRegex.matches(in: block, range: full) {
            let c = ns.substring(with: m.range(at: 1))
            if AirportDB.airline(c) != nil { airline = c; number = ns.substring(with: m.range(at: 2)); break }
        }
        guard let al = airline, let num = number else { return nil }

        var dep: String?, arr: String?
        if let m = pairRegex.firstMatch(in: block, range: full) {
            let a = ns.substring(with: m.range(at: 1)), b = ns.substring(with: m.range(at: 2))
            if AirportDB.airport(a) != nil, AirportDB.airport(b) != nil { dep = a; arr = b }
        }
        if dep == nil {
            let codes = parenRegex.matches(in: block, range: full).map { ns.substring(with: $0.range(at: 1)) }.filter { AirportDB.airport($0) != nil }
            if codes.count >= 2 { dep = codes[0]; arr = codes[1] }
        }
        var date = fallbackDate
        if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let m = det.firstMatch(in: block, range: full), let d = m.date { date = d }

        if let d = dep, let a = arr, let da = AirportDB.airport(d), let aa = AirportDB.airport(a) {
            var cal = Calendar.current; cal.timeZone = da.timeZone
            var dt = date
            if cal.component(.hour, from: date) == 0 && cal.component(.minute, from: date) == 0 {
                dt = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
            }
            let hours = Geo.distanceMiles(da, aa) / 480 + 0.6
            return Flight(airlineCode: al, number: num, dep: d, arr: a, schedDep: dt, schedArr: dt.addingTimeInterval(hours * 3600), source: source)
        }
        // Only a flight number: let the data provider fill the route.
        if let f = SimulatedProvider.shared.lookup(airlineCode: al, number: num, date: date) {
            f.sourceRaw = source.rawValue
            return f
        }
        return nil
    }
}

enum CSVImporter {
    struct Result { var flights: [Flight]; var skipped: Int; var formatName: String }

    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", inQuotes = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" { if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false } }
                else { field.append(c) }
            } else if c == "\"" { inQuotes = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\n" { row.append(field); field = ""; if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }; row = [] }
            else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func airportCode(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: #"\(([A-Z]{3})(?:/[A-Z]{4})?\)"#, options: .regularExpression) {
            let inner = t[r].dropFirst().prefix(3); return String(inner)
        }
        if t.count == 3, t == t.uppercased() { return t }
        return nil
    }

    static func importFile(_ text: String) -> Result {
        let rows = parseCSV(text)
        guard let header = rows.first else { return Result(flights: [], skipped: 0, formatName: "Empty file") }
        let h = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_") }
        func col(_ names: [String]) -> Int? { names.compactMap { h.firstIndex(of: $0) }.first }
        let cDate = col(["date"]), cFrom = col(["from", "origin", "departure"]), cTo = col(["to", "destination", "arrival"])
        let cNum = col(["flight_number", "flight", "flight_no"]), cAirline = col(["airline"])
        let cDep = col(["dep_time", "departure_time"]), cArr = col(["arr_time", "arrival_time"])
        let cSeat = col(["seat", "seat_number"]), cReg = col(["registration", "tail", "tail_number"])
        let cPlane = col(["plane", "aircraft"]), cNote = col(["note", "notes"]), cReason = col(["reason", "flight_reason"])
        let format = h.contains("from_oid") ? "OpenFlights" : (h.contains("dep_id") ? "myFlightRadar24" : "Flightly / generic CSV")
        var flights: [Flight] = [], skipped = 0
        let dfs = ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "MM/dd/yyyy", "dd/MM/yyyy"].map { fmt -> DateFormatter in
            let f = DateFormatter(); f.dateFormat = fmt; f.locale = Locale(identifier: "en_US_POSIX"); return f }
        for r in rows.dropFirst() {
            func v(_ i: Int?) -> String { guard let i, i < r.count else { return "" }; return r[i].trimmingCharacters(in: .whitespaces) }
            guard let dep = airportCode(v(cFrom)), let arr = airportCode(v(cTo)),
                  let da = AirportDB.airport(dep), let aa = AirportDB.airport(arr),
                  let dateStr = Optional(v(cDate)), !dateStr.isEmpty else { skipped += 1; continue }
            var date: Date?
            for f in dfs { f.timeZone = da.timeZone; if let d = f.date(from: dateStr) { date = d; break } }
            guard var depDate = date else { skipped += 1; continue }
            var cal = Calendar.current; cal.timeZone = da.timeZone
            if cal.component(.hour, from: depDate) == 0, let t = timeOfDay(v(cDep)) {
                depDate = cal.date(bySettingHour: t.0, minute: t.1, second: 0, of: depDate) ?? depDate
            } else if cal.component(.hour, from: depDate) == 0 {
                depDate = cal.date(bySettingHour: 12, minute: 0, second: 0, of: depDate) ?? depDate
            }
            var arrDate = depDate.addingTimeInterval((Geo.distanceMiles(da, aa) / 480 + 0.6) * 3600)
            if let t = timeOfDay(v(cArr)) {
                var ac = Calendar.current; ac.timeZone = aa.timeZone
                if let candidate = ac.date(bySettingHour: t.0, minute: t.1, second: 0, of: depDate), candidate > depDate.addingTimeInterval(1800) { arrDate = candidate }
            }
            var code = v(cNum).uppercased().replacingOccurrences(of: " ", with: "")
            var airlineCode = ""
            if let m = code.range(of: #"^[A-Z0-9]{2}(?=\d)"#, options: .regularExpression), AirportDB.airline(String(code[m])) != nil {
                airlineCode = String(code[m]); code = String(code[m.upperBound...])
            } else if let a = AirportDB.airlines.first(where: { $0.name.lowercased() == v(cAirline).lowercased() }) { airlineCode = a.code }
            else if let m = v(cAirline).range(of: #"\(([A-Z0-9]{2})\)"#, options: .regularExpression) { airlineCode = String(v(cAirline)[m].dropFirst().prefix(2)) }
            let f = Flight(airlineCode: airlineCode.isEmpty ? "XX" : airlineCode, number: code.isEmpty ? "0" : code, dep: dep, arr: arr,
                           schedDep: depDate, schedArr: arrDate, source: .csv)
            if !v(cSeat).isEmpty { f.seat = v(cSeat) }
            if !v(cReg).isEmpty { f.tail = v(cReg) }
            if !v(cPlane).isEmpty { f.aircraft = v(cPlane) }
            if !v(cNote).isEmpty { f.notes = v(cNote) }
            if let tr = TravelReason.allCases.first(where: { $0.rawValue.lowercased() == v(cReason).lowercased() }) { f.reason = tr }
            else if v(cReason).lowercased().hasPrefix("b") { f.reason = .business }
            flights.append(f)
        }
        return Result(flights: flights, skipped: skipped, formatName: format)
    }

    private static func timeOfDay(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: ":").compactMap { Int($0.filter(\.isNumber)) }
        guard parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    static func export(_ flights: [Flight]) -> String {
        var out = "Date,Flight_Number,Airline,From,To,Dep_Time,Arr_Time,Distance,Seat,Registration,Plane,Reason,Note\n"
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        for f in flights.sorted(by: { $0.schedDep < $1.schedDep }) {
            let d = DateFormatter(); d.dateFormat = "yyyy-MM-dd"; d.timeZone = f.depAirport?.timeZone ?? .current
            let t = DateFormatter(); t.dateFormat = "HH:mm"; t.timeZone = f.depAirport?.timeZone ?? .current
            let t2 = DateFormatter(); t2.dateFormat = "HH:mm"; t2.timeZone = f.arrAirport?.timeZone ?? .current
            out += [d.string(from: f.schedDep), f.code, f.airlineName, f.dep, f.arr, t.string(from: f.schedDep), t2.string(from: f.schedArr),
                    String(Int(f.distanceMiles)), f.seat, f.tail, f.aircraft, f.reason.rawValue, f.notes].map(q).joined(separator: ",") + "\n"
        }
        return out
    }
}

enum ICSImporter {
    /// Parses an iCalendar feed (e.g. a TripIt calendar feed URL) into flights.
    static func flights(fromICS ics: String) -> [Flight] {
        let unfolded = ics.replacingOccurrences(of: "\r\n ", with: "").replacingOccurrences(of: "\n ", with: "")
        var out: [Flight] = []
        for chunk in unfolded.components(separatedBy: "BEGIN:VEVENT").dropFirst() {
            func prop(_ name: String) -> String? {
                for line in chunk.components(separatedBy: .newlines) where line.hasPrefix(name) {
                    if let idx = line.firstIndex(of: ":") { return String(line[line.index(after: idx)...]) }
                }
                return nil
            }
            let text = [prop("SUMMARY"), prop("DESCRIPTION")?.replacingOccurrences(of: "\\n", with: "\n"), prop("LOCATION")].compactMap { $0 }.joined(separator: "\n")
            var date = Date()
            if let s = prop("DTSTART") {
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = s.hasSuffix("Z") ? "yyyyMMdd'T'HHmmss'Z'" : (s.contains("T") ? "yyyyMMdd'T'HHmmss" : "yyyyMMdd")
                if s.hasSuffix("Z") { f.timeZone = TimeZone(identifier: "UTC") }
                if let d = f.date(from: s) { date = d }
            }
            if let fl = TextFlightParser.parseBlock(text, fallbackDate: date, source: .tripit) { out.append(fl) }
        }
        return out
    }
}

@MainActor
enum CalendarSync {
    static func scan(daysBack: Int = 365, daysForward: Int = 365) async throws -> [Flight] {
        let store = EKEventStore()
        let granted: Bool
        if #available(iOS 17.0, *) { granted = try await store.requestFullAccessToEvents() }
        else { granted = try await store.requestAccess(to: .event) }
        guard granted else { throw NSError(domain: "Flightly", code: 1, userInfo: [NSLocalizedDescriptionKey: "Calendar access was not granted."]) }
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: daysForward, to: Date())!
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        var out: [Flight] = []
        for e in events {
            let text = [e.title, e.location, e.notes].compactMap { $0 }.joined(separator: "\n")
            if let f = TextFlightParser.parseBlock(text, fallbackDate: e.startDate, source: .calendar) {
                if let s = e.startDate, abs(s.timeIntervalSince(f.schedDep)) > 86400 { continue }
                out.append(f)
            }
        }
        return out
    }
}
