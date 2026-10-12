import SwiftUI
import SwiftData
import MapKit
import Charts

enum Countries {
    static let code: [String: String] = ["United States": "US", "Canada": "CA", "Mexico": "MX", "Brazil": "BR", "Argentina": "AR", "Colombia": "CO",
        "United Kingdom": "GB", "Ireland": "IE", "France": "FR", "Netherlands": "NL", "Germany": "DE", "Spain": "ES", "Italy": "IT", "Switzerland": "CH",
        "Türkiye": "TR", "Iceland": "IS", "United Arab Emirates": "AE", "Qatar": "QA", "India": "IN", "Sri Lanka": "LK", "Thailand": "TH", "Singapore": "SG",
        "Hong Kong": "HK", "China": "CN", "South Korea": "KR", "Japan": "JP", "Australia": "AU", "New Zealand": "NZ", "South Africa": "ZA", "Egypt": "EG", "Ethiopia": "ET"]
    static func flag(_ country: String) -> String { code[country] ?? "··" }
}

private enum SortKey: String, CaseIterable { case date = "Date", from = "From", to = "To", airline = "Airline", aircraft = "Aircraft" }
private enum StatsKind: String, Identifiable { case flights, delays, aircraft; var id: String { rawValue } }

/// Passport tab: globe + white sheet with "All-Time / 2025" chips, three gradient summary cards and the Past Flights log.
struct PassportView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Flight.schedDep) private var all: [Flight]
    @AppStorage("my_name") private var myName = "Me"
    @State private var detent: SheetDetent = .medium
    @State private var year: Int? = nil
    @State private var sort: SortKey = .date
    @State private var ascending = false
    @State private var grid = false
    @State private var mapHybrid = true
    @State private var stats: StatsKind?
    @State private var path: [Flight] = []

    // MARK: data
    private var taken: [Flight] { all.filter { $0.ownerName == nil && $0.schedArr < model.clock } }
    private var years: [Int] { Array(Set(taken.map { Calendar.current.component(.year, from: $0.schedDep) })).sorted(by: >) }
    private var flights: [Flight] { year == nil ? taken : taken.filter { Calendar.current.component(.year, from: $0.schedDep) == year } }
    private var miles: Double { flights.reduce(0) { $0 + $1.distanceMiles } }
    private var hours: Double { flights.reduce(0) { $0 + $1.durationHours } }
    private var airports: [String] { Array(Set(flights.flatMap { [$0.dep, $0.arr] })) }
    private var airlines: Int { Set(flights.map { $0.airlineCode }).count }
    private var longHaul: Int { flights.filter { $0.durationHours >= 6 }.count }
    private var delayed: [(Flight, Int)] { flights.compactMap { f in let d = model.live(f).arrDelay; return d >= 15 ? (f, d) : nil } }
    private var lostMinutes: Int { delayed.reduce(0) { $0 + $1.1 } }
    private var topAircraft: (String, Int)? {
        let g = Dictionary(grouping: flights, by: { $0.aircraft })
        guard let m = g.max(by: { $0.value.count < $1.value.count }) else { return nil }
        return (m.key, m.value.count)
    }
    private var sorted: [Flight] {
        let f = flights
        let r: [Flight]
        switch sort {
        case .date: r = f.sorted { $0.schedDep < $1.schedDep }
        case .from: r = f.sorted { $0.dep < $1.dep }
        case .to: r = f.sorted { $0.arr < $1.arr }
        case .airline: r = f.sorted { $0.airlineName < $1.airlineName }
        case .aircraft: r = f.sorted { $0.aircraft < $1.aircraft }
        }
        return ascending ? r : r.reversed()
    }
    private var title: String { year.map(String.init) ?? "All-Time" }

    var body: some View {
        NavigationStack(path: $path) {
            MapSheet(detent: $detent, map: { mapLayer }, controls: {
                Button { mapHybrid.toggle() } label: { GlassMapButton(symbol: "map.fill") }.buttonStyle(.plain)
            }, header: { header }, content: { sheetContent })
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Flight.self) { FlightDetailView(flight: $0) }
            .sheet(item: $stats) { StatsSheet(kind: $0, flights: flights, model: model, year: title) }
        }
    }

    // MARK: map
    private var mapLayer: some View {
        let counts = Dictionary(grouping: flights.flatMap { [$0.dep, $0.arr] }, by: { $0 }).mapValues(\.count)
        let home = counts.max { $0.value < $1.value }.flatMap { AirportDB.airport($0.key) }
        let lat = home?.lat ?? 30, lon = home?.lon ?? -40
        return Map(initialPosition: .camera(MapCamera(centerCoordinate: .init(latitude: lat, longitude: lon), distance: 18_000_000))) {
            ForEach(flights) { f in
                if let a = f.depAirport, let b = f.arrAirport {
                    MapPolyline(coordinates: [a.coordinate, b.coordinate], contourStyle: .geodesic).stroke(Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.9), lineWidth: 1.8)
                }
            }
            ForEach(airports, id: \.self) { c in
                if let a = AirportDB.airport(c) { Annotation("", coordinate: a.coordinate) { Circle().fill(Color(red: 0.55, green: 0.75, blue: 1.0)).frame(width: 9, height: 9).overlay(Circle().stroke(.white, lineWidth: 1.5)) } }
            }
        }
        .mapStyle(mapHybrid ? .hybrid(elevation: .realistic) : .imagery(elevation: .realistic)).mapControls { }
    }

    // MARK: sheet
    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Passport").font(.f(32, .bold))
                Spacer()
                ShareLink(item: shareSummary) { OutlineCircleButton(symbol: "square.and.arrow.up") }.buttonStyle(.plain)
                ProfileAvatar(name: myName)
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    yearChip("All-Time", selected: year == nil) { year = nil }
                    ForEach(years, id: \.self) { y in yearChip(String(y), selected: year == y) { year = y } }
                }.padding(.horizontal, 16).padding(.vertical, 4)
            }
        }.padding(.bottom, 4)
    }
    private var shareSummary: String { "\(title) Flightly Passport: \(flights.count) flights, \(Int(miles).formatted()) mi, \(airports.count) airports." }

    private func yearChip(_ t: String, selected: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.f(18, .medium)).foregroundStyle(selected ? Color.primary : .secondary)
                .padding(.horizontal, 20).frame(height: 44)
                .background { if selected { Capsule().fill(Color(.systemBackground)).overlay(Capsule().stroke(Theme.hairline, lineWidth: 1)).shadow(color: .black.opacity(0.07), radius: 6, y: 2) } }
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var sheetContent: some View {
        if flights.isEmpty {
            VStack(spacing: 8) {
                Text("Your Passport is empty").font(.f(17, .bold))
                Text("Past flights build your map, stats, delays and aircraft. Import a log from Settings or load sample flights.").font(.f(14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(40)
        } else {
            VStack(spacing: 14) {
                passportCard; delayCard; aircraftCard
                pastFlights
            }.padding(.horizontal, 16).padding(.top, 8)
        }
    }

    // MARK: cards
    private var passportCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(title.uppercased()) FLIGHTLY PASSPORT").font(.system(size: 21, weight: .regular)).tracking(0.3).lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 6) { Image(systemName: "person.text.rectangle.fill").font(.system(size: 13)); Text("PASSPORT • PASS • PASAPORTE").font(.system(size: 13, weight: .semibold)).tracking(0.3) }
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                shareIcon
            }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 16) {
                GridRow {
                    metric("FLIGHTS", "\(flights.count)", sub: "\(longHaul) Long Haul", big: true)
                    metric("DISTANCE", "\(Int(miles).formatted()) mi", sub: String(format: "%.1fx around the world", miles / 24901), big: true)
                }
                GridRow {
                    metric("FLIGHT TIME", durationText(hours), sub: nil, big: false)
                    HStack(alignment: .top, spacing: 28) { metric("AIRPORTS", "\(airports.count)", sub: nil, big: false); metric("AIRLINES", "\(airlines)", sub: nil, big: false) }
                }
            }
            statsButton("All Flight Stats") { stats = .flights }
        }
        .foregroundStyle(.white).padding(22)
        .background(LinearGradient(colors: [Color(red: 0.06, green: 0.03, blue: 0.28), Color(red: 0.10, green: 0.14, blue: 0.48), Color(red: 0.16, green: 0.30, blue: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
    private func metric(_ label: String, _ value: String, sub: String?, big: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 16, weight: .regular)).foregroundStyle(Color(red: 0.62, green: 0.72, blue: 1.0))
            Text(value).font(.system(size: big ? 46 : 38, weight: .bold)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            if let sub { Text(sub).font(.system(size: 17)).foregroundStyle(Color(red: 0.62, green: 0.72, blue: 1.0)).lineLimit(1).minimumScaleFactor(0.8) }
        }
    }

    private var delayCard: some View {
        let hrs = lostMinutes / 60
        let avg = delayed.isEmpty ? 0 : lostMinutes / delayed.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) { Text("\(hrs)").font(.system(size: 76, weight: .heavy)).monospacedDigit(); Spacer(); shareIcon }
            Text("hours lost from delays").font(.system(size: 26, weight: .semibold))
            Text("Delayed flights averaged \(shortDuration(Double(avg) * 60)) late").font(.system(size: 20)).foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.72))
            statsButton("All Delay Stats") { stats = .delays }.padding(.top, 14)
        }
        .foregroundStyle(.white).padding(22)
        .background(LinearGradient(colors: [Color(red: 0.72, green: 0.07, blue: 0.10), Color(red: 0.36, green: 0.02, blue: 0.06), Color(red: 0.50, green: 0.14, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var aircraftCard: some View {
        let navy = Color(red: 0.08, green: 0.13, blue: 0.40)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) { Text("Most flown aircraft").font(.system(size: 26, weight: .semibold)); Spacer(); Image(systemName: "square.and.arrow.up").font(.system(size: 18)).foregroundStyle(navy) }
            Text(topAircraft?.0.replacingOccurrences(of: "Boeing ", with: "B").replacingOccurrences(of: "Airbus ", with: "") ?? "—").font(.system(size: 42, weight: .regular)).minimumScaleFactor(0.6).lineLimit(1)
            Text("\(topAircraft?.1 ?? 0) flights").font(.system(size: 22)).foregroundStyle(navy.opacity(0.55))
            AircraftPhoto(type: topAircraft?.0, height: 180).shadow(color: navy.opacity(0.25), radius: 8, y: 4).padding(.vertical, 8)
            statsButton("All Aircraft Stats", dark: true) { stats = .aircraft }
        }
        .foregroundStyle(navy).padding(22)
        .background(LinearGradient(colors: [Color(red: 0.86, green: 0.84, blue: 0.97), Color(red: 0.72, green: 0.82, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color(red: 0.55, green: 0.65, blue: 0.95).opacity(0.5), lineWidth: 1))
    }

    private var shareIcon: some View { Image(systemName: "square.and.arrow.up").font(.system(size: 18)).foregroundStyle(.white) }
    private func statsButton(_ t: String, dark: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(t).font(.system(size: 20, weight: .semibold)); Spacer(); Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold)) }
                .padding(.horizontal, 18).frame(height: 58)
                .background((dark ? Color(red: 0.30, green: 0.40, blue: 0.80) : Color.white).opacity(dark ? 0.30 : 0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
        }.buttonStyle(.plain)
    }
    private func durationText(_ h: Double) -> String { h >= 24 ? "\(Int(h / 24))d \(Int(h) % 24)h" : "\(Int(h))h \(Int((h - floor(h)) * 60))m" }

    // MARK: Past flights
    private var pastFlights: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Past Flights").font(.system(size: 32, weight: .bold))
                Spacer()
                HStack(spacing: 0) {
                    layoutButton("list.bullet", on: !grid) { grid = false }
                    layoutButton("square.grid.2x2", on: grid) { grid = true }
                }.padding(3).background(Color(.tertiarySystemFill), in: Capsule())
            }.padding(.top, 18).padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(SortKey.allCases, id: \.self) { k in
                        Button { if sort == k { ascending.toggle() } else { sort = k; ascending = k != .date } } label: {
                            HStack(spacing: 4) { Text(k.rawValue); if sort == k { Image(systemName: ascending ? "arrow.up" : "arrow.down").font(.system(size: 13, weight: .semibold)) } }
                                .font(.f(19, .medium)).foregroundStyle(sort == k ? Color.primary : .secondary)
                                .padding(.horizontal, 18).frame(height: 44)
                                .background { if sort == k { Capsule().fill(Color(.systemBackground)).overlay(Capsule().stroke(Theme.hairline, lineWidth: 1)).shadow(color: .black.opacity(0.07), radius: 6, y: 2) } }
                        }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 10)
            }

            if sort == .date {
                ForEach(groupedByYear, id: \.0) { y, fs in
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(y)).font(.system(size: 24, weight: .semibold)); Spacer()
                        Text("\(fs.count) FLIGHT\(fs.count == 1 ? "" : "S")").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 4).padding(.top, 22).padding(.bottom, 10)
                    Divider()
                    flightList(fs)
                }
            } else { Divider().padding(.top, 8); flightList(sorted) }
        }
    }
    private var groupedByYear: [(Int, [Flight])] {
        let g = Dictionary(grouping: sorted) { Calendar.current.component(.year, from: $0.schedDep) }
        return g.keys.sorted(by: ascending ? (<) : (>)).map { ($0, g[$0]!) }
    }
    private func layoutButton(_ s: String, on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: s).font(.system(size: 17, weight: .medium)).foregroundStyle(on ? Color.primary : .secondary).frame(width: 46, height: 38)
            .background(on ? Color(.systemBackground) : .clear, in: Capsule()) }.buttonStyle(.plain)
    }

    @ViewBuilder private func flightList(_ fs: [Flight]) -> some View {
        if grid {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(fs) { f in
                    Button { path.append(f) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            AirlineMark(code: f.airlineCode, size: 30)
                            Text("\(f.dep) → \(f.arr)").font(.f(20, .bold)); Text(f.cityTitle).font(.f(13)).foregroundStyle(.secondary).lineLimit(1)
                            Text(f.schedDep.formatted(date: .abbreviated, time: .omitted)).font(.f(12)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Theme.sheetGroup, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }.padding(.top, 12)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(fs.enumerated()), id: \.element.id) { i, f in
                    Button { path.append(f) } label: { pastRow(f) }.buttonStyle(.plain)
                    if i < fs.count - 1 { Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 78) }
                }
            }.padding(.horizontal, -16)
        }
    }

    /// Row as in Flighty: logo | "AA 2772  JFK → AUS" + date on the caption line, "New York to Austin" below ("to" in a lighter weight).
    private func pastRow(_ f: Flight) -> some View {
        HStack(alignment: .center, spacing: 0) {
            AirlineMark(code: f.airlineCode, size: 46).frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(f.spacedCode).foregroundStyle(Color(.systemGray))
                    Text("\(f.dep) → \(f.arr)").foregroundStyle(Color(.systemGray3))
                    Spacer(minLength: 6)
                    Text(f.schedDep.formatted(.dateTime.month(.abbreviated).day().year())).foregroundStyle(Color(.systemGray))
                }.font(.system(size: 17)).lineLimit(1).minimumScaleFactor(0.8)
                (Text(f.depAirport?.city ?? f.dep).fontWeight(.medium) + Text(" to ").fontWeight(.regular).foregroundStyle(Color(.systemGray)) + Text(f.arrAirport?.city ?? f.arr).fontWeight(.medium))
                    .font(.system(size: 22)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.vertical, 16).padding(.horizontal, 20).contentShape(Rectangle())
    }
}

