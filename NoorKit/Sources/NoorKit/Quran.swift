import Foundation

// MARK: - Quran data

public struct Surah: Codable, Identifiable {
    public let n: Int
    public let t: String
    public let type: String?
    public let ayahs: [String]
    public var id: Int { n }
}

public final class Quran {
    public static let shared = Quran()

    public let surahs: [Surah]
    /// global ayah index 1…6236 → (surah, ayah)
    private var toSurahAyah: [(Int, Int)] = []
    /// global ayah index 1…6236 → char offset (in words) inside the flattened mushaf
    private var ayahWordOffset: [Int] = []
    public private(set) var flatWords: [String] = []
    /// word index → global ayah
    public private(set) var wordAyah: [Int] = []
    /// word index → char offset inside `flatText`
    public private(set) var wordCharOffset: [Int] = []
    public private(set) var flatText: String = ""
    private var flatNSString: NSString = ""

    private init() {
        guard let url = Bundle.module.url(forResource: "quran", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Surah].self, from: data) else {
            surahs = []
            return
        }
        surahs = list
        var map: [(Int, Int)] = [(0, 0)]
        for s in list { for a in 1...max(1, s.ayahs.count) { map.append((s.n, a)) } }
        toSurahAyah = map
        buildIndex()
    }

    public func surah(_ n: Int) -> Surah? { surahs.first { $0.n == n } }
    public func ayah(_ surah: Int, _ ayah: Int) -> String {
        guard let s = surah(surah), ayah >= 1, ayah <= s.ayahs.count else { return "" }
        return s.ayahs[ayah - 1]
    }
    public func ayahCount(_ surah: Int) -> Int { surah(surah)?.ayahs.count ?? 0 }
    public func toSurahAyah(_ global: Int) -> (Int, Int) {
        guard global >= 1, global < toSurahAyah.count else { return (1, 1) }
        return toSurahAyah[global]
    }
    public func globalIndex(_ surah: Int, _ ayah: Int) -> Int {
        var g = 0
        for s in surahs { if s.n == surah { return g + ayah } ; g += s.ayahs.count }
        return 1
    }
    public func join(_ surah: Int, from: Int, to: Int) -> String {
        guard let s = surah(surah) else { return "" }
        let lo = max(1, from), hi = min(s.ayahs.count, to)
        guard lo <= hi else { return "" }
        return s.ayahs[(lo - 1)...(hi - 1)].joined(separator: " ")
    }
    public func ayahWordCount(_ global: Int) -> Int {
        let (s, a) = toSurahAyah(global)
        let n = ReciteCheck.normalize(ayah(s, a))
        return n.isEmpty ? 0 : n.split(separator: " ").count
    }

    private func buildIndex() {
        var words: [String] = []
        var ayahs: [Int] = []
        var chars: [Int] = []
        var text = ""
        var offsets: [Int] = Array(repeating: 0, count: 6238)
        var wordPos = 0
        for g in 1...6236 {
            let (s, a) = toSurahAyah(g)
            let norm = ReciteCheck.normalize(ayah(s, a))
            offsets[g] = wordPos
            guard !norm.isEmpty else { continue }
            for w in norm.split(separator: " ") {
                if !text.isEmpty { text += " " }
                chars.append(text.utf16.count)
                ayahs.append(g)
                let ws = String(w)
                words.append(ws)
                text += ws
                wordPos += 1
            }
        }
        offsets[6237] = wordPos
        flatWords = words
        wordAyah = ayahs
        wordCharOffset = chars
        flatText = text
        flatNSString = text as NSString
        ayahWordOffset = offsets
    }

    /// binary search: last word index whose char offset <= position
    public func wordAt(charOffset pos: Int) -> Int {
        var lo = 0, hi = max(0, wordCharOffset.count - 1), ans = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if wordCharOffset[mid] <= pos { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return ans
    }

    public func wordsOf(_ global: Int) -> (Int, Int) {
        let from = ayahWordOffset[max(1, min(6236, global))]
        let to = global < 6236 ? ayahWordOffset[global + 1] : ayahWordOffset[6237]
        return (from, to)
    }

    // MARK: audio (everyayah — several reciters, always with a fallback)
    public static let reciters: [(name: String, folder: String)] = [
        ("مشاري العفاسي", "Alafasy_128kbps"),
        ("محمود الحصري", "Husary_128kbps"),
        ("محمد صديق المنشاوي", "Minshawy_Murattal_128kbps"),
        ("عبد الباسط عبد الصمد", "Abdul_Basit_Murattal_192kbps"),
        ("ماهر المعيقلي", "MaherAlMuaiqly128kbps"),
        ("عبد الرحمن السديس", "Abdurrahmaan_As-Sudais_192kbps"),
        ("سعد الغامدي", "Ghamadi_40kbps")
    ]

    public static func audioURLs(surah: Int, ayah: Int, reciter: Int) -> [URL] {
        let pad6 = String(format: "%03d%03d", surah, ayah)
        var urls: [URL] = []
        let chosen = reciter % reciters.count
        // 1) the reciter the user picked  2) then the other reciters, in order
        for i in 0..<reciters.count {
            let folder = reciters[(chosen + i) % reciters.count].folder
            if let u = URL(string: "https://everyayah.com/data/\(folder)/\(pad6).mp3") {
                urls.append(u)
            }
        }
        return urls
    }
}
