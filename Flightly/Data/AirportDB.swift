import Foundation
import CoreLocation

struct Airport: Identifiable, Hashable {
    var id: String { iata }
    let iata: String, name: String, city: String, country: String
    let lat: Double, lon: Double
    let tz: String
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }
}

struct Airline: Identifiable, Hashable {
    var id: String { code }
    let code: String, name: String
}

enum AirportDB {
    static let all: [Airport] = [
        .init(iata: "ATL", name: "Hartsfield-Jackson Atlanta Intl", city: "Atlanta", country: "United States", lat: 33.6407, lon: -84.4277, tz: "America/New_York"),
        .init(iata: "LAX", name: "Los Angeles Intl", city: "Los Angeles", country: "United States", lat: 33.9416, lon: -118.4085, tz: "America/Los_Angeles"),
        .init(iata: "ORD", name: "O'Hare Intl", city: "Chicago", country: "United States", lat: 41.9742, lon: -87.9073, tz: "America/Chicago"),
        .init(iata: "DFW", name: "Dallas/Fort Worth Intl", city: "Dallas", country: "United States", lat: 32.8998, lon: -97.0403, tz: "America/Chicago"),
        .init(iata: "AUS", name: "Austin-Bergstrom Intl", city: "Austin", country: "United States", lat: 30.1945, lon: -97.6699, tz: "America/Chicago"),
        .init(iata: "IAH", name: "George Bush Intercontinental", city: "Houston", country: "United States", lat: 29.9902, lon: -95.3368, tz: "America/Chicago"),
        .init(iata: "DEN", name: "Denver Intl", city: "Denver", country: "United States", lat: 39.8561, lon: -104.6737, tz: "America/Denver"),
        .init(iata: "JFK", name: "John F. Kennedy Intl", city: "New York", country: "United States", lat: 40.6413, lon: -73.7781, tz: "America/New_York"),
        .init(iata: "EWR", name: "Newark Liberty Intl", city: "Newark", country: "United States", lat: 40.6895, lon: -74.1745, tz: "America/New_York"),
        .init(iata: "LGA", name: "LaGuardia", city: "New York", country: "United States", lat: 40.7769, lon: -73.8740, tz: "America/New_York"),
        .init(iata: "BOS", name: "Logan Intl", city: "Boston", country: "United States", lat: 42.3656, lon: -71.0096, tz: "America/New_York"),
        .init(iata: "MIA", name: "Miami Intl", city: "Miami", country: "United States", lat: 25.7959, lon: -80.2870, tz: "America/New_York"),
        .init(iata: "SFO", name: "San Francisco Intl", city: "San Francisco", country: "United States", lat: 37.6213, lon: -122.3790, tz: "America/Los_Angeles"),
        .init(iata: "SEA", name: "Seattle-Tacoma Intl", city: "Seattle", country: "United States", lat: 47.4502, lon: -122.3088, tz: "America/Los_Angeles"),
        .init(iata: "LAS", name: "Harry Reid Intl", city: "Las Vegas", country: "United States", lat: 36.0840, lon: -115.1537, tz: "America/Los_Angeles"),
        .init(iata: "PHX", name: "Phoenix Sky Harbor Intl", city: "Phoenix", country: "United States", lat: 33.4342, lon: -112.0116, tz: "America/Phoenix"),
        .init(iata: "MCO", name: "Orlando Intl", city: "Orlando", country: "United States", lat: 28.4312, lon: -81.3081, tz: "America/New_York"),
        .init(iata: "IAD", name: "Washington Dulles Intl", city: "Washington", country: "United States", lat: 38.9531, lon: -77.4565, tz: "America/New_York"),
        .init(iata: "DCA", name: "Reagan National", city: "Washington", country: "United States", lat: 38.8512, lon: -77.0402, tz: "America/New_York"),
        .init(iata: "HNL", name: "Daniel K. Inouye Intl", city: "Honolulu", country: "United States", lat: 21.3187, lon: -157.9225, tz: "Pacific/Honolulu"),
        .init(iata: "YYZ", name: "Toronto Pearson Intl", city: "Toronto", country: "Canada", lat: 43.6777, lon: -79.6248, tz: "America/Toronto"),
        .init(iata: "YVR", name: "Vancouver Intl", city: "Vancouver", country: "Canada", lat: 49.1967, lon: -123.1815, tz: "America/Vancouver"),
        .init(iata: "MEX", name: "Benito Juárez Intl", city: "Mexico City", country: "Mexico", lat: 19.4361, lon: -99.0719, tz: "America/Mexico_City"),
        .init(iata: "CUN", name: "Cancún Intl", city: "Cancún", country: "Mexico", lat: 21.0365, lon: -86.8771, tz: "America/Cancun"),
        .init(iata: "GRU", name: "São Paulo–Guarulhos Intl", city: "São Paulo", country: "Brazil", lat: -23.4356, lon: -46.4731, tz: "America/Sao_Paulo"),
        .init(iata: "EZE", name: "Ministro Pistarini Intl", city: "Buenos Aires", country: "Argentina", lat: -34.8222, lon: -58.5358, tz: "America/Argentina/Buenos_Aires"),
        .init(iata: "BOG", name: "El Dorado Intl", city: "Bogotá", country: "Colombia", lat: 4.7016, lon: -74.1469, tz: "America/Bogota"),
        .init(iata: "LHR", name: "Heathrow", city: "London", country: "United Kingdom", lat: 51.4700, lon: -0.4543, tz: "Europe/London"),
        .init(iata: "LGW", name: "Gatwick", city: "London", country: "United Kingdom", lat: 51.1537, lon: -0.1821, tz: "Europe/London"),
        .init(iata: "DUB", name: "Dublin", city: "Dublin", country: "Ireland", lat: 53.4264, lon: -6.2499, tz: "Europe/Dublin"),
        .init(iata: "CDG", name: "Charles de Gaulle", city: "Paris", country: "France", lat: 49.0097, lon: 2.5479, tz: "Europe/Paris"),
        .init(iata: "AMS", name: "Schiphol", city: "Amsterdam", country: "Netherlands", lat: 52.3105, lon: 4.7683, tz: "Europe/Amsterdam"),
        .init(iata: "FRA", name: "Frankfurt am Main", city: "Frankfurt", country: "Germany", lat: 50.0379, lon: 8.5622, tz: "Europe/Berlin"),
        .init(iata: "MUC", name: "Munich", city: "Munich", country: "Germany", lat: 48.3538, lon: 11.7861, tz: "Europe/Berlin"),
        .init(iata: "MAD", name: "Adolfo Suárez Madrid–Barajas", city: "Madrid", country: "Spain", lat: 40.4983, lon: -3.5676, tz: "Europe/Madrid"),
        .init(iata: "BCN", name: "Barcelona–El Prat", city: "Barcelona", country: "Spain", lat: 41.2974, lon: 2.0833, tz: "Europe/Madrid"),
        .init(iata: "FCO", name: "Leonardo da Vinci–Fiumicino", city: "Rome", country: "Italy", lat: 41.8003, lon: 12.2389, tz: "Europe/Rome"),
        .init(iata: "ZRH", name: "Zürich", city: "Zürich", country: "Switzerland", lat: 47.4647, lon: 8.5492, tz: "Europe/Zurich"),
        .init(iata: "IST", name: "Istanbul", city: "Istanbul", country: "Türkiye", lat: 41.2753, lon: 28.7519, tz: "Europe/Istanbul"),
        .init(iata: "KEF", name: "Keflavík Intl", city: "Reykjavík", country: "Iceland", lat: 63.9850, lon: -22.6056, tz: "Atlantic/Reykjavik"),
        .init(iata: "DXB", name: "Dubai Intl", city: "Dubai", country: "United Arab Emirates", lat: 25.2532, lon: 55.3657, tz: "Asia/Dubai"),
        .init(iata: "DOH", name: "Hamad Intl", city: "Doha", country: "Qatar", lat: 25.2731, lon: 51.6081, tz: "Asia/Qatar"),
        .init(iata: "DEL", name: "Indira Gandhi Intl", city: "Delhi", country: "India", lat: 28.5562, lon: 77.1000, tz: "Asia/Kolkata"),
        .init(iata: "BOM", name: "Chhatrapati Shivaji Maharaj Intl", city: "Mumbai", country: "India", lat: 19.0896, lon: 72.8656, tz: "Asia/Kolkata"),
        .init(iata: "CMB", name: "Bandaranaike Intl", city: "Colombo", country: "Sri Lanka", lat: 7.1808, lon: 79.8841, tz: "Asia/Colombo"),
        .init(iata: "BKK", name: "Suvarnabhumi", city: "Bangkok", country: "Thailand", lat: 13.6900, lon: 100.7501, tz: "Asia/Bangkok"),
        .init(iata: "SIN", name: "Changi", city: "Singapore", country: "Singapore", lat: 1.3644, lon: 103.9915, tz: "Asia/Singapore"),
        .init(iata: "HKG", name: "Hong Kong Intl", city: "Hong Kong", country: "Hong Kong", lat: 22.3080, lon: 113.9185, tz: "Asia/Hong_Kong"),
        .init(iata: "PEK", name: "Beijing Capital Intl", city: "Beijing", country: "China", lat: 40.0799, lon: 116.6031, tz: "Asia/Shanghai"),
        .init(iata: "PVG", name: "Shanghai Pudong Intl", city: "Shanghai", country: "China", lat: 31.1443, lon: 121.8083, tz: "Asia/Shanghai"),
        .init(iata: "ICN", name: "Incheon Intl", city: "Seoul", country: "South Korea", lat: 37.4602, lon: 126.4407, tz: "Asia/Seoul"),
        .init(iata: "HND", name: "Tokyo Haneda", city: "Tokyo", country: "Japan", lat: 35.5494, lon: 139.7798, tz: "Asia/Tokyo"),
        .init(iata: "NRT", name: "Narita Intl", city: "Tokyo", country: "Japan", lat: 35.7720, lon: 140.3929, tz: "Asia/Tokyo"),
        .init(iata: "SYD", name: "Sydney Kingsford Smith", city: "Sydney", country: "Australia", lat: -33.9399, lon: 151.1753, tz: "Australia/Sydney"),
        .init(iata: "MEL", name: "Melbourne", city: "Melbourne", country: "Australia", lat: -37.6690, lon: 144.8410, tz: "Australia/Melbourne"),
        .init(iata: "AKL", name: "Auckland", city: "Auckland", country: "New Zealand", lat: -37.0082, lon: 174.7850, tz: "Pacific/Auckland"),
        .init(iata: "JNB", name: "O.R. Tambo Intl", city: "Johannesburg", country: "South Africa", lat: -26.1367, lon: 28.2411, tz: "Africa/Johannesburg"),
        .init(iata: "CAI", name: "Cairo Intl", city: "Cairo", country: "Egypt", lat: 30.1219, lon: 31.4056, tz: "Africa/Cairo"),
        .init(iata: "ADD", name: "Bole Intl", city: "Addis Ababa", country: "Ethiopia", lat: 8.9779, lon: 38.7993, tz: "Africa/Addis_Ababa"),
    ]
    static let airlines: [Airline] = [
        .init(code: "AA", name: "American Airlines"), .init(code: "DL", name: "Delta Air Lines"),
        .init(code: "UA", name: "United Airlines"), .init(code: "WN", name: "Southwest Airlines"),
        .init(code: "B6", name: "JetBlue"), .init(code: "AS", name: "Alaska Airlines"),
        .init(code: "NK", name: "Spirit Airlines"), .init(code: "F9", name: "Frontier Airlines"),
        .init(code: "AC", name: "Air Canada"), .init(code: "BA", name: "British Airways"),
        .init(code: "VS", name: "Virgin Atlantic"), .init(code: "AF", name: "Air France"),
        .init(code: "KL", name: "KLM"), .init(code: "LH", name: "Lufthansa"),
        .init(code: "LX", name: "SWISS"), .init(code: "IB", name: "Iberia"),
        .init(code: "TK", name: "Turkish Airlines"), .init(code: "EK", name: "Emirates"),
        .init(code: "QR", name: "Qatar Airways"), .init(code: "EY", name: "Etihad Airways"),
        .init(code: "SQ", name: "Singapore Airlines"), .init(code: "CX", name: "Cathay Pacific"),
        .init(code: "JL", name: "Japan Airlines"), .init(code: "NH", name: "ANA"),
        .init(code: "KE", name: "Korean Air"), .init(code: "QF", name: "Qantas"),
        .init(code: "NZ", name: "Air New Zealand"), .init(code: "UL", name: "SriLankan Airlines"),
        .init(code: "AI", name: "Air India"), .init(code: "ET", name: "Ethiopian Airlines"),
        .init(code: "FI", name: "Icelandair"), .init(code: "LA", name: "LATAM Airlines"),
    ]
    static let aircraft = ["Boeing 737-800", "Boeing 737 MAX 8", "Airbus A320neo", "Airbus A321", "Boeing 787-9", "Airbus A350-900", "Boeing 777-300ER", "Airbus A330-300", "Embraer E175", "Airbus A220-300"]

