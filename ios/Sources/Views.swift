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

final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var tab = 0
}

@main
struct TSTZBotApp: App {
    @Environment(\.scenePhase) private var phase
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("accent") private var accent = 0

    init() { UNUserNotificationCenter.current().delegate = NotifDelegate.shared }

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
                .tint(Theme.accent(accent))
                .onOpenURL { URLRouter.handle($0) }
        }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await Tasks.refresh(); await Evolve.run() } }
        }
    }
}

// 其他应用调用：tstzbot://ask?q=问题   tstzbot://run?name=技能名&input=内容&x-success=回调地址
enum URLRouter {
    @MainActor static func handle(_ url: URL) {
        guard url.scheme == "tstzbot" else { return }
        var q: [String: String] = [:]
        for i in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { q[i.name] = i.value ?? "" }
        switch url.host {
        case "ask":
            AppState.shared.tab = 0
            Task { await Agent.shared.send(q["q"] ?? "") }
        case "run":
            let out = Skills.run(q["name"] ?? "", q["input"] ?? "").1
            if let s = q["x-success"], var c = URLComponents(string: s) {
                c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "result", value: out)]
                if let u = c.url { Task { await UIApplication.shared.open(u) } }
            }
        default:
            break
        }
    }
}

struct RootView: View {
    @ObservedObject var state = AppState.shared
    var body: some View {
        TabView(selection: $state.tab) {
            ChatView().tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right.fill") }.tag(0)
            KBView().tabItem { Label("知识库", systemImage: "books.vertical.fill") }.tag(1)
            ToolboxView().tabItem { Label("工具箱", systemImage: "square.grid.2x2.fill") }.tag(2)
            TasksView().tabItem { Label("任务", systemImage: "clock.badge.checkmark.fill") }.tag(3)
            SettingsView().tabItem { Label("设置", systemImage: "gearshape.fill") }.tag(4)
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

// 文件卡片：图片显示缩略图，其他显示类型与大小
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
        let n = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isImage, let ui = UIImage(contentsOfFile: url.path) {
                Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack(spacing: 10) {
                Image(systemName: kind.0).font(.title3).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.1).font(.subheadline.weight(.medium))
                    Text(sizeText).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button { preview = url } label: { Image(systemName: "eye") }
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: 300, alignment: .leading)
    }
}
