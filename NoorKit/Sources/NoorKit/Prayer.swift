import Foundation

// MARK: - prayer times, Hijri date, qibla — the same astronomy as the Android build

public struct PrayerCalc {

    public struct Settings {
        public var lat: Double
        public var lon: Double
        public var method: Int          // index into `methods`
        public var offsets: [Int]       // fajr, sunrise, dhuhr, asr, maghrib, isha (minutes)
        public init(lat: Double = 30.5965, lon: Double = 31.5021, method: Int = 0,
                    offsets: [Int] = [0, 0, 0, 0, 0, 0]) {
            self.lat = lat; self.lon = lon; self.method = method
            self.offsets = offsets.count == 6 ? offsets : [0, 0, 0, 0, 0, 0]
        }
    }

    public static let methods: [(name: String, fajr: Double, isha: Double)] = [
        ("الهيئة المصرية العامة للمساحة", 19.5, 17.5),
        ("رابطة العالم الإسلامي", 18.0, 17.0),
        ("أم القرى — مكة المكرمة", 18.5, 0.0),
        ("ISNA — أمريكا الشمالية", 15.0, 15.0),
        ("معهد الجيوفيزياء — طهران", 17.7, 14.0)
    ]

    public static let names = ["الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"]

    public let s: Settings
    public init(_ s: Settings) { self.s = s }

    /// decimal hours 0…24, index 0 = fajr … 5 = isha
    public func times(year: Int, month: Int, day: Int, tz: Double) -> [Double] {
        let m = max(0, min(Self.methods.count - 1, s.method))
        let fajrAngle = Self.methods[m].fajr
        let ishaAngle = Self.methods[m].isha

        let jd = Self.julian(year, month, day) - s.lon / 360.0
        let D = jd - 2451545.0
        let g = Self.fixAngle(357.529 + 0.98560028 * D)
        let q = Self.fixAngle(280.459 + 0.98564736 * D)
        let L = Self.fixAngle(q + 1.915 * sin(g) + 0.020 * sin(2 * g))
        let e = 23.439 - 0.00000036 * D
        let decl = Self.asin(sin(e) * sin(L))
        let RA = Self.fixHour(Self.atan2(cos(e) * sin(L), cos(L)) / 15.0)
        let eqt = q / 15.0 - RA
        let midDay = Self.fixHour(12 - eqt)
        let offset = tz - s.lon / 15.0

        var r = [Double](repeating: 0, count: 6)
        r[0] = midDay - hourAngle(-fajrAngle, decl) + offset
        r[1] = midDay - hourAngle(-0.833, decl) + offset
        r[2] = midDay + 1.0 / 15.0 + offset
        r[3] = midDay + hourAngle(asrAltitude(decl), decl) + offset
        r[4] = midDay + hourAngle(-0.833, decl) + offset
        r[5] = ishaAngle <= 0 ? r[4] + 1.5 : midDay + hourAngle(-ishaAngle, decl) + offset
        for i in 0..<6 { r[i] = Self.fixHour(r[i] + Double(s.offsets[i]) / 60.0) }
        return r
    }

    /// tomorrow's times (for the countdown after isha)
    public func nextDayTimes(now: Date = Date()) -> [Double] {
        let cal = Calendar(identifier: .gregorian)
        var c = cal.dateComponents([.year, .month, .day], from: now)
        c.day! += 1
        return times(year: c.year!, month: c.month!, day: c.day!, tz: Self.tzOffsetHours())
    }

