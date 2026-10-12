import SwiftUI
import SwiftData

enum FriendLink {
    struct Payload: Codable { var name: String; var airline: String; var number: String; var dep: String; var arr: String; var depTime: Date; var arrTime: Date }

    static func url(for f: Flight, name: String) -> URL {
        let p = Payload(name: name, airline: f.airlineCode, number: f.number, dep: f.dep, arr: f.arr, depTime: f.schedDep, arrTime: f.schedArr)
        let data = (try? JSONEncoder().encode(p)) ?? Data()
        var c = URLComponents(); c.scheme = "flightly"; c.host = "friend"
        c.queryItems = [URLQueryItem(name: "d", value: data.base64EncodedString())]
        return c.url!
    }

    @discardableResult
    static func handle(_ url: URL, context: ModelContext) -> String? {
        guard url.scheme == "flightly", url.host == "friend",
              let d = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" })?.value,
              let data = Data(base64Encoded: d), let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let f = Flight(airlineCode: p.airline, number: p.number, dep: p.dep, arr: p.arr, schedDep: p.depTime, schedArr: p.arrTime, source: .friend, ownerName: p.name)
        context.insert(f); try? context.save()
        return p.name
    }
}

/// "Friends' Flights" – a map-less list with a search field and avatar filter chips, as in Flighty's Friends tab.
struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Flight.schedDep) private var all: [Flight]
    @AppStorage("my_name") private var myName = "Me"
    @State private var filter: String? = nil
    @State private var showAdd = false
    @State private var link = ""
    @State private var msg: String?
    @State private var query = ""

    private var friendFlights: [Flight] { all.filter { $0.ownerName != nil } }
    private var names: [String] { Array(Set(friendFlights.compactMap { $0.ownerName })).sorted() }
    private var mine: [Flight] { all.filter { $0.ownerName == nil && !$0.isPast } }
    private var shown: [Flight] {
        friendFlights.filter { (filter == nil || $0.ownerName == filter) && (query.isEmpty || $0.cityTitle.localizedCaseInsensitiveContains(query) || $0.code.localizedCaseInsensitiveContains(query) || ($0.ownerName ?? "").localizedCaseInsensitiveContains(query)) }
            .sorted { $0.schedDep < $1.schedDep }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Text("Friends' Flights").font(.f(32, .bold))
                        Spacer()
                        Menu {
                            ForEach(mine) { f in ShareLink(item: FriendLink.url(for: f, name: myName), message: Text("Follow my flight \(f.spacedCode) \(f.dep)→\(f.arr) in Flightly")) { Label("\(f.spacedCode) · \(f.dep)→\(f.arr)", systemImage: "square.and.arrow.up") } }
                            if mine.isEmpty { Text("Add an upcoming flight to share it") }
                        } label: { OutlineCircleButton(symbol: "square.and.arrow.up") }
                        Button { showAdd = true } label: { OutlineCircleButton(symbol: "person.badge.plus") }.buttonStyle(.plain)
                    }.padding(.horizontal, 20).padding(.top, 8)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                        TextField("Search to add flights", text: $query).font(.f(15))
                    }.padding(.horizontal, 12).frame(height: 38).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous)).padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("All", name: nil)
                            ForEach(names, id: \.self) { chip($0, name: $0) }
                        }.padding(.horizontal, 16)
                    }

                    if shown.isEmpty {
                        VStack(spacing: 8) {
                            Text("No friends' flights yet").font(.f(17, .bold))
                            Text("When a friend shares a flight with you it appears here with live status. Tap the person icon to paste their link.").font(.f(14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.padding(40)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, f in
                            NavigationLink { FlightDetailView(flight: f) } label: {
                                FlightRow(flight: f, state: model.live(f), now: model.clock, owner: f.ownerName)
                            }.buttonStyle(.plain)
                            .contextMenu { Button("Stop following", systemImage: "person.badge.minus", role: .destructive) { context.delete(f) } }
                            if i < shown.count - 1 { Divider().padding(.leading, 60) }
                        }
                    }.padding(.horizontal, 16)
                }.padding(.bottom, 110)
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("Add a friend's flight", isPresented: $showAdd) {
                TextField("flightly://friend?d=…", text: $link)
                Button("Add") { if let u = URL(string: link), let n = FriendLink.handle(u, context: context) { msg = "Now following \(n)." } else { msg = "That link isn't valid." }; link = "" }
                Button("Cancel", role: .cancel) {}
            }
            .alert(msg ?? "", isPresented: Binding(get: { msg != nil }, set: { if !$0 { msg = nil } })) { Button("OK") {} }
        }
    }

    private func chip(_ t: String, name: String?) -> some View {
        let sel = filter == name
        return Button { filter = name } label: {
            HStack(spacing: 6) {
                if let name { AvatarCircle(name: name, size: 20) }
                Text(t).font(.f(14, .semibold))
            }
            .padding(.horizontal, name == nil ? 14 : 8).padding(.trailing, name == nil ? 0 : 6).frame(height: 34)
            .foregroundStyle(sel ? Color(.systemBackground) : .primary)
            .background(sel ? Color.primary : Color(.tertiarySystemFill), in: Capsule())
        }
    }
}
