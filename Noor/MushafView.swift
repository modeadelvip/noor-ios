import SwiftUI
import AVFoundation
import UIKit
import NoorKit

// MARK: - ayah audio with a fallback chain (never a single source)

@MainActor
final class AyahPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing: Int? = nil          // global ayah index
    @Published var loading = false
    @Published var lastError = ""
    private var player: AVAudioPlayer?
    private var queue: [URL] = []
    private var index = 0

    func play(global: Int, reciter: Int, repeatCount: Int = 0) {
        stop()
        let (s, a) = Quran.shared.toSurahAyah(global)
        queue = Quran.audioURLs(surah: s, ayah: a, reciter: reciter)
        index = 0
        playing = global
        next()
    }

    private func next() {
        guard index < queue.count else {
            lastError = "تعذّر تحميل الصوت — جرّب قارئ تاني"
            playing = nil; loading = false
            return
        }
        let url = queue[index]
        index += 1
        loading = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            Task { @MainActor in
                guard let data = data, !data.isEmpty else { self.next(); return }
                do {
                    self.player = try AVAudioPlayer(data: data)
                    self.player?.delegate = self
                    self.player?.play()
                    self.loading = false
                } catch {
                    self.next()
                }
            }
        }.resume()
    }

    func stop() {
        player?.stop(); player = nil
        playing = nil; loading = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = nil }
    }
}

// MARK: - mushaf

struct MushafView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = Store.shared
    @State private var surah = 1
    @State private var showPicker = false
    @State private var weakWords: Set<String> = []
    @State private var selected: Int? = nil
    @State private var noteDraft = ""
    @StateObject private var audio = AyahPlayer()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack {
                    Text(Quran.shared.surah(surah)?.t ?? "")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(P.gold)
                    Spacer()
                    Button("اختيار السورة") { showPicker = true }
                        .font(.system(size: 12)).foregroundStyle(P.txt)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(P.card2))
                }
                .padding(.horizontal, 14)

                ForEach(Array((Quran.shared.surah(surah)?.ayahs ?? []).enumerated()), id: \.offset) { i, text in
                    let g = Quran.shared.globalIndex(surah, i + 1)
                    Card(fill: P.paper) {
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack {
                                Button {
                                    if audio.playing == g { audio.stop() }
                                    else { audio.play(global: g, reciter: store.reciter) }
                                } label: {
                                    Text(audio.playing == g ? "⏸" : "▶︎")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(P.paperGreen)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Text("\(fmt(i + 1))").font(.system(size: 10)).foregroundStyle(P.inkSoft)
                            }
                            Text(attributed(text))
                                .font(.system(size: CGFloat(store.fontSize)))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .environment(\.layoutDirection, .rightToLeft)
                                .onTapGesture { selected = g; noteDraft = store.notes["\(g)"] ?? "" }
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.bottom, 26)
        }
        .sheet(isPresented: $showPicker) { SurahPicker(selected: $surah) }
        .sheet(item: Binding(get: { selected.map(IdentifiableInt.init) },
                             set: { selected = $0?.value })) { box in
            AyahSheet(global: box.value, note: $noteDraft,
                      isBookmarked: store.bookmarks.contains(box.value),
                      onBookmark: { store.toggleBookmark(box.value) },
                      onSaveNote: {
                          var n = store.notes
                          n["\(box.value)"] = noteDraft
                          store.notes = n
                      },
                      onStudy: {
                          app.jumpGlobal = box.value
                          app.session = nil
                          selected = nil
                      })
        }
        .onChange(of: app.jumpGlobal) { _, g in
            if let g = g {
                let (s, _) = Quran.shared.toSurahAyah(g)
                surah = s
                app.jumpGlobal = nil
            }
        }
        .onAppear { if let s = app.session { markWeak(s) } }
        .onChange(of: app.session?.percent) { _, _ in if let s = app.session { markWeak(s) } }
    }

    private func attributed(_ text: String) -> AttributedString {
        var out = AttributedString("")
        for piece in text.split(separator: " ") {
            let key = ReciteCheck.normalize(String(piece))
            var a = AttributedString(String(piece) + " ")
            a.foregroundColor = weakWords.contains(key) ? P.paperRed : P.ink
            out += a
        }
        return out
    }

    private func markWeak(_ s: Session) {
        weakWords = []
        for ac in s.ayahs {
            for w in ac.result.words where w.state == .wrong || w.state == .missing {
                weakWords.insert(w.normalized)
            }
        }
    }
}