    public func todayTimes(now: Date = Date()) -> [Double] {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: now)
        return times(year: c.year!, month: c.month!, day: c.day!, tz: Self.tzOffsetHours())
    }

    public static func tzOffsetHours(_ date: Date = Date()) -> Double {
        Double(TimeZone.current.secondsFromGMT(for: date)) / 3600.0
    }

    /// index of the next prayer + the remaining seconds
    public func next(now: Date = Date()) -> (index: Int, remaining: TimeInterval, tomorrow: Bool) {
        let t = todayTimes(now: now)
        let c = Calendar(identifier: .gregorian).dateComponents([.hour, .minute, .second], from: now)
        let h = Double(c.hour!) + Double(c.minute!) / 60 + Double(c.second!) / 3600
        for i in 0..<6 where t[i] > h + 1.0 / 3600 {
            return (i, (t[i] - h) * 3600, false)
        }
        let tomorrow = nextDayTimes(now: now)
        return (0, (24 - h + tomorrow[0]) * 3600, true)
    }

    // ---- qibla
    public func qiblaBearing() -> Double {
        let kaabaLat = 21.4225, kaabaLon = 39.8262
        let dLon = (kaabaLon - s.lon) * .pi / 180
        let p1 = s.lat * .pi / 180, p2 = kaabaLat * .pi / 180
        let y = Foundation.sin(dLon)
        let x = Foundation.cos(p1) * Foundation.tan(p2) - Foundation.sin(p1) * Foundation.cos(dLon)
        let b = Foundation.atan2(y, x) * 180 / .pi
        return (b + 360).truncatingRemainder(dividingBy: 360)
    }

    // ---- Hijri
    public static let hijriMonths = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر",
                                     "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان",
                                     "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]

    public static func hijri(_ date: Date = Date()) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        let y = c.year!, m = c.month!, d = c.day!
        var jd: Double
        if y > 1582 || (y == 1582 && (m > 10 || (m == 10 && d > 14))) { jd = julian(y, m, d) + 0.5 }
        else { jd = julianJul(y, m, d) + 0.5 }
        var l = Int64(jd - 1948440 + 10632)
        let n = (l - 1) / 10631
        l = l - 10631 * n + 354
        let j = Int64(floor((10985.0 - Double(l)) / 5316.0)) * Int64(floor(50.0 * Double(l) / 17719.0))
              + Int64(floor(Double(l) / 5670.0)) * Int64(floor(43.0 * Double(l) / 15238.0))
        l = l - Int64(floor((30.0 - Double(j)) / 15.0)) * Int64(floor(17719.0 * Double(j) / 50.0))
              - Int64(floor(Double(j) / 16.0)) * Int64(floor(15238.0 * Double(j) / 43.0)) + 29
        var mh = Int(floor(24.0 * Double(l) / 709.0))
        let dh = Int(Double(l) - floor(709.0 * Double(mh) / 24.0))
        let yh = 30 * Int(n) + Int(j) - 30
        mh = max(1, min(12, mh))
        return "\(fmt(dh)) \(hijriMonths[mh - 1]) \(fmt(yh)) هـ"
    }

    // ---- helpers
    func hourAngle(_ altitude: Double, _ decl: Double) -> Double {
        var cosH = (Self.sin(altitude) - Self.sin(decl) * Self.sin(s.lat)) / (Self.cos(decl) * Self.cos(s.lat))
        cosH = max(-1, min(1, cosH))
        return Self.acos(cosH) / 15.0
    }
    func asrAltitude(_ decl: Double) -> Double {
        Foundation.atan(1.0 / (1.0 + Foundation.tan((abs(s.lat - decl)) * .pi / 180))) * 180 / .pi
    }

    public static func julian(_ y0: Int, _ m0: Int, _ d: Int) -> Double {
        var y = y0, m = m0
        if m <= 2 { y -= 1; m += 12 }
        let A = floor(Double(y) / 100.0)
        let B = 2 - A + floor(A / 4.0)
        return floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + Double(d) + B - 1524.5
    }
    static func julianJul(_ y0: Int, _ m0: Int, _ d: Int) -> Double {
        var y = y0, m = m0
        if m <= 2 { y -= 1; m += 12 }
        return floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + Double(d) - 1524.5
    }
    static func fix(_ a0: Double, _ b: Double) -> Double {
        var a = a0 - b * floor(a0 / b)
        if a < 0 { a += b }
        return a
    }
    static func fixAngle(_ a: Double) -> Double { fix(a, 360) }
    static func fixHour(_ a: Double) -> Double { fix(a, 24) }
    static func sin(_ d: Double) -> Double { Foundation.sin(d * .pi / 180) }
    static func cos(_ d: Double) -> Double { Foundation.cos(d * .pi / 180) }
    static func asin(_ v: Double) -> Double { Foundation.asin(max(-1, min(1, v))) * 180 / .pi }
    static func acos(_ v: Double) -> Double { Foundation.acos(max(-1, min(1, v))) * 180 / .pi }
    static func atan2(_ y: Double, _ x: Double) -> Double { Foundation.atan2(y, x) * 180 / .pi }

    /// «٤:٥١ ص»
    public static func clock(_ h0: Double) -> String {
        let h = fixHour(h0 + 0.5 / 60)
        let hh = Int(h)
        var mm = Int(((h - Double(hh)) * 60).rounded())
        var h12 = hh % 12
        if mm == 60 { mm = 0; h12 = (h12 + 1) % 12 }
        if h12 == 0 { h12 = 12 }
        let ampm = hh < 12 ? "ص" : "م"
        return "\(fmt(h12)):\(mm < 10 ? "٠" : "")\(fmt(mm)) \(ampm)"
    }

    public static func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return "\(h > 0 ? "\(fmt(h)) س " : "")\(fmt(m)) د \(fmt(sec)) ث"
    }
}

