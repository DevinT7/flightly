import SwiftUI

// MARK: - Design tokens (sampled from Flighty's App Store screenshots)

enum Theme {
    /// Status colours as they appear on Flighty's rows: green times, amber "Tight", red "Running Late".
    static let good = Color(red: 0.12, green: 0.62, blue: 0.31)
    static let warn = Color(red: 0.95, green: 0.60, blue: 0.10)
    static let bad = Color(red: 0.88, green: 0.20, blue: 0.17)
    /// Flighty's brand violet (marketing "Fly smarter." + Passport).
    static let violet = Color(red: 0.42, green: 0.30, blue: 0.96)
    static let accent = Color(red: 0.10, green: 0.45, blue: 0.95)
    static let sheet = Color(.systemBackground)
    static let sheetGroup = Color(.secondarySystemBackground)
    static let hairline = Color(.separator).opacity(0.55)

    static func delayColor(_ m: Int) -> Color { m >= 45 ? bad : (m >= 15 ? warn : good) }
    static func severityColor(_ s: Int) -> Color { [good, Color.yellow, warn, bad][min(3, max(0, s))] }
}

extension Font {
    static func f(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

extension Flight {
    func fmt(_ date: Date, airport: Airport?) -> String {
        var f = Date.FormatStyle(date: .omitted, time: .shortened)
        f.timeZone = airport?.timeZone ?? .current
        return date.formatted(f).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{202F}", with: "")
    }
    func depTime(_ d: Date? = nil) -> String { fmt(d ?? schedDep, airport: depAirport) }
    func arrTime(_ d: Date? = nil) -> String { fmt(d ?? schedArr, airport: arrAirport) }
    func dayString(_ d: Date? = nil) -> String {
        var f = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        f.timeZone = depAirport?.timeZone ?? .current
        return (d ?? schedDep).formatted(f)
    }
    var cityTitle: String { "\(depAirport?.city ?? dep) to \(arrAirport?.city ?? arr)" }
    var spacedCode: String { "\(airlineCode) \(number)" }
}

func statusColor(_ s: LiveState) -> Color {
    switch s.phase {
    case .canceled: Theme.bad
    case .arrived, .landed: s.arrDelay >= 15 ? Theme.warn : Theme.good
    default: Theme.delayColor(s.depDelay)
    }
}

func statusText(_ s: LiveState) -> String {
    switch s.phase {
    case .scheduled, .boarding: s.depDelay >= 15 ? "Delayed \(s.depDelay)m" : (s.phase == .boarding ? "Boarding" : "On time")
    case .taxiingOut: "Taxiing"
    case .enRoute: "In air"
    default: s.phase.rawValue
    }
}

func shortDuration(_ interval: TimeInterval) -> String {
    let m = max(0, Int(interval / 60))
    if m >= 1440 { return "\(m / 1440)d \((m % 1440) / 60)h" }
    if m >= 60 { return "\(m / 60)h \(m % 60)m" }
    return "\(m)m"
}

// MARK: - Atoms

/// Real airline logo, loaded on demand (not bundled) from a public logo CDN; plain glyph while loading / if unavailable.
struct AirlineMark: View {
    let code: String
    var size: CGFloat = 16
    /// Codes the logo CDN has no artwork for (it serves its own placeholder), so show the neutral glyph instead.
    private static let noLogo: Set<String> = ["WN", "XX"]
    var body: some View {
        AsyncImage(url: Self.noLogo.contains(code.uppercased()) ? nil : URL(string: "https://images.kiwi.com/airlines/128/\(code.uppercased()).png")) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFit()
            default: Image(systemName: "airplane").resizable().scaledToFit().padding(size * 0.2).foregroundStyle(Color(.systemGray4))
            }
        }
        .frame(width: size, height: size)
    }
}

/// "NRT 6:10PM" chip with the small circular status glyph Flighty puts in front of the airport code.
struct AirportTimeChip: View {
    enum Kind { case takeoff, landing }
    let code: String, time: String, kind: Kind
    let color: Color?        // nil = scheduled / neutral
    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().fill(color ?? Color(.systemGray3)).frame(width: 14, height: 14)
                Image(systemName: kind == .takeoff ? "airplane.departure" : "airplane.arrival")
                    .font(.system(size: 7.5, weight: .bold)).foregroundStyle(.white)
            }
            Text(code).font(.f(13, .semibold)).foregroundStyle(color == nil ? Color.secondary : Color.primary)
            Text(time).font(.f(13, .semibold)).monospacedDigit().foregroundStyle(color ?? .primary)
        }
    }
}

