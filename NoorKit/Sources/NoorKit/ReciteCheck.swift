import Foundation

// MARK: - word / edit / result models

public struct WordEdit: Hashable {
    public enum Kind: String { case sub, ins, del }
    public var expected: String
    public var got: String
    public var kind: Kind
}

public final class WordCheck: Identifiable {
    public var id = UUID()
    public var target: String          // original, with diacritics
    public var normalized: String
    public var spoken: String?         // nil = the word was not recited
    public var correct = false
    public var lettersSpelledDifferently = false
    public var similarity: Double = 0
    public var letterPercent: Double = 0
    public var edits: [WordEdit] = []
    public var expectedHarakat = ""
    public var gotHarakat = ""
    public var harakaNote = ""
    public var harakaScore: Double = 1

    public init(target: String, normalized: String) {
        self.target = target
        self.normalized = normalized
    }

    public var state: State {
        if spoken == nil { return .missing }
        if correct { return harakaScore < 0.999 ? .haraka : .correct }
        return .wrong
    }
    public enum State { case correct, haraka, wrong, missing }
}

public final class AyahResult {
    public var words: [WordCheck] = []
    public var extra: [String] = []
    public var correct = 0, wrong = 0, missing = 0, accepted = 0
    public var percent = 0, letterPercent = 0
    public var harakaTotal = 0, harakaCorrect = 0, harakaPercent = 0, wrongHarakat = 0
    public var harakaVerdict = ""
    public var feedback = ""
}

public struct AyahCheck: Identifiable {
    public var id = UUID()
    public var sura: Int
    public var ayah: Int
    public var text: String
    public var spoken: String
    public var result: AyahResult
}

public struct Mistake: Identifiable {
    public var id = UUID()
    public var sura: Int
    public var ayah: Int
    public var kind: String           // «كلمة غلط» / «ناقصة» / «حركة»
    public var target: String
    public var got: String
    public var detail: String
}

public struct Session {
    public var sura = 1
    public var ayahs: [AyahCheck] = []
    public var correct = 0, wrong = 0, missing = 0, wrongHarakat = 0, ayahsPerfect = 0
    public var percent = 0, harakaPercent = 0
    public var heardWords = 0
    public var resumeAyah = 1
    public var feedback = ""
    public var mistakes: [Mistake] = []
    public var isEmpty: Bool { ayahs.isEmpty }
    public var ayahRange: String {
        guard let f = ayahs.first, let l = ayahs.last else { return "—" }
        return f.ayah == l.ayah ? "آية \(fmt(f.ayah))" : "من آية \(fmt(f.ayah)) إلى \(fmt(l.ayah))"
    }
}

public func fmt(_ v: Int) -> String {
    // Arabic-Indic digits, the same convention as the Android app
    let map: [Character: Character] = ["0": "٠", "1": "١", "2": "٢", "3": "٣", "4": "٤",
                                       "5": "٥", "6": "٦", "7": "٧", "8": "٨", "9": "٩"]
    return String(String(v).map { map[$0] ?? $0 })
}

// MARK: - engine

public enum ReciteCheck {

    // ---------------------------------------------------------------- normalisation
    private static func isDiacritic(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        if v >= 0x0610 && v <= 0x061A { return true }
        if v >= 0x064B && v <= 0x065F { return true }
        if v == 0x0670 { return true }
        if v >= 0x06D6 && v <= 0x06ED { return true }
        if v == 0x0640 { return true }
        return false
    }

