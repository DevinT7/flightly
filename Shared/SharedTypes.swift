import Foundation
import ActivityKit

let appGroupID = "group.com.flightly.app"

/// Compact flight snapshot shared between the app, widgets and Live Activities.
struct FlightSnapshot: Codable, Hashable {
    var flightCode: String
    var from: String
    var to: String
    var depTime: Date
    var arrTime: Date
    var status: String
    var delayMinutes: Int
    var gate: String
    var progress: Double
    var flightID: String = ""
}

enum SnapshotStore {
    private static let key = "nextFlights"
    static func save(_ items: [FlightSnapshot]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults(suiteName: appGroupID)?.set(data, forKey: key)
    }
    static func load() -> [FlightSnapshot] {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: key),
              let items = try? JSONDecoder().decode([FlightSnapshot].self, from: data) else { return [] }
        return items
    }
}

/// Phases a flight moves through; drives what the Live Activity / Dynamic Island shows.
enum LivePhase: String, Codable, Hashable {
    case scheduled, boarding, taxiing, enRoute, landed, arrived, canceled
}

struct FlightActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: LivePhase
        var delayMinutes: Int
        var arrDelayMinutes: Int
        var depGate: String
        var arrGate: String
        var baggage: String
        var depTerminal: String
        var arrTerminal: String
        var progress: Double
        var estDep: Date
        var estArr: Date
        /// Seconds the app's simulated clock runs ahead of the real clock (0 in normal use). System countdown timers
        /// run on the real clock, so the widget subtracts this to keep them correct under the Time Machine.
        var clockOffset: TimeInterval = 0
    }
    var flightCode: String
    var from: String
    var to: String
    var schedDep: Date
    var schedArr: Date
    var confirmation: String
    var flightID: String

    var deepLink: URL { URL(string: "flightly://flight?id=\(flightID)")! }
}
