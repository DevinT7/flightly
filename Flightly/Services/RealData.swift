import Foundation

/// Free, keyless public data sources. Everything here degrades gracefully: on any failure the app keeps using the
/// built-in simulator and marks the data as simulated.
///  - Weather: NOAA Aviation Weather Center METARs (aviationweather.gov)
///  - Airport delays / ground stops: FAA National Airspace System status (nasstatus.faa.gov, US airports only)
///  - Aircraft photos by registration: Planespotters.net public photo API

// MARK: - Airport ICAO codes (needed by the METAR API)

extension Airport {
    private static let icaoOverrides: [String: String] = [
        "HNL": "PHNL", "YYZ": "CYYZ", "YVR": "CYVR", "MEX": "MMMX", "CUN": "MMUN", "GRU": "SBGR", "EZE": "SAEZ", "BOG": "SKBO",
        "LHR": "EGLL", "LGW": "EGKK", "DUB": "EIDW", "CDG": "LFPG", "AMS": "EHAM", "FRA": "EDDF", "MUC": "EDDM", "MAD": "LEMD",
        "BCN": "LEBL", "FCO": "LIRF", "ZRH": "LSZH", "IST": "LTFM", "KEF": "BIKF", "DXB": "OMDB", "DOH": "OTHH", "DEL": "VIDP",
        "BOM": "VABB", "CMB": "VCBI", "BKK": "VTBS", "SIN": "WSSS", "HKG": "VHHH", "PEK": "ZBAA", "PVG": "ZSPD", "ICN": "RKSI",
        "HND": "RJTT", "NRT": "RJAA", "SYD": "YSSY", "MEL": "YMML", "AKL": "NZAA", "JNB": "FAOR", "CAI": "HECA", "ADD": "HAAB",
    ]
    var icao: String { icaoCode ?? Self.icaoOverrides[iata] ?? "K" + iata }
}

// MARK: - METAR weather

struct MetarService {
    static func fetch(icaos: [String]) async -> [String: WeatherInfo] {
        guard !icaos.isEmpty,
              let url = URL(string: "https://aviationweather.gov/api/data/metar?ids=\(icaos.joined(separator: ","))&format=json") else { return [:] }
        var req = URLRequest(url: url); req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var out: [String: WeatherInfo] = [:]
        for m in arr {
            guard let icao = m["icaoId"] as? String else { continue }
            out[icao] = parse(m)
        }
        return out
    }

    private static func parse(_ m: [String: Any]) -> WeatherInfo {
        let temp = (m["temp"] as? Double) ?? Double(m["temp"] as? Int ?? 15)
        let wind = (m["wspd"] as? Int) ?? Int(m["wspd"] as? Double ?? 0)
        let visRaw = m["visib"]
        let vis: Int = {
            if let s = visRaw as? String { return Int(Double(s.replacingOccurrences(of: "+", with: "")) ?? 10) }
            if let d = visRaw as? Double { return Int(d) }
            return 10
        }()
        let wx = (m["wxString"] as? String ?? "").uppercased()
        let cover = (m["cover"] as? String ?? "").uppercased()
        let (cond, sym): (String, String) = {
            if wx.contains("TS") { return ("Thunderstorms", "cloud.bolt.rain.fill") }
            if wx.contains("SN") || wx.contains("SG") { return ("Snow", "snowflake") }
            if wx.contains("FG") || (wx.contains("BR") && vis < 3) { return ("Fog", "cloud.fog.fill") }
            if wx.contains("RA") || wx.contains("DZ") { return ("Rain", "cloud.rain.fill") }
            switch cover {
            case "CLR", "SKC", "CAVOK": return ("Clear", "sun.max.fill")
            case "FEW": return ("Mostly clear", "sun.max.fill")
            case "SCT": return ("Partly cloudy", "cloud.sun.fill")
            case "BKN": return ("Mostly cloudy", "cloud.fill")
            case "OVC", "OVX", "VV": return ("Overcast", "cloud.fill")
            default: return cover.isEmpty ? ("Clear", "sun.max.fill") : ("Overcast", "cloud.fill")
            }
        }()
        let raw = (m["rawOb"] as? String) ?? ""
        return WeatherInfo(condition: cond, symbol: sym, tempC: Int(temp.rounded()), windKts: wind, visibilityMi: vis, metar: raw)
    }
}

// MARK: - FAA airport status

struct FAAStatus: Hashable {
    enum Kind: String { case closure = "Airport closed", groundStop = "Ground stop", groundDelay = "Ground delay program", delay = "Delays" }
    let iata: String
    let kind: Kind
    let reason: String
    let averageMinutes: Int?
    let detail: String          // human text, e.g. "Avg 56 min · max 1h 44m"

    var severity: Int {
        switch kind {
        case .closure, .groundStop: 3
        case .groundDelay: (averageMinutes ?? 0) >= 60 ? 3 : 2
        case .delay: (averageMinutes ?? 0) >= 45 ? 3 : 2
        }
    }
}

