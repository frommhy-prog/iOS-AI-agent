import SwiftUI
import UserNotifications
import UIKit

final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

@main
struct TSTZBotApp: App {
    @Environment(\.scenePhase) private var phase
    @AppStorage("appearance") private var appearance = 0

    init() {
        UNUserNotificationCenter.current().delegate = NotifDelegate.shared
        // 主题只保留「跟随系统 / 浅色 / 深色」，升级后默认恢复为跟随系统
        let ud = UserDefaults.standard
        if !ud.bool(forKey: "themeReset05") {
            ud.set(0, forKey: "appearance")
            ud.set(true, forKey: "themeReset05")
        }
    }

    private var scheme: ColorScheme? {
        switch appearance {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(scheme)
                .tint(Brand.accent)
                .onOpenURL { URLRouter.handle($0) }
        }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await Tasks.refresh(); await Evolve.run() } }
        }
    }
}

// 其他应用调用：tstzbot://ask?q=问题   tstzbot://run?name=技能名&input=内容&x-success=回调地址
// 内部回调：tstzbot://clock（系统时钟闹钟）  tstzbot://connector（连接器结果）
enum URLRouter {
    @MainActor static func handle(_ url: URL) {
        guard url.scheme == "tstzbot" else { return }
        var q: [String: String] = [:]
        for i in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { q[i.name] = i.value ?? "" }
        AppState.shared.drawer = false
        AppState.shared.page = nil
        switch url.host {
        case "ask":
            Agent.shared.start(q["q"] ?? "")
        case "run":
            let out = Skills.run(q["name"] ?? "", q["input"] ?? "").1
            if let s = q["x-success"], var c = URLComponents(string: s) {
                c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "result", value: out)]
                if let u = c.url { Task { await UIApplication.shared.open(u) } }
            }
        case "clock":
            ClockBridge.callback(q)
        case "connector":
            Connectors.callback(q)
        default:
            break
        }
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// 应用标志：TSTZ 字母 + 海军蓝与金色
struct LogoMark: View {
    var size: CGFloat = 64
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.06, green: 0.14, blue: 0.32), Color(red: 0.01, green: 0.04, blue: 0.13)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(spacing: 0) {
                HStack(spacing: 0) { letter("T", .white); letter("S", .white) }
                HStack(spacing: 0) { letter("T", .white); letter("Z", Theme.gold) }
            }
        }
        .frame(width: size, height: size)
    }

    private func letter(_ s: String, _ c: Color) -> some View {
        Text(s)
            .font(.system(size: size * 0.34, weight: .black, design: .rounded))
            .foregroundStyle(c)
            .frame(width: size * 0.4, height: size * 0.4)
    }
}

// 文件卡片：图片显示缩略图（读不出来会明确提示），其他显示类型与大小
struct FileCard: View {
    let url: URL
    @Binding var preview: URL?

    private var ext: String { url.pathExtension.lowercased() }
    private var isImage: Bool { Convert.imgExt.contains(ext) }

    private var kind: (String, String) {
        if isImage { return ("photo", "图片") }
        if ext == "pdf" { return ("doc.richtext", "PDF 文档") }
        if ["csv", "tsv", "json"].contains(ext) { return ("tablecells", "表格数据") }
        if ["txt", "md", "html", "rtf"].contains(ext) { return ("doc.text", "文本文档") }
        if Convert.vidExt.contains(ext) { return ("film", "视频") }
        if ext == "m4a" { return ("waveform", "音频") }
        return ("doc", "文件")
    }

    private var sizeText: String {
        guard let n = Files.size(url) else { return "文件不存在" }
        return n == 0 ? "空文件" : ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isImage {
                if let ui = Files.thumb(url, max: 900) {
                    Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onTapGesture { preview = url }
                } else {
                    Label("这张图片无法读取", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.red)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: kind.0).font(.title3).foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.1).font(.subheadline.weight(.medium)).foregroundStyle(Brand.ink)
                    Text(sizeText).font(.footnote).foregroundStyle(Brand.sub)
                }
                Spacer(minLength: 12)
                Button { preview = url } label: { Image(systemName: "eye") }
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .padding(12)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Brand.line, lineWidth: 1))
        .frame(maxWidth: 300, alignment: .leading)
    }
}
