import Foundation
import SwiftData

enum TravelReason: String, CaseIterable, Codable, Identifiable {
    case leisure = "Leisure", business = "Business", crew = "Crew", other = "Other"
    var id: String { rawValue }
}

enum FlightSource: String, Codable {
    case manual, search, csv, calendar, email, tripit, friend
}

struct ChangeRecord: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var text: String
}

@Model
final class Flight {
    var uuid: UUID = UUID()
    var airlineCode: String = ""
    var number: String = ""
    var dep: String = ""
    var arr: String = ""
    var schedDep: Date = Date()
    var schedArr: Date = Date()
    var tail: String = ""
    var aircraft: String = ""
    var depTerminal: String = ""
    var depGate: String = ""
    var arrTerminal: String = ""
    var arrGate: String = ""
    var baggage: String = ""
    var seat: String = ""
    var notes: String = ""
    var reasonRaw: String = TravelReason.leisure.rawValue
    var sourceRaw: String = FlightSource.manual.rawValue
    var ownerName: String? = nil          // nil = my flight, otherwise a friend's
    var alertsEnabled: Bool = true
    var changesData: Data? = nil
    var lastDelay: Int = 0
    var lastPhase: String = ""
    var isReal: Bool = false              // schedule/gates/status come from a live data provider
    var liveOptOut: Bool = false          // user turned the Live Activity off for this flight
    var createdAt: Date = Date()

    init(airlineCode: String, number: String, dep: String, arr: String, schedDep: Date, schedArr: Date,
         source: FlightSource = .manual, ownerName: String? = nil) {
        self.airlineCode = airlineCode.uppercased(); self.number = number
        self.dep = dep.uppercased(); self.arr = arr.uppercased()
        self.schedDep = schedDep; self.schedArr = schedArr
        self.sourceRaw = source.rawValue; self.ownerName = ownerName
        let seed = Seed(key: "\(airlineCode)\(number)\(dep)\(arr)")
        var r = seed.rng
        self.aircraft = AirportDB.aircraft[r.int(AirportDB.aircraft.count)]
        self.tail = "N\(100 + r.int(899))\(["AA","DL","UA","WN","JB"][r.int(5)])"
        self.depTerminal = ["A","B","C","D","1","2","3"][r.int(7)]
        self.arrTerminal = ["A","B","C","D","1","2","3"][r.int(7)]
        self.depGate = "\(["A","B","C","D"][r.int(4)])\(1 + r.int(40))"
        self.arrGate = "\(["A","B","C","D"][r.int(4)])\(1 + r.int(40))"
        self.baggage = "\(1 + r.int(12))"
    }

    var code: String { airlineCode + number }
    var airlineName: String { AirportDB.airline(airlineCode)?.name ?? airlineCode }
    var depAirport: Airport? { AirportDB.airport(dep) }
    var arrAirport: Airport? { AirportDB.airport(arr) }
    var reason: TravelReason { get { TravelReason(rawValue: reasonRaw) ?? .leisure } set { reasonRaw = newValue.rawValue } }
    var source: FlightSource { FlightSource(rawValue: sourceRaw) ?? .manual }
    var distanceMiles: Double {
        guard let a = depAirport, let b = arrAirport else { return 0 }
        return Geo.distanceMiles(a, b)
    }
    var durationHours: Double { schedArr.timeIntervalSince(schedDep) / 3600 }
    var isPast: Bool { schedArr < Date().addingTimeInterval(-3600 * 2) }
    var changes: [ChangeRecord] {
        get { (try? JSONDecoder().decode([ChangeRecord].self, from: changesData ?? Data())) ?? [] }
        set { changesData = try? JSONEncoder().encode(newValue) }
    }
    func record(_ text: String, at date: Date = Date()) {
        var c = changes; c.append(.init(date: date, text: text)); changes = c
    }
    var snapshotDelayedMinutes: Int { lastDelay }
}

// MARK: - Deterministic randomness (stable across launches, unlike hashValue)

struct Seed {
    let value: UInt64
    init(key: String) {
        var h: UInt64 = 0xcbf29ce484222325
        for b in key.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        value = h
    }
    var rng: SeededRNG { SeededRNG(state: value) }
}

struct SeededRNG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &+ 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
    mutating func double() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * double() }
}
