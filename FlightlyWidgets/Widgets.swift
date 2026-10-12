import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - Home / Lock Screen widget

struct FlightEntry: TimelineEntry { let date: Date; let flight: FlightSnapshot? }

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> FlightEntry { .init(date: .now, flight: sample) }
    func getSnapshot(in context: Context, completion: @escaping (FlightEntry) -> Void) { completion(.init(date: .now, flight: SnapshotStore.load().first ?? sample)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FlightEntry>) -> Void) {
        let f = SnapshotStore.load().first
        completion(Timeline(entries: [FlightEntry(date: .now, flight: f)], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
    var sample: FlightSnapshot { .init(flightCode: "DL1486", from: "AUS", to: "ATL", depTime: .now.addingTimeInterval(7200), arrTime: .now.addingTimeInterval(16000), status: "On time", delayMinutes: 0, gate: "B12", progress: 0) }
}

struct NextFlightView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FlightEntry
    var body: some View {
        Group {
            if let f = entry.flight {
                switch family {
                case .accessoryInline: Text("✈︎ \(f.flightCode) \(f.from)→\(f.to) \(f.depTime.formatted(date: .omitted, time: .shortened))")
                case .accessoryCircular:
                    Gauge(value: f.progress) { Image(systemName: "airplane") } currentValueLabel: { Text(f.to).font(.caption2) }.gaugeStyle(.accessoryCircular)
                case .accessoryRectangular:
                    VStack(alignment: .leading) { Text("\(f.from) → \(f.to)").font(.headline); Text("\(f.flightCode) · \(f.status)"); Text("Gate \(f.gate) · \(f.depTime.formatted(date: .omitted, time: .shortened))") }
                case .systemMedium: medium(f)
                default: small(f)
                }
            } else { Text("No upcoming flights").font(.caption) }
        }
        .widgetURL(entry.flight.flatMap { URL(string: "flightly://flight?id=\($0.flightID)") })
    }
    private func small(_ f: FlightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(f.flightCode).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(f.from) → \(f.to)").font(.title3.bold())
            Text(f.depTime, style: .time).font(.title2.monospacedDigit())
            Spacer()
            Text(f.delayMinutes >= 15 ? "Delayed \(f.delayMinutes)m" : f.status).font(.caption.bold()).foregroundStyle(f.delayMinutes >= 15 ? .orange : .green)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func medium(_ f: FlightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(f.flightCode).font(.subheadline.bold()); Spacer(); Text(f.delayMinutes >= 15 ? "Delayed \(f.delayMinutes)m" : f.status).font(.caption.bold()).foregroundStyle(f.delayMinutes >= 15 ? .orange : .green) }
            HStack { Text(f.from).font(.largeTitle.bold()); Spacer(); Image(systemName: "airplane"); Spacer(); Text(f.to).font(.largeTitle.bold()) }
            ProgressView(value: f.progress)
            HStack { Text("Gate \(f.gate)"); Spacer(); Text("Departs \(f.depTime.formatted(date: .omitted, time: .shortened))") }.font(.caption)
        }
    }
}

