import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import UIKit

// MARK: 知识库
struct KBView: View {
    @ObservedObject var folders = Folders.shared
    @State private var docs: [Row] = []
    @State private var chunks = 0
    @State private var q = ""
    @State private var hits: [String] = []
    @State private var showPicker = false
    @State private var folderMode = false
    @State private var info = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        stat("文档", "\(docs.count)")
                        Divider()
                        stat("知识片段", "\(chunks)")
                    }
                    .frame(height: 56)
                }
                Section("搜索") {
                    TextField("描述你要找的内容", text: $q)
                        .submitLabel(.search)
                        .onSubmit { hits = KB.shared.search(q, k: 5) }
                    ForEach(hits, id: \.self) { Text($0).font(.subheadline).padding(.vertical, 2) }
                }
                Section("我的文档") {
                    if docs.isEmpty { Text("还没有文档，点右上角「导入」").foregroundStyle(.secondary) }
                    ForEach(docs.indices, id: \.self) { i in
                        HStack(spacing: 12) {
                            Image(systemName: icon(docs[i].s("name"))).foregroundStyle(Color.accentColor).frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title(docs[i].s("name"))).lineLimit(1)
                                Text("\(docs[i].i("n")) 个片段").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .onDelete { idx in
                        for i in idx { KB.shared.delete(docs[i].i("id")) }
                        reload()
                    }
                    if !info.isEmpty { Text(info).foregroundStyle(Color.accentColor) }
                }
                Section("已授权的文件夹（助理可查找、读取）") {
                    ForEach(Array(folders.names.enumerated()), id: \.offset) { _, n in
                        Label(n, systemImage: "folder")
                    }
                    .onDelete { idx in for i in idx { folders.remove(at: i) } }
                    Button {
                        folderMode = true
                        showPicker = true
                    } label: { Label("授权文件夹", systemImage: "folder.badge.plus") }
                }
            }
            .navigationTitle("知识库")
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        folderMode = false
                        showPicker = true
                    } label: { Label("导入", systemImage: "plus") }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { hideKeyboard() }
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: folderMode ? [.folder] : [.item], allowsMultipleSelection: true) { r in
                let urls = (try? r.get()) ?? []
                if folderMode {
                    for u in urls { folders.add(u) }
                    info = urls.isEmpty ? "" : "已授权 \(urls.count) 个文件夹"
                } else {
                    var n = 0
                    for u in urls { n += KB.shared.ingest(u) > 0 ? 1 : 0 }
                    info = "已导入 \(n) 个文档"
                }
                reload()
            }
            .onAppear(perform: reload)
        }
    }

    func stat(_ t: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title2.bold())
            Text(t).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    func title(_ n: String) -> String {
        if n == "记忆" { return "我的记忆" }
        if n == "进化提炼" { return "进化提炼的记忆" }
        if n.hasPrefix("技能:") { return "脚本技能 · " + n.dropFirst(3) }
        return n
    }

    func icon(_ n: String) -> String {
        if n == "记忆" || n == "进化提炼" { return "brain" }
        if n.hasPrefix("技能:") { return "wand.and.stars" }
        let e = (n as NSString).pathExtension.lowercased()
        if e == "pdf" { return "doc.richtext" }
        if ["csv", "tsv", "json"].contains(e) { return "tablecells" }
        return "doc.text"
    }

    func reload() {
        docs = KB.shared.docs()
        chunks = DB.shared.rows("SELECT COUNT(*) AS n FROM chunk").first?.i("n") ?? 0
    }
}

