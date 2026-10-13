import SwiftUI
import SwiftData
import MapKit
import Charts

/// Flight detail: same map + sheet scaffold as the rest of the app. Back/menu live in the sheet header (never float over
/// scrolling content); sections are flat with bold titles and hairlines, like Flighty.
struct FlightDetailView: View {
    @Bindable var flight: Flight
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Flight.schedDep) private var all: [Flight]
    @State private var detent: SheetDetent = .medium
    @AppStorage("detail_map_satellite") private var satellite = false
    @State private var showEdit = false
    @State private var confirmDelete = false
    @AppStorage("my_name") private var myName = "Me"

    var body: some View {
        let s = model.live(flight)
        MapSheet(detent: $detent, map: { FlightMap(flight: flight, state: s, satellite: satellite) },
                 controls: { Button { withAnimation(.easeInOut(duration: 0.25)) { satellite.toggle() } } label: { GlassMapButton(symbol: satellite ? "map.fill" : "globe.americas.fill", onDarkMap: true) }.buttonStyle(.plain) },
                 header: { header(s) }, content: { content(s) }, backdrop: satellite ? Color(red: 0.07, green: 0.14, blue: 0.24) : Color(red: 0.09, green: 0.10, blue: 0.13))
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .sheet(isPresented: $showEdit) { EditFlightView(flight: flight) }
            .confirmationDialog("Delete this flight?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { model.stopActivity(flight); context.delete(flight); dismiss() }
            }
    }

    // MARK: header (inside the sheet)
    private func header(_ s: LiveState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { dismiss() } label: { OutlineCircleButton(symbol: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                ShareLink(item: FriendLink.url(for: flight, name: myName), subject: Text("Follow \(flight.spacedCode)"),
                          message: Text("Follow my flight \(flight.spacedCode) \(flight.dep)→\(flight.arr) in Flightly.")) { OutlineCircleButton(symbol: "square.and.arrow.up") }.buttonStyle(.plain)
                Menu {
                    Button { showEdit = true } label: { Label("Edit flight", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete flight", systemImage: "trash") }
                } label: { OutlineCircleButton(symbol: "ellipsis") }
            }
            HStack(spacing: 6) {
                AirlineMark(code: flight.airlineCode, size: 18)
                Text("\(flight.airlineName) \(flight.number)").font(.f(15)).foregroundStyle(.secondary)
                Spacer()
                Text(flight.dayString()).font(.f(15)).foregroundStyle(.secondary)
            }
            Text(flight.cityTitle).font(.f(30, .bold)).lineLimit(1).minimumScaleFactor(0.7)
            statusLine(s)
            sourceLine(s)
        }
        .padding(.horizontal, 20).padding(.bottom, 10)
    }

    /// Where this flight's data comes from, and a manual refresh for real flights (costs API units).
    @ViewBuilder private func sourceLine(_ s: LiveState) -> some View {
        HStack(spacing: 6) {
            Circle().fill(s.isReal ? Theme.good : Theme.warn).frame(width: 6, height: 6)
            if s.isReal {
                Text(s.updatedAt.map { $0 == .distantPast ? "Live data · not yet loaded" : "Live data · updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Live data").font(.f(12)).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await model.refreshRealFlights(all, context: context, force: flight) } } label: {
                    HStack(spacing: 4) { if model.adbBusy { ProgressView().controlSize(.mini) } else { Image(systemName: "arrow.clockwise") }; Text("Refresh") }.font(.f(12, .semibold))
                }.disabled(model.adbBusy)
            } else { Text("Simulated flight data").font(.f(12)).foregroundStyle(.secondary) }
        }
        if s.isReal, s.phase == .enRoute {
            HStack(spacing: 6) {
                Image(systemName: s.positionLive ? "location.fill" : "location").font(.system(size: 10)).foregroundStyle(s.positionLive ? Theme.good : .secondary)
                Text(s.positionLive ? "Live position · \(s.positionTime.map { $0.formatted(date: .omitted, time: .shortened) } ?? "now")" : "Position estimated along the route").font(.f(12)).foregroundStyle(.secondary)
            }
        }
        if s.isReal, let e = model.adbError { Text(e).font(.f(12)).foregroundStyle(Theme.warn) }
    }

    @ViewBuilder private func statusLine(_ s: LiveState) -> some View {
        let late = s.depDelay >= 15 || s.arrDelay >= 15
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if s.phase == .canceled { StatusBadge(text: "Canceled", color: Theme.bad) }
            else if late && s.phase != .arrived && s.phase != .landed { StatusBadge(text: "Running late", color: Theme.bad) }
            else { Text(statusText(s)).font(.f(16, .bold)).foregroundStyle(statusColor(s)) }
            Text(s.prediction).font(.f(15)).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    // MARK: content
    private func content(_ s: LiveState) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            endpoints(s)
            if s.phase == .enRoute { progressStrip(s) }
            if !s.inbound.isEmpty { wheresMyPlane(s) }
            notices(s)
            connectionCard(s)
            timeline(s)
            if !s.forecast.isEmpty { forecastCard(s) }
            if !s.trend.isEmpty { trendCard(s) }
            weatherCard(s)
            assistantsCard(s)
            aircraftCard(s)
            controls(s)
            if !flight.changes.isEmpty { changesCard }
            notesCard
        }
        .padding(.horizontal, 20).padding(.top, 6)
    }

    private func endpoints(_ s: LiveState) -> some View {
        HStack(alignment: .top, spacing: 0) {
            endpoint(code: flight.dep, city: flight.depAirport?.city ?? "", time: flight.depTime(s.estDep), sched: flight.depTime(),
                     late: s.depDelay >= 15, terminal: flight.depTerminal, gate: s.depGate, trailing: false)
            Spacer(minLength: 8)
            Image(systemName: "airplane").font(.system(size: 18)).foregroundStyle(Color(.systemGray3)).padding(.top, 14)
            Spacer(minLength: 8)
            endpoint(code: flight.arr, city: flight.arrAirport?.city ?? "", time: flight.arrTime(s.estArr), sched: flight.arrTime(),
                     late: s.arrDelay >= 15, terminal: flight.arrTerminal, gate: s.arrGate, trailing: true, bag: s.baggage)
        }
    }

    private func endpoint(code: String, city: String, time: String, sched: String, late: Bool, terminal: String, gate: String, trailing: Bool, bag: String? = nil) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
            Text(code).font(.f(38, .heavy)).tracking(-0.5)
            Text(city).font(.f(14)).foregroundStyle(.secondary)
            Text(time).font(.f(22, .bold)).monospacedDigit().foregroundStyle(late ? Theme.warn : Theme.good)
            if time != sched { Text(sched).font(.f(13)).monospacedDigit().strikethrough().foregroundStyle(.secondary) }
            HStack(spacing: 6) {
                if terminal != "—", !terminal.isEmpty { chip(terminal.allSatisfy(\.isNumber) ? "T\(terminal)" : "Term \(terminal)") }
                if gate != "—", !gate.isEmpty { gateChip(gate) }
                if let bag, bag != "—" { chip("Bag \(bag)") }
            }.padding(.top, 4)
        }
    }
    private func chip(_ t: String) -> some View {
        Text(t).font(.f(12, .bold)).foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 3).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    private func gateChip(_ g: String) -> some View {
        HStack(spacing: 3) { Image(systemName: "door.left.hand.open").font(.system(size: 9, weight: .bold)); Text(g).font(.f(12, .heavy)) }
            .foregroundStyle(.black).padding(.horizontal, 7).padding(.vertical, 3).background(Color(red: 1.0, green: 0.80, blue: 0.20), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func progressStrip(_ s: LiveState) -> some View {
        VStack(spacing: 8) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 4)
                    Capsule().fill(Theme.accent).frame(width: g.size.width * s.progress, height: 4)
                    Image(systemName: "airplane").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent)
                        .offset(x: max(0, min(g.size.width - 14, g.size.width * s.progress - 7)), y: -1)
                }.frame(height: 14)
            }.frame(height: 14)
            HStack { Text("\(Int(s.progress * 100))% flown"); Spacer()
                Text("\(s.altitudeFt.formatted()) ft · \(s.speedKts) kt"); Spacer()
                Text("Landing in \(shortDuration(s.estArr.timeIntervalSince(model.clock)))").fontWeight(.semibold).foregroundStyle(Theme.good) }
                .font(.f(13)).foregroundStyle(.secondary)
        }
    }

    // MARK: flat section scaffolding
    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.f(22, .bold))
            VStack(alignment: .leading, spacing: 0) { c() }
        }
    }
    private func row(_ k: String, _ v: String, vColor: Color = .primary, last: Bool = false) -> some View {
        HStack { Text(k).font(.f(16)); Spacer(); Text(v).font(.f(16, .semibold)).foregroundStyle(vColor).multilineTextAlignment(.trailing) }
            .padding(.vertical, 13).overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.hairline).frame(height: 0.5) } }
    }

    // MARK: Where's my plane
    private func wheresMyPlane(_ s: LiveState) -> some View {
        let late = s.delayReason == "Late-arriving aircraft"
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Where's My Plane?").font(.f(18, .bold)).foregroundStyle(.white)
                Text("\(flight.aircraft) · \(flight.tail)").font(.f(14, .medium)).foregroundStyle(.white.opacity(0.9))
                AircraftPhoto(type: flight.aircraft, tail: flight.tail, height: 130, cornerRadius: 12).padding(.top, 8)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.25, green: 0.52, blue: 0.86), Color(red: 0.55, green: 0.74, blue: 0.94)], startPoint: .top, endPoint: .bottom))

            VStack(alignment: .leading, spacing: 12) {
                if late { StatusBadge(text: "Running late", color: Theme.bad) } else { StatusBadge(text: "On schedule", color: Theme.good, symbol: "checkmark.circle.fill") }
                Text(late ? "\(s.depDelay >= 15 ? s.depDelay : (s.inbound.last?.delay ?? 0))m delay predicted due to late arriving aircraft" : "Your plane is on schedule to turn around for this flight.").font(.f(15, .medium))
                HStack { Text("My Flight").font(.f(14, .semibold)); Spacer()
                    Text(late ? "\(max(s.depDelay, 0))m Delay Predicted" : "On time").font(.f(14, .semibold)).foregroundStyle(late ? Theme.bad : Theme.good) }
                    .padding(.horizontal, 12).padding(.vertical, 10).background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                ForEach(Array(s.inbound.reversed().enumerated()), id: \.element.id) { i, leg in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: leg.landed ? "airplane.arrival" : "airplane").font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 20).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(AirportDB.airport(leg.from)?.city ?? leg.from) to \(AirportDB.airport(leg.to)?.city ?? leg.to)").font(.f(15, .bold))
                            Text(leg.landed ? "Landed \(leg.estArr.formatted(date: .omitted, time: .shortened))" : "Lands in \(shortDuration(leg.estArr.timeIntervalSince(model.clock)))").font(.f(13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(leg.delay >= 15 ? "\(leg.delay)m Late" : (leg.delay <= -5 ? "\(-leg.delay)m Early" : "On Time")).font(.f(13, .semibold)).foregroundStyle(Theme.delayColor(leg.delay))
                    }
                }
            }.padding(16)
        }
        .background(Theme.sheetGroup)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Real FAA programs (ground stops, ground delay programs, delays, closures) at either airport. Only shown when the
    /// FAA is actually reporting one, so nothing here is invented. US airports only.
    @ViewBuilder private func notices(_ s: LiveState) -> some View {
        let items: [(String, FAAStatus)] = [(flight.dep, s.faaDep), (flight.arr, s.faaArr)].compactMap { code, st in st.map { (code, $0) } }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    let (code, st) = item
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: st.severity >= 3 ? "exclamationmark.octagon.fill" : "exclamationmark.circle.fill").foregroundStyle(st.severity >= 3 ? Theme.bad : Theme.warn).font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(code): \(st.kind.rawValue)").font(.f(15, .bold)).foregroundStyle(st.severity >= 3 ? Theme.bad : Theme.warn)
                            Text(st.reason.prefix(1).uppercased() + st.reason.dropFirst()).font(.f(14, .medium))
                            if !st.detail.isEmpty { Text(st.detail).font(.f(13)).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                    }.padding(16)
                    if i < items.count - 1 { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
                }
                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                Text("Live · FAA National Airspace System status").font(.f(11)).foregroundStyle(.tertiary).padding(.horizontal, 16).padding(.vertical, 10)
            }
            .background(Theme.sheetGroup, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func connectionCard(_ s: LiveState) -> some View {
        let next = all.filter { $0.ownerName == nil && $0.dep == flight.arr && $0.schedDep > flight.schedArr && $0.schedDep.timeIntervalSince(flight.schedArr) < 12 * 3600 }.min { $0.schedDep < $1.schedDep }
        return Group {
            if let next {
                let ns = model.live(next)
                let layover = Int(ns.estDep.timeIntervalSince(s.estArr) / 60)
                let intl = flight.arrAirport?.country != flight.depAirport?.country
                let minTime = intl ? 90 : 45
                let same = flight.arrTerminal == next.depTerminal
                let walk = same ? 8 : 20
                let risk = layover - minTime - walk
                section("Connection") {
                    HStack { Text("\(next.spacedCode) to \(next.arrAirport?.city ?? next.arr)").font(.f(16, .semibold)); Spacer()
                        Text(risk >= 20 ? "Comfortable" : (risk >= 0 ? "Tight" : "At risk")).font(.f(14, .bold)).foregroundStyle(risk >= 20 ? Theme.good : (risk >= 0 ? Theme.warn : Theme.bad)) }
                        .padding(.vertical, 13).overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
                    row("Layover", "\(max(0, layover)) min")
                    row("Typical minimum", "\(minTime) min")
                    row("Terminal change", same ? "None" : "T\(flight.arrTerminal) → T\(next.depTerminal) · ~\(walk) min")
                    row("Next gate", ns.depGate, last: true)
                }
            }
        }
    }

    // MARK: Timeline (vertical dots + rail)
    private func timeline(_ s: LiveState) -> some View {
        func t(_ d: Date?, _ ap: Airport?) -> String { d.map { flight.fmt($0, airport: ap) } ?? "—" }
        let steps: [(String, String, Bool)] = [
            ("Departs gate", flight.depTime(s.estDep), s.phase != .scheduled && s.phase != .boarding),
            ("Takes off", t(s.wheelsUp, flight.depAirport), s.actDep != nil),
            ("Lands", t(s.wheelsDown, flight.arrAirport), s.actArr != nil),
            ("Arrives at gate", flight.arrTime(s.estArr), s.phase == .arrived || s.phase == .landed),
        ]
        return section("Timeline") {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, st in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Circle().fill(st.2 ? Theme.good : Color(.systemBackground)).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(st.2 ? Theme.good : Color(.systemGray3), lineWidth: 2)).padding(.top, 4)
                        if i < steps.count - 1 { Rectangle().fill(st.2 ? Theme.good : Color(.systemGray4)).frame(width: 2).frame(maxHeight: .infinity) }
                    }.frame(width: 12)
                    HStack { Text(st.0).font(.f(16)); Spacer(); Text(st.1).font(.f(16, .semibold)).monospacedDigit() }.padding(.bottom, i < steps.count - 1 ? 18 : 0)
                }
            }
            if s.taxiOutMin > 0 || s.taxiInMin > 0 { Text("Taxi out \(s.taxiOutMin) min · taxi in \(s.taxiInMin) min").font(.f(13)).foregroundStyle(.secondary).padding(.top, 12) }
        }
    }

    private func forecastCard(_ s: LiveState) -> some View {
        section("Arrival forecast (sample data)") {
            Text("\(Int(s.routeOnTimePct))% of \(flight.dep)→\(flight.arr) flights on \(flight.airlineName) arrived on time in the last 60 days. Average delay \(s.routeAvgDelay) min.")
                .font(.f(14)).foregroundStyle(.secondary).padding(.bottom, 8)
            Chart(s.forecast) { b in
                BarMark(x: .value("Share", b.pct), y: .value("Outcome", b.label), height: .fixed(14))
                    .foregroundStyle(b.id == "canc" || b.id == "l60" ? Theme.bad : (b.id == "l30" || b.id == "l15" ? Theme.warn : Theme.good)).cornerRadius(4)
                    .annotation(position: .trailing) { Text("\(Int(b.pct.rounded()))%").font(.f(11, .semibold)).foregroundStyle(.secondary) }
            }
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisValueLabel().font(.system(size: 13)).foregroundStyle(Color.secondary) } }
            .frame(height: 190)
        }
    }

    private func trendCard(_ s: LiveState) -> some View {
        let depHour = Calendar.current.dateComponents(in: flight.depAirport?.timeZone ?? .current, from: flight.schedDep).hour ?? 0
        return section("Delay trend at \(flight.dep) (sample data)") {
            Chart(Array(s.trend.enumerated()), id: \.offset) { h, v in
                AreaMark(x: .value("Hour", h), y: .value("Delay", v)).foregroundStyle(Theme.warn.opacity(0.22))
                LineMark(x: .value("Hour", h), y: .value("Delay", v)).foregroundStyle(Theme.warn)
                if h == depHour { PointMark(x: .value("Hour", h), y: .value("Delay", v)).foregroundStyle(Theme.accent).symbolSize(100) }
            }
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { v in AxisValueLabel { if let h = v.as(Int.self) { Text(h == 0 ? "12a" : (h < 12 ? "\(h)a" : (h == 12 ? "12p" : "\(h - 12)p"))).font(.system(size: 11)).foregroundStyle(Color.secondary) } } } }
            .frame(height: 120)
        }
    }

    private func weatherCard(_ s: LiveState) -> some View {
        section("Good to know") {
            weatherRow(flight.dep, s.depWeather, live: s.weatherLive)
            weatherRow(flight.arr, s.arrWeather, live: s.weatherLive)
            if let a = flight.depAirport, let b = flight.arrAirport {
                let diff = (b.timeZone.secondsFromGMT() - a.timeZone.secondsFromGMT()) / 3600
                row("Time zone change", diff == 0 ? "None" : "\(diff > 0 ? "+" : "")\(diff) h", last: true)
            }
        }
    }
    private func weatherRow(_ code: String, _ w: WeatherInfo, live: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Image(systemName: w.symbol).symbolRenderingMode(.multicolor).frame(width: 24); Text("\(code) · \(w.condition)").font(.f(16, .semibold))
                Text(live ? "LIVE" : "SIMULATED").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(live ? Theme.good : .secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2).background((live ? Theme.good : Color.secondary).opacity(0.14), in: Capsule())
                Spacer()
                Text("\(w.tempC)°C · \(w.windKts) kt").font(.f(15)).foregroundStyle(.secondary) }
            Text(w.metar).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary).padding(.leading, 32)
        }.padding(.vertical, 13).overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    private func assistantsCard(_ s: LiveState) -> some View {
        let leave = s.estDep.addingTimeInterval(-(flight.depAirport?.country == "United States" ? 2.0 : 3.0) * 3600)
        return section("Assistants") {
            assistant("checkmark.seal.fill", "Check-In", s.minutesToBoarding < 24 * 60 ? "Open now" : "Opens \(flight.schedDep.addingTimeInterval(-86400).formatted(date: .abbreviated, time: .shortened))")
            assistant("sunrise.fill", "Morning-Of", "Be at \(flight.dep) by \(flight.depTime(leave))")
            assistant("door.left.hand.open", "Boarding", "About \(flight.depTime(s.estDep.addingTimeInterval(-40 * 60))) at gate \(s.depGate)")
            if let url = URL(string: "https://www.google.com/search?q=\(flight.airlineName.replacingOccurrences(of: " ", with: "+"))+online+check-in") {
                Link(destination: url) { HStack { Text("Open \(flight.airlineName) check-in").font(.f(16, .semibold)); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .bold)) }.padding(.vertical, 13) }
            }
        }
    }
    private func assistant(_ icon: String, _ t: String, _ sub: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) { Text(t).font(.f(16, .semibold)); Text(sub).font(.f(14)).foregroundStyle(.secondary) }
            Spacer()
        }.padding(.vertical, 12).overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    private func aircraftCard(_ s: LiveState) -> some View {
        section("Aircraft") {
            row("Type", flight.aircraft.isEmpty ? "—" : flight.aircraft); row("Tail number", flight.tail.isEmpty ? "—" : flight.tail)
            row("Airline", flight.airlineName, last: s.phase != .enRoute)
            if s.phase == .enRoute { row("Heading", "\(Int(s.heading))°", last: true) }
        }
    }

    private func controls(_ s: LiveState) -> some View {
        section("Alerts") {
            toggleRow("Push alerts", $flight.alertsEnabled).onChange(of: flight.alertsEnabled) { _, on in if on { model.scheduleReminders(for: flight) } }
            toggleRow("Live Activity", Binding(get: { model.isTracking(flight) }, set: { model.setTracking(flight, on: $0) }))
            HStack { Text("Reason for travel").font(.f(16)); Spacer()
                Picker("", selection: $flight.reasonRaw) { ForEach(TravelReason.allCases) { Text($0.rawValue).tag($0.rawValue) } }.labelsHidden() }
                .padding(.vertical, 5).overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
            HStack { Text("Seat").font(.f(16)); Spacer(); TextField("Add seat", text: $flight.seat).multilineTextAlignment(.trailing).font(.f(16, .semibold)).frame(width: 140) }.padding(.vertical, 13)
        }
    }
    private func toggleRow(_ t: String, _ b: Binding<Bool>) -> some View {
        Toggle(t, isOn: b).font(.f(16)).padding(.vertical, 6).overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    private var changesCard: some View {
        section("Record of changes") {
            ForEach(flight.changes.reversed()) { c in
                HStack(alignment: .top) { Text(c.date.formatted(date: .abbreviated, time: .shortened)).font(.f(13)).foregroundStyle(.secondary).frame(width: 118, alignment: .leading)
                    Text(c.text).font(.f(15)) }.padding(.vertical, 12).overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
            }
        }
    }

    private var notesCard: some View {
        section("Notes") {
            TextField("Add a note about this flight", text: $flight.notes, axis: .vertical).lineLimit(2...6).font(.f(16)).padding(.vertical, 12)
        }
    }
}

