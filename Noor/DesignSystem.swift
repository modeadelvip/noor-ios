import SwiftUI
import AVFoundation
import Speech

// MARK: - palette (the same dark/gold identity as the Android app)

enum P {
    static let bg = Color(hex: 0x070C16)
    static let card = Color(hex: 0x101A2B)
    static let card2 = Color(hex: 0x152238)
    static let surface = Color(hex: 0x0D1420)
    static let gold = Color(hex: 0xE7BE72)
    static let teal = Color(hex: 0x3FBF9F)
    static let red = Color(hex: 0xE05A55)
    static let amber = Color(hex: 0xD48A2A)
    static let sub = Color(hex: 0x8A94A6)
    static let txt = Color(hex: 0xF2F5FA)
    static let paper = Color(hex: 0xFFFDF7)
    static let ink = Color(hex: 0x1B1a17)
    static let inkSoft = Color(hex: 0x6B6355)
    static let paperRed = Color(hex: 0xB3261E)
    static let paperAmber = Color(hex: 0xB36B00)
    static let paperGreen = Color(hex: 0x1B6B3A)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - root

struct RootView: View {
    @StateObject private var app = AppState()
    @State private var tab = 0
    @State private var ready = false

    var body: some View {
        ZStack {
            P.bg.ignoresSafeArea()
            if !ready {
                SplashView()
            } else {
                VStack(spacing: 0) {
                    header
                    TabView(selection: $tab) {
                        NavigationStack { TimesView() }.tag(0)
                        NavigationStack { MushafView() }.tag(1)
                        NavigationStack { FreeReciteView() }.tag(2)
                        NavigationStack { AdhkarView() }.tag(3)
                        NavigationStack { QiblaView() }.tag(4)
                        NavigationStack { MoreView2() }.tag(5)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    tabBar
                }
            }
        }
        .environmentObject(app)
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.dark)
        .onAppear { AudioKeepAlive.shared.activate() }
        .onChange(of: app.tabRequest) { _, t in
            if let t = t { tab = t; app.tabRequest = nil }
        }
        .task {
            // warm the whole-Quran index once, so «فحص» is instant later
            if Quran.shared.surahs.isEmpty {
                app.lastCrash = "تعذّر تحميل بيانات القرآن (quran.json مفقود من الحزمة)"
            }
            ready = true
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("نُور").font(.system(size: 26, weight: .bold)).foregroundStyle(P.gold)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("مواقيت · قرآن · أذكار · تلاوة").font(.system(size: 11)).foregroundStyle(P.sub)
                Text("نور ١٫٠ — آيفون").font(.system(size: 9)).foregroundStyle(P.sub.opacity(0.7))
            }
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 8)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            item("🕌", "المواقيت", 0)
            item("📖", "القرآن", 1)
            item("🎙", "تلاوة", 2)
            item("📿", "الأذكار", 3)
            item("🧭", "القبلة", 4)
            item("⋯", "المزيد", 5)
        }
        .padding(.top, 7)
        .padding(.bottom, 2)
        .background(P.card.ignoresSafeArea())
    }

    private func item(_ icon: String, _ title: String, _ i: Int) -> some View {
        Button { withAnimation(.easeOut(duration: 0.12)) { tab = i } } label: {
            VStack(spacing: 2) {
                Text(icon).font(.system(size: 18))
                Text(title).font(.system(size: 8.5, weight: tab == i ? .bold : .regular))
                    .foregroundStyle(tab == i ? P.gold : P.sub)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("نُور").font(.system(size: 44, weight: .bold)).foregroundStyle(P.gold)
            Text("بسم الله الرحمن الرحيم").font(.system(size: 13)).foregroundStyle(P.sub)
            ProgressView().tint(P.gold).padding(.top, 6)
        }
    }
}

// MARK: - app state

final class AppState: ObservableObject {
    @Published var hideTashkeel = true
    @Published var session: Session?
    @Published var lastCrash = ""
    @Published var jumpGlobal: Int? = nil       // set by «كمّل من الآية اللي بعدها»
    @Published var tabRequest: Int? = nil       // ask RootView to switch tab
    init() {
        if let data = UserDefaults.standard.data(forKey: "lastCrash"),
           let t = String(data: data, encoding: .utf8) { lastCrash = t }
    }
    func record(_ text: String) {
        lastCrash = text
        UserDefaults.standard.set(Data(text.utf8), forKey: "lastCrash")
    }
}

// MARK: - small components

struct Card<Content: View>: View {
    var fill: Color
    let content: Content

    init(fill: Color = P.card, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.content = content()
    }
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
    }
}

struct GoldButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: 0x1B1408))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(P.gold))
        }
        .buttonStyle(.plain)
    }
}

struct GrayButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(P.txt)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(P.card2))
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    var title: String
    var on: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: on ? .bold : .regular))
                .foregroundStyle(on ? Color(hex: 0x1B1408) : P.sub)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(on ? P.gold : P.card2))
        }
        .buttonStyle(.plain)
    }
}

/// level bar built from plain rectangles (never throws, works with any appearance)
struct LevelBar: View {
    var level: Int
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(P.card2)
                Capsule()
                    .fill(level > 3 ? P.teal : P.sub.opacity(0.5))
                    .frame(width: max(6, geo.size.width * CGFloat(min(100, max(0, level))) / 100))
            }
        }
        .frame(height: 8)
    }
}