struct StatusBadge: View {
    let text: String, color: Color
    var symbol: String? = "exclamationmark.triangle.fill"
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            Text(text.uppercased()).font(.f(11, .heavy)).tracking(0.3)
        }
        .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 5)
        .background(color, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct AvatarCircle: View {
    let name: String
    var size: CGFloat = 34
    var body: some View {
        let hue = Double(Seed(key: name).value % 360) / 360
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(Color(hue: hue, saturation: 0.7, brightness: 0.45))
            .frame(width: size, height: size)
            .background(Color(hue: hue, saturation: 0.25, brightness: 1.0), in: Circle())
    }
}

struct CircleButton: View {
    let symbol: String
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.primary)
            .frame(width: size, height: size).background(Color(.tertiarySystemFill), in: Circle())
    }
}

// MARK: - Flight row (the signature element of Flighty's list)

struct FlightRow: View {
    let flight: Flight
    let state: LiveState
    var now: Date
    var connection: (layover: String, tight: Bool)? = nil
    var owner: String? = nil

    private var near: Bool { flight.schedDep.timeIntervalSince(now) < 36 * 3600 }
    private var depColor: Color? {
        switch state.phase {
        case .scheduled where !near: nil
        case .canceled: Theme.bad
        default: state.depDelay >= 15 ? Theme.warn : Theme.good
        }
    }
    private var arrColor: Color? {
        switch state.phase {
        case .scheduled where !near: nil
        case .canceled: Theme.bad
        default: state.arrDelay >= 15 ? Theme.warn : Theme.good
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leading.frame(width: 48)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    AirlineMark(code: flight.airlineCode, size: 15)
                    Text(flight.spacedCode).font(.f(12, .medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    trailingTop
                }
                Text(flight.cityTitle).font(.f(17, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 14) {
                    AirportTimeChip(code: flight.dep, time: flight.depTime(state.estDep), kind: .takeoff, color: depColor)
                    AirportTimeChip(code: flight.arr, time: flight.arrTime(state.estArr), kind: .landing, color: arrColor)
                }
                if let c = connection {
                    HStack(spacing: 6) {
                        Text("\(c.layover) at \(flight.arr)").font(.f(12, .semibold)).foregroundStyle(c.tight ? Theme.warn : Theme.good)
                        if c.tight { Text("Tight").font(.f(11, .bold)).foregroundStyle(Theme.warn).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.warn.opacity(0.15), in: Capsule()) }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var leading: some View {
        if let owner {
            VStack(spacing: 3) {
                AvatarCircle(name: owner, size: 34)
                if state.phase == .enRoute { Text("IN AIR").font(.f(8.5, .heavy)).foregroundStyle(.secondary) }
            }
        } else {
            switch state.phase {
            case .enRoute:
                VStack(spacing: 3) { Image(systemName: "airplane").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent).rotationEffect(.degrees(-0))
                    Text("IN AIR").font(.f(8.5, .heavy)).foregroundStyle(Theme.accent) }
            case .landed, .arrived:
                VStack(spacing: 3) { Image(systemName: "checkmark.circle.fill").font(.system(size: 17)).foregroundStyle(Theme.good)
                    Text("LANDED").font(.f(8.5, .heavy)).foregroundStyle(.secondary) }
            case .canceled:
                VStack(spacing: 3) { Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(Theme.bad)
                    Text("CANCELED").font(.f(8, .heavy)).foregroundStyle(Theme.bad) }
            default:
                let secs = state.estDep.timeIntervalSince(now)
                if secs > 0 && secs < 72 * 3600 {
                    VStack(spacing: 1) {
                        let m = Int(secs / 60)
                        Text(m >= 60 ? "\(m / 60)h" : "\(m)").font(.f(24, .bold)).monospacedDigit()
                        Text(m >= 60 ? "\(m % 60) MIN" : "MINUTES").font(.f(8.5, .heavy)).foregroundStyle(.secondary)
                    }
                } else { Color.clear }
            }
        }
    }

    @ViewBuilder private var trailingTop: some View {
        switch state.phase {
        case .enRoute:
            (Text("Landing in ").foregroundStyle(.secondary) + Text(shortDuration(state.estArr.timeIntervalSince(now))).foregroundStyle(state.arrDelay >= 15 ? Theme.warn : Theme.good).bold()).font(.f(11.5))
        case .canceled:
            Text("Canceled").font(.f(11.5, .bold)).foregroundStyle(Theme.bad)
        default:
            if near && state.depDelay >= 15 { Text("Delayed \(state.depDelay)m").font(.f(11.5, .bold)).foregroundStyle(state.depDelay >= 45 ? Theme.bad : Theme.warn) }
            else { Text(flight.dayString()).font(.f(11.5)).foregroundStyle(.secondary) }
        }
    }
}

// MARK: - Flat list helpers (Flighty uses hairline-separated groups, not boxed cards)

struct FlatSection<Content: View>: View {
    let title: String?
    var accessory: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title).font(.f(13, .semibold)).foregroundStyle(.secondary).textCase(.uppercase).tracking(0.4)
                    .padding(.horizontal, 20).padding(.bottom, 8)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 16).padding(.vertical, 4)
                .background(Theme.sheetGroup, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
        }
    }
}

struct Line: View {
    let k: String, v: String
    var vColor: Color = .primary
    var body: some View {
        HStack { Text(k).font(.f(15)); Spacer(); Text(v).font(.f(15, .semibold)).foregroundStyle(vColor).multilineTextAlignment(.trailing) }
            .padding(.vertical, 11)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }
}

struct KeyValue: View {
    let k: String, v: String
    var body: some View { Line(k: k, v: v) }
}

struct StatTile: View {
    let value: String, label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.f(26, .bold)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.f(12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(Theme.sheetGroup, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct AirportPicker: View {
    @Binding var selection: String
    let title: String
    @State private var show = false
    var body: some View {
        Button { show = true } label: {
            HStack { Text(title).foregroundStyle(.primary); Spacer()
                Text(selection.isEmpty ? "Select" : "\(selection) · \(AirportDB.airport(selection)?.city ?? "")").foregroundStyle(.secondary) }
        }.sheet(isPresented: $show) { AirportSearchSheet(selection: $selection) }
    }
}

struct AirportSearchSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    var body: some View {
        NavigationStack {
            List(AirportDB.search(q)) { a in
                Button { selection = a.iata; dismiss() } label: {
                    HStack { Text(a.iata).font(.headline.monospaced()).frame(width: 52, alignment: .leading)
                        VStack(alignment: .leading) { Text(a.city).foregroundStyle(.primary); Text(a.name).font(.caption).foregroundStyle(.secondary) } }
                }
            }
            .searchable(text: $q, prompt: "City, airport or code")
            .navigationTitle("Airport").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Small pill kept for lists that still need one (airports board).
struct StatusPill: View {
    let text: String, color: Color
    var body: some View {
        Text(text).font(.f(12, .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule()).foregroundStyle(color)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    var symbol: String? = nil
    @ViewBuilder var content: Content
    var body: some View { FlatSection(title: title) { content.padding(.vertical, 8) } }
}

// MARK: - Aircraft photos

/// Resolves a real photo of an aircraft type from Wikipedia's page image (hosted on Wikimedia Commons, freely licensed).
/// Loaded on demand and cached for the session; nothing is bundled.
actor AircraftPhotoCache {
    static let shared = AircraftPhotoCache()
    private var cache: [String: URL?] = [:]

    static func wikiTitle(for type: String) -> String? {
        let t = type.lowercased()
        if t.contains("737") && t.contains("max") { return "Boeing_737_MAX" }
        if t.contains("737") { return "Boeing_737_Next_Generation" }
        if t.contains("787") { return "Boeing_787_Dreamliner" }
        if t.contains("777") { return "Boeing_777" }
        if t.contains("a350") { return "Airbus_A350" }
        if t.contains("a330") { return "Airbus_A330" }
        if t.contains("a321") { return "Airbus_A321" }
        if t.contains("a320") { return "Airbus_A320neo_family" }
        if t.contains("a220") { return "Airbus_A220" }
        if t.contains("e175") || t.contains("embraer") { return "Embraer_E-Jet_family" }
        return nil
    }

    func url(for type: String) async -> URL? {
        if let hit = cache[type] { return hit }
        var result: URL?
        if let title = Self.wikiTitle(for: type),
           let api = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(title)") {
            var req = URLRequest(url: api)
            req.setValue("FlightlyApp/1.0 (personal flight tracker experiment)", forHTTPHeaderField: "User-Agent")
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let thumb = (json["thumbnail"] as? [String: Any])?["source"] as? String {
                // Ask for a larger rendition than the default 330px thumbnail.
                result = URL(string: thumb.replacingOccurrences(of: "/330px-", with: "/960px-"))
            }
        }
        cache[type] = result
        return result
    }
}

struct AircraftPhoto: View {
    let type: String?
    var tail: String? = nil
    var height: CGFloat = 170
    var cornerRadius: CGFloat = 16
    @State private var url: URL?
    @State private var credit = ""
    @State private var page: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: placeholder
                    default: Color.white.opacity(0.25).overlay(ProgressView())
                    }
                }
            } else { placeholder }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            if url != nil {
                Group {
                    if let page { Link(credit, destination: page) } else { Text(credit) }
                }
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2).background(.black.opacity(0.45), in: Capsule()).padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: "\(type ?? "")|\(tail ?? "")") {
            // Prefer a real photo of this exact aircraft (by registration); fall back to a photo of the type.
            if let tail, let p = await TailPhotoCache.shared.photo(forRegistration: tail) {
                url = p.url; credit = "Photo: \(p.photographer) · Planespotters.net"; page = p.page; return
            }
            guard let type else { return }
            url = await AircraftPhotoCache.shared.url(for: type)
            credit = "Type photo: Wikimedia Commons"; page = nil
        }
    }
    private var placeholder: some View {
        Image(systemName: "airplane").font(.system(size: 64, weight: .light)).foregroundStyle(.white.opacity(0.8)).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
