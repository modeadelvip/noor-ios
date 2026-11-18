import Foundation

// MARK: - everything the app remembers (UserDefaults, no account, no cloud)

public final class Store: ObservableObject {
    public static let shared = Store()
    private let d = UserDefaults.standard

    // ---- prayer settings
    @Published public var lat: Double { didSet { d.set(lat, forKey: "lat") } }
    @Published public var lon: Double { didSet { d.set(lon, forKey: "lon") } }
    @Published public var method: Int { didSet { d.set(method, forKey: "method") } }
    @Published public var offsets: [Int] { didSet { d.set(offsets, forKey: "offsets") } }
    @Published public var alarmsOn: Bool { didSet { d.set(alarmsOn, forKey: "alarms") } }
    @Published public var preMinutes: Int { didSet { d.set(preMinutes, forKey: "pre") } }
    @Published public var reciter: Int { didSet { d.set(reciter, forKey: "reciter") } }
    @Published public var fontSize: Int { didSet { d.set(fontSize, forKey: "font") } }
    @Published public var cityName: String { didSet { d.set(cityName, forKey: "city") } }

    // ---- reading progress
    @Published public var khatmaDays: Int { didSet { d.set(khatmaDays, forKey: "khatma") } }
    @Published public var khatmaDone: [Int] { didSet { d.set(khatmaDone, forKey: "khatmaDone") } }
    @Published public var streak: Int { didSet { d.set(streak, forKey: "streak") } }
    @Published public var bestStreak: Int { didSet { d.set(bestStreak, forKey: "best") } }
    @Published public var lastReadGlobal: Int { didSet { d.set(lastReadGlobal, forKey: "lastGlobal") } }
    @Published public var bookmarks: [Int] { didSet { d.set(bookmarks, forKey: "marks") } }
    @Published public var notes: [String: String] { didSet { d.set(notes, forKey: "notes") } }
    @Published public var tasbeeh: Int { didSet { d.set(tasbeeh, forKey: "tasbeeh") } }
    @Published public var tasbeehTarget: Int { didSet { d.set(tasbeehTarget, forKey: "tasbeehTarget") } }

    // ---- recitation history
    public struct Attempt: Codable, Identifiable {
        public var id = UUID()
        public var date: Date
        public var sura: Int
        public var percent: Int
        public var haraka: Int
    }
    @Published public var attempts: [Attempt] { didSet { saveAttempts() } }

    private init() {
        lat = d.object(forKey: "lat") as? Double ?? 30.5965
        lon = d.object(forKey: "lon") as? Double ?? 31.5021
        method = d.object(forKey: "method") as? Int ?? 0
        offsets = d.object(forKey: "offsets") as? [Int] ?? [0, 0, 0, 0, 0, 0]
        alarmsOn = d.object(forKey: "alarms") as? Bool ?? true
        preMinutes = d.object(forKey: "pre") as? Int ?? 10
        reciter = d.object(forKey: "reciter") as? Int ?? 0
        fontSize = d.object(forKey: "font") as? Int ?? 21
        cityName = d.string(forKey: "city") ?? "المنصورة"
        khatmaDays = d.object(forKey: "khatma") as? Int ?? 30
        khatmaDone = d.object(forKey: "khatmaDone") as? [Int] ?? []
        streak = d.object(forKey: "streak") as? Int ?? 0
        bestStreak = d.object(forKey: "best") as? Int ?? 0
        lastReadGlobal = d.object(forKey: "lastGlobal") as? Int ?? 1
        bookmarks = d.object(forKey: "marks") as? [Int] ?? []
        notes = (d.object(forKey: "notes") as? [String: String]) ?? [:]
        tasbeeh = d.object(forKey: "tasbeeh") as? Int ?? 0
        tasbeehTarget = d.object(forKey: "tasbeehTarget") as? Int ?? 33
        if let data = d.data(forKey: "attempts"),
           let list = try? JSONDecoder().decode([Attempt].self, from: data) {
            attempts = list
        } else {
            attempts = []
        }
    }

    private func saveAttempts() {
        if let data = try? JSONEncoder().encode(attempts) { d.set(data, forKey: "attempts") }
    }

    public func addAttempt(sura: Int, percent: Int, haraka: Int) {
        attempts.append(Attempt(date: Date(), sura: sura, percent: percent, haraka: haraka))
        if attempts.count > 200 { attempts.removeFirst(attempts.count - 200) }
        bumpStreak()
    }

    public func bumpStreak() {
        let cal = Calendar(identifier: .gregorian)
        let key = "lastDayStamp"
        let today = cal.startOfDay(for: Date())
        let last = d.object(forKey: key) as? Date ?? .distantPast
        if cal.isDate(last, inSameDayAs: today) { return }
        if let y = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: last)),
           cal.isDate(y, inSameDayAs: today) {
            streak += 1
        } else {
            streak = 1
        }
        bestStreak = max(bestStreak, streak)
        d.set(today, forKey: key)
    }

    public func toggleBookmark(_ global: Int) {
        if let i = bookmarks.firstIndex(of: global) { bookmarks.remove(at: i) }
        else { bookmarks.append(global) }
    }

    public var average: Int {
        attempts.isEmpty ? 0 : attempts.map(\.percent).reduce(0, +) / attempts.count
    }
    public var best: Int { attempts.map(\.percent).max() ?? 0 }

    /// khatma: which global ayahs belong to today
    public func khatmaTodayPortion() -> Range<Int> {
        let perDay = max(1, 6236 / max(1, khatmaDays))
        let day = Calendar(identifier: .gregorian).component(.day, from: Date())
        let idx = (day * perDay) % max(1, 6236 - perDay)
        return idx..<(idx + perDay)
    }
    public var khatmaPercent: Int {
        Int((Double(khatmaDone.count) / 6236.0 * 100).rounded())
    }
}
