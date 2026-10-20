import SwiftUI
import UIKit

struct MsgRow: View {
    let m: Msg
    @Binding var preview: URL?

    var body: some View {
        let me = m.role == "user"
        VStack(alignment: me ? .trailing : .leading, spacing: 8) {
            ForEach(m.files, id: \.self) { FileCard(url: $0, preview: $preview) }
            if !m.text.isEmpty {
                Text(m.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(me ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                    .foregroundStyle(me ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contextMenu {
                        Button { UIPasteboard.general.string = m.text } label: { Label("复制", systemImage: "doc.on.doc") }
                        ShareLink(item: m.text) { Label("分享", systemImage: "square.and.arrow.up") }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: me ? .trailing : .leading)
    }
}

// MARK: 对话记录
struct HistoryView: View {
    @ObservedObject var agent = Agent.shared
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = []

    var body: some View {
        NavigationStack {
            List {
                Button { agent.newChat(); dismiss() } label: { Label("新建对话", systemImage: "square.and.pencil") }
                Section("历史对话") {
                    ForEach(rows.indices, id: \.self) { i in
                        Button { agent.open(rows[i].i("id")); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rows[i].s("title")).foregroundStyle(.primary).lineLimit(1)
                                Text(Sys.fmt(Date(timeIntervalSince1970: rows[i].d("ts")))).font(.footnote).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete { idx in
                        for i in idx { agent.deleteConv(rows[i].i("id")) }
                        rows = agent.convs()
                    }
                }
            }
            .navigationTitle("对话记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .onAppear { rows = agent.convs() }
        }
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
            .navigationTitle("分享对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task(id: "\(scope)-\(dark)") { render() }
        }
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
    @AppStorage("accent") private var accent = 0

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
                        .background(me ? Theme.accent(accent) : (dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)))
                        .foregroundStyle(me ? Color.white : (dark ? Color.white : Color.black))
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
