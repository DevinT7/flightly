import SwiftUI
import SwiftData
import MapKit

/// Flighty's home: a satellite globe with route arcs, and a persistent white bottom sheet titled "My Flights".
struct FlightsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Flight.schedDep) private var all: [Flight]
    @AppStorage("my_name") private var myName = "Me"
    @State private var showPast = false
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var detent: SheetDetent = .medium
    @State private var camera: MapCameraPosition = .camera(MapCamera(centerCoordinate: .init(latitude: 36, longitude: -40), distance: 24_000_000))
    @State private var path: [Flight] = []
    @State private var mapStyleIndex = 0
    @State private var showAirports = false

    private var mine: [Flight] { all.filter { $0.ownerName == nil } }
    private var upcoming: [Flight] { mine.filter { !$0.isPast } }
    private var past: [Flight] { mine.filter { $0.isPast }.reversed() }
    private var listed: [Flight] { showPast ? past : upcoming }

    var body: some View {
        NavigationStack(path: $path) {
            MapSheet(detent: $detent, map: { mapLayer }, controls: { mapControls }, header: { header },
                     content: { rows }, onRefresh: { model.refresh(all, context: context) },
                     backdrop: mapStyleIndex == 0 ? .black : Color(red: 0.55, green: 0.78, blue: 0.93))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Flight.self) { FlightDetailView(flight: $0) }
            .navigationDestination(isPresented: $showAirports) { AirportsView() }
            .onChange(of: model.pendingFlightID) { _, id in openPending(id) }
            .onAppear { openPending(model.pendingFlightID) }
            .sheet(isPresented: $showAdd) { AddFlightView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private func openPending(_ id: UUID?) {
        guard let id, let f = all.first(where: { $0.uuid == id }) else { return }
        showAirports = false; path = [f]; model.pendingFlightID = nil
    }

    // MARK: map
    private var mapLayer: some View {
        Map(position: $camera) {
            ForEach(upcoming) { f in
                if let a = f.depAirport, let b = f.arrAirport {
                    MapPolyline(coordinates: [a.coordinate, b.coordinate], contourStyle: .geodesic).stroke(Color(red: 0.2, green: 0.5, blue: 1.0), lineWidth: 2.2)
                    Annotation("", coordinate: a.coordinate) { dot }
                    Annotation("", coordinate: b.coordinate) { dot }
                    let s = model.live(f)
                    if s.phase == .enRoute, let p = s.position {
                        Annotation("", coordinate: p) {
                            Image(systemName: "airplane").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                                .rotationEffect(.degrees(s.heading - 90)).shadow(color: .black.opacity(0.5), radius: 3)
                        }
                    }
                }
            }
        }
        .mapStyle(mapStyleIndex == 0 ? .imagery(elevation: .realistic) : .standard(elevation: .realistic))
        .mapControls { }
    }
    private var dot: some View { Circle().fill(Color(red: 0.2, green: 0.5, blue: 1.0)).frame(width: 11, height: 11).overlay(Circle().stroke(.white, lineWidth: 2)) }

    private var mapControls: some View {
        VStack(spacing: 10) {
            let dark = mapStyleIndex == 0
            Button { withAnimation(.easeInOut(duration: 0.25)) { mapStyleIndex = 1 - mapStyleIndex } } label: { GlassMapButton(symbol: dark ? "map.fill" : "globe.americas.fill", onDarkMap: dark) }.buttonStyle(.plain)
            Button { showAirports = true } label: { GlassMapButton(symbol: "building.2.fill", onDarkMap: dark) }.buttonStyle(.plain)
            Button { camera = .camera(MapCamera(centerCoordinate: .init(latitude: 36, longitude: -40), distance: 24_000_000)) } label: { GlassMapButton(symbol: "location.north.fill", onDarkMap: dark) }.buttonStyle(.plain)
        }
    }

    // MARK: sheet
    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    Button { showPast = false } label: { Label("My Flights", systemImage: showPast ? "" : "checkmark") }
                    Button { showPast = true } label: { Label("Past Flights", systemImage: showPast ? "checkmark" : "") }
                } label: {
                    HStack(spacing: 5) {
                        Text(showPast ? "Past Flights" : "My Flights").font(.f(32, .bold)).foregroundStyle(Color.primary)
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary).padding(.top, 8)
                    }
                }.buttonStyle(.plain)
                Spacer()
                ShareLink(item: shareText) { OutlineCircleButton(symbol: "square.and.arrow.up") }.buttonStyle(.plain)
                Button { showSettings = true } label: { ProfileAvatar(name: myName) }.buttonStyle(.plain)
            }
            searchField
        }
        .padding(.horizontal, 20).padding(.bottom, 6)
    }

    private var rows: some View {
        LazyVStack(spacing: 0) {
            if listed.isEmpty { empty }
            ForEach(Array(listed.enumerated()), id: \.element.id) { i, f in
                Button { path.append(f) } label: {
                    FlightRow(flight: f, state: model.live(f), now: model.clock, connection: connection(after: f))
                }.buttonStyle(.plain)
                .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { context.delete(f) } }
                if i < listed.count - 1 { Divider().padding(.leading, 60) }
            }
        }.padding(.horizontal, 20)
    }

    private var shareText: String {
        upcoming.map { "\($0.spacedCode) \($0.dep)→\($0.arr) \($0.dayString())" }.joined(separator: "\n")
    }

    private var searchField: some View {
        Button { showAdd = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                Text("Search to add flights").font(.f(15)).foregroundStyle(.secondary); Spacer()
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }.buttonStyle(.plain)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text(showPast ? "No past flights" : "No upcoming flights").font(.f(17, .bold))
            Text("Search by flight number or route, import from your calendar, or forward a booking email.").font(.f(14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Load sample flights") { DemoData.load(into: context) }.font(.f(15, .semibold)).padding(.top, 4)
        }.padding(.vertical, 36).padding(.horizontal, 20)
    }

    private func connection(after f: Flight) -> (layover: String, tight: Bool)? {
        guard let next = upcoming.first(where: { $0.dep == f.arr && $0.schedDep > f.schedArr && $0.schedDep.timeIntervalSince(f.schedArr) < 12 * 3600 }) else { return nil }
        let s = model.live(f), ns = model.live(next)
        let lay = ns.estDep.timeIntervalSince(s.estArr)
        let intl = f.arrAirport?.country != f.depAirport?.country
        return (shortDuration(lay), lay < (intl ? 90 : 55) * 60)
    }
}

