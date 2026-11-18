import SwiftUI
import Speech
import AVFoundation
import UIKit
import NoorKit

// MARK: - the free-mode recorder (continuous, never auto-checks)

@MainActor
final class ReciteEngine: ObservableObject {
    enum Method: String, CaseIterable { case voice = "🎤 اتكلم", audio = "🎙 مسجل", type = "⌨️ كتابة" }

    @Published var method: Method = .voice
    @Published var recording = false
    @Published var level = 0
    @Published var status = "اضغط المايك واقرأ براحتك"
    @Published var segments: [String] = []
    @Published var heard = ""            // live partial
    @Published var permissionDenied = false
    @Published var elapsed = 0

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audio = AVAudioEngine()
    private var ticker: Timer?

    // duplicate handling (the Android 5.6 fix, same rules)
    private var transcript = ""

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "ar"))
    }

    var fullTranscript: String { transcript }

    func appendTyped(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        transcript = transcript.isEmpty ? t : transcript + " " + t
        segments.append(t)
        status = "✅ اتضاف — لسه مسجل: \(fmt(transcript.split(separator: " ").count)) كلمة"
    }

    func reset() {
        stop()
        transcript = ""
        segments = []
        status = "اضغط المايك واقرأ براحتك"
    }

    // ---------------------------------------------------------------- permissions
    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        let ok = (speech == .authorized) && mic
        permissionDenied = !ok
        if !ok {
            status = speech == .denied
                ? "❌ إذن التعرّف مرفوض — الإعدادات ← نور ← التعرّف على الكلام"
                : "❌ إذن المايك مرفوض — الإعدادات ← نور ← الميكروفون"
        }
        return ok
    }

    // ---------------------------------------------------------------- voice
    func startVoice() {
        guard !recording else { stop(); return }
        Task {
            guard await requestPermissions() else { return }
            do { try beginSession() } catch {
                status = "⚠ تعذّر بدء المايك: \(error.localizedDescription)"
            }
        }
    }

    private func beginSession() throws {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            status = "❌ خدمة التعرّف مش متاحة — جرّب «مسجل» أو «كتابة»"
            return
        }
        // one engine, one recognizer, restarted only when iOS ends the task itself
        if !audio.isRunning { try startEngine() }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let input = audio.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.inputFormat(forBus: 0)) { [weak self] buf, _ in
            self?.request?.append(buf)
            let lvl = ReciteEngine.levelOf(buf)
            DispatchQueue.main.async { self?.level = lvl }
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.heard = text
                    if result.isFinal {
                        self.acceptSegment(text)
                        self.restartTask()
                    } else {
                        self.status = "🔴 … " + String(text.suffix(28))
                    }
                }
                if let error = error {
                    self.status = "… بيكمّل (iOS قطع الجملة)"
                    _ = error
                    self.restartTask()
                }
            }
        }
        recording = true
        status = "🔴 بيسجّل… اقرأ براحتك ومن غير ما تقف"
        startTicker()
    }

    private func startEngine() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        audio.prepare()
        try audio.start()
    }

    /// iOS ends a recognition task every ~60 s — restart it silently (never ask the user)
    private func restartTask() {
        guard recording else { return }
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        Task { @MainActor in
            do { try self.beginSession() }
            catch { self.status = "⚠ مشكلة في المايك: \(error.localizedDescription)" }
        }
    }

    private func acceptSegment(_ text: String) {
        let add = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !add.isEmpty else { return }
        let cur = transcript
        if cur.isEmpty { transcript = add }
        else if cur.hasSuffix(add) { return }
        else if add.count > cur.count && add.hasPrefix(cur) { transcript = add }
        else if cur.contains(add) { return }
        else { transcript = cur + " " + add }
        if segments.last != add { segments.append(add) }
        if segments.count > 40 { segments.removeFirst() }
        status = "✅ وصل: \"\(add.count > 30 ? String(add.prefix(30)) + "…" : add)\""
        heard = ""
    }

    func stop() {
        recording = false
        ticker?.invalidate(); ticker = nil
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        audio.inputNode.removeTap(onBus: 0)
        if audio.isRunning { audio.stop() }
        level = 0
        status = transcript.isEmpty ? "اضغط المايك واقرأ براحتك" : "التسجيل واقف — اضغط 🔍 فحص"
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            Task { @MainActor in self.elapsed += 0 }
        }
    }

    /// RMS of the buffer → 0…100 for the level bar
    static func levelOf(_ buf: AVAudioPCMBuffer) -> Int {
        guard let ch = buf.floatChannelData?[0] else { return 0 }
        let n = Int(buf.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = sqrt(sum / Float(n))
        return Int(min(100, max(0, rms * 900)))
    }
}

