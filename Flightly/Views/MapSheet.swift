import SwiftUI
import UIKit

enum SheetDetent { case small, medium, large }

enum Screen {
    static var topInset: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets.top ?? 59
    }
}

/// Flighty's signature scaffold: a full-screen map with a persistent white sheet that runs *under* the
/// floating tab bar. Partial detents float with a margin; the large detent goes edge to edge below the status bar.
struct MapSheet<Map: View, Controls: View, Header: View, Content: View>: View {
    @Binding var detent: SheetDetent
    @ViewBuilder var map: Map
    @ViewBuilder var controls: Controls
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    var onRefresh: (() async -> Void)? = nil
    /// Shown in the floating sheet's margins and rounded corners; match it to the map style (black for the space globe).
    var backdrop: Color = .black

    @GestureState private var drag: CGFloat = 0
    private let minHeight: CGFloat = 176

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height
            let top = Screen.topInset
            let maxH = H - top
            let base: CGFloat = detent == .small ? minHeight : (detent == .medium ? H * 0.56 : maxH)
            let height = min(maxH, max(minHeight, base + drag))
            let isLarge = height > maxH - 60
            let margin: CGFloat = isLarge ? 0 : 8

            ZStack(alignment: .bottom) {
                // Map ends at the sheet's top edge so its camera centres on the visible area; the small
                // inset keeps the required "Maps · Legal" attribution clear of the sheet's rounded corner.
                map
                    .safeAreaPadding(.bottom, 18)
                    .frame(height: max(120, H - height))
                    .frame(maxHeight: .infinity, alignment: .top)
                controls.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.top, top + 8).padding(.trailing, 14)

                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Capsule().fill(Color(.systemGray4)).frame(width: 36, height: 5).padding(.top, 6).padding(.bottom, 8)
                        header
                    }
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    ScrollView {
                        content.padding(.bottom, 130)
                    }
                    .scrollDisabled(detent != .large)
                    .refreshable { await onRefresh?() }
                }
                .frame(maxWidth: .infinity).frame(height: height, alignment: .top)
                .background(Theme.sheet, in: UnevenRoundedRectangle(topLeadingRadius: 38, bottomLeadingRadius: isLarge ? 0 : 38, bottomTrailingRadius: isLarge ? 0 : 38, topTrailingRadius: 38, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 18, y: -2)
                .padding(.horizontal, margin).padding(.bottom, margin)
                .simultaneousGesture(detent == .large ? nil : dragGesture)
            }
            .frame(width: geo.size.width, height: H)
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: detent)
        }
        .background(backdrop.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: backdrop)
        .ignoresSafeArea()
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8).updating($drag) { v, s, _ in s = -v.translation.height }.onEnded { v in
            let dy = v.predictedEndTranslation.height
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                if dy < -90 { detent = detent == .small ? .medium : .large } else if dy > 90 { detent = detent == .large ? .medium : .small }
            }
        }
    }
}

/// Round map-overlay button (Flighty's right-hand stack).
struct GlassMapButton: View {
    let symbol: String
    /// Whether the map behind the button is dark (satellite globe) or light (standard map); keeps the icon legible.
    var onDarkMap: Bool = true
    var body: some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(onDarkMap ? Color.white : Color.black.opacity(0.8)).frame(width: 42, height: 42)
            .glassEffect(.regular.interactive(), in: Circle())
            .environment(\.colorScheme, onDarkMap ? .dark : .light)
    }
}

/// Profile avatar used in sheet headers (initials on a sky-blue gradient).
struct ProfileAvatar: View {
    let name: String
    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
        Text(initials.isEmpty ? "ME" : initials).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(LinearGradient(colors: [Color(red: 0.45, green: 0.78, blue: 0.98), Color(red: 0.30, green: 0.60, blue: 0.95)], startPoint: .top, endPoint: .bottom), in: Circle())
    }
}

struct OutlineCircleButton: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(.primary).frame(width: 46, height: 46)
            .background(Color(.systemBackground), in: Circle())
            .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
    }
}
