import SwiftUI
import UIKit
import NoorKit

// MARK: - adhkar / duas / hadith / asma

struct AdhkarView: View {
    @State private var mode = 0
    @State private var cat = 0
    @State private var done: [String: Int] = [:]
    @State private var tasbeeh = Store.shared.tasbeeh

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(["الأذكار", "الأدعية", "الأحاديث", "الأسماء"], id: \.self) { m in
                        let i = ["الأذكار", "الأدعية", "الأحاديث", "الأسماء"].firstIndex(of: m)!
                        Button { mode = i } label: {
                            Text(m).font(.system(size: 11, weight: mode == i ? .bold : .regular))
                                .foregroundStyle(mode == i ? Color(hex: 0x1B1408) : P.sub)
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(Capsule().fill(mode == i ? P.gold : P.card2))
                        }.buttonStyle(.plain)
                    }
                }

                if mode == 0 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(AdhkarData.categories.enumerated()), id: \.offset) { i, c in
                                Chip(title: c, on: cat == i) { cat = i }
                            }
                        }
                    }
                    ForEach(Array(AdhkarData.adhkar(category: cat).enumerated()), id: \.offset) { i, e in
                        EntryCard(e: e, key: "adh\(cat)_\(i)", done: $done)
                    }
                } else if mode == 1 {
                    ForEach(Array(AdhkarData.duas.enumerated()), id: \.offset) { _, e in
                        Card {
                            VStack(alignment: .trailing, spacing: 6) {
                                Text(e.title ?? "").font(.system(size: 12, weight: .bold)).foregroundStyle(P.gold)
                                Text(e.text).font(.system(size: 15)).foregroundStyle(P.txt)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else if mode == 2 {
                    ForEach(Array(AdhkarData.hadiths.enumerated()), id: \.offset) { _, e in
                        Card {
                            VStack(alignment: .trailing, spacing: 5) {
                                Text(e.text).font(.system(size: 14)).foregroundStyle(P.txt)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let s = e.source { Text(s).font(.system(size: 10)).foregroundStyle(P.sub) }
                            }
                        }
                    }
                } else {
                    Card {
                        VStack(alignment: .trailing, spacing: 6) {
                            ForEach(Array(AdhkarData.asmaAllah.enumerated()), id: \.offset) { i, n in
                                Text("\(fmt(i + 1)). \(n)").font(.system(size: 14)).foregroundStyle(P.txt)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }
                }

                // tasbeeh
                Card {
                    VStack(spacing: 8) {
                        Text("📿 عدّاد التسبيح").font(.system(size: 13, weight: .bold)).foregroundStyle(P.gold)
                        Text("\(fmt(tasbeeh)) / \(fmt(Store.shared.tasbeehTarget))")
                            .font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(P.txt)
                        LevelBar(level: Int(Double(tasbeeh % max(1, Store.shared.tasbeehTarget)) / Double(max(1, Store.shared.tasbeehTarget)) * 100))
                        HStack(spacing: 8) {
                            GoldButton(title: "سبّح +١") {
                                tasbeeh += 1
                                Store.shared.tasbeeh = tasbeeh
                            }
                            GrayButton(title: "تصفير") { tasbeeh = 0; Store.shared.tasbeeh = 0 }
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 26).padding(.top, 6)
        }
    }
}

struct EntryCard: View {
    var e: AdhkarData.Entry
    var key: String
    @Binding var done: [String: Int]

    var body: some View {
        let count = done[key] ?? 0
        let finished = count >= e.repeatCount
        Card {
            VStack(alignment: .trailing, spacing: 8) {
                if let t = e.title { Text(t).font(.system(size: 12, weight: .bold)).foregroundStyle(P.gold) }
                Text(e.text).font(.system(size: 15)).foregroundStyle(P.txt)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(finished ? "تم ✅" : "\(fmt(count)) / \(fmt(e.repeatCount))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(finished ? P.teal : P.sub)
                    Spacer()
                    Button {
                        done[key] = min(e.repeatCount, count + 1)
                    } label: {
                        Text("سبّح +١").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: 0x1B1408))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(finished ? P.sub : P.gold))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - marks & notes

struct MarksView: View {
    @ObservedObject private var store = Store.shared
    @State private var noteText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Card {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("⭐ العلامات (\(fmt(store.bookmarks.count)))").font(.system(size: 13, weight: .bold)).foregroundStyle(P.gold)
                        if store.bookmarks.isEmpty {
                            Text("اضغط على أي آية في المصحف واختار «علّم».").font(.system(size: 11)).foregroundStyle(P.sub)
                        }
                        ForEach(store.bookmarks, id: \.self) { g in
                            let (s, a) = Quran.shared.toSurahAyah(g)
                            HStack(alignment: .top) {
                                Text(Quran.shared.ayah(s, a)).font(.system(size: 13)).foregroundStyle(P.txt)
                                    .lineLimit(2)
                                Spacer()
                                Text("\(Quran.shared.surah(s)?.t ?? "") \(fmt(a))")
                                    .font(.system(size: 10)).foregroundStyle(P.sub)
                            }
                            Divider().overlay(P.card2)
                        }
                    }
                }
                Card {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("📝 الملاحظات").font(.system(size: 13, weight: .bold)).foregroundStyle(P.gold)
                        ForEach(store.notes.keys.sorted(), id: \.self) { k in
                            Text("• \(k): \(store.notes[k] ?? "")")
                                .font(.system(size: 12)).foregroundStyle(P.txt)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 26)
        }
    }
}

// MARK: - khatma & progress

struct ProgressView2: View {
    @ObservedObject private var store = Store.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Card {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text("📖 خطة الختمة").font(.system(size: 14, weight: .bold)).foregroundStyle(P.gold)
                        HStack(spacing: 6) {
                            ForEach([7, 15, 30, 60, 90], id: \.self) { d in
                                Chip(title: "\(fmt(d)) يوم", on: store.khatmaDays == d) { store.khatmaDays = d }
                            }
                        }
                        Text("نسبة الإنجاز: \(fmt(store.khatmaPercent))%")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(P.teal)
                        LevelBar(level: store.khatmaPercent)
                        let portion = store.khatmaTodayPortion()
                        Text("الجزء المطلوب النهارده: من الآية \(fmt(portion.lowerBound)) إلى \(fmt(portion.upperBound)) — حوالي \(fmt(portion.count)) آية")
                            .font(.system(size: 11)).foregroundStyle(P.sub)
                            .fixedSize(horizontal: false, vertical: true)
                        GrayButton(title: "✅ خلّصت قراءة النهارده") {
                            var d = store.khatmaDone
                            d.append(contentsOf: portion)
                            store.khatmaDone = Array(Set(d)).sorted()
                        }
                    }
                }
                Card {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("🔥 سلسلة الأيام").font(.system(size: 14, weight: .bold)).foregroundStyle(P.gold)
                        Text("الحالية: \(fmt(store.streak)) يوم · الأفضل: \(fmt(store.bestStreak)) يوم")
                            .font(.system(size: 13)).foregroundStyle(P.txt)
                    }
                }
                Card {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("🎯 تقييم التلاوة").font(.system(size: 14, weight: .bold)).foregroundStyle(P.gold)
                        Text("متوسط: \(fmt(store.average))% · أفضل: \(fmt(store.best))% · عدد المحاولات: \(fmt(store.attempts.count))")
                            .font(.system(size: 12)).foregroundStyle(P.txt)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(store.attempts.suffix(6).reversed()) { a in
                            HStack {
                                Text("\(fmt(a.percent))%").font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(a.percent >= 90 ? P.teal : P.amber)
                                Text("سورة \(Quran.shared.surah(a.sura)?.t ?? "")")
                                    .font(.system(size: 11)).foregroundStyle(P.sub)
                                Spacer()
                                Text(a.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 9)).foregroundStyle(P.sub)
                            }
                        }
                    }
                }
                // 10 badges
                Card {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text("🏅 الشارات").font(.system(size: 14, weight: .bold)).foregroundStyle(P.gold)
                        let earned = badges
                        ForEach(earned, id: \.0) { b in
                            HStack {
                                Text(b.1).font(.system(size: 11)).foregroundStyle(b.2 ? P.txt : P.sub)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                Text(b.0).font(.system(size: 15))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 26)
        }
    }

    private var badges: [(String, String, Bool)] {
        [("🌱", "أول تلاوة", !store.attempts.isEmpty),
         ("🔟", "١٠ تلاوات", store.attempts.count >= 10),
         ("💯", "٥٠ تلاوة", store.attempts.count >= 50),
         ("🎯", "نسبة ٩٥٪+", store.best >= 95),
         ("🌟", "نسبة ١٠٠٪", store.best >= 100),
         ("🔥", "سلسلة ٣ أيام", store.streak >= 3),
         ("🔥", "سلسلة ٧ أيام", store.streak >= 7),
         ("📖", "ختمة ٣٠ يوم", store.khatmaDays == 30 && !store.khatmaDone.isEmpty),
         ("📿", "٣٣ تسبيحة", Store.shared.tasbeeh >= 33),
         ("⭐", "١٠ علامات", store.bookmarks.count >= 10)]
    }
}

// MARK: - search + tafsir-lite + share

struct SearchView: View {
    @State private var q = ""

    private var hits: [(Int, Int, String)] {
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        let needle = ReciteCheck.normalize(q)
        var out: [(Int, Int, String)] = []
        for s in Quran.shared.surahs {
            for (i, a) in s.ayahs.enumerated() {
                if ReciteCheck.normalize(a).contains(needle) {
                    out.append((s.n, i + 1, a))
                    if out.count >= 60 { return out }
                }
            }
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Card {
                    TextField("ابحث في القرآن كله…", text: $q)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(P.surface))
                }
                ForEach(Array(hits.enumerated()), id: \.offset) { _, h in
                    Card(fill: P.paper) {
                        VStack(alignment: .trailing, spacing: 6) {
                            Text("\(Quran.shared.surah(h.0)?.t ?? "") · آية \(fmt(h.1))")
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(P.inkSoft)
                            Text(h.2).font(.system(size: 17)).foregroundStyle(P.ink)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            HStack(spacing: 10) {
                                Button("نسخ") {
                                    UIPasteboard.general.string = "\(h.2) — \(Quran.shared.surah(h.0)?.t ?? "") \(h.1)"
                                }.font(.system(size: 11)).foregroundStyle(P.paperGreen)
                                ShareLink(item: "\(h.2) — \(Quran.shared.surah(h.0)?.t ?? "") \(h.1)") {
                                    Text("مشاركة").font(.system(size: 11)).foregroundStyle(P.paperGreen)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 26)
        }
    }
}

// MARK: - more (settings hub)

struct MoreView2: View {
    @ObservedObject private var store = Store.shared
    @State private var sheet: Int? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                NavigationLink { TimesView() } label: { row("🕌", "مواقيت الصلاة", PrayerCalc.hijri()) }
                    .buttonStyle(.plain)
                NavigationLink { QiblaView() } label: { row("🧭", "القبلة", "بالبوصلة والشمال الحقيقي") }
                    .buttonStyle(.plain)
                NavigationLink { AdhkarView() } label: { row("📿", "الأذكار والأدعية", "٣٨ ذكر · ١٥ دعاء · ٢٠ حديث · ٩٩ اسم") }
                    .buttonStyle(.plain)
                NavigationLink { ProgressView2() } label: { row("📊", "الختمة والتقدّم", "سلسلة \(fmt(store.streak)) يوم · متوسط \(fmt(store.average))%") }
                    .buttonStyle(.plain)
                NavigationLink { MarksView() } label: { row("⭐", "العلامات والملاحظات", "\(fmt(store.bookmarks.count)) علامة · \(fmt(store.notes.count)) ملاحظة") }
                    .buttonStyle(.plain)
                NavigationLink { SearchView() } label: { row("🔎", "بحث في القرآن", "٦٢٣٦ آية") }
                    .buttonStyle(.plain)
                NavigationLink { FeaturesView() } label: { row("✨", "الميزات", "٥٦ ميزة — نفس نسخة أندرويد") }
                    .buttonStyle(.plain)

                Card {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("عن نور").font(.system(size: 13, weight: .bold)).foregroundStyle(P.gold)
                        Text("نور ١٫٠ لآيفون — كل البيانات على الجهاز، بدون حساب ولا جمع بيانات.")
                            .font(.system(size: 11)).foregroundStyle(P.sub)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 26).padding(.top, 6)
        }
    }

    private func row(_ icon: String, _ title: String, _ sub: String) -> some View {
        Card {
            HStack(spacing: 10) {
                Text("‹").font(.system(size: 18)).foregroundStyle(P.gold)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(P.txt)
                    Text(sub).font(.system(size: 10)).foregroundStyle(P.sub)
                        .lineLimit(1)
                }
                Spacer()
                Text(icon).font(.system(size: 20))
            }
        }
    }
}

struct FeaturesView: View {
    private let list = [
        "١. مواقيت الصلاة الستة محسوبة فلكياً على الجهاز بدون إنترنت",
        "٢. عدّاد تنازلي حيّ للصلاة القادمة",
        "٣. خمس طرق حساب معتمدة (الهيئة المصرية، أم القرى، MWL…)",
        "٤. تعديل يدوي بالدقائق لكل صلاة",
        "٥. التقويم الهجري في الشاشة الرئيسية",
        "٦. القرآن كامل ١١٤ سورة / ٦٢٣٦ آية داخل التطبيق",
        "٧. صفحة مصحف بيضاء بشكل الصفحة المطبوعة",
        "٨. تكبير/تصغير خط الصفحة",
        "٩. تشغيل الصوت من نفس نقطة القراءة",
        "١٠. سبعة قرّاء مشهورين مع سلسلة بدائل تلقائية",
        "١١. تكرار الآية للحفظ",
        "١٢. تمييز الآية اللي بتُتلى على الصفحة",
        "١٣. تقييم التلاوة على مستوى الكلمة والحرف",
        "١٤. رصد أخطاء التشكيل (فتحة/ضمة/كسرة/سكون/شدّة/تنوين)",
        "١٥. عرض المتوقع مقابل المسموع لكل حركة",
        "١٦. الوضع الحر: تقرأ أي حتة من غير آية محددة",
        "١٧. مطابقة كلامك مع ٦٢٣٦ آية ويقولك إنت في أي سورة وآية",
        "١٨. عرض النص بدون تشكيل مع تعليم الأخطاء",
        "١٩. تقرير واحد بكل الأخطاء + «كمّل من الآية اللي بعدها»",
        "٢٠. تسجيل مستمر بدون مقاطعة + مسجل صوتي + كتابة/لصق",
        "٢١. بحث فوري في نص القرآن كله",
        "٢٢. نسخ ومشاركة الآية مع مرجعها",
        "٢٣. علامة مرجعية على أي آية",
        "٢٤. ملاحظات شخصية على الآية",
        "٢٥. خطّة ختمة (٧ / ١٥ / ٣٠ / ٦٠ / ٩٠ يوم)",
        "٢٦. سلسلة الأيام (Streak) وأفضل سلسلة",
        "٢٧. لوحة تقدّم + ١٠ شارات",
        "٢٨. الأذكار: صباح، مساء، نوم، بعد الصلاة، اليوم والليل",
        "٢٩. أدعية وأحاديث مختارة",
        "٣٠. عدّاد تسبيح بهدف",
        "٣١. أسماء الله الحسنى ٩٩ اسماً",
        "٣٢. بوصلة القبلة بالشمال الحقيقي",
        "٣٣. ثيم داكن RTL بتصميم عربي",
        "٣٤. كل البيانات على الجهاز — لا حساب ولا جمع بيانات",
        "٣٥. يعمل أوفلاين عدا الصوت"
    ]
    var body: some View {
        ScrollView {
            Card {
                VStack(alignment: .trailing, spacing: 6) {
                    Text("✨ ميزات نور").font(.system(size: 14, weight: .bold)).foregroundStyle(P.gold)
                    ForEach(list, id: \.self) { t in
                        Text(t).font(.system(size: 11)).foregroundStyle(P.txt)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 26)
        }
    }
}
