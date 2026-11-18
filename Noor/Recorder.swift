import Foundation
import AVFoundation
import SwiftUI

/// Records the recitation to an m4a file inside the app (works with no speech service at all),
/// plays it back, and exports it to the Files app so it can be sent anywhere.
@MainActor
final class AudioFileRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var level = 0
    @Published var seconds = 0
    @Published var message = ""

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("noor-recitation.m4a")
    }

    func start() {
        Task {
            let ok = await AVAudioApplication.requestRecordPermission()
            guard ok else { message = "❌ إذن المايك مرفوض"; return }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try session.setActive(true)

                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
                let url = AudioFileRecorder.fileURL
                try? FileManager.default.removeItem(at: url)
                let r = try AVAudioRecorder(url: url, settings: settings)
                r.isMeteringEnabled = true
                r.record()
                recorder = r
                isRecording = true
                seconds = 0
                message = ""
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                    Task { @MainActor in self.tick() }
                }
            } catch {
                message = "⚠ تعذّر التسجيل: \(error.localizedDescription)"
            }
        }
    }

    private func tick() {
        guard let r = recorder, r.isRecording else { return }
        r.updateMeters()
        let db = r.averagePower(forChannel: 0)          // -160…0
        level = Int(max(0, min(100, (db + 55) * 1.8)))
        seconds = Int(r.currentTime)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        level = 0
        message = "اتحفظ: noor-recitation.m4a (\(sizeText))"
    }

    func play() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            player = try AVAudioPlayer(contentsOf: AudioFileRecorder.fileURL)
            player?.play()
            message = "بيشتغل…"
        } catch {
            message = "مفيش تسجيل يتشغّل"
        }
    }

    func export() {
        let src = AudioFileRecorder.fileURL
        guard FileManager.default.fileExists(atPath: src.path) else { message = "مفيش تسجيل"; return }
        let url = src
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.keyWindow?.rootViewController {
            root.present(av, animated: true)
        }
    }

    private var sizeText: String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: AudioFileRecorder.fileURL.path)
        let bytes = (attrs?[.size] as? Int) ?? 0
        return "\(fmt(bytes / 1024)) ك.ب"
    }
}

/// keeps the audio session alive between screens
final class AudioKeepAlive {
    static let shared = AudioKeepAlive()
    func activate() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio,
                                                        options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