// MARK: - adhkar / duas / hadith data

public enum AdhkarData {
    public struct Entry: Identifiable, Decodable {
        public var id: Int { text.hashValue }
        public let title: String?
        public let text: String
        public let repeatCount: Int
        public let source: String?
    }

    struct Raw: Decodable {
        let adhkarCats: [String]
        let adhkar: [[[String]]]
        let duas: [[String]]
        let hadiths: [[String]]
    }

    static let raw: Raw? = {
        guard let url = Bundle.module.url(forResource: "adhkar", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Raw.self, from: data)
    }()

    public static var categories: [String] { raw?.adhkarCats ?? [] }
    public static func adhkar(category: Int) -> [Entry] {
        guard let raw = raw, category >= 0, category < raw.adhkar.count else { return [] }
        return raw.adhkar[category].compactMap { row in
            guard let t = row.first else { return nil }
            let n = row.count > 1 ? (Int(row[1]) ?? 1) : 1
            return Entry(title: nil, text: t, repeatCount: n, source: nil)
        }
    }
    public static var duas: [Entry] {
        (raw?.duas ?? []).compactMap { row in
            guard row.count >= 2 else { return nil }
            return Entry(title: row[0], text: row[1], repeatCount: 1, source: nil)
        }
    }
    public static var hadiths: [Entry] {
        (raw?.hadiths ?? []).compactMap { row in
            guard let t = row.first else { return nil }
            return Entry(title: nil, text: t, repeatCount: 1, source: row.count > 1 ? row[1] : nil)
        }
    }

    /// the 99 names
    public static let asmaAllah: [String] = [
        "الرَّحْمَنُ", "الرَّحِيمُ", "الْمَلِكُ", "الْقُدُّوسُ", "السَّلَامُ", "الْمُؤْمِنُ",
        "الْمُهَيْمِنُ", "الْعَزِيزُ", "الْجَبَّارُ", "الْمُتَكَبِّرُ", "الْخَالِقُ", "الْبَارِئُ",
        "الْمُصَوِّرُ", "الْغَفَّارُ", "الْقَهَّارُ", "الْوَهَّابُ", "الرَّزَّاقُ", "الْفَتَّاحُ",
        "الْعَلِيمُ", "الْقَابِضُ", "الْبَاسِطُ", "الْخَافِضُ", "الرَّافِعُ", "الْمُعِزُّ",
        "الْمُذِلُّ", "السَّمِيعُ", "الْبَصِيرُ", "الْحَكَمُ", "الْعَدْلُ", "اللَّطِيفُ",
        "الْخَبِيرُ", "الْحَلِيمُ", "الْعَظِيمُ", "الْغَفُورُ", "الشَّكُورُ", "الْعَلِيُّ",
        "الْكَبِيرُ", "الْحَفِيظُ", "الْمُقِيتُ", "الْحَسِيبُ", "الْجَلِيلُ", "الْكَرِيمُ",
        "الرَّقِيبُ", "الْمُجِيبُ", "الْوَاسِعُ", "الْحَكِيمُ", "الْوَدُودُ", "الْمَجِيدُ",
        "الْبَاعِثُ", "الشَّهِيدُ", "الْحَقُّ", "الْوَكِيلُ", "الْقَوِيُّ", "الْمَتِينُ",
        "الْوَلِيُّ", "الْحَمِيدُ", "الْمُحْصِي", "الْمُبْدِئُ", "الْمُعِيدُ", "الْمُحْيِي",
        "الْمُمِيتُ", "الْحَيُّ", "الْقَيُّومُ", "الْوَاجِدُ", "الْمَاجِدُ", "الْوَاحِدُ",
        "الْأَحَدُ", "الصَّمَدُ", "الْقَادِرُ", "الْمُقْتَدِرُ", "الْمُقَدِّمُ", "الْمُؤَخِّرُ",
        "الْأَوَّلُ", "الْآخِرُ", "الظَّاهِرُ", "الْبَاطِنُ", "الْوَالِي", "الْمُتَعَالِي",
        "الْبَرُّ", "التَّوَّابُ", "الْمُنْتَقِمُ", "الْعَفُوُّ", "الرَّءُوفُ", "مَالِكُ الْمُلْكِ",
        "ذُو الْجَلَالِ وَالْإِكْرَامِ", "الْمُقْسِطُ", "الْجَامِعُ", "الْغَنِيُّ", "الْمُغْنِي",
        "الْمَانِعُ", "الضَّارُّ", "النَّافِعُ", "النُّورُ", "الْهَادِي", "الْبَدِيعُ",
        "الْبَاقِي", "الْوَارِثُ", "الرَّشِيدُ", "الصَّبُورُ"
    ]
}