struct NextFlightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextFlight", provider: Provider()) { NextFlightView(entry: $0).containerBackground(.fill.tertiary, for: .widget) }
            .configurationDisplayName("Next flight").description("Live status for your next flight.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Live Activity presentation model

private let flGreen = Color(red: 0.25, green: 0.88, blue: 0.50)
private let flAmber = Color(red: 1.0, green: 0.80, blue: 0.20)
private let flRed = Color(red: 1.0, green: 0.38, blue: 0.34)

private func hm(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{202F}", with: "") }

/// Everything the three presentations need, derived once from the state so they stay consistent.
struct LiveView {
    let a: FlightActivityAttributes
    let s: FlightActivityAttributes.ContentState

    var tint: Color {
        switch s.phase {
        case .canceled: flRed
        case .landed, .arrived: s.arrDelayMinutes >= 15 ? flAmber : flGreen
        default: s.delayMinutes >= 15 ? flAmber : flGreen
        }
    }
    private func dur(_ m: Int) -> String { m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m" }
    var depStatus: String {
        if s.phase == .canceled { return "Canceled" }
        return s.delayMinutes >= 15 ? "Delayed \(dur(s.delayMinutes))" : "On Time"
    }
    var arrStatus: String {
        if s.phase == .canceled { return "" }
        if s.arrDelayMinutes >= 15 { return "\(dur(s.arrDelayMinutes)) Late" }
        if s.arrDelayMinutes <= -5 { return "\(dur(-s.arrDelayMinutes)) Early" }
        return "On Time"
    }
    /// The chip at the trailing side: departure gate before takeoff, arrival gate in the air, baggage once landed.
    var chip: String {
        switch s.phase {
        case .scheduled, .boarding, .taxiing: s.depGate
        case .enRoute: s.arrGate
        case .landed, .arrived: "Bag \(s.baggage)"
        case .canceled: "—"
        }
    }
    var chipIsBaggage: Bool { s.phase == .landed || s.phase == .arrived }
    /// Moment the countdown runs to, and what it is counting to.
    var target: Date { (s.phase == .enRoute ? s.estArr : s.estDep).addingTimeInterval(-s.clockOffset) }
    var caption: String {
        switch s.phase {
        case .scheduled: "UNTIL DEPARTURE"
        case .boarding: "UNTIL DEPARTURE · BOARDING"
        case .taxiing: "TAXIING TO RUNWAY"
        case .enRoute: "UNTIL GATE ARRIVAL"
        case .landed: "LANDED · GATE \(s.arrGate)"
        case .arrived: "ARRIVED · BAGGAGE CLAIM \(s.baggage)"
        case .canceled: "FLIGHT CANCELED"
        }
    }
    /// Short label for the compact island when there is no countdown.
    var shortPhase: String {
        switch s.phase {
        case .taxiing: "Taxiing"
        case .landed: "Landed"
        case .arrived: "Arrived"
        case .canceled: "Canceled"
        default: ""
        }
    }
    var showsCountdown: Bool { s.phase == .scheduled || s.phase == .boarding || s.phase == .enRoute }
    var phrase: String {
        switch s.phase {
        case .scheduled: "Departs Gate in"
        case .boarding: "Boarding · departs in"
        case .taxiing: "Taxiing"
        case .enRoute: "Lands in"
        case .landed: "Landed"
        case .arrived: "Arrived"
        case .canceled: "Canceled"
        }
    }
    private func term(_ t: String) -> String { t.allSatisfy(\.isNumber) ? "T\(t)" : "Term \(t)" }
    var leftTerminalLine: String { "\(term(s.depTerminal)) • \(depStatus)" }
    var rightLine: String { s.phase == .canceled ? "" : (arrStatus.isEmpty ? "" : "\(arrStatus) • \(term(s.arrTerminal))") }
}

struct GateChip: View {
    let text: String
    var baggage = false
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: baggage ? "suitcase.rolling.fill" : "door.left.hand.open").font(.system(size: 9, weight: .bold))
            Text(baggage ? text.replacingOccurrences(of: "Bag ", with: "") : text).font(.system(size: 12, weight: .heavy))
        }
        .foregroundStyle(.black).padding(.horizontal, 7).padding(.vertical, 3).background(flAmber, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Curved progress line with the aircraft riding it (Flighty's lock-screen gauge).
struct FlightArc: View {
    let progress: Double
    let tint: Color

    private func curve(_ size: CGSize) -> (start: CGPoint, control: CGPoint, end: CGPoint) {
        (CGPoint(x: 0, y: size.height), CGPoint(x: size.width / 2, y: -size.height * 0.6), CGPoint(x: size.width, y: size.height))
    }
    private func point(_ c: (start: CGPoint, control: CGPoint, end: CGPoint), _ t: Double) -> CGPoint {
        let u = 1 - t
        let x: Double = u * u * Double(c.start.x) + 2 * u * t * Double(c.control.x) + t * t * Double(c.end.x)
        let y: Double = u * u * Double(c.start.y) + 2 * u * t * Double(c.control.y) + t * t * Double(c.end.y)
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        GeometryReader { g in
            let c = curve(g.size)
            let t = min(1, max(0, progress))
            let path = Path { p in p.move(to: c.start); p.addQuadCurve(to: c.end, control: c.control) }
            let pos = point(c, t)
            ZStack {
                path.stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
                path.trimmedPath(from: 0, to: t).stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                Image(systemName: "airplane").font(.system(size: 12, weight: .bold)).foregroundStyle(tint).position(pos)
            }
        }
    }
}

// MARK: - Lock Screen

struct FlightLiveActivityLockView: View {
    let ctx: ActivityViewContext<FlightActivityAttributes>
    var body: some View {
        let v = LiveView(a: ctx.attributes, s: ctx.state)
        VStack(spacing: 8) {
            HStack {
                Text(ctx.attributes.flightCode).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.65)); Spacer()
                if ctx.isStale { Label("Updating…", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55)) }
                else { Text(ctx.attributes.confirmation).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.5)) }
            }
            HStack(spacing: 6) {
                HStack(spacing: 4) { Text(ctx.attributes.from).fontWeight(.heavy).foregroundStyle(.white); Text(hm(ctx.state.estDep)).fontWeight(.semibold).foregroundStyle(v.tint) }
                Spacer(minLength: 2)
                Image(systemName: "airplane").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 2)
                HStack(spacing: 4) { Text(hm(ctx.state.estArr)).fontWeight(.semibold).foregroundStyle(v.tint); Text(ctx.attributes.to).fontWeight(.heavy).foregroundStyle(.white) }
            }.font(.system(size: 17)).monospacedDigit()
            HStack {
                Text(v.leftTerminalLine).foregroundStyle(v.tint); Spacer()
                Text(v.rightLine).foregroundStyle(v.tint)
            }.font(.system(size: 11, weight: .semibold))
            FlightArc(progress: ctx.state.progress, tint: v.tint).frame(height: 26).padding(.horizontal, 24)
            VStack(spacing: 1) {
                if v.showsCountdown {
                    Text(v.target, style: .relative).font(.system(size: 20, weight: .bold)).monospacedDigit().foregroundStyle(.white).multilineTextAlignment(.center)
                } else {
                    Text(v.phrase).font(.system(size: 20, weight: .bold)).foregroundStyle(v.tint)
                }
                Text(v.caption).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .opacity(ctx.isStale ? 0.85 : 1)
        .activityBackgroundTint(Color(white: 0.06, opacity: 0.92))
        .widgetURL(ctx.attributes.deepLink)
    }
}