struct SurahPicker: View {
    @Binding var selected: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(Quran.shared.surahs) { s in
                Button {
                    selected = s.n; dismiss()
                } label: {
                    HStack {
                        Text(fmt(s.n)).foregroundStyle(.secondary)
                        Text(s.t)
                        Spacer()
                        Text("\(fmt(s.ayahs.count)) آية").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("السور")
        }
    }
}

// MARK: - listen tab (reciter picker + ayah player)

struct ListenView: View {
    @ObservedObject private var store = Store.shared
    @State private var surah = 1
    @State private var ayah = 1
    @StateObject private var audio = AyahPlayer()
    @State private var repeatAyah = false
    @State private var sleepMinutes = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Card {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text("🎧 استماع").font(.system(size: 15, weight: .bold)).foregroundStyle(P.gold)
                        Picker("القارئ", selection: $store.reciter) {
                            ForEach(Array(Quran.reciters.enumerated()), id: \.offset) { i, r in
                                Text(r.name).tag(i)
                            }
                        }
                        .pickerStyle(.menu)
                        HStack(spacing: 10) {
                            stepper("السورة", Quran.shared.surah(surah)?.t ?? "", dec: { surah = max(1, surah - 1) }, inc: { surah = min(114, surah + 1) })
                            stepper("الآية", fmt(ayah), dec: { ayah = max(1, ayah - 1) }, inc: { ayah = min(Quran.shared.ayahCount(surah), ayah + 1) })
                        }
                        Text(Quran.shared.ayah(surah, ayah))
                            .font(.system(size: 19))
                            .foregroundStyle(P.paper)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(P.surface))
                        HStack(spacing: 8) {
                            GoldButton(title: audio.playing == nil ? "▶︎ شغّل الآية" : "⏸ وقف" ) {
                                let g = Quran.shared.globalIndex(surah, ayah)
                                if audio.playing == nil { audio.play(global: g, reciter: store.reciter) }
                                else { audio.stop() }
                            }
                            GrayButton(title: "التالي") {
                                ayah = min(Quran.shared.ayahCount(surah), ayah + 1)
                                audio.play(global: Quran.shared.globalIndex(surah, ayah), reciter: store.reciter)
                            }
                        }
                        HStack(spacing: 8) {
                            Chip(title: repeatAyah ? "تكرار: مفعّل" : "تكرار الآية", on: repeatAyah) {
                                repeatAyah.toggle()
                            }
                            Chip(title: sleepMinutes == 0 ? "مؤقّت نوم" : "نوم: \(fmt(sleepMinutes)) د",
                                 on: sleepMinutes > 0) {
                                sleepMinutes = sleepMinutes == 0 ? 30 : 0
                            }
                        }
                        if repeatAyah {
                            Text("🔁 هيفضل يعيد الآية لحد ما توقف").font(.system(size: 10)).foregroundStyle(P.sub)
                        }
                        if audio.loading { ProgressView().tint(P.gold) }
                        if !audio.lastError.isEmpty {
                            Text(audio.lastError).font(.system(size: 10)).foregroundStyle(P.amber)
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 26)
        }
        .onChange(of: surah) { _, _ in ayah = 1 }
    }

    private func stepper(_ title: String, _ value: String, dec: @escaping () -> Void, inc: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundStyle(P.sub)
            HStack(spacing: 10) {
                Button("−") { dec() }.foregroundStyle(P.gold)
                Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(P.txt)
                    .frame(minWidth: 70)
                Button("+") { inc() }.foregroundStyle(P.gold)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(P.surface))
    }
}

// MARK: - more

struct MoreView: View {
    @EnvironmentObject private var app: AppState
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Card {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("عن نور").font(.system(size: 14, weight: .bold)).foregroundStyle(P.gold)
                        Text("نور ١٫٠ لآيفون — نفس محرك التصحيح اللي في نسخة أندرويد: محاذاة كلمة-بكلمة، حركات، وتقرير واحد لكل الأخطاء.")
                            .font(.system(size: 11)).foregroundStyle(P.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Card {
                    VStack(alignment: .trailing, spacing: 8) {
                        Toggle(isOn: $app.hideTashkeel) {
                            Text("إخفاء التشكيل في التقرير").font(.system(size: 12)).foregroundStyle(P.txt)
                        }
                        .tint(P.gold)
                    }
                }
                if !app.lastCrash.isEmpty {
                    Card {
                        VStack(alignment: .trailing, spacing: 6) {
                            Text("⚠ تقرير آخر خطأ").font(.system(size: 13, weight: .bold)).foregroundStyle(P.gold)
                            Text(app.lastCrash).font(.system(size: 9)).foregroundStyle(P.sub)
                            GrayButton(title: "📋 انسخ") { UIPasteboard.general.string = app.lastCrash }
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 26)
        }
    }
}

// MARK: - ayah actions sheet (bookmark · note · study)

struct IdentifiableInt: Identifiable {
    let value: Int
    var id: Int { value }
    init(_ v: Int) { value = v }
}

struct AyahSheet: View {
    var global: Int
    @Binding var note: String
    var isBookmarked: Bool
    var onBookmark: () -> Void
    var onSaveNote: () -> Void
    var onStudy: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let (s, a) = Quran.shared.toSurahAyah(global)
            let text = Quran.shared.ayah(s, a)
            ScrollView {
                VStack(alignment: .trailing, spacing: 12) {
                    Text("\(Quran.shared.surah(s)?.t ?? "") · آية \(fmt(a))")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(P.gold)
                    Text(text).font(.system(size: 20)).foregroundStyle(P.txt)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    HStack(spacing: 8) {
                        GrayButton(title: isBookmarked ? "★ إزالة العلامة" : "☆ علّم") { onBookmark() }
                        GrayButton(title: "نسخ") {
                            UIPasteboard.general.string = "\(text) — \(Quran.shared.surah(s)?.t ?? "") \(a)"
                        }
                        GrayButton(title: "مشاركة") { /* ShareLink below */ }
                    }
                    ShareLink(item: "\(text) — \(Quran.shared.surah(s)?.t ?? "") \(a)") {
                        Text("📤 مشاركة الآية").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(P.txt).frame(maxWidth: .infinity)
                            .padding(.vertical, 11).background(Capsule().fill(P.card2))
                    }
                    GoldButton(title: "🎙 اقرأها واختبرها") { onStudy(); dismiss() }
                    Text("📝 ملاحظة").font(.system(size: 12, weight: .bold)).foregroundStyle(P.gold)
                    TextEditor(text: $note)
                        .frame(height: 90)
                        .scrollContentBackground(.hidden)
                        .background(RoundedRectangle(cornerRadius: 12).fill(P.card2))
                        .foregroundStyle(P.txt)
                        .onChange(of: note) { _, _ in onSaveNote() }
                }
                .padding(16)
            }
            .navigationTitle("الآية")
            .toolbar { Button("تمام") { dismiss() } }
        }
    }
}
