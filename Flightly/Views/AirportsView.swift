import SwiftUI
import MapKit
import Charts

struct AirportsView: View {
    @Environment(AppModel.self) private var model
    @State private var q = ""
    @State private var showMap = true

    var body: some View {
        NavigationStack {
            let now = model.clock
            let statuses = AirportDB.search(q).map { model.airportStatus($0) }
            List {
                if q.isEmpty {
                    Section {
                        Map { ForEach(statuses, id: \.airport.iata) { st in
                            Annotation(st.airport.iata, coordinate: st.airport.coordinate) {
                                Circle().fill(Theme.severityColor(st.severity)).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        } }.mapStyle(.standard(elevation: .flat)).frame(height: 240).listRowInsets(EdgeInsets())
                        HStack(spacing: 14) { legend(0, "Normal"); legend(1, "Minor"); legend(2, "Moderate"); legend(3, "Severe") }.font(.caption)
                    } header: { Text("Airport status map") }
                    let favs = statuses.filter { model.favoriteAirports.contains($0.airport.iata) }
                    if !favs.isEmpty { Section("Favorites") { ForEach(favs, id: \.airport.iata) { row($0) } } }
                    Section("Disruptions") {
                        let bad = statuses.filter { $0.severity >= 2 }.sorted { $0.avgDelay > $1.avgDelay }
                        if bad.isEmpty { Text("No major disruptions right now.").foregroundStyle(.secondary) }
                        ForEach(bad, id: \.airport.iata) { row($0) }
                    }
                }
                Section("All airports") { ForEach(statuses, id: \.airport.iata) { row($0) } }
            }
            .searchable(text: $q, prompt: "Search airports")
            .navigationTitle("Airports")
        }
    }
    private func legend(_ s: Int, _ t: String) -> some View { HStack(spacing: 4) { Circle().fill(Theme.severityColor(s)).frame(width: 8, height: 8); Text(t) } }
    private func row(_ st: SimulatedProvider.AirportStatus) -> some View {
        NavigationLink { AirportDetailView(airport: st.airport) } label: {
            HStack {
                Text(st.airport.iata).font(.headline.monospaced()).frame(width: 48, alignment: .leading)
                VStack(alignment: .leading) { Text(st.airport.city); Text(st.reason).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                StatusPill(text: st.severity == 0 ? "Normal" : "+\(st.avgDelay)m", color: Theme.severityColor(st.severity))
            }
        }
    }
}

struct AirportDetailView: View {
    let airport: Airport
    @Environment(AppModel.self) private var model
    @State private var departures = true
    @State private var realRows: [SimulatedProvider.BoardRow]?
    @State private var boardNote: String?
    @State private var loadingBoard = false

    var body: some View {
        let now = model.clock
        let st = model.airportStatus(airport)
        let board = realRows ?? SimulatedProvider.shared.board(airport, departures: departures, now: now)
        let hourly = SimulatedProvider.shared.hourlyPerformance(airport, now)
        let isFav = model.favoriteAirports.contains(airport.iata)
        ScrollView {
            VStack(spacing: 14) {
                SectionCard(title: airport.name, symbol: "building.2.fill") {
                    HStack { StatusPill(text: st.severity == 0 ? "Normal operations" : "Avg delay \(st.avgDelay) min", color: Theme.severityColor(st.severity)); Spacer()
                        Text(airport.city + ", " + airport.country).font(.caption).foregroundStyle(.secondary) }
                    Text(st.reason).font(.subheadline)
                    HStack { Image(systemName: st.weather.symbol).symbolRenderingMode(.multicolor); Text("\(st.weather.condition) · \(st.weather.tempC)°C · \(st.weather.windKts) kt") }.font(.subheadline)
                    Text(st.weather.metar).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    Button { var f = model.favoriteAirports; if isFav { f.removeAll { $0 == airport.iata } } else { f.append(airport.iata) }; model.favoriteAirports = f } label: {
                        Label(isFav ? "Remove from favorites" : "Favorite · get disruption alerts", systemImage: isFav ? "star.fill" : "star") }.buttonStyle(.bordered)
                }
                SectionCard(title: "Hourly on-time performance (sample data)", symbol: "chart.xyaxis.line") {
                    Chart(hourly, id: \.hour) { LineMark(x: .value("Hour", $0.hour), y: .value("On-time %", $0.onTime)).foregroundStyle(Theme.accent); AreaMark(x: .value("Hour", $0.hour), y: .value("On-time %", $0.onTime)).foregroundStyle(Theme.accent.opacity(0.15)) }
                        .chartYScale(domain: 30...100).frame(height: 150)
                }
                SectionCard(title: realRows != nil ? "Flight board · live" : "Flight board (sample data)", symbol: "list.bullet.rectangle") {
                    Picker("", selection: $departures) { Text("Departures").tag(true); Text("Arrivals").tag(false) }.pickerStyle(.segmented)
                    ForEach(board) { r in
                        HStack {
                            Text(r.time.formatted(date: .omitted, time: .shortened)).font(.caption.monospacedDigit()).frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading) { Text(r.code).fontWeight(.semibold); Text(departures ? "to \(r.other)" : "from \(r.other)").font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Text("Gate \(r.gate)").font(.caption).foregroundStyle(.secondary)
                            StatusPill(text: r.delay > 14 ? "+\(r.delay)m" : r.status, color: r.delay > 14 ? Theme.warn : Theme.good)
                        }.font(.subheadline)
                    }
                }
                SectionCard(title: "Runway Regulars (sample data)", symbol: "trophy.fill") {
                    ForEach(Array(SimulatedProvider.shared.runwayRegulars(airport).enumerated()), id: \.offset) { i, r in
                        HStack { Text(["🥇", "🥈", "🥉"][i]); Text(r.name); Spacer(); Text("\(r.flights) flights").foregroundStyle(.secondary) }.font(.subheadline)
                    }
                }
            }.padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(airport.iata).navigationBarTitleDisplayMode(.inline)
        .task(id: departures) { await loadBoard() }
    }

    /// Real board for the next ~2.5 h (costs a few API units, so it is cached per airport/direction for 20 minutes).
    private func loadBoard() async {
        realRows = nil
        guard ADB.hasKey, model.adbAuto || true else { return }
        let key = "\(airport.iata)-\(departures)"
        if let hit = BoardCache.shared.get(key) { realRows = hit; return }
        if let r = model.quota.unitsRemaining, r < ADBQuota.autoFloor { return }
        loadingBoard = true; defer { loadingBoard = false }
        if let rows = try? await model.realBoard(iata: airport.iata, departures: departures), !rows.isEmpty {
            BoardCache.shared.set(key, rows); realRows = rows
        }
    }
}

final class BoardCache {
    static let shared = BoardCache()
    private var store: [String: (Date, [SimulatedProvider.BoardRow])] = [:]
    func get(_ k: String) -> [SimulatedProvider.BoardRow]? { store[k].flatMap { Date().timeIntervalSince($0.0) < 20 * 60 ? $0.1 : nil } }
    func set(_ k: String, _ v: [SimulatedProvider.BoardRow]) { store[k] = (Date(), v) }
}