// MARK: - Live Activity + Dynamic Island

struct FlightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { ctx in
            FlightLiveActivityLockView(ctx: ctx)
        } dynamicIsland: { ctx in
            let v = LiveView(a: ctx.attributes, s: ctx.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ctx.attributes.from).font(.system(size: 20, weight: .heavy))
                        Text(hm(ctx.state.estDep)).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(v.tint)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(ctx.attributes.to).font(.system(size: 20, weight: .heavy))
                        Text(hm(ctx.state.estArr)).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(v.tint)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(ctx.attributes.flightCode).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Text(v.leftTerminalLine).font(.system(size: 11, weight: .semibold)).foregroundStyle(v.tint)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        FlightArc(progress: ctx.state.progress, tint: v.tint).frame(height: 18).padding(.horizontal, 10)
                        HStack(spacing: 4) {
                            Image(systemName: ctx.state.phase == .enRoute ? "airplane" : "play.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(v.tint)
                            if v.showsCountdown {
                                (Text(v.phrase + " ") + Text(v.target, style: .relative)).font(.system(size: 14, weight: .bold)).foregroundStyle(v.tint).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                            } else { Text(v.phrase).font(.system(size: 14, weight: .bold)).foregroundStyle(v.tint) }
                            Spacer(minLength: 4)
                            if ctx.isStale { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11)).foregroundStyle(.secondary) }
                            GateChip(text: v.chip, baggage: v.chipIsBaggage)
                        }
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Circle().fill(v.tint).frame(width: 13, height: 13).overlay(Image(systemName: ctx.state.phase == .enRoute ? "airplane" : "play.fill").font(.system(size: 6, weight: .black)).foregroundStyle(.black))
                    if v.showsCountdown {
                        Text(v.target, style: .timer).font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(v.tint).frame(maxWidth: 46, alignment: .leading).lineLimit(1).minimumScaleFactor(0.6)
                    } else { Text(v.shortPhase).font(.system(size: 11, weight: .bold)).foregroundStyle(v.tint).lineLimit(1) }
                }
            } compactTrailing: {
                GateChip(text: v.chip, baggage: v.chipIsBaggage)
            } minimal: {
                ZStack { Circle().fill(v.tint); Image(systemName: "airplane").font(.system(size: 9, weight: .black)).foregroundStyle(.black) }
            }
            .keylineTint(v.tint)
            .widgetURL(ctx.attributes.deepLink)
        }
    }
}

@main
struct FlightlyWidgetBundle: WidgetBundle {
    var body: some Widget { NextFlightWidget(); FlightLiveActivity() }
}
