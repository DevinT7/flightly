import Foundation
import SwiftUI
import SwiftData
import UserNotifications
import ActivityKit
import WidgetKit
import BackgroundTasks

@MainActor
@Observable
final class AppModel {
    static let refreshTaskID = "com.flightly.app.refresh"

    var now = Date()
    private var timer: Timer?
    let provider: FlightDataProvider = SimulatedProvider.shared
    private var activities: [String: Activity<FlightActivityAttributes>] = [:]
    /// Last state pushed to each activity, used to decide when an update deserves an alert.
    private var lastPushed: [String: FlightActivityAttributes.ContentState] = [:]
    var simulatedClockOffset: TimeInterval = 0   // lets you "fast-forward" to watch a flight play out
    /// Set by a flightly://flight?id=… link (Live Activity / widget tap); the Flights tab consumes it.
    var pendingFlightID: UUID?
    var requestedTab: Int?

    @ObservationIgnored @AppStorage("notif_basics") var notifBasics = true
    @ObservationIgnored @AppStorage("notif_beyond") var notifBeyond = true
    @ObservationIgnored @AppStorage("notif_plan") var notifPlan = true
    @ObservationIgnored @AppStorage("notif_arrival") var notifArrival = true
    @ObservationIgnored @AppStorage("fav_airports") var favAirportsRaw = "AUS,LHR"
    @ObservationIgnored @AppStorage("auto_live_activity") var autoLiveActivity = true

    var favoriteAirports: [String] {
        get { favAirportsRaw.split(separator: ",").map(String.init) }
        set { favAirportsRaw = newValue.joined(separator: ",") }
    }

    var clock: Date { now.addingTimeInterval(simulatedClockOffset) }

    func start() {
        // Test aid: `-simOffsetHours 14` on launch fast-forwards the simulated clock.
        let launchOffset = UserDefaults.standard.double(forKey: "simOffsetHours")
        if launchOffset != 0 { simulatedClockOffset = launchOffset * 3600 }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        // Re-adopt activities that survived an app relaunch so we keep updating them instead of starting duplicates.
        for a in Activity<FlightActivityAttributes>.activities { activities[a.attributes.flightID] = a }
    }

    func live(_ f: Flight) -> LiveState { provider.state(for: f, at: clock) }

    // MARK: Deep links

    func handle(url: URL) {
        guard url.scheme == "flightly", url.host == "flight",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
              let uuid = UUID(uuidString: id) else { return }
        requestedTab = 0
        pendingFlightID = uuid
    }

    // MARK: Refresh

    /// Detects changes, writes records, fires alerts, refreshes widgets and Live Activities.
    func refresh(_ flights: [Flight], context: ModelContext) {
        now = Date()
        let mine = flights.filter { $0.ownerName == nil }
        for f in mine where !f.isPast || f.lastPhase.isEmpty {
            let s = live(f)
            let phase = s.phase.rawValue
            if !f.lastPhase.isEmpty, f.lastPhase != phase {
                f.record("Status changed to \(phase)")
                if f.alertsEnabled { alertForPhase(f, s) }
            }
            if abs(f.lastDelay - s.depDelay) >= 10 {
                let d = s.depDelay
                f.record(d > 0 ? "Departure now \(d) min late" : "Departure back on time")
                if f.alertsEnabled && notifBasics {
                    Notifier.post(title: "\(f.code) \(f.dep)→\(f.arr)", body: d > 0 ? "Delayed \(d) minutes. New departure \(s.estDep.formatted(date: .omitted, time: .shortened))." : "Back on schedule.", id: "d\(f.uuid)\(d)")
                }
            }
            f.lastDelay = s.depDelay; f.lastPhase = phase
        }
        try? context.save()
        syncSnapshots(mine)
        manageActivities(mine)
    }

