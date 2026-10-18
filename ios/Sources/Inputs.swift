import Foundation
import UIKit
import Speech
import AVFoundation
import Vision

// 语音输入：优先端侧识别（中文）
final class Voice: ObservableObject {
    @Published var listening = false
    @Published var text = ""
    private let rec = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let engine = AVAudioEngine()
    private var req: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() { listening ? stop() : start() }

    func start() {
        SFSpeechRecognizer.requestAuthorization { st in
            guard st == .authorized else { return }
            AVAudioApplication.requestRecordPermission { ok in
                guard ok else { return }
                DispatchQueue.main.async { self.begin() }
            }
        }
    }

    private func begin() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.record, mode: .measurement, options: .duckOthers)
            try s.setActive(true, options: .notifyOthersOnDeactivation)
            let r = SFSpeechAudioBufferRecognitionRequest()
            r.shouldReportPartialResults = true
            if rec?.supportsOnDeviceRecognition == true { r.requiresOnDeviceRecognition = true }
            req = r
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { b, _ in r.append(b) }
            engine.prepare()
            try engine.start()
            text = ""
            listening = true
            task = rec?.recognitionTask(with: r) { [weak self] res, err in
                DispatchQueue.main.async {
                    if let res { self?.text = res.bestTranscription.formattedString }
                    if err != nil || res?.isFinal == true { self?.stop() }
                }
            }
        } catch {
            listening = false
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        req?.endAudio()
        task?.cancel()
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

// 图片文字识别（端侧 Vision）
enum OCR {
    static func text(_ url: URL) -> String {
        guard let cg = UIImage(contentsOfFile: url.path)?.cgImage else { return "" }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["zh-Hans", "en-US"]
        req.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

// 用户授权的文件夹（iOS 只允许读取授权过的位置）
final class Folders: ObservableObject {
    static let shared = Folders()
    @Published var names: [String] = []
    private var urls: [URL] = []

    init() { reload() }

    func reload() {
        let arr = UserDefaults.standard.array(forKey: "folders") as? [Data] ?? []
        urls = arr.compactMap { d in
            var stale = false
            guard let u = try? URL(resolvingBookmarkData: d, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
            _ = u.startAccessingSecurityScopedResource()
            return u
        }
        names = urls.map { $0.lastPathComponent }
    }

    func add(_ u: URL) {
        _ = u.startAccessingSecurityScopedResource()
        guard let d = try? u.bookmarkData() else { return }
        var arr = UserDefaults.standard.array(forKey: "folders") as? [Data] ?? []
        arr.append(d)
        UserDefaults.standard.set(arr, forKey: "folders")
        reload()
    }

    func remove(at i: Int) {
        var arr = UserDefaults.standard.array(forKey: "folders") as? [Data] ?? []
        guard i < arr.count else { return }
        arr.remove(at: i)
        UserDefaults.standard.set(arr, forKey: "folders")
        reload()
    }

    func find(_ kw: String) -> [URL] {
        var out: [URL] = []
        let roots = urls + [Store.dir("Inbox"), Store.dir("Outputs")]
        for root in roots {
            guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let f as URL in en where f.lastPathComponent.localizedCaseInsensitiveContains(kw) {
                out.append(f)
                if out.count >= 15 { return out }
            }
        }
        return out
    }
}