enum DemoData {
    static func load(into context: ModelContext) {
        let cal = Calendar.current
        func mk(_ al: String, _ n: String, _ d: String, _ a: String, daysFromNow: Int, hour: Int, hours: Double? = nil, minuteOffset: Int = 0) -> Flight? {
            guard let da = AirportDB.airport(d), let aa = AirportDB.airport(a) else { return nil }
            let base = cal.startOfDay(for: Date().addingTimeInterval(Double(daysFromNow) * 86400))
            let dep = cal.date(byAdding: .minute, value: hour * 60 + minuteOffset, to: base)!
            let dur = hours ?? (Geo.distanceMiles(da, aa) / 480 + 0.6)
            return Flight(airlineCode: al, number: n, dep: d, arr: a, schedDep: dep, schedArr: dep.addingTimeInterval(dur * 3600), source: .manual)
        }
        let now = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        let items: [Flight?] = [
            mk("DL", "1486", "AUS", "ATL", daysFromNow: 0, hour: 0, hours: 2.4, minuteOffset: max(0, now - 70)),
            mk("DL", "2210", "ATL", "LHR", daysFromNow: 2, hour: 18),
            mk("BA", "216", "LHR", "AUS", daysFromNow: 9, hour: 10),
            mk("UA", "1123", "AUS", "DEN", daysFromNow: 1, hour: 7),
            mk("WN", "4312", "DEN", "LAX", daysFromNow: 1, hour: 11),
            mk("AA", "1", "JFK", "LAX", daysFromNow: -40, hour: 8), mk("AA", "2", "LAX", "JFK", daysFromNow: -35, hour: 23),
            mk("EK", "201", "JFK", "DXB", daysFromNow: -120, hour: 22), mk("EK", "384", "DXB", "CMB", daysFromNow: -118, hour: 9),
            mk("UL", "225", "CMB", "SIN", daysFromNow: -100, hour: 10), mk("SQ", "321", "SIN", "SYD", daysFromNow: -90, hour: 9),
            mk("QF", "11", "SYD", "LAX", daysFromNow: -60, hour: 11), mk("AS", "311", "SEA", "AUS", daysFromNow: -200, hour: 13),
            mk("AF", "1234", "CDG", "AMS", daysFromNow: -300, hour: 15), mk("JL", "5", "HND", "SFO", daysFromNow: -250, hour: 17),
        ]
        for f in items.compactMap({ $0 }) { context.insert(f) }
        try? context.save()
    }
}
