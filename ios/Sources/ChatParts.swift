import SwiftUI
import UIKit
import AVFoundation

// 朗读回答
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()
    @Published var speakingId: UUID?
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func toggle(_ text: String, id: UUID) {
        if speakingId == id {
            synth.stopSpeaking(at: .immediate)
            speakingId = nil
            return
        }
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let plain = text.replacingOccurrences(of: "[*#`>_]", with: "", options: .regularExpression)
        let u = AVSpeechUtterance(string: plain)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        speakingId = id
        synth.speak(u)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingId = nil }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingId = nil }
    }
}

struct ThinkingView: View {
    @State private var spin = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .foregroundStyle(Brand.ink)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: spin)
            Text("思考中…").foregroundStyle(Brand.sub)
        }
        .onAppear { spin = true }
    }
}

// 一条消息：我的消息在右侧浅色气泡；助理的回答直接排在页面上（Markdown、可复制、朗读、重新生成）
struct MessageView: View {
    let m: Msg
    let isLast: Bool
    @Binding var preview: URL?
    var onRegenerate: () -> Void
    @ObservedObject private var speaker = Speaker.shared
    @State private var copied = false

    var body: some View {
        if m.role == "user" { user } else { assistant }
    }

    var user: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(m.files, id: \.self) { FileCard(url: $0, preview: $preview) }
            if !m.text.isEmpty {
                Text(m.text)
                    .font(.system(size: 17))
                    .foregroundStyle(Brand.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Brand.userBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .contextMenu {
                        Button { UIPasteboard.general.string = m.text } label: { Label("复制", systemImage: "doc.on.doc") }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 44)
    }

    var assistant: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(m.files, id: \.self) { FileCard(url: $0, preview: $preview) }
            if m.text.isEmpty && m.streaming {
                ThinkingView()
            } else if !m.text.isEmpty {
                MarkdownText(text: m.text)
            }
            if !m.streaming && !m.text.isEmpty { actions }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var actions: some View {
        HStack(spacing: 20) {
            Button {
                UIPasteboard.general.string = m.text
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copied = false
                }
            } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
            Button { speaker.toggle(m.text, id: m.id) } label: {
                Image(systemName: speaker.speakingId == m.id ? "speaker.slash" : "speaker.wave.2")
            }
            ShareLink(item: m.text) { Image(systemName: "square.and.arrow.up") }
            if isLast {
                Button { onRegenerate() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(Brand.sub)
        .padding(.top, 2)
    }
}

// MARK: 分享对话（图片 / 文字）
struct ShareView: View {
    @ObservedObject var agent = Agent.shared
    @Environment(\.dismiss) private var dismiss
    @State private var scope = 0
    @State private var dark = false
    @State private var url: URL?
    @State private var image: UIImage?
    @State private var saved = false

    var chosen: [Msg] { scope == 1 ? Array(agent.msgs.suffix(2)) : Array(agent.msgs.suffix(30)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("范围", selection: $scope) {
                        Text("整段对话").tag(0)
                        Text("最近一轮").tag(1)
                    }
                    .pickerStyle(.segmented)
                    Picker("样式", selection: $dark) {
                        Text("浅色").tag(false)
                        Text("深色").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                    }
                    if let url, let image {
                        ShareLink(item: url, preview: SharePreview("TSTZ Bot 对话", image: Image(uiImage: image))) {
                            Label("分享图片到微信、QQ、微博等", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Button {
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            saved = true
                        } label: {
                            Label(saved ? "已保存到相册" : "保存到相册", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    ShareLink(item: agent.transcript(chosen)) {
                        Label("分享文字", systemImage: "text.bubble").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(16)
            }
            .background(Brand.bg)
            .navigationTitle("分享对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task(id: "\(scope)-\(dark)") { render() }
        }
        .presentationBackground(Brand.bg)
    }

    @MainActor func render() {
        let r = ImageRenderer(content: ShareCard(msgs: chosen, dark: dark))
        r.scale = 3
        guard let img = r.uiImage, let d = img.pngData() else { return }
        let u = Store.dir("Outputs").appendingPathComponent("TSTZ Bot 对话.png")
        try? d.write(to: u)
        image = img
        url = u
        saved = false
    }
}

struct ShareCard: View {
    let msgs: [Msg]
    let dark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                LogoMark(size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TSTZ Bot").font(.headline)
                    Text(Sys.fmtFull(Date())).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            ForEach(msgs) { m in
                let me = m.role == "user"
                HStack {
                    if me { Spacer(minLength: 40) }
                    Text(m.text.isEmpty ? "[文件]" : String(m.text.prefix(400)))
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(me ? (dark ? Color.white : Color.black) : (dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)))
                        .foregroundStyle(me ? (dark ? Color.black : Color.white) : (dark ? Color.white : Color.black))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    if !me { Spacer(minLength: 40) }
                }
            }
            Divider()
            HStack {
                Text("由 TSTZ Bot 生成").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Label("开发者微信 TSTZ-M", systemImage: "message.fill").font(.footnote.weight(.semibold))
            }
        }
        .padding(20)
        .frame(width: 390)
        .background(dark ? Color(red: 0.07, green: 0.08, blue: 0.11) : Color.white)
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}