    /// Uthmani-safe normalisation: strips harakat/waqf marks, folds hamza/alif/ya/ta-marbuta.
    public static func normalize(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        for ch in input {
            guard let v = ch.unicodeScalars.first?.value else { continue }
            if isDiacritic(ch) { continue }
            if v == 0x0640 || v == 0x0670 || v == 0x06E1 || v == 0x06E2 || v == 0x06E5
                || v == 0x06E6 || v == 0x06E9 || (v >= 0x06D6 && v <= 0x06ED) { continue }
            var c = ch
            switch ch {
            case "ٱ", "أ", "إ", "آ", "ٲ", "ٳ", "ٵ": c = "ا"
            case "ة", "ہ", "ۀ": c = "ه"
            case "ى", "ئ", "ي", "ﻯ": c = "ي"
            case "ؤ": c = "و"
            case "ک": c = "ك"
            default: break
            }
            if c.unicodeScalars.first?.value == 0x0621 { continue }   // bare hamza
            if c == " " || c == "\n" || c == "\t" {
                if out.hasSuffix(" ") { continue }
                c = " "
            }
            out.append(c)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// consonant skeleton (long-vowel carriers removed) — what 5.2 taught us to compare on
    public static func skeleton(_ s: String) -> String {
        let n = normalize(s)
        let stripped = n.filter { $0 != "ا" && $0 != "و" && $0 != "ي" }
        return stripped.isEmpty ? n : stripped
    }

    public static func words(_ s: String) -> [String] {
        let n = normalize(s)
        return n.isEmpty ? [] : n.split(separator: " ").map(String.init)
    }

    // ---------------------------------------------------------------- similarity
    public static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let la = a.count, lb = b.count
        if la == 0 || lb == 0 { return 0 }
        let A = Array(a), B = Array(b)
        var prev = Array(0...lb), cur = [Int](repeating: 0, count: lb + 1)
        for i in 1...la {
            cur[0] = i
            for j in 1...lb {
                let cost = A[i - 1] == B[j - 1] ? 0 : 1
                cur[j] = min(cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return 1.0 - Double(prev[lb]) / Double(max(la, lb))
    }

    public static func diffChars(_ expected: String, _ got: String) -> [WordEdit] {
        let A = Array(expected), B = Array(got)
        let n = A.count, m = B.count
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    dp[i][j] = min(dp[i - 1][j] + 1, dp[i][j - 1] + 1,
                                   dp[i - 1][j - 1] + (A[i - 1] == B[j - 1] ? 0 : 1))
                }
            }
        }
        var edits: [WordEdit] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && dp[i][j] == dp[i - 1][j - 1] + (A[i - 1] == B[j - 1] ? 0 : 1) {
                if A[i - 1] != B[j - 1] {
                    edits.insert(WordEdit(expected: String(A[i - 1]), got: String(B[j - 1]), kind: .sub), at: 0)
                }
                i -= 1; j -= 1
            } else if i > 0 && dp[i][j] == dp[i - 1][j] + 1 {
                edits.insert(WordEdit(expected: String(A[i - 1]), got: "", kind: .del), at: 0)
                i -= 1
            } else {
                edits.insert(WordEdit(expected: "", got: String(B[j - 1]), kind: .ins), at: 0)
                j -= 1
            }
        }
        return edits
    }

    // ---------------------------------------------------------------- diacritics
    public enum Haraka: Int { case fatha, damma, kasra, sukun, shadda, tanween, none }
    public static let harakaNames = ["فتحة", "ضمة", "كسرة", "سكون", "شدّة", "تنوين", "بدون حركة"]

    private static func harakaOf(_ c: Character) -> Haraka? {
        switch c {
        case "\u{064E}": return .fatha
        case "\u{064F}": return .damma
        case "\u{0650}": return .kasra
        case "\u{0652}": return .sukun
        case "\u{0651}": return .shadda
        case "\u{064B}", "\u{064C}", "\u{064D}": return .tanween
        default: return nil
        }
    }