// MARK: - "All … Stats" detail sheets

private struct StatsSheet: View {
    let kind: StatsKind
    let flights: [Flight]
    let model: AppModel
    let year: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                switch kind {
                case .flights: flightStats
                case .delays: delayStats
                case .aircraft: aircraftStats
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private var title: String { kind == .flights ? "\(year) Flight Stats" : (kind == .delays ? "\(year) Delay Stats" : "\(year) Aircraft Stats") }

    @ViewBuilder private var flightStats: some View {
        let miles = flights.reduce(0) { $0 + $1.distanceMiles }
        let airports = Dictionary(grouping: flights.flatMap { [$0.dep, $0.arr] }, by: { $0 }).mapValues(\.count).sorted { $0.value > $1.value }
        let countries = Array(Set(flights.flatMap { [$0.depAirport?.country, $0.arrAirport?.country].compactMap { $0 } })).sorted()
        let airlines = Dictionary(grouping: flights, by: { $0.airlineName }).mapValues(\.count).sorted { $0.value > $1.value }
        Section("Totals") {
            LabeledContent("Flights", value: "\(flights.count)"); LabeledContent("Distance", value: "\(Int(miles).formatted()) mi")
            LabeledContent("Time in the air", value: "\(Int(flights.reduce(0) { $0 + $1.durationHours }))h")
            LabeledContent("Countries", value: "\(countries.count)  (\(countries.map(Countries.flag).joined(separator: " ")))")
            if let l = flights.max(by: { $0.distanceMiles < $1.distanceMiles }) { LabeledContent("Longest", value: "\(l.dep)→\(l.arr) · \(Int(l.distanceMiles)) mi") }
            if let s = flights.min(by: { $0.distanceMiles < $1.distanceMiles }) { LabeledContent("Shortest", value: "\(s.dep)→\(s.arr) · \(Int(s.distanceMiles)) mi") }
        }
        Section("Top airports") {
            Chart(airports.prefix(6), id: \.key) { BarMark(x: .value("Visits", $0.value), y: .value("Airport", $0.key)).foregroundStyle(Theme.accent).cornerRadius(4) }.frame(height: 170)
        }
        Section("Airlines") { ForEach(airlines, id: \.key) { LabeledContent($0.key, value: "\($0.value) flights") } }
    }

    @ViewBuilder private var delayStats: some View {
        let rows = flights.map { ($0, model.live($0).arrDelay) }
        let late = rows.filter { $0.1 >= 15 }
        Section("Summary") {
            LabeledContent("Flights delayed 15m+", value: "\(late.count) of \(flights.count)")
            LabeledContent("Time lost", value: shortDuration(Double(late.reduce(0) { $0 + $1.1 }) * 60))
            LabeledContent("On time or early", value: "\(rows.filter { $0.1 < 15 }.count)")
            if let w = late.max(by: { $0.1 < $1.1 }) { LabeledContent("Worst delay", value: "\(shortDuration(Double(w.1) * 60)) · \(w.0.code) \(w.0.dep)→\(w.0.arr)") }
        }
        Section("Worst flights") { ForEach(late.sorted { $0.1 > $1.1 }.prefix(8), id: \.0.id) { LabeledContent("\($0.0.code) \($0.0.dep)→\($0.0.arr)", value: shortDuration(Double($0.1) * 60)) } }
    }

    @ViewBuilder private var aircraftStats: some View {
        let types = Dictionary(grouping: flights, by: { $0.aircraft }).mapValues { ($0.count, $0.reduce(0) { $0 + $1.durationHours }) }.sorted { $0.value.0 > $1.value.0 }
        Section("Aircraft types") { ForEach(types, id: \.key) { LabeledContent($0.key, value: "\($0.value.0) flights · \(Int($0.value.1))h") } }
        Section("Individual aircraft") {
            LabeledContent("Total aircraft", value: "\(Set(flights.map { $0.tail }).count)")
            ForEach(Dictionary(grouping: flights, by: { $0.tail }).sorted { $0.value.count > $1.value.count }.prefix(8), id: \.key) { LabeledContent($0.key, value: "\($0.value.count) flights · \($0.value[0].aircraft)") }
        }
    }
}
