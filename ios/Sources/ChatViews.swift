import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

// MARK: 对话页
struct ChatView: View {
    @ObservedObject var agent = Agent.shared
    @StateObject private var voice = Voice()
    @AppStorage("autoSend") private var autoSend = false
    @State private var input = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhoto = false
    @State private var showFile = false
    @State private var showHistory = false
    @State private var showShare = false
    @State private var preview: URL?
    @FocusState private var focus: Bool

    private let ideas: [(String, String)] = [
        ("alarm", "明早十点叫我起床"),
        ("calendar.badge.clock", "一周后下午三点提醒我交报告"),
        ("sparkles", "每天早上八点总结我的待办"),
        ("arrow.triangle.2.circlepath", "把图片转成 PDF")
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if agent.msgs.isEmpty { emptyState }
                    LazyVStack(spacing: 14) {
                        ForEach(agent.msgs) { MsgRow(m: $0, preview: $preview) }
                        if agent.busy {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("思考中…").foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Color(.systemGroupedBackground))
                .onChange(of: agent.msgs.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: agent.busy) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("TSTZ Bot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                        .disabled(agent.msgs.isEmpty)
                    Button { agent.newChat() } label: { Image(systemName: "square.and.pencil") }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focus = false }
                }
            }
            .sheet(isPresented: $showHistory) { HistoryView() }
            .sheet(isPresented: $showShare) { ShareView() }
            .photosPicker(isPresented: $showPhoto, selection: $photoItem, matching: .images)
            .fileImporter(isPresented: $showFile, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
                for u in (try? r.get()) ?? [] {
                    if let c = Store.copyIn(u) { agent.attachments.append(Attach(url: c)) }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let d = try? await item.loadTransferable(type: Data.self) {
                        let u = Store.stamped("照片", "jpg")
                        try? d.write(to: u)
                        agent.attachments.append(Attach(url: u))
                    }
                    photoItem = nil
                }
            }
            .quickLookPreview($preview)
            .onAppear {
                voice.onText = { input = $0 }
                voice.onFinished = { t in if autoSend && !t.isEmpty { send() } }
            }
        }
    }

    // MARK: 空状态
    var emptyState: some View {
        VStack(spacing: 14) {
            LogoMark(size: 76).padding(.top, 36)
            Text("你好，我是 TSTZ Bot").font(.title2.bold())
            Text("说出你想做的事，我来帮你完成").foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ideas, id: \.1) { idea in
                    Button {
                        input = idea.1
                        focus = true
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: idea.0).font(.title3).foregroundStyle(Color.accentColor)
                            Text(idea.1).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding(.bottom, 12)
    }

    // MARK: 输入区
    var inputBar: some View {
        VStack(spacing: 8) {
            if !voice.error.isEmpty {
                Text(voice.error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
            if !agent.attachments.isEmpty { attachmentRow }
            if voice.listening { listeningBar } else { typeBar }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    var typeBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Menu {
                Button { paste() } label: { Label("粘贴", systemImage: "doc.on.clipboard") }
                Button { showPhoto = true } label: { Label("照片", systemImage: "photo") }
                Button { showFile = true } label: { Label("文件", systemImage: "paperclip") }
            } label: {
                Image(systemName: "plus").font(.title3.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Circle())
            }
            TextField("发消息给 TSTZ Bot", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($focus)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            actionButton
        }
    }

    var actionButton: some View {
        let empty = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && agent.attachments.isEmpty
        return Button {
            if empty { focus = false; voice.start() } else { send() }
        } label: {
            Image(systemName: empty ? "mic.fill" : "arrow.up")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.accentColor)
                .clipShape(Circle())
        }
        .disabled(agent.busy && !empty)
    }

    var listeningBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(0..<14, id: \.self) { i in
                    Capsule().fill(Color.accentColor)
                        .frame(width: 3, height: 8 + voice.level * 22 * CGFloat(abs(sin(Double(i) * 0.9))))
                }
            }
            .frame(height: 34)
            .animation(.easeOut(duration: 0.1), value: voice.level)
            Text(voice.live.isEmpty ? "正在聆听，说完点右边按钮" : voice.live)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { voice.stop() } label: {
                Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Color.accentColor).clipShape(Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    var attachmentRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(agent.attachments) { a in
                        ZStack(alignment: .topTrailing) {
                            thumb(a.url)
                            Button { agent.attachments.removeAll { $0.id == a.id } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.white, Color.black.opacity(0.6))
                            }
                            .offset(x: 6, y: -6)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
            }
            if agent.attachments.contains(where: { Convert.imgExt.contains($0.url.pathExtension.lowercased()) }) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("识别文字")
                        chip("转成PDF")
                        chip("转成PNG")
                    }
                }
            }
        }
    }

    func thumb(_ u: URL) -> some View {
        Group {
            if let ui = UIImage(contentsOfFile: u.path), Convert.imgExt.contains(u.pathExtension.lowercased()) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Image(systemName: "doc").font(.title2).foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 60, height: 60)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func chip(_ t: String) -> some View {
        Button(t) { input = t; send() }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.14))
            .clipShape(Capsule())
    }

    func send() {
        let t = input
        input = ""
        focus = false
        if voice.listening { voice.stop() }
        Task { await agent.send(t) }
    }

    func paste() {
        let pb = UIPasteboard.general
        if let img = pb.image, let d = img.pngData() {
            let u = Store.stamped("粘贴图片", "png")
            try? d.write(to: u)
            agent.attachments.append(Attach(url: u))
        } else if let s = pb.string {
            input += s
            focus = true
        }
    }
}

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
