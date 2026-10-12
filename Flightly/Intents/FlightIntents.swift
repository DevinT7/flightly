import AppIntents

struct NextFlightIntent: AppIntent {
    static var title: LocalizedStringResource = "Next flight status"
    static var description = IntentDescription("Hear the status of your next flight.")
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let f = SnapshotStore.load().first else { return .result(dialog: "You don't have any upcoming flights in Flightly.") }
        let t = f.depTime.formatted(date: .omitted, time: .shortened)
        let delay = f.delayMinutes >= 15 ? "It's delayed \(f.delayMinutes) minutes. " : ""
        return .result(dialog: "\(f.flightCode) from \(f.from) to \(f.to) is \(f.status.lowercased()). \(delay)Departure \(t) from gate \(f.gate).")
    }
}

struct NextGateIntent: AppIntent {
    static var title: LocalizedStringResource = "Next departure gate"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let f = SnapshotStore.load().first else { return .result(dialog: "No upcoming flights found.") }
        return .result(dialog: "Your next departure, \(f.flightCode), leaves from gate \(f.gate).")
    }
}

struct FlightlyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextFlightIntent(), phrases: ["What's my next flight in \(.applicationName)", "Flight status in \(.applicationName)"], shortTitle: "Next flight", systemImageName: "airplane")
        AppShortcut(intent: NextGateIntent(), phrases: ["What's my gate in \(.applicationName)"], shortTitle: "Next gate", systemImageName: "door.left.hand.open")
    }
}