// MARK: 工具箱
struct ToolboxView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                    card("文件转换", "图片、PDF、表格、视频互相转换", "arrow.triangle.2.circlepath", .blue) { ConvertView() }
                    card("脚本技能", "一句话生成脚本，自动测试并运行", "wand.and.stars", .purple) { SkillsView() }
                    card("连接器", "连接快捷指令、Scriptable 和各种接口", "link", .orange) { ConnectorsView() }
                    card("快捷指令", "把本 App 的动作加入系统快捷指令", "square.stack.3d.up.fill", .teal) { ShortcutsView() }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("工具箱")
        }
    }

    func card<D: View>(_ t: String, _ s: String, _ icon: String, _ c: Color, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink {
            dest()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.title2).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(c)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(t).font(.headline).foregroundStyle(.primary)
                Text(s).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

// MARK: 文件转换
struct ConvertView: View {
    @State private var file: URL?
    @State private var showPick = false
    @State private var target = ""
    @State private var outs: [URL] = []
    @State private var busy = false
    @State private var err = ""
    @State private var preview: URL?

    static let names: [String: String] = [
        "jpg": "JPG 图片", "png": "PNG 图片", "heic": "HEIC 图片", "pdf": "PDF", "tiff": "TIFF 图片", "gif": "GIF 图片", "bmp": "BMP 图片",
        "txt": "文字", "csv": "CSV 表格", "json": "JSON", "md": "Markdown", "html": "网页", "tsv": "TSV 表格",
        "mp4": "MP4 视频", "mov": "MOV 视频", "m4a": "音频", "compress": "压缩视频"
    ]

    var targets: [String] {
        guard let f = file else { return [] }
        let e = f.pathExtension.lowercased()
        if Convert.imgExt.contains(e) { return ["jpg", "png", "heic", "pdf", "tiff", "gif", "bmp", "txt"] }
        if e == "pdf" { return ["png", "jpg", "txt"] }
        if Convert.vidExt.contains(e) { return ["mp4", "mov", "m4a", "compress", "jpg"] }
        return ["csv", "json", "md", "html", "txt", "tsv", "pdf"]
    }

    var body: some View {
        List {
            Section {
                Button { showPick = true } label: {
                    Label(file == nil ? "选择要转换的文件" : "已选择：" + (file?.lastPathComponent ?? ""), systemImage: "doc.badge.plus")
                }
            }
            if !targets.isEmpty {
                Section("转换成") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(targets, id: \.self) { t in
                            Button { target = t } label: {
                                Text(Self.names[t] ?? t).font(.subheadline)
                                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                                    .background(target == t ? Color.accentColor : Color(.tertiarySystemFill))
                                    .foregroundStyle(target == t ? Color.white : Color.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    Button { convert() } label: {
                        HStack { if busy { ProgressView() }; Text(busy ? "转换中…" : "开始转换").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || target.isEmpty)
                    .listRowBackground(Color.clear)
                }
            }
            if !err.isEmpty { Section { Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
            if !outs.isEmpty {
                Section("转换结果") {
                    ForEach(outs, id: \.self) { u in
                        VStack(alignment: .leading, spacing: 8) {
                            FileCard(url: u, preview: $preview)
                            if Convert.imgExt.contains(u.pathExtension.lowercased()) || Convert.vidExt.contains(u.pathExtension.lowercased()) {
                                Button("存入相册") { saveToPhotos(u) }
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                }
            }
            Section {
                Text("支持图片、PDF、表格（CSV、JSON、Markdown、网页）、文本、视频互相转换，也能识别图片中的文字。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("文件转换")
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($preview)
        .fileImporter(isPresented: $showPick, allowedContentTypes: [.item]) { r in
            if let u = try? r.get(), let c = Store.copyIn(u) {
                file = c
                outs = []
                err = ""
                target = targets.first ?? ""
            }
        }
    }

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

// MARK: 脚本技能
struct SkillsView: View {
    @State private var skills: [Row] = []
    @State private var spec = ""
    @State private var busy = false
    @State private var status = ""
    @State private var result: (name: String, ok: Bool, out: String)?
    @State private var showPack = false

    var body: some View {
        List {
            Section("用一句话创建") {
                TextField("例如：把输入的文字倒过来", text: $spec, axis: .vertical).lineLimit(2...4)
                Button { create() } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView() }
                        Text(busy ? status : "创建并运行").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || spec.trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowBackground(Color.clear)
                if let r = result {
                    if r.ok {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("已创建「\(r.name)」并运行成功", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("运行结果：" + r.out).textSelection(.enabled)
                        }
                    } else {
                        Label("没能生成可运行的脚本（\(r.out)），请换个描述再试一次", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
            Section("我的技能") {
                if skills.isEmpty { Text("还没有技能，先在上面创建一个").foregroundStyle(.secondary) }
                ForEach(skills.indices, id: \.self) { i in
                    NavigationLink {
                        SkillRunView(name: skills[i].s("name"))
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(skills[i].s("name")).font(.headline)
                            Text(skills[i].s("desc")).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { idx in
                    for i in idx { Skills.remove(skills[i].s("name")) }
                    reload()
                }
            }
            Section {
                Button { showPack = true } label: { Label("导入技能包", systemImage: "square.and.arrow.down") }
            }
        }
        .navigationTitle("脚本技能")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { hideKeyboard() } } }
        .fileImporter(isPresented: $showPack, allowedContentTypes: [.json]) { r in
            if let u = try? r.get() { Skills.importPack(u); reload() }
        }
        .onAppear(perform: reload)
    }

    func reload() { skills = Skills.list() }

    func create() {
        let s = spec
        hideKeyboard()
        busy = true
        result = nil
        status = "准备中…"
        Task {
            let r = await Skills.create(s) { msg in DispatchQueue.main.async { status = msg } }
            result = r
            busy = false
            if r.ok { spec = "" }
            reload()
        }
    }
}

struct SkillRunView: View {
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var out = ""
    @State private var ok = true
    @State private var copied = false

    var body: some View {
        List {
            Section("输入内容") {
                TextField("可以留空", text: $input, axis: .vertical).lineLimit(1...5)
            }
            Section {
                Button {
                    hideKeyboard()
                    let r = Skills.run(name, input)
                    ok = r.0
                    out = r.1
                } label: { Label("运行", systemImage: "play.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            }
            if !out.isEmpty {
                Section("运行结果") {
                    Text(out).textSelection(.enabled).foregroundStyle(ok ? Color.primary : Color.red)
                }
            }
            Section("给其他应用调用") {
                Button {
                    let n = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
                    UIPasteboard.general.string = "tstzbot://run?name=\(n)&input="
                    copied = true
                } label: { Label(copied ? "已复制调用链接" : "复制调用链接", systemImage: "link") }
            }
            Section {
                Button("删除这个技能", role: .destructive) {
                    Skills.remove(name)
                    dismiss()
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { hideKeyboard() } } }
    }
}

// MARK: 连接器
struct ConnectorsView: View {
    @State private var rows: [Row] = []
    @State private var showAdd = false

    var body: some View {
        List {
            Section {
                Text("连接本机已有的应用或网络接口，让助理在对话里直接调用，例如说「用快捷指令 XX 处理这段话」。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("已连接") {
                if rows.isEmpty { Text("还没有连接器，点右上角添加").foregroundStyle(.secondary) }
                ForEach(rows.indices, id: \.self) { i in
                    NavigationLink {
                        ConnectorRunView(name: rows[i].s("name"))
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rows[i].s("name")).font(.headline)
                            Text(Connectors.kindName(rows[i].s("kind"))).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { idx in
                    for i in idx { Connectors.remove(rows[i].i("id")) }
                    reload()
                }
            }
        }
        .navigationTitle("连接器")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd, onDismiss: reload) { AddConnectorView() }
        .onAppear(perform: reload)
    }

    func reload() { rows = Connectors.all() }
}

struct AddConnectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "shortcut"
    @State private var name = ""
    @State private var target = ""
    @State private var method = "GET"
    @State private var headers = ""
    @State private var bodyText = ""

    var hint: String {
        switch kind {
        case "shortcut": return "快捷指令的名称"
        case "scriptable": return "Scriptable 脚本的名称"
        case "url": return "目标应用的网址，用 [内容] 代表传入的文字"
        default: return "接口地址，用 [内容] 代表传入的文字"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("类型", selection: $kind) {
                        Text("快捷指令").tag("shortcut")
                        Text("Scriptable 脚本").tag("scriptable")
                        Text("其他 App").tag("url")
                        Text("网络接口").tag("http")
                    }
                    .pickerStyle(.menu)
                }
                Section("名称（对话里用它来调用）") { TextField("例如：整理文字", text: $name) }
                Section(hint) { TextField("请输入", text: $target).textInputAutocapitalization(.never).autocorrectionDisabled() }
                if kind == "http" {
                    Section("请求方式") {
                        Picker("方式", selection: $method) {
                            Text("GET").tag("GET")
                            Text("POST").tag("POST")
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("请求头（每行一项，写成 名称: 值）") { TextEditor(text: $headers).frame(minHeight: 70) }
                    if method == "POST" { Section("发送内容（用 [内容] 代表传入的文字）") { TextEditor(text: $bodyText).frame(minHeight: 90) } }
                }
            }
            .navigationTitle("添加连接器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        Connectors.add(
                            name: name.trimmingCharacters(in: .whitespaces), kind: kind,
                            url: target.replacingOccurrences(of: "[内容]", with: "{{input}}"),
                            method: method, headers: headers,
                            body: bodyText.replacingOccurrences(of: "[内容]", with: "{{input}}")
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || target.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct ConnectorRunView: View {
    let name: String
    @State private var input = ""
    @State private var out = ""
    @State private var busy = false

    var body: some View {
        List {
            Section("传入内容") { TextField("可以留空", text: $input, axis: .vertical).lineLimit(1...5) }
            Section {
                Button {
                    hideKeyboard()
                    busy = true
                    Task {
                        out = await Connectors.run(name, input)
                        busy = false
                    }
                } label: {
                    HStack { if busy { ProgressView() }; Text(busy ? "调用中…" : "调用").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
                .listRowBackground(Color.clear)
            }
            if !out.isEmpty { Section("返回结果") { Text(out).textSelection(.enabled) } }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { hideKeyboard() } } }
    }
}

// MARK: 快捷指令
struct ShortcutsView: View {
    @State private var copied = ""

    var body: some View {
        List {
            Section {
                Link(destination: URL(string: "shortcuts://")!) { Label("打开快捷指令", systemImage: "square.stack.3d.up") }
                Link(destination: URL(string: "shortcuts://create-shortcut")!) { Label("新建快捷指令", systemImage: "plus.square") }
            }
            Section("本 App 提供的动作") {
                action("sparkles", "询问助理", "把一句话交给助理，拿到回答")
                action("magnifyingglass", "检索知识库", "按语义查找知识库内容")
                action("tray.and.arrow.down", "加入知识库", "把文字存进知识库")
                action("wand.and.stars", "运行脚本技能", "运行你创建的脚本并返回结果")
                action("bell", "N 分钟后提醒", "几分钟后发送通知提醒")
            }
            Section("怎么用") {
                Text("1. 打开快捷指令，点右上角加号新建\n2. 点「添加操作」，搜索 TSTZ Bot\n3. 选择上面的动作，再接上你想要的步骤\n4. 在「自动化」里设置时间，就能定时自动运行")
                    .font(.subheadline)
            }
            Section("让其他应用调用本 App") {
                Button { copy("tstzbot://ask?q=", "提问") } label: { Label(copied == "提问" ? "已复制提问链接" : "复制「提问」链接", systemImage: "link") }
                Button { copy("tstzbot://run?name=", "运行") } label: { Label(copied == "运行" ? "已复制运行链接" : "复制「运行脚本」链接", systemImage: "link") }
            }
        }
        .navigationTitle("快捷指令")
        .navigationBarTitleDisplayMode(.inline)
    }

    func copy(_ s: String, _ k: String) {
        UIPasteboard.general.string = s
        copied = k
    }

    func action(_ icon: String, _ t: String, _ d: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(t)
                Text(d).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: 任务与进化
struct TasksView: View {
    @State private var tasks: [Row] = []
    @State private var alarms: [Row] = []
    @State private var text = ""
    @State private var info = ""
    @State private var busy = false
    @State private var preparing = false
    @State private var prepInfo = ""
    @State private var evolving = false
    @State private var evoInfo = ""

    var body: some View {
        NavigationStack {
            List {
                Section("新建") {
                    TextField("例：明早十点叫我起床", text: $text, axis: .vertical).lineLimit(1...3)
                    Button { create() } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView() }
                            Text(busy ? "创建中…" : "创建").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .listRowBackground(Color.clear)
                    if !info.isEmpty { Text(info).foregroundStyle(Color.accentColor) }
                }
                Section("闹钟") {
                    if alarms.isEmpty { Text("没有闹钟").foregroundStyle(.secondary) }
                    ForEach(alarms.indices, id: \.self) { i in
                        HStack(spacing: 12) {
                            Image(systemName: "alarm.fill").foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(alarms[i].s("label"))
                                Text((alarms[i].i("rep") > 0 ? Sys.repText(alarms[i].i("rep")) + " " : "") + Sys.friendly(Date(timeIntervalSince1970: alarms[i].d("due"))))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .onDelete { idx in
                        for i in idx { Sys.cancelAlarm(alarms[i].s("id")) }
                        reload()
                    }
                }
                Section("定时任务") {
                    if tasks.isEmpty { Text("没有定时任务").foregroundStyle(.secondary) }
                    ForEach(tasks.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tasks[i].s("title")).font(.headline)
                            Text((tasks[i].i("rep") > 0 ? Sys.repText(tasks[i].i("rep")) + " " : "") + Sys.friendly(Date(timeIntervalSince1970: tasks[i].d("due"))) + (tasks[i].i("state") == 1 ? " · 已完成" : " · 待执行"))
                                .font(.subheadline).foregroundStyle(.secondary)
                            if !tasks[i].s("result").isEmpty { Text(tasks[i].s("result")).font(.subheadline) }
                        }
                        .padding(.vertical, 3)
                    }
                    .onDelete { idx in
                        for i in idx { Tasks.remove(tasks[i].i("id")) }
                        reload()
                    }
                    Button {
                        preparing = true
                        prepInfo = ""
                        Task {
                            let n = await Tasks.refresh()
                            prepInfo = n > 0 ? "已为 \(n) 个任务准备好内容并安排了通知" : "没有需要准备的任务"
                            preparing = false
                            reload()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if preparing { ProgressView() }
                            Text(preparing ? "正在准备…" : "立即准备并安排通知")
                        }
                    }
                    .disabled(preparing)
                    if !prepInfo.isEmpty { Text(prepInfo).foregroundStyle(Color.accentColor) }
                }
                Section("进化") {
                    Text("上次进化：" + (Evolve.lastTime().map { Sys.friendly($0) } ?? "尚未进行")).foregroundStyle(.secondary)
                    Button {
                        evolving = true
                        evoInfo = ""
                        Task {
                            evoInfo = await Evolve.run(force: true)
                            evolving = false
                            reload()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if evolving { ProgressView() }
                            Text(evolving ? "正在进化…" : "立即进化")
                        }
                    }
                    .disabled(evolving)
                    if !evoInfo.isEmpty { Text(evoInfo).foregroundStyle(Color.accentColor) }
                    NavigationLink("查看进化记录") { EvolveLogView() }
                }
            }
            .navigationTitle("任务")
            .scrollDismissesKeyboard(.immediately)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { hideKeyboard() } } }
            .onAppear(perform: reload)
        }
    }

    func create() {
        let t = text
        hideKeyboard()
        busy = true
        info = ""
        Task {
            let r = await Router.handle(t)
            info = r ?? "没能识别时间，请说得具体一些，比如「明早十点叫我起床」"
            if r != nil { text = "" }
            busy = false
            reload()
        }
    }

    func reload() {
        tasks = Tasks.list()
        alarms = Tasks.alarms()
    }
}

struct EvolveLogView: View {
    @State private var log: [Row] = []
    @State private var vers: [Row] = []

    var body: some View {
        List {
            Section("每次进化都做了什么") {
                if log.isEmpty { Text("还没有进化记录。聊几轮之后会自动进化，也可以在「任务」页点「立即进化」。").foregroundStyle(.secondary) }
                ForEach(log.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Sys.fmt(Date(timeIntervalSince1970: log[i].d("ts")))).font(.subheadline).foregroundStyle(.secondary)
                        Text(log[i].s("summary")).font(.headline)
                        if !log[i].s("facts").isEmpty {
                            ForEach(log[i].s("facts").split(separator: "\n").map(String.init), id: \.self) { f in
                                Label(f, systemImage: "brain").font(.subheadline)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("系统提示版本") {
                ForEach(vers.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("第 \(vers[i].i("ver")) 版" + (i == 0 ? "（当前）" : "")).font(.headline)
                        Text(vers[i].s("body")).font(.subheadline).foregroundStyle(.secondary)
                        if i > 0 {
                            Button("回滚到这一版") {
                                Evolve.saveVersion(vers[i].s("body"))
                                reload()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if vers.isEmpty { Text("当前使用默认提示").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("进化记录")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    func reload() {
        log = Evolve.log()
        vers = Evolve.versions()
    }
}

// MARK: 设置
struct SettingsView: View {
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("accent") private var accent = 0
    @AppStorage("saveHistory") private var saveHistory = true
    @AppStorage("style") private var style = 0
    @AppStorage("autoSend") private var autoSend = false
    @AppStorage("liveOn") private var liveOn = true
    @State private var exportURL: URL?
    @State private var confirmChats = false
    @State private var confirmKB = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("主题", selection: $appearance) {
                        Text("跟随系统").tag(0)
                        Text("浅色").tag(1)
                        Text("深色").tag(2)
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 14) {
                        Text("主题色")
                        Spacer()
                        ForEach(0..<Theme.accents.count, id: \.self) { i in
                            Button { accent = i } label: {
                                Circle().fill(Theme.accents[i].1).frame(width: 28, height: 28)
                                    .overlay { if accent == i { Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(.white) } }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("对话") {
                    Toggle("保存对话记录", isOn: $saveHistory)
                    Picker("回答风格", selection: $style) {
                        Text("简洁").tag(0)
                        Text("详细").tag(1)
                    }
                    Toggle("语音说完后自动发送", isOn: $autoSend)
                }
                Section("灵动岛与实时活动") {
                    Toggle("在灵动岛显示思考、闹钟与任务倒计时", isOn: $liveOn)
                }
                Section("权限") {
                    Button { openSettings() } label: { Label("通知、闹钟、日历、麦克风等权限", systemImage: "gearshape") }
                }
                Section("数据") {
                    if let u = exportURL {
                        ShareLink(item: u) { Label("导出全部对话", systemImage: "square.and.arrow.up") }
                    }
                    Button(role: .destructive) { confirmChats = true } label: { Label("清空所有对话", systemImage: "trash") }
                    Button(role: .destructive) { confirmKB = true } label: { Label("清空知识库", systemImage: "trash") }
                }
                Section("关于") {
                    HStack {
                        LogoMark(size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TSTZ Bot").font(.headline)
                            Text("版本 0.3").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    HStack {
                        Text("开发者微信")
                        Spacer()
                        Text("TSTZ-M").foregroundStyle(.secondary)
                        Button { UIPasteboard.general.string = "TSTZ-M"; copied = true } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle("设置")
            .onAppear { exportURL = exportAll() }
            .confirmationDialog("清空所有对话？此操作无法撤销", isPresented: $confirmChats, titleVisibility: .visible) {
                Button("清空", role: .destructive) { Agent.shared.clearAll() }
            }
            .confirmationDialog("清空知识库？此操作无法撤销", isPresented: $confirmKB, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    DB.shared.run("DELETE FROM chunk")
                    DB.shared.run("DELETE FROM doc")
                }
            }
        }
    }

    func openSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
    }

    func exportAll() -> URL? {
        var s = "# TSTZ Bot 对话记录\n\n"
        for c in DB.shared.rows("SELECT id,title,ts FROM conv ORDER BY ts") {
            s += "## " + c.s("title") + "（" + Sys.fmt(Date(timeIntervalSince1970: c.d("ts"))) + "）\n\n"
            for m in DB.shared.rows("SELECT role,text FROM msg WHERE conv=? ORDER BY id", [c.i("id")]) {
                s += (m.s("role") == "user" ? "**我**：" : "**TSTZ Bot**：") + m.s("text") + "\n\n"
            }
        }
        let u = Store.dir("Outputs").appendingPathComponent("TSTZ Bot 对话记录.md")
        try? s.write(to: u, atomically: true, encoding: .utf8)
        return u
    }
}