    public static func harakaSignature(_ word: String) -> [Haraka] {
        let chars = Array(word)
        var out: [Haraka] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if isDiacritic(c) { i += 1; continue }
            var h = Haraka.none
            var j = i + 1
            while j < chars.count, isDiacritic(chars[j]) {
                if let cand = harakaOf(chars[j]) { h = cand; break }
                j += 1
            }
            out.append(h)
            i += 1
        }
        return out
    }

    private static func harakaText(_ word: String) -> String {
        harakaSignature(word).map { harakaNames[$0.rawValue] }.joined(separator: " ")
    }

    /// compares the vowels; positions the recogniser never reported are NOT mistakes
    private static func compareHarakat(_ w: WordCheck, spoken: String) {
        let exp = harakaSignature(w.target)
        let got = harakaSignature(spoken)
        w.expectedHarakat = harakaText(w.target)
        w.gotHarakat = harakaText(spoken)
        if got.isEmpty || exp.isEmpty { w.harakaScore = 1; w.harakaNote = ""; return }
        let pairs = min(exp.count, got.count)
        var wrong = 0, checked = 0
        var detail: [String] = []
        for i in 0..<pairs {
            if got[i] == .none { continue }
            checked += 1
            if exp[i] != got[i] {
                wrong += 1
                detail.append("الحرف \(fmt(i + 1)): المتوقع \(harakaNames[exp[i].rawValue]) والمقروء \(harakaNames[got[i].rawValue])")
            }
        }
        w.harakaScore = checked == 0 ? 1 : 1.0 - Double(wrong) / Double(checked)
        w.harakaNote = detail.joined(separator: " · ")
    }

    // ---------------------------------------------------------------- single ayah check
    public static func check(_ ayahText: String, _ spokenText: String) -> AyahResult {
        let r = AyahResult()
        for t in ayahText.split(separator: " ") where !t.trimmingCharacters(in: .whitespaces).isEmpty {
            r.words.append(WordCheck(target: String(t), normalized: normalize(String(t))))
        }
        let spoken = words(spokenText)

        if spoken.count == r.words.count, looksAligned(r, spoken) {
            for i in 0..<r.words.count { classify(r.words[i], spoken[i]) }
        } else {
            alignAndClassify(r, spoken)
        }
        tally(r)
        return r
    }

    static func looksAligned(_ r: AyahResult, _ spoken: [String]) -> Bool {
        var good = 0
        for i in 0..<r.words.count {
            let a = skeleton(r.words[i].normalized), b = skeleton(spoken[i])
            if a == b || similarity(r.words[i].normalized, spoken[i]) >= 0.75 { good += 1 }
        }
        return good * 2 >= r.words.count
    }

    static func classify(_ w: WordCheck, _ spokenNorm: String) {
        w.spoken = spokenNorm
        let sim = similarity(w.normalized, spokenNorm)
        w.similarity = sim
        w.letterPercent = max(0, min(1, similarity(skeleton(w.normalized), skeleton(spokenNorm))))
        let exact = sim >= 0.999
        let skeletonOk = skeleton(w.normalized) == skeleton(spokenNorm)
        let closeEnough = sim >= 0.6
        w.correct = exact || (skeletonOk && closeEnough)
        w.lettersSpelledDifferently = !exact && w.correct
        compareHarakat(w, spoken: spokenNorm)
        if !w.correct || w.harakaScore < 1.0 {
            w.edits = diffChars(w.normalized, spokenNorm)
        } else {
            w.edits = []
        }
    }

    static func alignAndClassify(_ r: AyahResult, _ spoken: [String]) {
        let n = r.words.count, m = spoken.count
        var dp = [[Double]](repeating: [Double](repeating: 0, count: m + 1), count: n + 1)
        var back = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 {
            var i = 1
            while i <= n { dp[i][0] = dp[i - 1][0] - 1; back[i][0] = 1; i += 1 }
        }
        if m > 0 {
            var j = 1
            while j <= m { dp[0][j] = dp[0][j - 1] - 1; back[0][j] = 2; j += 1 }
        }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let sim = similarity(r.words[i - 1].normalized, spoken[j - 1])
                    let match = dp[i - 1][j - 1] + (sim >= 0.75 ? 1 : (sim >= 0.55 ? 0.4 : -0.6))
                    let miss = dp[i - 1][j] - 1, extra = dp[i][j - 1] - 1
                    var best = match, dir = 0
                    if miss > best { best = miss; dir = 1 }
                    if extra > best { best = extra; dir = 2 }
                    dp[i][j] = best
                    back[i][j] = dir
                }
            }
        }
        var i = n, j = m
        while i > 0 || j > 0 {
            let dir = i == 0 ? 2 : (j == 0 ? 1 : back[i][j])
            if dir == 0 { classify(r.words[i - 1], spoken[j - 1]); i -= 1; j -= 1 }
            else if dir == 1 { r.words[i - 1].correct = false; i -= 1 }
            else { r.extra.append(spoken[j - 1]); j -= 1 }
        }
    }

    static func tally(_ r: AyahResult) {
        var sum = 0.0
        for w in r.words {
            let len = max(1, w.normalized.count)
            if w.correct { r.correct += 1; sum += 1; if w.lettersSpelledDifferently { r.accepted += 1 } }
            else if w.spoken == nil { r.missing += 1 }
            else { r.wrong += 1; sum += w.letterPercent }
            if w.correct {
                r.harakaTotal += len
                r.harakaCorrect += Int((w.harakaScore * Double(len)).rounded())
                if w.harakaScore < 0.999 { r.wrongHarakat += 1 }
            }
        }
        r.percent = min(100, Int((100 * sum / Double(max(1, r.words.count))).rounded()))
        r.harakaPercent = r.harakaTotal == 0 ? 0 : Int((100 * Double(r.harakaCorrect) / Double(r.harakaTotal)).rounded())
        r.harakaVerdict = harakaVerdict(r)
        r.feedback = feedbackFor(r)
    }

    static func harakaVerdict(_ r: AyahResult) -> String {
        if r.harakaTotal == 0 { return "مش ممكن نقيس التشكيل — الحروف نفسها في كلمات غلط" }
        if r.wrongHarakat == 0 { return "التشكيل مضبوط ✅" }
        if r.harakaPercent >= 90 { return "شبه مضبوط — راجع \(fmt(r.wrongHarakat)) كلمة" }
        if r.harakaPercent >= 75 { return "فيه \(fmt(r.wrongHarakat)) كلمة حركتها غلط — اسمع القارئ وركّز" }
        return "التشكيل محتاج مراجعة جدية (\(fmt(r.wrongHarakat)) كلمة)"
    }

    static func feedbackFor(_ r: AyahResult) -> String {
        switch r.percent {
        case 100: return "ما شاء الله! تلاوة متقنة تماماً 🌟"
        case 95...: return "ممتاز! غلطة صغيرة جداً — راجعها وكمّل 👏"
        case 85...: return "أحسنت! فيه كلمات بسيطة تحتاج ضبط 💪"
        case 70...: return "جيد — راجع الكلمات الملوّنة واستمع للقارئ مرة كمان 🎧"
        case 50...: return "محتاج مراجعة — اسمع الآية وردّ وراها كلمة بكلمة"
        default: return "خلّينا نبدأ بالاستماع للآية الأول، وبعدين جرّب تاني 🎧"
        }
    }

    // ---------------------------------------------------------------- whole-Quran locate
    /// returns (global ayah, word offset inside that ayah) — the anchor of the recitation
    public static func locate(_ spoken: String) -> (global: Int, offset: Int)? {
        let q = Quran.shared
        let sw = normalize(spoken).split(separator: " ").map(String.init)
        guard sw.count >= 3, !q.flatText.isEmpty else { return nil }
        let big = q.flatText as NSString

        var bestLen = 0, bestP = 0, bestQ = 0
        var p = 0
        while p + 2 < sw.count {
            var len = 7
            while len >= 3 {
                if p + len <= sw.count && len > bestLen {
                    let gram = sw[p..<(p + len)].joined(separator: " ")
                    let at = big.range(of: gram).location
                    if at != NSNotFound {
                        bestLen = len; bestP = p; bestQ = q.wordAt(charOffset: at)
                        break
                    }
                }
                len -= 1
            }
            if bestLen >= 9 { break }
            p += 1
        }
        guard bestLen > 0 else { return nil }
        let startWord = max(0, bestQ - bestP)
        guard startWord < q.wordAyah.count else { return nil }
        let global = q.wordAyah[startWord]
        let (from, _) = q.wordsOf(global)
        return (global, max(0, startWord - from))
    }

    // ---------------------------------------------------------------- the «فحص» pass
    /// Grades the whole transcript in ONE pass with a word-level diff, so a missing
    /// word never shifts the rest of the page (the 5.3 fix, ported 1:1).
    public static func analyze(_ spoken: String) -> Session {
        let q = Quran.shared
        var se = Session()
        let sw = words(spoken)
        se.heardWords = sw.count
        guard let anchor = locate(spoken), sw.count >= 3 else {
            se.feedback = "مش قادرين نحدد الآية — اقرأ آية كاملة بوضوح"
            return se
        }
        let (sura, anchorAyah) = q.toSurahAyah(anchor.global)
        se.sura = sura
        let maxA = q.ayahCount(sura)

        // target stream from the anchor ayah forward
        var tw: [String] = [], tAyah: [Int] = [], tGlobal: [Int] = []
        let cap = sw.count + 30
        var first = true
        var ay = anchorAyah
        while ay <= maxA && tw.count < cap {
            let gl = q.globalIndex(sura, ay)
            let parts = normalize(q.ayah(sura, ay)).split(separator: " ").map(String.init)
            for (wi, w) in parts.enumerated() {
                if w.isEmpty { continue }
                if first && wi < anchor.offset { continue }
                tw.append(w); tAyah.append(ay); tGlobal.append(gl)
            }
            first = false
            ay += 1
        }
        guard !tw.isEmpty else { se.feedback = "تعذّر تحميل نص السورة"; return se }

        // ---- word-level DP alignment
        let n = tw.count, m = sw.count
        var dp = [[Float]](repeating: [Float](repeating: 0, count: m + 1), count: n + 1)
        var bk = [[Int8]](repeating: [Int8](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 {
            var i = 1
            while i <= n { dp[i][0] = dp[i - 1][0] - 1.2; bk[i][0] = 1; i += 1 }
        }
        if m > 0 {
            var j = 1
            while j <= m { dp[0][j] = dp[0][j - 1] - 1.2; bk[0][j] = 2; j += 1 }
        }

        if n > 0 && m > 0 {
            var i = 1
            while i <= n {
                let w = tw[i - 1]
                let sk = skeleton(w)
                var j = 1
                while j <= m {
                    let v = sw[j - 1]
                    var match: Float
                    if w == v { match = 2.0 }
                    else if sk == skeleton(v) { match = 1.4 }
                    else {
                        let sim = similarity(w, v)
                        match = sim >= 0.8 ? 0.9 : (sim >= 0.62 ? 0.2 : -1.2)
                    }
                    var best = dp[i - 1][j - 1] + match
                    var dir: Int8 = 0
                    let up = dp[i - 1][j] - 1.2
                    let left = dp[i][j - 1] - 1.2
                    if up > best { best = up; dir = 1 }
                    if left > best { best = left; dir = 2 }
                    dp[i][j] = best
                    bk[i][j] = dir
                    j += 1
                }
                i += 1
            }
        }

        // ---- backtrack
        var matchSpoken = [String?](repeating: nil, count: n)
        var i = n, j = m
        while i > 0 || j > 0 {
            let dir: Int8 = i == 0 ? 2 : (j == 0 ? 1 : bk[i][j])
            if dir == 0 { matchSpoken[i - 1] = sw[j - 1]; i -= 1; j -= 1 }
            else if dir == 1 { matchSpoken[i - 1] = nil; i -= 1 }
            else { j -= 1 }   // extra spoken word
        }

        // ---- group per ayah
        var list: [AyahCheck] = []
        var idx = 0
        while idx < n {
            let ayah = tAyah[idx]
            var wordsOut: [WordCheck] = []
            let original = q.ayah(sura, ayah)
            var spokeOfAyah: [String] = []
            while idx < n && tAyah[idx] == ayah {
                let target = tw[idx]
                let sp = matchSpoken[idx]
                let w = WordCheck(target: target, normalized: target)
                w.spoken = sp
                if let sp = sp {
                    w.similarity = similarity(target, sp)
                    w.letterPercent = max(0, min(1, similarity(skeleton(target), skeleton(sp))))
                    let sameChars = target == sp || skeleton(target) == skeleton(sp)
                    w.correct = sameChars
                    w.lettersSpelledDifferently = sameChars && target != sp
                    compareHarakat(w, spoken: sp)
                    if !w.correct { w.edits = diffChars(target, sp) }
                    spokeOfAyah.append(sp)
                }
                wordsOut.append(w)
                idx += 1
            }
            let r = AyahResult()
            r.words = wordsOut
            tally(r)
            list.append(AyahCheck(sura: sura, ayah: ayah, text: original,
                                  spoken: spokeOfAyah.joined(separator: " "), result: r))
        }

        // ---- trim the tail: the reciter stopped somewhere (no «ghost» ayahs)
        var lastGood = -1
        for (k, ac) in list.enumerated() where ac.result.percent >= 40 || ac.result.correct > 0 {
            lastGood = k
        }
        if lastGood >= 0 && lastGood + 1 < list.count { list = Array(list[0...lastGood]) }

        se.ayahs = list
        var sum = 0.0
        for ac in list {
            let r = ac.result
            se.correct += r.correct
            se.wrong += r.wrong
            se.missing += r.missing
            se.wrongHarakat += r.wrongHarakat
            if r.percent == 100 && r.wrongHarakat == 0 { se.ayahsPerfect += 1 }
            sum += Double(r.correct)
            for w in r.words where !w.correct && w.spoken != nil { sum += w.letterPercent }
            se.mistakes.append(contentsOf: mistakes(of: ac))
        }
        let total = max(1, se.correct + se.wrong + se.missing)
        se.percent = min(100, Int((100 * sum / Double(total)).rounded()))
        var hTotal = 0, hOk = 0
        for ac in list { hTotal += ac.result.harakaTotal; hOk += ac.result.harakaCorrect }
        se.harakaPercent = hTotal == 0 ? 0 : Int((100 * Double(hOk) / Double(hTotal)).rounded())
        se.resumeAyah = min(maxA, (list.last?.ayah ?? anchorAyah) + 1)

        let errors = se.wrong + se.missing
        se.feedback = errors == 0 && se.wrongHarakat == 0
            ? "ما شاء الله — كل اللي قريته صح ✅"
            : errors == 0
            ? "الحروف كلها صح — راجع \(fmt(se.wrongHarakat)) حركة (تشكيل) 🟡"
            : "فيه \(fmt(errors)) خطأ — شوف القايمة تحت"
        return se
    }

    /// every mistake of one ayah, in one flat list (so all of them show at once)
    public static func mistakes(of ac: AyahCheck) -> [Mistake] {
        var out: [Mistake] = []
        for w in ac.result.words {
            switch w.state {
            case .wrong:
                let edits = w.edits.map { e -> String in
                    switch e.kind {
                    case .sub: return "«\(e.expected)» ← «\(e.got)»"
                    case .del: return "ناقص حرف «\(e.expected)»"
                    case .ins: return "زودت «\(e.got)»"
                    }
                }.joined(separator: " · ")
                out.append(Mistake(sura: ac.sura, ayah: ac.ayah, kind: "كلمة غلط",
                                   target: w.target, got: w.spoken ?? "", detail: edits))
            case .missing:
                out.append(Mistake(sura: ac.sura, ayah: ac.ayah, kind: "ناقصة",
                                   target: w.target, got: "", detail: "الكلمة مش متقروءة"))
            case .haraka:
                out.append(Mistake(sura: ac.sura, ayah: ac.ayah, kind: "حركة",
                                   target: w.target, got: w.spoken ?? "", detail: w.harakaNote))
            case .correct: break
            }
        }
        return out
    }
}