final class FAAParser: NSObject, XMLParserDelegate {
    private var stack: [String] = []
    private var text = ""
    private var fields: [String: String] = [:]
    private var list = ""
    private var delayKind: FAAStatus.Kind = .delay
    private(set) var results: [String: FAAStatus] = [:]

    func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        stack.append(name); text = ""
        if name.hasSuffix("_List") {
            list = name
            delayKind = name.contains("Ground_Stop") ? .groundStop : name.contains("Ground_Delay") ? .groundDelay : name.contains("Closure") ? .closure : .delay
        }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
    func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        stack.removeLast()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if stack.last?.hasSuffix("_List") == true {
            finishRecord(); return
        }
        if !value.isEmpty, stack.count >= 2, !name.hasSuffix("_List") { fields[name] = value }
    }

    private func minutes(_ s: String?) -> Int? {
        guard let s = s?.lowercased() else { return nil }
        var total = 0
        let parts = s.replacingOccurrences(of: "and", with: " ").split(separator: " ")
        var i = 0
        while i < parts.count - 1 {
            if let n = Int(parts[i]) {
                let unit = parts[i + 1]
                if unit.hasPrefix("hour") { total += n * 60 } else if unit.hasPrefix("min") { total += n }
                i += 2
            } else { i += 1 }
        }
        return total > 0 ? total : nil
    }

    private func finishRecord() {
        defer { fields = [:] }
        guard let arpt = fields["ARPT"] else { return }
        let reason = (fields["Reason"] ?? "unspecified").replacingOccurrences(of: "WX:", with: "weather: ").replacingOccurrences(of: "VOL:", with: "volume: ").lowercased()
        let avg = minutes(fields["Avg"] ?? fields["Min"])
        var detail = ""
        switch delayKind {
        case .groundStop: detail = fields["End_Time"].map { "Expected to end \($0)" } ?? "Ground stop in effect"
        case .groundDelay: detail = [avg.map { "Average \(Self.fmt($0))" }, minutes(fields["Max"]).map { "up to \(Self.fmt($0))" }].compactMap { $0 }.joined(separator: " · ")
        case .delay: detail = [avg.map { "\(Self.fmt($0))" }, fields["Trend"]].compactMap { $0 }.joined(separator: " · ")
        case .closure: detail = fields["Reopen"].map { "Reopens \($0)" } ?? "Closed"
        }
        // "Closures" in this feed are NOTAMs and are mostly partial (e.g. closed to non-scheduled general aviation).
        // Only surface ones that read as a full closure so we never claim an airport is shut when airlines still operate.
        if delayKind == .closure {
            let r = (fields["Reason"] ?? "").lowercased()
            if r.contains("clsd to") || r.contains(" exc ") || r.contains("wingspan") || r.contains("ga acft") || r.contains("non sked") { return }
        }
        let new = FAAStatus(iata: arpt, kind: delayKind, reason: reason, averageMinutes: avg, detail: detail)
        if let old = results[arpt], old.severity >= new.severity { return }
        results[arpt] = new
    }
    private static func fmt(_ m: Int) -> String { m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) min" }
}

enum FAAService {
    struct Outcome { var statuses: [String: FAAStatus]?; var error: String? }
    static func fetch() async -> Outcome {
        guard let url = URL(string: "https://nasstatus.faa.gov/api/airport-status-information") else { return .init(statuses: nil, error: "bad URL") }
        var req = URLRequest(url: url); req.timeoutInterval = 25
        req.setValue("application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard code == 200 else { return .init(statuses: nil, error: "HTTP \(code)") }
            let parser = FAAParser()
            let xml = XMLParser(data: data); xml.delegate = parser
            if xml.parse() { return .init(statuses: parser.results, error: nil) }
            return .init(statuses: nil, error: "XML parse failed: \(xml.parserError?.localizedDescription ?? "unknown")")
        } catch { return .init(statuses: nil, error: error.localizedDescription) }
    }
}

// MARK: - Planespotters photo by registration

struct TailPhoto { let url: URL; let photographer: String; let page: URL? }

actor TailPhotoCache {
    static let shared = TailPhotoCache()
    private var cache: [String: TailPhoto?] = [:]

    func photo(forRegistration reg: String) async -> TailPhoto? {
        let key = reg.uppercased().trimmingCharacters(in: .whitespaces)
        guard key.count >= 4, key.count <= 8, !key.contains("/") else { return nil }
        if let hit = cache[key] { return hit }
        var result: TailPhoto?
        if let url = URL(string: "https://api.planespotters.net/pub/photos/reg/\(key)") {
            var req = URLRequest(url: url)
            // Planespotters requires a contact URL in the User-Agent. Replace with your own project URL.
            req.setValue("FlightlyApp/1.0 (+https://github.com/DevinT7/flightly)", forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let p = (json["photos"] as? [[String: Any]])?.first,
               let src = ((p["thumbnail_large"] as? [String: Any])?["src"] as? String).flatMap(URL.init(string:)) {
                result = TailPhoto(url: src, photographer: (p["photographer"] as? String) ?? "Planespotters.net", page: (p["link"] as? String).flatMap(URL.init(string:)))
            }
        }
        cache[key] = result
        return result
    }
}
