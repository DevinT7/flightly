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
    @State private var keyDraft = ""

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
                Section {
                    sourceRow("Weather (METAR)", "NOAA Aviation Weather Center", model.weatherUpdated)
                    sourceRow("Airport delays & ground stops", "FAA NAS status · US airports" + (model.faaError.map { " · error: \($0)" } ?? ""), model.faaUpdated)
                    HStack { Text("Aircraft photos").font(.subheadline); Spacer(); Text("Planespotters.net by tail no.").font(.caption).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { Text("Flights (AeroDataBox)").font(.subheadline); Spacer()
                            Text(model.hasKey ? "Key set" : "Not set · simulated").font(.caption.weight(.semibold)).foregroundStyle(model.hasKey ? Theme.good : Theme.warn) }
                        if let r = model.quota.unitsRemaining, let l = model.quota.unitsLimit {
                            Text("\(r) of \(l) API units left" + (model.quota.resetAt.map { " · resets \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")).font(.caption).foregroundStyle(.secondary)
                        }
                        if let e = model.adbError { Text(e).font(.caption).foregroundStyle(Theme.warn) }
                    }
                    SecureField("RapidAPI key", text: $keyDraft).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save key") { model.saveKey(keyDraft); keyDraft = "" }.disabled(keyDraft.isEmpty)
                    if let m = model.keyMessage { Text(m).font(.caption).foregroundStyle(.secondary) }
                    if model.hasKey { Button("Remove key", role: .destructive) { model.removeKey(); keyDraft = "" } }
                    Toggle("Auto-refresh live flights", isOn: $model.adbAuto)
                    Button("Refresh live data now") { Task { await model.refreshRealData(force: true) } }
                } header: { Text("Data sources") } footer: { Text("Weather and FAA status are real. With an AeroDataBox key, flights you add by number are real: schedule, gates, terminals, baggage, status, tail number and photo. Auto-refresh is paced to your monthly quota (about 20 units per tracked flight) and pauses when 60 units remain. Anything the provider doesn't supply is left blank, not invented.") }
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
    private func sourceRow(_ title: String, _ detail: String, _ updated: Date?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title).font(.subheadline); Spacer()
                if let updated { Text("Live · \(updated.formatted(date: .omitted, time: .shortened))").font(.caption.weight(.semibold)).foregroundStyle(Theme.good) }
                else { Text("Unavailable (simulated)").font(.caption.weight(.semibold)).foregroundStyle(Theme.warn) } }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var offsetLabel: String {
        let h = model.simulatedClockOffset / 3600
        return h == 0 ? "now" : String(format: "%@%.1f h", h > 0 ? "+" : "", h)
    }
}
