import SwiftUI
import SwiftData

struct AddFlightView: View {
    var embedded = false
    var onDone: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @State private var mode = 0
    // flight number
    @State private var airline = "DL"
    @State private var searching = false
    @State private var searchError: String?
    @State private var number = ""
    @State private var date = Date()
    // route
    @State private var from = ""
    @State private var to = ""
    // manual
    @State private var mAirline = ""
    @State private var mNumber = ""
    @State private var mFrom = ""
    @State private var mTo = ""
    @State private var mDep = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var mArr = Calendar.current.date(byAdding: .day, value: -7, to: Date().addingTimeInterval(7200))!
    @State private var results: [Flight] = []
    @State private var searched = false
    @State private var showImport = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $mode) { Text("Flight no.").tag(0); Text("Route").tag(1); Text("Past flight").tag(2) }.pickerStyle(.segmented).listRowBackground(Color.clear)
                switch mode {
                case 0:
                    Section {
                        TextField("Flight number, e.g. DL 1486", text: $number).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                        Button { Task { await searchNumber() } } label: { HStack { Text(searching ? "Searching…" : "Search"); if searching { ProgressView() } } }.disabled(number.trimmingCharacters(in: .whitespaces).count < 3 || searching)
                    } header: { Text("Search by flight number") } footer: {
                        if model.hasKey { Text("Looks up the real flight (uses about 2 of your monthly API units).") }
                        else { Text("No live data key set, so this searches built-in sample schedules. Add a key in Settings → Data sources for real flights.") }
                    }
                    if let searchError { Section { Text(searchError).font(.footnote).foregroundStyle(Theme.warn)
                        if model.hasKey { Button("Use a sample schedule instead") { let (c, n) = parseFlightText(number); search { [model.provider.lookup(airlineCode: c, number: n, date: date)].compactMap { $0 } }; self.searchError = nil } } } }
                case 1:
                    Section {
                        AirportPicker(selection: $from, title: "From"); AirportPicker(selection: $to, title: "To")
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                        Button("Search") { search { model.provider.routeSearch(from: from, to: to, date: date) } }.disabled(from.isEmpty || to.isEmpty)
                    } header: { Text("Search by route") } footer: { Text("Route search uses sample schedules. For a real flight, search by flight number.") }
                default:
                    Section("Add a flight you've already taken") {
                        Picker("Airline", selection: $mAirline) { Text("Select").tag(""); ForEach(AirportDB.airlines) { Text("\($0.code) · \($0.name)").tag($0.code) } }
                        TextField("Flight number", text: $mNumber).keyboardType(.numberPad)
                        AirportPicker(selection: $mFrom, title: "From"); AirportPicker(selection: $mTo, title: "To")
                        DatePicker("Departed", selection: $mDep); DatePicker("Arrived", selection: $mArr)
                        Button("Add to log") { addManual() }.disabled(mFrom.isEmpty || mTo.isEmpty || mFrom == mTo)
                    }
                }
                if mode < 2 && searched {
                    Section(results.isEmpty ? "No flights found" : "Results") {
                        ForEach(results) { f in
                            Button { add(f) } label: {
                                HStack { VStack(alignment: .leading) { HStack(spacing: 6) { Text("\(f.airlineName) \(f.code)").foregroundStyle(.primary).fontWeight(.semibold)
                                        Text(f.isReal ? "LIVE" : "SAMPLE").font(.system(size: 9, weight: .heavy)).foregroundStyle(f.isReal ? Theme.good : .secondary)
                                            .padding(.horizontal, 5).padding(.vertical, 2).background((f.isReal ? Theme.good : Color.secondary).opacity(0.14), in: Capsule()) }
                                    Text("\(f.dep) \(f.depTime()) → \(f.arr) \(f.arrTime())").font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); Image(systemName: "plus.circle.fill") }
                            }
                        }
                    }
                }
                Section("Other ways to add flights") {
                    Button { showImport = true } label: { Label("Import: file, email, calendar, TripIt", systemImage: "square.and.arrow.down") }
                }
                Section { Text("Schedules and live data in this build come from a built-in simulator so every feature works with no account or API key.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Add flight").navigationBarTitleDisplayMode(.inline)
            .toolbar { if !embedded { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } } }
            .sheet(isPresented: $showImport) { ImportView() }
        }
    }

    private func search(_ f: () -> [Flight]) { results = f(); searched = true }
    private func parseFlightText(_ t: String) -> (String, String) {
        let c = t.uppercased().filter { !$0.isWhitespace }
        return (String(c.prefix(2)), String(c.dropFirst(2)))
    }
    private func searchNumber() async {
        let (code, num) = parseFlightText(number)
        searchError = nil; searching = true; defer { searching = false }
        if model.hasKey {
            do {
                let found = try await model.lookupRealFlights(code: code, number: num, date: date)
                results = found; searched = true
                if found.isEmpty { searchError = "No flight \(code) \(num) found for that date. Check the number and date." }
            } catch { searchError = error.localizedDescription }
        } else {
            search { [model.provider.lookup(airlineCode: code, number: num, date: date)].compactMap { $0 } }
            if results.isEmpty { searchError = "That airline code isn't in the sample data." }
        }
    }
    private func add(_ f: Flight) {
        if f.isReal { model.adopt(f) }
        context.insert(f); try? context.save(); model.scheduleReminders(for: f); if let onDone { onDone() } else { dismiss() }
    }
    private func addManual() {
        let f = Flight(airlineCode: mAirline.isEmpty ? "XX" : mAirline, number: mNumber.isEmpty ? "0" : mNumber, dep: mFrom, arr: mTo, schedDep: mDep, schedArr: max(mArr, mDep.addingTimeInterval(1800)), source: .manual)
        add(f)
    }
}

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Query private var existing: [Flight]
    @State private var tab = 0
    @State private var showFile = false
    @State private var emailText = ""
    @State private var icsURL = ""
    @State private var message: String?
    @State private var working = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $tab) { Text("File").tag(0); Text("Email").tag(1); Text("Calendar").tag(2); Text("TripIt").tag(3) }.pickerStyle(.segmented).listRowBackground(Color.clear)
                switch tab {
                case 0:
                    Section("Flight log file (CSV)") {
                        Text("Works with exports from myFlightRadar24, OpenFlights and Flightly. Columns are detected automatically. Unlimited history, no 365-day cap.").font(.footnote).foregroundStyle(.secondary)
                        Button("Choose CSV file…") { showFile = true }
                    }
                case 1:
                    Section("Paste a confirmation email") {
                        TextEditor(text: $emailText).frame(minHeight: 160).font(.footnote.monospaced())
                        Button("Find flights") { run { TextFlightParser.parse(emailText, source: .email) } }.disabled(emailText.isEmpty)
                        Text("In Flighty you forward emails to a Flighty address. Without a server, paste the email text here (or share it to the app).").font(.footnote).foregroundStyle(.secondary)
                    }
                case 2:
                    Section("Calendar sync") {
                        Text("Scans events from the last and next 365 days for flight numbers.").font(.footnote).foregroundStyle(.secondary)
                        Button("Scan calendar") { Task { working = true; defer { working = false }
                            do { let found = try await CalendarSync.scan(); finish(found) } catch { message = error.localizedDescription } } }
                    }
                default:
                    Section("TripIt calendar feed") {
                        TextField("https:// … TripIt iCal feed URL", text: $icsURL).textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                        Button("Sync TripIt") { Task { await syncICS() } }.disabled(icsURL.isEmpty)
                        Text("In TripIt: Settings → Calendar Feed, then paste the link. Any iCalendar (.ics) feed with flight events works.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if working { ProgressView() }
                if let message { Section { Text(message) } }
                Section("Export") {
                    ShareLink(item: exportFile()) { Label("Export flight log (CSV)", systemImage: "square.and.arrow.up") }
                }
            }
            .navigationTitle("Import").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $showFile, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { r in
                guard case .success(let url) = r else { return }
                let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { message = "Couldn't read that file."; return }
                let res = CSVImporter.importFile(text)
                finish(res.flights, extra: "Detected \(res.formatName). Skipped \(res.skipped) unrecognized rows.")
            }
        }
    }

    private func exportFile() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("flightly-flights.csv")
        try? CSVImporter.export(existing.filter { $0.ownerName == nil }).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    private func run(_ f: () -> [Flight]) { finish(f()) }
    private func syncICS() async {
        guard let url = URL(string: icsURL.replacingOccurrences(of: "webcal://", with: "https://")) else { message = "That isn't a valid URL."; return }
        working = true; defer { working = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            finish(ICSImporter.flights(fromICS: String(decoding: data, as: UTF8.self)))
        } catch { message = "Couldn't load the feed: \(error.localizedDescription)" }
    }
    private func finish(_ found: [Flight], extra: String = "") {
        var added = 0
        for f in found {
            let dupe = existing.contains { $0.ownerName == nil && $0.code == f.code && Calendar.current.isDate($0.schedDep, inSameDayAs: f.schedDep) && $0.dep == f.dep }
            if !dupe { context.insert(f); added += 1 }
        }
        try? context.save()
        message = "Added \(added) flight\(added == 1 ? "" : "s"). \(found.count - added) duplicate\(found.count - added == 1 ? "" : "s") skipped. \(extra)"
    }
}

