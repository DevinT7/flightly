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
    @State private var showEdit = false
    @State private var confirmDelete = false
    @AppStorage("my_name") private var myName = "Me"

    var body: some View {
        let s = model.live(flight)
        MapSheet(detent: $detent, map: { FlightMap(flight: flight, state: s) }, controls: { EmptyView() },
                 header: { header(s) }, content: { content(s) })
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
        }
        .padding(.horizontal, 20).padding(.bottom, 10)
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
            wheresMyPlane(s)
            notices(s)
            connectionCard(s)
            timeline(s)
            forecastCard(s)
            trendCard(s)
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
                chip(terminal.allSatisfy(\.isNumber) ? "T\(terminal)" : "Term \(terminal)")
                gateChip(gate)
                if let bag { chip("Bag \(bag)") }
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
                AircraftPhoto(type: flight.aircraft, height: 130, cornerRadius: 12).padding(.top, 8)
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
                Text("Photo: Wikimedia Commons").font(.f(10)).foregroundStyle(.tertiary)
            }.padding(16)
        }
        .background(Theme.sheetGroup)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// ATC advisory card for airport programs (red, like Flighty's notices).
    @ViewBuilder private func notices(_ s: LiveState) -> some View {
        let reason = s.delayReason ?? ""
        if reason.hasPrefix("Weather") || reason.hasPrefix("Ground stop") || reason.hasPrefix("Air traffic") {
            let code = reason.hasSuffix(flight.dep) ? flight.dep : flight.arr
            VStack(alignment: .leading, spacing: 0) {
                HStack { Text("\(code) \(code == flight.dep ? "Departures" : "Arrivals")").font(.f(15, .semibold)); Spacer()
                    Text("\(max(s.depDelay, 15))m delay").font(.f(13, .semibold)).foregroundStyle(Theme.bad) }.padding(16)
                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.bad).font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reason.hasPrefix("Ground stop") ? "Flights to \(code) grounded" : reason).font(.f(15, .bold)).foregroundStyle(Theme.bad)
                        Text("Advisory from Air Traffic Control. Expect holds until conditions improve.").font(.f(13)).foregroundStyle(.secondary)
                    }
                }.padding(16)
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
        let wheelsUp = s.estDep.addingTimeInterval(Double(s.taxiOutMin) * 60)
        let wheelsDown = s.estArr.addingTimeInterval(-Double(s.taxiInMin) * 60)
        let steps: [(String, String, Bool)] = [
            ("Departs gate", flight.depTime(s.estDep), s.phase != .scheduled && s.phase != .boarding),
            ("Takes off", flight.depTime(wheelsUp), s.actDep != nil),
            ("Lands", flight.arrTime(wheelsDown), s.actArr != nil),
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
            Text("Taxi out \(s.taxiOutMin) min · taxi in \(s.taxiInMin) min").font(.f(13)).foregroundStyle(.secondary).padding(.top, 12)
        }
    }

    private func forecastCard(_ s: LiveState) -> some View {
        section("Arrival forecast") {
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
        return section("Delay trend at \(flight.dep)") {
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
            weatherRow(flight.dep, s.depWeather)
            weatherRow(flight.arr, s.arrWeather)
            if let a = flight.depAirport, let b = flight.arrAirport {
                let diff = (b.timeZone.secondsFromGMT() - a.timeZone.secondsFromGMT()) / 3600
                row("Time zone change", diff == 0 ? "None" : "\(diff > 0 ? "+" : "")\(diff) h", last: true)
            }
        }
    }
    private func weatherRow(_ code: String, _ w: WeatherInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Image(systemName: w.symbol).symbolRenderingMode(.multicolor).frame(width: 24); Text("\(code) · \(w.condition)").font(.f(16, .semibold)); Spacer()
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
            row("Type", flight.aircraft); row("Tail number", flight.tail)
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

struct FlightMap: View {
    let flight: Flight
    let state: LiveState
    var body: some View {
        if let a = flight.depAirport, let b = flight.arrAirport {
            Map(initialPosition: .rect(boundingRect(Geo.path(a, b)))) {
                MapPolyline(coordinates: [a.coordinate, b.coordinate], contourStyle: .geodesic).stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 3, dash: [2, 6]))
                if state.progress > 0, state.progress < 1 {
                    let pts = Geo.path(a, b)
                    MapPolyline(coordinates: Array(pts.prefix(Int(state.progress * 64) + 1))).stroke(Color(red: 0.25, green: 0.6, blue: 1.0), lineWidth: 4)
                }
                Annotation(a.iata, coordinate: a.coordinate) { pin }
                Annotation(b.iata, coordinate: b.coordinate) { pin }
                if state.phase == .enRoute, let p = state.position {
                    Annotation("", coordinate: p) {
                        Image(systemName: "airplane").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                            .rotationEffect(.degrees(state.heading - 90)).shadow(color: .black.opacity(0.5), radius: 4)
                    }
                }
            }.mapStyle(.imagery(elevation: .realistic)).mapControls { }
        } else { Color.black }
    }
    private var pin: some View { Circle().fill(Color(red: 0.2, green: 0.5, blue: 1.0)).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2.5)) }
    private func boundingRect(_ pts: [CLLocationCoordinate2D]) -> MKMapRect {
        var rect = MKMapRect.null
        for p in pts { let mp = MKMapPoint(p); rect = rect.union(MKMapRect(x: mp.x, y: mp.y, width: 0.1, height: 0.1)) }
        return rect.insetBy(dx: -rect.width * 0.3 - 300_000, dy: -rect.height * 0.5 - 300_000)
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
