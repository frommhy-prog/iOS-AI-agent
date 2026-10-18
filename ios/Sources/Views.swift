import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook
import UserNotifications

final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

@main
struct TSTZAgentApp: App {
    @Environment(\.scenePhase) private var phase
    init() { UNUserNotificationCenter.current().delegate = NotifDelegate.shared }
    var body: some Scene {
        WindowGroup { RootView().preferredColorScheme(.dark) }
            .onChange(of: phase) { _, p in
                if p == .active { Task { await Tasks.refresh(); await Evolve.run() } }
            }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            ChatView().tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right") }
            KBView().tabItem { Label("知识库", systemImage: "books.vertical") }
            ToolsView().tabItem { Label("工具", systemImage: "wand.and.stars") }
            TasksView().tabItem { Label("任务", systemImage: "clock.badge.checkmark") }
        }
        .tint(T.mint)
    }
}

// MARK: 对话
struct ChatView: View {
    @ObservedObject var agent = Agent.shared
    @StateObject var voice = Voice()
    @State private var input = ""
    @State private var photo: PhotosPickerItem?
    @State private var showFile = false
    @State private var preview: URL?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TSTZ Agent").font(.title2.bold())
                Spacer()
                Text("联网 · 端侧模型").font(.caption).foregroundStyle(T.mint)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(T.mint.opacity(0.15)).clipShape(Capsule())
            }
            .padding(.horizontal, 16).padding(.top, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(agent.msgs) { bubble($0) }
                        if agent.busy { ProgressView().tint(T.mint) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(16)
                }
                .onChange(of: agent.msgs.count) { _, _ in withAnimation { proxy.scrollTo("end") } }
            }
            inputArea
        }
        .background(T.bg)
        .fileImporter(isPresented: $showFile, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            for u in (try? r.get()) ?? [] {
                if let c = Store.copyIn(u) { agent.attachments.append(Attach(url: c)) }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let d = try? await item.loadTransferable(type: Data.self) {
                    let u = Store.dir("Inbox").appendingPathComponent("photo-\(Int(Date().timeIntervalSince1970)).jpg")
                    try? d.write(to: u)
                    agent.attachments.append(Attach(url: u))
                }
                photo = nil
            }
        }
        .onChange(of: voice.text) { _, t in if voice.listening { input = t } }
        .quickLookPreview($preview)
    }

    func bubble(_ m: Msg) -> some View {
        let me = m.role == "user"
        return VStack(alignment: me ? .trailing : .leading, spacing: 6) {
            if !m.text.isEmpty {
                Text(m.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(me ? T.mint : T.card)
                    .foregroundStyle(me ? Color.black.opacity(0.85) : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .textSelection(.enabled)
            }
            ForEach(m.files, id: \.self) { u in
                VStack(alignment: .leading, spacing: 6) {
                    if let ui = UIImage(contentsOfFile: u.path) {
                        Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    HStack {
                        Button { preview = u } label: { Label(u.lastPathComponent, systemImage: "doc").lineLimit(1) }
                        ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }
                    }
                    .font(.footnote)
                }
                .padding(8).background(T.card).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: me ? .trailing : .leading)
    }

    var inputArea: some View {
        VStack(spacing: 8) {
            if !agent.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(agent.attachments) { a in
                            HStack(spacing: 4) {
                                Image(systemName: "paperclip")
                                Text(a.url.lastPathComponent).lineLimit(1)
                                Button { agent.attachments.removeAll { $0.id == a.id } } label: { Image(systemName: "xmark.circle.fill") }
                            }
                            .font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(T.card).clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            HStack(spacing: 20) {
                Button { paste() } label: { Label("粘贴", systemImage: "doc.on.clipboard") }
                PhotosPicker(selection: $photo, matching: .images) { Label("图片", systemImage: "photo") }
                Button { showFile = true } label: { Label("文件", systemImage: "paperclip") }
                Button { voice.toggle() } label: { Label(voice.listening ? "停止" : "语音", systemImage: voice.listening ? "stop.circle.fill" : "mic") }
                    .foregroundStyle(voice.listening ? Color.red : T.mint)
                Spacer()
            }
            .font(.footnote).foregroundStyle(T.mint).padding(.horizontal, 16)
            HStack(spacing: 10) {
                TextField("问点什么，或交代任务", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(T.card).clipShape(RoundedRectangle(cornerRadius: 16))
                Button {
                    let t = input
                    input = ""
                    if voice.listening { voice.stop() }
                    Task { await agent.send(t) }
                } label: {
                    Image(systemName: "arrow.up").font(.headline).foregroundStyle(.black)
                        .frame(width: 42, height: 42).background(T.mint).clipShape(Circle())
                }
                .disabled(agent.busy)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(T.bg)
    }

    func paste() {
        let pb = UIPasteboard.general
        if let img = pb.image, let d = img.pngData() {
            let u = Store.dir("Inbox").appendingPathComponent("paste-\(Int(Date().timeIntervalSince1970)).png")
            try? d.write(to: u)
            agent.attachments.append(Attach(url: u))
        } else if let s = pb.string {
            input += s
        }
    }
}

// MARK: 知识库
struct KBView: View {
    @ObservedObject var folders = Folders.shared
    @State private var docs: [Row] = []
    @State private var q = ""
    @State private var hits: [String] = []
    @State private var pick = false
    @State private var pickFolder = false
    @State private var info = ""

    var body: some View {
        NavigationStack {
            List {
                Section("语义检索") {
                    TextField("描述你要找的内容", text: $q).onSubmit { hits = KB.shared.search(q, k: 5) }
                    ForEach(hits, id: \.self) { Text($0).font(.footnote) }
                }
                Section("文档 \(docs.count) 个") {
                    ForEach(docs.indices, id: \.self) { i in
                        VStack(alignment: .leading) {
                            Text(docs[i].s("name"))
                            Text("\(docs[i].i("n")) 片段").font(.caption).foregroundStyle(T.mute)
                        }
                    }
                    .onDelete { idx in
                        for i in idx { KB.shared.delete(docs[i].i("id")) }
                        reload()
                    }
                    if !info.isEmpty { Text(info).font(.caption).foregroundStyle(T.mint) }
                }
                Section("已授权文件夹（助理可查找、读取）") {
                    ForEach(Array(folders.names.enumerated()), id: \.offset) { _, n in Text(n) }
                        .onDelete { idx in for i in idx { folders.remove(at: i) } }
                    Button("授权文件夹") { pickFolder = true }
                        .fileImporter(isPresented: $pickFolder, allowedContentTypes: [.folder]) { r in
                            if let u = try? r.get() { folders.add(u) }
                        }
                }
            }
            .navigationTitle("知识库")
            .toolbar { Button("导入") { pick = true } }
            .fileImporter(isPresented: $pick, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
                var n = 0
                for u in (try? r.get()) ?? [] { n += KB.shared.ingest(u) > 0 ? 1 : 0 }
                info = "已导入 \(n) 个文件"
                reload()
            }
            .onAppear(perform: reload)
        }
    }

    func reload() { docs = KB.shared.docs() }
}

// MARK: 工具
struct ToolsView: View {
    @State private var file: URL?
    @State private var pick = false
    @State private var target = ""
    @State private var outs: [URL] = []
    @State private var busy = false
    @State private var err = ""
    @State private var preview: URL?
    @State private var skills: [Row] = []
    @State private var newSkill = ""
    @State private var skillOut = ""
    @State private var packPick = false

    var targets: [String] {
        guard let f = file else { return [] }
        let e = f.pathExtension.lowercased()
        if Convert.imgExt.contains(e) { return ["jpg", "png", "heic", "pdf", "tiff", "gif", "bmp", "txt"] }
        if e == "pdf" { return ["png", "jpg", "txt"] }
        if Convert.vidExt.contains(e) { return ["mp4", "mov", "m4a", "compress", "jpg"] }
        return ["csv", "json", "md", "html", "txt", "tsv", "pdf"]
    }

    var body: some View {
        NavigationStack {
            List {
                Section("文件格式转换") {
                    Button(file == nil ? "选择文件" : file!.lastPathComponent) { pick = true }
                    if !targets.isEmpty {
                        Picker("转成", selection: $target) { ForEach(targets, id: \.self) { Text($0).tag($0) } }
                        Button(busy ? "转换中…" : "开始转换") { convert() }.disabled(busy)
                    }
                    if !err.isEmpty { Text(err).font(.caption).foregroundStyle(.red) }
                    ForEach(outs, id: \.self) { u in
                        HStack {
                            Button { preview = u } label: { Label(u.lastPathComponent, systemImage: "doc").lineLimit(1) }
                            Spacer()
                            if Convert.imgExt.contains(u.pathExtension.lowercased()) || Convert.vidExt.contains(u.pathExtension.lowercased()) {
                                Button("存相册") { saveToPhotos(u) }.font(.caption)
                            }
                            ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }
                        }
                    }
                    Text("支持：图片 ↔ PDF/HEIC/PNG/JPG/文字识别；PDF → 图片/文字；表格 csv/json/md/html；视频 mp4/mov/m4a/压缩/截帧").font(.caption).foregroundStyle(T.mute)
                }
                Section("脚本技能（JS）") {
                    ForEach(skills.indices, id: \.self) { i in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(skills[i].s("name"))
                                Text(skills[i].s("desc")).font(.caption).foregroundStyle(T.mute)
                            }
                            Spacer()
                            Button("运行") { skillOut = Skills.run(skills[i].s("name"), "") }
                        }
                    }
                    .onDelete { idx in for i in idx { Skills.remove(skills[i].s("name")) }; reload() }
                    if !skillOut.isEmpty { Text(skillOut).font(.footnote).textSelection(.enabled) }
                    TextField("一句话描述想要的脚本", text: $newSkill)
                    Button("让助理创建并保存") {
                        let t = newSkill
                        newSkill = ""
                        Task { _ = await Agent.shared.send("创建脚本技能并保存：" + t); reload() }
                    }
                    Button("导入脚本包（.json）") { packPick = true }
                }
                Section("快捷指令") {
                    Link("打开快捷指令 App", destination: URL(string: "shortcuts://")!)
                    Link("新建快捷指令", destination: URL(string: "shortcuts://create-shortcut")!)
                    Text("本 App 已向快捷指令提供动作：询问助理、检索知识库、加入知识库、N 分钟后提醒。在快捷指令里搜索 TSTZ 添加，配合「自动化」可定时触发。")
                        .font(.caption).foregroundStyle(T.mute)
                }
            }
            .navigationTitle("工具")
            .fileImporter(isPresented: $pick, allowedContentTypes: [.item]) { r in
                if let u = try? r.get(), let c = Store.copyIn(u) {
                    file = c
                    outs = []
                    err = ""
                    target = targets.first ?? ""
                }
            }
            .fileImporter(isPresented: $packPick, allowedContentTypes: [.json]) { r in
                if let u = try? r.get() { Skills.importPack(u); reload() }
            }
            .quickLookPreview($preview)
            .onAppear(perform: reload)
        }
    }

    func reload() { skills = Skills.list() }

    func convert() {
        guard let f = file else { return }
        busy = true
        err = ""
        Task {
            do { outs = try await Convert.run(f, to: target) } catch { err = error.localizedDescription }
            busy = false
        }
    }

    func saveToPhotos(_ u: URL) {
        if let img = UIImage(contentsOfFile: u.path) { UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil) }
        else if Convert.vidExt.contains(u.pathExtension.lowercased()) { UISaveVideoAtPathToSavedPhotosAlbum(u.path, nil, nil, nil) }
    }
}

// MARK: 任务与进化
struct TasksView: View {
    @State private var tasks: [Row] = []
    @State private var text = ""
    @State private var vers: [Row] = []
    @State private var info = ""

    var body: some View {
        NavigationStack {
            List {
                Section("新建定时任务") {
                    TextField("例：每天早上8点总结我的待办", text: $text)
                    Button("交给助理创建") {
                        let t = text
                        text = ""
                        Task {
                            let r = await Agent.shared.quick("设定定时任务：" + t)
                            info = r
                            reload()
                        }
                    }
                    if !info.isEmpty { Text(info).font(.caption).foregroundStyle(T.mint) }
                }
                Section("任务") {
                    ForEach(tasks.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tasks[i].s("title"))
                            Text(Sys.fmt(Date(timeIntervalSince1970: tasks[i].d("due"))) + (tasks[i].i("rep") == 1 ? " · 每天" : "") + (tasks[i].i("state") == 1 ? " · 已完成" : " · 待执行"))
                                .font(.caption).foregroundStyle(T.mute)
                            if !tasks[i].s("result").isEmpty { Text(tasks[i].s("result")).font(.caption) }
                        }
                    }
                    .onDelete { idx in for i in idx { Tasks.remove(tasks[i].i("id")) }; reload() }
                    Button("立即准备并安排通知") { Task { await Tasks.refresh(); reload() } }
                }
                Section("进化") {
                    Text("上次进化：" + (Evolve.lastTime().map { Sys.fmtFull($0) } ?? "尚未进行")).font(.caption)
                    Button("立即进化") { Task { await Evolve.run(force: true); reload() } }
                    ForEach(vers.indices, id: \.self) { i in
                        VStack(alignment: .leading) {
                            Text("v\(vers[i].i("ver"))" + (i == 0 ? "（当前）" : "")).font(.caption.bold())
                            Text(vers[i].s("body")).font(.caption).foregroundStyle(T.mute)
                            if i > 0 { Button("回滚到此版本") { Evolve.rollback(vers[i].s("body")); reload() }.font(.caption) }
                        }
                    }
                }
            }
            .navigationTitle("任务与进化")
            .onAppear(perform: reload)
        }
    }

    func reload() {
        tasks = Tasks.list()
        vers = Evolve.versions()
    }
}