// MARK: - the whole free-recitation screen

struct FreeReciteView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var engine = ReciteEngine()
    @StateObject private var recorder = AudioFileRecorder()
    @State private var typed = ""
    @State private var checking = false
    @State private var showDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                hero
                methodPicker
                if engine.method == .voice { voiceCard }
                if engine.method == .audio { audioCard }
                if engine.method == .type { typeCard }

                HStack(spacing: 8) {
                    GoldButton(title: "🔍 فحص الكلام اللي قريته") { runCheck() }
                    GrayButton(title: "امسح") { engine.reset(); app.session = nil }
                }
                Text(counterText).font(.system(size: 11)).foregroundStyle(P.sub)

                if let s = app.session {
                    ReportView(session: s, hideTashkeel: app.hideTashkeel,
                               onResume: { app.session = nil; engine.startVoice() },
                               onClear: { engine.reset(); app.session = nil },
                               onOpenMushaf: { ayah in
                                   app.jumpGlobal = Quran.shared.globalIndex(s.sura, ayah)
                                   app.tabRequest = 1
                               })
                }
                else { hintCard }
            }
            .padding(.horizontal, 14).padding(.bottom, 26).padding(.top, 6)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView(engine: engine) }
    }

    // ---------------------------------------------------------------- pieces
    private var hero: some View {
        Card {
            VStack(alignment: .trailing, spacing: 6) {
                Text("🎧 اقرأ براحتك — وافحص لما تخلص")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(P.gold)
                Text("التسجيل مستمر ومش بيقاطعك، ومفيش فحص تلقائي. اضغط المايك واقرأ، ولما تخلص اضغط «فحص» مرة واحدة.")
                    .font(.system(size: 11)).foregroundStyle(P.sub)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Chip(title: app.hideTashkeel ? "بدون تشكيل" : "بالتشكيل", on: app.hideTashkeel) {
                        app.hideTashkeel.toggle()
                    }
                    Chip(title: "تشخيص", on: false) { showDiagnostics = true }
                }.padding(.top, 4)
            }
        }
    }

    private var methodPicker: some View {
        HStack(spacing: 6) {
            ForEach(ReciteEngine.Method.allCases, id: \.self) { m in
                Button {
                    engine.stop()
                    engine.method = m
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 11, weight: engine.method == m ? .bold : .regular))
                        .foregroundStyle(engine.method == m ? Color(hex: 0x1B1408) : P.sub)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Capsule().fill(engine.method == m ? P.gold : P.card2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var voiceCard: some View {
        Card {
            VStack(spacing: 10) {
                Button {
                    engine.startVoice()
                } label: {
                    ZStack {
                        Circle().fill(engine.recording ? P.red : P.gold).frame(width: 78, height: 78)
                        Text(engine.recording ? "⏸" : "🎙").font(.system(size: 30))
                    }
                }
                .buttonStyle(.plain)

                LevelBar(level: engine.level)
                HStack(spacing: 6) {
                    Text("🔈 مستوى الصوت").font(.system(size: 10)).foregroundStyle(P.sub)
                    Text(engine.level > 3 ? "واصل ✅" : "ساكت")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(engine.level > 3 ? P.teal : P.sub)
                }
                Text(engine.status)
                    .font(.system(size: 12, weight: engine.recording ? .semibold : .regular))
                    .foregroundStyle(engine.recording ? P.teal : P.sub)
                    .multilineTextAlignment(.center)

                if !engine.segments.isEmpty {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("آخر اللي وصل (\(fmt(engine.segments.count)) جملة)")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(P.sub)
                        ForEach(engine.segments.suffix(3), id: \.self) { s in
                            Text("• " + (s.count > 40 ? String(s.prefix(40)) + "…" : s))
                                .font(.system(size: 11)).foregroundStyle(P.txt)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(P.surface))
                }
            }
        }
    }

    private var audioCard: some View {
        Card {
            VStack(spacing: 10) {
                Button {
                    if recorder.isRecording { recorder.stop() } else { recorder.start() }
                } label: {
                    ZStack {
                        Circle().fill(recorder.isRecording ? P.red : Color(hex: 0xB3261E))
                            .frame(width: 76, height: 76)
                        Text(recorder.isRecording ? "⏹" : "🔴").font(.system(size: 28))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                LevelBar(level: recorder.level)
                Text(clock(recorder.seconds))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(recorder.isRecording ? P.teal : P.sub)
                Text(recorder.isRecording ? "🔴 بيسجّل — اقرأ براحتك ولا تستعجل"
                     : "سجّل قراءتك كملف صوتي (m4a) — يشتغل من غير أي خدمة تعرّف")
                    .font(.system(size: 11)).foregroundStyle(P.sub).multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    GrayButton(title: "▶ اسمع") { recorder.play() }
                    GrayButton(title: "📤 صدّر") { recorder.export() }
                }
                if !recorder.message.isEmpty {
                    Text(recorder.message).font(.system(size: 10)).foregroundStyle(P.gold)
                }
            }
        }
    }

    private var typeCard: some View {
        Card {
            VStack(spacing: 8) {
                TextEditor(text: $typed)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .background(RoundedRectangle(cornerRadius: 12).fill(P.surface))
                    .foregroundStyle(P.txt)
                    .font(.system(size: 14))
                    .overlay(alignment: .topTrailing) {
                        if typed.isEmpty {
                            Text("اكتب أو الصق اللي قرأته… (أو 🎤 في الكيبورد)")
                                .font(.system(size: 11)).foregroundStyle(P.sub)
                                .padding(10).allowsHitTesting(false)
                        }
                    }
                HStack(spacing: 8) {
                    GoldButton(title: "➕ ضيف للتسجيل") {
                        engine.appendTyped(typed); typed = ""
                    }
                    GrayButton(title: "📋 الصق") {
                        typed = UIPasteboard.general.string ?? ""
                    }
                }
                Text(engine.status).font(.system(size: 11)).foregroundStyle(P.sub)
            }
        }
    }

    private var hintCard: some View {
        Card(fill: P.surface) {
            VStack(alignment: .trailing, spacing: 6) {
                Text("إزاي بتستخدمها").font(.system(size: 13, weight: .bold)).foregroundStyle(P.gold)
                ForEach([
                    "١. اضغط المايك — بيسجّل بدون ما يقاطعك.",
                    "٢. اقرأ اللي إنت عايزه: آية، صفحة، أو ربع — مش لازم تكمل آية.",
                    "٣. لما تخلص اضغط «🔍 فحص» مرة واحدة.",
                    "٤. التقرير يقولك قريت منين لفين، وكل غلطة (حرف/حركة/كلمة ناقصة) في قايمة واحدة.",
                    "٥. وفيه زرار «كمّل من الآية اللي بعدها»."
                ], id: \.self) { s in
                    Text(s).font(.system(size: 11)).foregroundStyle(P.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var counterText: String {
        let n = engine.fullTranscript.split(separator: " ").count
        if n == 0 { return "لسه مفيش كلام متسجل" }
        return app.session == nil ? "متسجل: \(fmt(n)) كلمة · مش متفحّص بعد" : "متسجل: \(fmt(n)) كلمة"
    }

    private func runCheck() {
        engine.stop()
        guard !Quran.shared.surahs.isEmpty else {
            engine.status = "⚠ بيانات القرآن مش محمّلة — أعد تثبيت التطبيق"
            return
        }
        let text = engine.fullTranscript
        guard !text.isEmpty else {
            engine.status = "لسه مفيش كلام متسجل — اضغط المايك الأول"
            return
        }
        checking = true
        Task.detached(priority: .userInitiated) {
            let s = ReciteCheck.analyze(text)
            await MainActor.run {
                app.session = s
                checking = false
                if !s.isEmpty {
                    Store.shared.addAttempt(sura: s.sura, percent: s.percent, haraka: s.harakaPercent)
                }
            }
        }
    }

    private func clock(_ s: Int) -> String { "\(fmt(s / 60)):\(s % 60 < 10 ? "٠" : "")\(fmt(s % 60))" }
}

// MARK: - report (all mistakes at once)

struct ReportView: View {
    var session: Session
    var hideTashkeel: Bool
    var onResume: () -> Void = {}
    var onClear: () -> Void = {}
    var onOpenMushaf: (Int) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 10) {
            Card {
                VStack(alignment: .trailing, spacing: 6) {
                    Text("📍 سورة \(Quran.shared.surah(session.sura)?.t ?? "") · \(session.ayahRange)")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(P.gold)
                    HStack(spacing: 10) {
                        stat("\(fmt(session.percent))%", "الدقة", session.percent >= 90 ? P.teal : (session.percent >= 60 ? P.amber : P.red))
                        stat(fmt(session.correct), "صح", P.teal)
                        stat(fmt(session.wrong), "غلط", P.red)
                        stat(fmt(session.missing), "ناقص", P.sub)
                        stat(fmt(session.wrongHarakat), "حركة", P.amber)
                    }
                    Text(session.feedback).font(.system(size: 11)).foregroundStyle(P.sub)
                }
            }

            ForEach(session.ayahs) { ac in AyahCard(check: ac, hideTashkeel: hideTashkeel) }

            if !session.mistakes.isEmpty {
                Card {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text("📋 كل الأخطاء (\(fmt(session.mistakes.count)))")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(P.gold)
                        ForEach(session.mistakes.prefix(60)) { m in
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("آية \(fmt(m.ayah)) · \(m.kind): \(strip(m.target))")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(P.txt)
                                if !m.got.isEmpty {
                                    Text("قلت: \(strip(m.got))").font(.system(size: 11)).foregroundStyle(P.sub)
                                }
                                if !m.detail.isEmpty {
                                    Text(m.detail).font(.system(size: 10)).foregroundStyle(P.amber)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.vertical, 5)
                            Divider().overlay(P.card2)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                GoldButton(title: "▶ كمّل من آية \(fmt(session.resumeAyah))") { onOpenMushaf(session.resumeAyah) }
                GrayButton(title: "🎤 كمّل تسجيل") { onResume() }
                GrayButton(title: "🔁 امسح") { onClear() }
            }
        }
    }

    private func stat(_ v: String, _ t: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 15, weight: .bold)).foregroundStyle(c)
            Text(t).font(.system(size: 9)).foregroundStyle(P.sub)
        }
        .frame(maxWidth: .infinity)
    }

    private func strip(_ s: String) -> String {
        hideTashkeel ? ReciteCheck.normalize(s) : s
    }
}

struct AyahCard: View {
    var check: AyahCheck
    var hideTashkeel: Bool

    var body: some View {
        Card(fill: P.paper) {
            VStack(alignment: .trailing, spacing: 8) {
                HStack {
                    Text("آية \(fmt(check.ayah))").font(.system(size: 11, weight: .bold)).foregroundStyle(P.inkSoft)
                    Spacer()
                    Text("\(fmt(check.result.percent))%").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(check.result.percent == 100 ? P.paperGreen : P.paperAmber)
                }
                Text(attributed).font(.system(size: 20)).multilineTextAlignment(.trailing)
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    /// the ayah with each word coloured by its verdict
    private var attributed: AttributedString {
        var out = AttributedString("")
        for w in check.result.words {
            let shown = hideTashkeel ? ReciteCheck.normalize(w.target) : w.target
            var piece = AttributedString(shown + " ")
            switch w.state {
            case .correct: piece.foregroundColor = P.paperGreen
            case .haraka: piece.foregroundColor = P.paperAmber
            case .wrong:
                piece.foregroundColor = P.paperRed
                piece.underlineStyle = .single
            case .missing:
                piece.foregroundColor = P.inkSoft.opacity(0.6)
                piece.underlineStyle = .single
            }
            out += piece
        }
        return out
    }
}

// MARK: - diagnostics

struct DiagnosticsView: View {
    var engine: ReciteEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                row("نظام التشغيل", UIDevice.current.systemVersion)
                row("خدمة التعرّف", SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))?.isAvailable == true ? "موجودة ✅" : "مش متاحة ❌")
                row("إذن التعرّف", authText(SFSpeechRecognizer.authorizationStatus()))
                row("إذن المايك", micText(AVAudioApplication.shared.recordPermission))
                row("مستوى الصوت", "\(fmt(engine.level))%")
                row("جمل وصلت", fmt(engine.segments.count))
                row("كلمات مسجلة", fmt(engine.fullTranscript.split(separator: " ").count))
            }
            .navigationTitle("تشخيص الصوت")
            .toolbar { Button("تمام") { dismiss() } }
        }
    }

    private func row(_ a: String, _ b: String) -> some View {
        HStack { Text(a); Spacer(); Text(b).foregroundStyle(.secondary) }
    }
    private func authText(_ s: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "ممنوح ✅"
        case .denied: return "مرفوض ❌"
        case .restricted: return "مقيّد ❌"
        case .notDetermined: return "لسه مش متحدد"
        @unknown default: return "?"
        }
    }
    private func micText(_ p: AVAudioApplication.recordPermission) -> String {
        switch p {
        case .granted: return "ممنوح ✅"
        case .denied: return "مرفوض ❌"
        case .undetermined: return "لسه مش متحدد"
        @unknown default: return "?"
        }
    }
}
