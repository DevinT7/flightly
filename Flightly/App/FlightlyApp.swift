import SwiftUI
import SwiftData

@main
struct FlightlyApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    let container: ModelContainer = {
        do { return try ModelContainer(for: Flight.self) }
        catch { fatalError("SwiftData container failed: \(error)") }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                .onAppear { model.start(); Notifier.requestAuth() }
                .onOpenURL { url in
                    if url.host == "flight" { model.handle(url: url) } else { FriendLink.handle(url, context: container.mainContext) }
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.scheduleBackgroundRefresh() } }
        .backgroundTask(.appRefresh(AppModel.refreshTaskID)) { await model.backgroundRefresh(container: container) }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Flight.schedDep) private var flights: [Flight]
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            Tab("My Flights", systemImage: "airplane", value: 0) { FlightsView() }
            Tab("Friends", systemImage: "person.2.fill", value: 1) { FriendsView() }
            Tab("Passport", systemImage: "person.text.rectangle.fill", value: 2) { PassportView() }
            Tab("Search", systemImage: "magnifyingglass", value: 3, role: .search) {
                NavigationStack { AddFlightView(embedded: true) { tab = 0 } }
            }
        }
        .task(id: model.now) { model.refresh(flights, context: context) }
        .onChange(of: model.requestedTab) { _, t in if let t { tab = t; model.requestedTab = nil } }
        .task(id: flights.count) { for f in flights where f.ownerName == nil { model.scheduleReminders(for: f) } }
    }
}