/// Route map: the whole great-circle route framed above the sheet, flat satellite view, thin curved arc
/// (solid where flown, dotted ahead), labelled airport pins and the aircraft riding the arc.
/// Route map: the whole great-circle route framed above the sheet. Default is a muted dark "stylized" basemap so the route
/// is the hero; satellite is one tap away. Thin curved arc (solid where flown, dotted ahead), labelled pins, aircraft on the arc.
struct FlightMap: View {
    let flight: Flight
    let state: LiveState
    var satellite = false
    private var accent: Color { satellite ? Color(red: 0.30, green: 0.62, blue: 1.0) : Color(red: 0.38, green: 0.66, blue: 1.0) }

    var body: some View {
        if let a = flight.depAirport, let b = flight.arrAirport {
            let path = Geo.path(a, b, steps: 96)
            let flown = Int((state.progress * 96).rounded())
            Map(initialPosition: .camera(camera(a, b))) {
                MapPolyline(coordinates: Array(path.suffix(from: min(flown, path.count - 1))))
                    .stroke(.white.opacity(satellite ? 0.75 : 0.55), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [0.5, 6]))
                if flown > 0 {
                    // soft glow under the flown segment
                    MapPolyline(coordinates: Array(path.prefix(flown + 1))).stroke(accent.opacity(0.28), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    MapPolyline(coordinates: Array(path.prefix(flown + 1))).stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                Annotation("", coordinate: a.coordinate, anchor: .center) { pin(a.iata) }
                Annotation("", coordinate: b.coordinate, anchor: .center) { pin(b.iata) }
                if state.phase == .enRoute, let p = state.position {
                    Annotation("", coordinate: p, anchor: .center) { plane }
                }
            }
            .mapStyle(satellite ? .imagery(elevation: .flat)
                                : .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .environment(\.colorScheme, .dark)
            .mapControls { }
        } else { Color.black }
    }

    private var plane: some View {
        Image(systemName: "airplane").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
            .rotationEffect(.degrees(state.heading - 90))
            .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
            .padding(6)
    }

    private func pin(_ code: String) -> some View {
        VStack(spacing: 3) {
            Circle().fill(.white).frame(width: 10, height: 10).overlay(Circle().stroke(accent, lineWidth: 3))
            Text(code).font(.system(size: 12, weight: .bold)).foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 2)
        }
    }

    private func camera(_ a: Airport, _ b: Airport) -> MapCamera {
        let mid = Geo.interpolate(a, b, 0.5)
        let metres = Geo.distanceMiles(a, b) * 1609.34
        return MapCamera(centerCoordinate: mid, distance: min(max(450_000, metres * 2.6), 40_000_000), heading: 0, pitch: 0)
    }
}

struct EditFlightView: View {
    @Bindable var flight: Flight
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Flight") {
                    TextField("Airline code (e.g. DL)", text: $flight.airlineCode).textInputAutocapitalization(.characters)
                    TextField("Flight number", text: $flight.number).keyboardType(.numberPad)
                    TextField("Tail number", text: $flight.tail); TextField("Aircraft", text: $flight.aircraft); TextField("Seat", text: $flight.seat)
                }
                Section("Route & times") {
                    AirportPicker(selection: $flight.dep, title: "From"); AirportPicker(selection: $flight.arr, title: "To")
                    DatePicker("Departs", selection: $flight.schedDep); DatePicker("Arrives", selection: $flight.schedArr)
                }
                Section("Gates") {
                    TextField("Departure terminal", text: $flight.depTerminal); TextField("Departure gate", text: $flight.depGate)
                    TextField("Arrival terminal", text: $flight.arrTerminal); TextField("Arrival gate", text: $flight.arrGate)
                    TextField("Baggage claim", text: $flight.baggage)
                }
            }
            .navigationTitle("Edit flight").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