    private func alertForPhase(_ f: Flight, _ s: LiveState) {
        switch s.phase {
        case .boarding where notifBasics: Notifier.post(title: "\(f.code) is boarding", body: "Gate \(s.depGate), Terminal \(f.depTerminal).", id: "b\(f.uuid)")
        case .enRoute where notifBasics: Notifier.post(title: "\(f.code) took off", body: "Estimated arrival \(s.estArr.formatted(date: .omitted, time: .shortened)) at \(f.arr).", id: "t\(f.uuid)")
        case .landed where notifArrival: Notifier.post(title: "\(f.code) landed", body: "Gate \(s.arrGate). Baggage claim \(s.baggage).", id: "l\(f.uuid)")
        case .canceled: Notifier.post(title: "\(f.code) canceled", body: "Open Flightly to see your options.", id: "c\(f.uuid)")
        default: break
        }
    }

    func syncSnapshots(_ mine: [Flight]) {
        let upcoming = mine.filter { !$0.isPast }.sorted { $0.schedDep < $1.schedDep }.prefix(5)
        let snaps = upcoming.map { f -> FlightSnapshot in
            let s = live(f)
            return FlightSnapshot(flightCode: f.code, from: f.dep, to: f.arr, depTime: s.estDep, arrTime: s.estArr, status: s.phase.rawValue, delayMinutes: s.depDelay, gate: s.depGate, progress: s.progress, flightID: f.uuid.uuidString)
        }
        SnapshotStore.save(Array(snaps))
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Live Activities

    func isTracking(_ f: Flight) -> Bool { activities[f.uuid.uuidString] != nil }

    private func livePhase(_ p: FlightPhase) -> LivePhase {
        switch p {
        case .scheduled: .scheduled; case .boarding: .boarding; case .taxiingOut: .taxiing; case .enRoute: .enRoute
        case .landed: .landed; case .arrived: .arrived; case .canceled: .canceled
        }
    }

    private func content(_ f: Flight, _ s: LiveState) -> FlightActivityAttributes.ContentState {
        .init(phase: livePhase(s.phase), delayMinutes: s.depDelay, arrDelayMinutes: s.arrDelay, depGate: s.depGate, arrGate: s.arrGate,
              baggage: s.baggage, depTerminal: f.depTerminal, arrTerminal: f.arrTerminal, progress: s.progress, estDep: s.estDep, estArr: s.estArr, clockOffset: simulatedClockOffset)
    }

    private func activityContent(_ st: FlightActivityAttributes.ContentState) -> ActivityContent<FlightActivityAttributes.ContentState> {
        // Marked stale if nothing refreshes it within 20 min; in-air flights outrank others when several are running.
        ActivityContent(state: st, staleDate: Date().addingTimeInterval(20 * 60), relevanceScore: st.phase == .enRoute ? 100 : (st.phase == .boarding ? 80 : 50))
    }

    /// User toggled the activity from the flight screen.
    func setTracking(_ f: Flight, on: Bool) {
        if on { f.liveOptOut = false; startActivity(f) } else { f.liveOptOut = true; stopActivity(f) }
    }

    func startActivity(_ f: Flight) {
        let key = f.uuid.uuidString
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activities[key] == nil else { return }
        let s = live(f)
        let attrs = FlightActivityAttributes(flightCode: f.spacedCode, from: f.dep, to: f.arr, schedDep: f.schedDep, schedArr: f.schedArr,
                                             confirmation: "#" + String(f.uuid.uuidString.prefix(6)), flightID: key)
        let st = content(f, s)
        if let a = try? Activity.request(attributes: attrs, content: activityContent(st), pushType: nil) {
            activities[key] = a; lastPushed[key] = st
        }
    }

    func stopActivity(_ f: Flight) { end(f.uuid.uuidString, final: nil, after: nil) }

    private func end(_ key: String, final: FlightActivityAttributes.ContentState?, after: Date?) {
        guard let a = activities.removeValue(forKey: key) else { return }
        lastPushed[key] = nil
        let policy: ActivityUIDismissalPolicy = after.map { .after($0) } ?? .immediate
        Task { await a.end(final.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: policy) }
    }

    /// Auto-starts activities 4 h before departure (like Flighty), pushes state changes (with an alert when something
    /// meaningful changed), and ends them shortly after arrival.
    private func manageActivities(_ mine: [Flight]) {
        for f in mine {
            let key = f.uuid.uuidString
            let s = live(f)
            let st = content(f, s)

            if activities[key] == nil {
                let windowStart = f.schedDep.addingTimeInterval(-4 * 3600)
                let active = clock >= windowStart && s.phase != .arrived && clock < s.estArr.addingTimeInterval(10 * 60)
                if autoLiveActivity && !f.liveOptOut && active { startActivity(f) }
                continue
            }
            guard let a = activities[key] else { continue }

            if s.phase == .arrived {
                end(key, final: st, after: Date().addingTimeInterval(15 * 60)); continue
            }
            let prev = lastPushed[key]
            guard prev != st else { continue }
            lastPushed[key] = st
            let alert = alertText(f, prev: prev, now: st)
            Task {
                if let alert, f.alertsEnabled {
                    await a.update(activityContent(st), alertConfiguration: AlertConfiguration(title: LocalizedStringResource(stringLiteral: alert.0), body: LocalizedStringResource(stringLiteral: alert.1), sound: .default))
                } else { await a.update(activityContent(st)) }
            }
        }
    }

    /// Changes worth waking the screen / expanding the Dynamic Island for.
    private func alertText(_ f: Flight, prev: FlightActivityAttributes.ContentState?, now st: FlightActivityAttributes.ContentState) -> (String, String)? {
        guard let prev else { return nil }
        if prev.phase != st.phase {
            switch st.phase {
            case .boarding: return ("\(f.code) is boarding", "Gate \(st.depGate), Terminal \(st.depTerminal)")
            case .enRoute: return ("\(f.code) took off", "Landing at \(f.arr) \(st.estArr.formatted(date: .omitted, time: .shortened))")
            case .landed: return ("\(f.code) landed", "Gate \(st.arrGate) · Baggage claim \(st.baggage)")
            case .canceled: return ("\(f.code) canceled", "Open Flightly for options")
            default: return nil
            }
        }
        if prev.depGate != st.depGate && st.phase == .scheduled || prev.depGate != st.depGate && st.phase == .boarding { return ("Gate changed", "\(f.code) now departs from gate \(st.depGate)") }
        if prev.arrGate != st.arrGate && st.phase == .enRoute { return ("Arrival gate changed", "\(f.code) now arrives at gate \(st.arrGate)") }
        if abs(prev.delayMinutes - st.delayMinutes) >= 10 {
            return st.delayMinutes >= 15 ? ("\(f.code) delayed", "Now \(st.delayMinutes) min late · departs \(st.estDep.formatted(date: .omitted, time: .shortened))") : ("\(f.code) back on time", "Departure \(st.estDep.formatted(date: .omitted, time: .shortened))")
        }
        return nil
    }

    // MARK: Reminders

    func scheduleReminders(for f: Flight) {
        guard f.alertsEnabled, f.schedDep > Date() else { return }
        let c = UNUserNotificationCenter.current()
        func add(_ id: String, _ title: String, _ body: String, _ when: Date) {
            guard when > Date() else { return }
            let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
            c.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
        if notifPlan { add("ci\(f.uuid)", "Check in for \(f.code)", "Check-in is open. \(f.dep) → \(f.arr) departs \(f.schedDep.formatted(date: .omitted, time: .shortened)).", f.schedDep.addingTimeInterval(-24 * 3600)) }
        if notifBasics {
            add("mo\(f.uuid)", "Time to leave for \(f.dep)?", "\(f.code) departs in 3 hours. Check traffic and security times.", f.schedDep.addingTimeInterval(-3 * 3600))
        }
    }

    // MARK: Background refresh (best effort: iOS decides when to run it)

    func scheduleBackgroundRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        req.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    func backgroundRefresh(container: ModelContainer) {
        let ctx = container.mainContext
        let flights = (try? ctx.fetch(FetchDescriptor<Flight>(sortBy: [SortDescriptor(\.schedDep)]))) ?? []
        refresh(flights, context: ctx)
        scheduleBackgroundRefresh()
    }
}

enum Notifier {
    static func requestAuth() { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in } }
    static func post(title: String, body: String, id: String) {
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
}
