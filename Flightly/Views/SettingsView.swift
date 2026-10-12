import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var flights: [Flight]
    @AppStorage("my_name") private var myName = "Me"
    @State private var showImport = false
    @State private var confirmWipe = false
    @State private var iconError: String?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section { HStack { Image(systemName: "star.circle.fill").foregroundStyle(Theme.accent).font(.title)
                    VStack(alignment: .leading) { Text("Pro is on").fontWeight(.semibold); Text("Every Flighty Pro feature is unlocked. No subscription.").font(.caption).foregroundStyle(.secondary) } } }
                Section("Profile") { TextField("Your name (shown to friends)", text: $myName) }
                Section("Push alerts") {
                    Toggle("Basics: delays, gate, boarding, takeoff", isOn: $model.notifBasics)
                    Toggle("Above & Beyond: inbound aircraft", isOn: $model.notifBeyond)
                    Toggle("Flight Plan: route and check-in", isOn: $model.notifPlan)
                    Toggle("Arrival: landing, gate, baggage", isOn: $model.notifArrival)
                    Toggle("Start Live Activities automatically (4 h before departure)", isOn: $model.autoLiveActivity)
                }
                Section("Import & export") { Button("Import flights / Export log") { showImport = true } }
                Section("App icon") {
                    ForEach([("Default", nil as String?), ("Night", "AppIconNight"), ("Sunrise", "AppIconSunrise")], id: \.0) { name, key in
                        Button(name) { UIApplication.shared.setAlternateIconName(key) { e in iconError = e?.localizedDescription } }
                    }
                    if let iconError { Text(iconError).font(.caption).foregroundStyle(Theme.bad) }
                }
                Section("Experiment") {
                    VStack(alignment: .leading) {
                        Text("Time machine: \(offsetLabel)").font(.subheadline)
                        Slider(value: $model.simulatedClockOffset, in: -86400...86400 * 2, step: 900)
                        Text("Shifts the clock the simulator uses so you can watch a flight go from scheduled to boarding, airborne and landed.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Reset time") { model.simulatedClockOffset = 0 }
                    Button("Load sample flights") { DemoData.load(into: context) }
                    Button("Delete all flights", role: .destructive) { confirmWipe = true }
                }
                Section("About") {
                    Text("Flightly is an independent, open experiment inspired by Flighty. Live data in this build is simulated by a built-in engine (see LiveEngine.swift); swap in a real provider via the FlightDataProvider protocol.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showImport) { ImportView() }
            .confirmationDialog("Delete every flight, including friends' flights?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { flights.forEach { context.delete($0) }; try? context.save() }
            }
        }
    }
    private var offsetLabel: String {
        let h = model.simulatedClockOffset / 3600
        return h == 0 ? "now" : String(format: "%@%.1f h", h > 0 ? "+" : "", h)
    }
}