    private static let byIata: [String: Airport] = Dictionary(uniqueKeysWithValues: all.map { ($0.iata, $0) })
    private static let byCode: [String: Airline] = Dictionary(uniqueKeysWithValues: airlines.map { ($0.code, $0) })
    static func airport(_ iata: String) -> Airport? { byIata[iata.uppercased()] }
    static func airline(_ code: String) -> Airline? { byCode[code.uppercased()] }
    static func search(_ q: String) -> [Airport] {
        let s = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return all }
        return all.filter { $0.iata.lowercased().hasPrefix(s) || $0.city.lowercased().contains(s) || $0.name.lowercased().contains(s) || $0.country.lowercased().contains(s) }
    }
}

enum Geo {
    static func distanceMiles(_ a: Airport, _ b: Airport) -> Double {
        let r = 3958.8
        let p1 = a.lat * .pi / 180, p2 = b.lat * .pi / 180
        let dp = (b.lat - a.lat) * .pi / 180, dl = (b.lon - a.lon) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
    /// Great-circle interpolation, fraction f in 0...1.
    static func interpolate(_ a: Airport, _ b: Airport, _ f: Double) -> CLLocationCoordinate2D {
        let lat1 = a.lat * .pi / 180, lon1 = a.lon * .pi / 180
        let lat2 = b.lat * .pi / 180, lon2 = b.lon * .pi / 180
        let d = 2 * asin(sqrt(pow(sin((lat2 - lat1) / 2), 2) + cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)))
        if d == 0 { return a.coordinate }
        let A = sin((1 - f) * d) / sin(d), B = sin(f * d) / sin(d)
        let x = A * cos(lat1) * cos(lon1) + B * cos(lat2) * cos(lon2)
        let y = A * cos(lat1) * sin(lon1) + B * cos(lat2) * sin(lon2)
        let z = A * sin(lat1) + B * sin(lat2)
        return .init(latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi, longitude: atan2(y, x) * 180 / .pi)
    }
    static func path(_ a: Airport, _ b: Airport, steps: Int = 64) -> [CLLocationCoordinate2D] {
        (0...steps).map { interpolate(a, b, Double($0) / Double(steps)) }
    }
    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let l1 = a.latitude * .pi / 180, l2 = b.latitude * .pi / 180, dl = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dl) * cos(l2), x = cos(l1) * sin(l2) - sin(l1) * cos(l2) * cos(dl)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
