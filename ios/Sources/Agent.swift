import Foundation
import SwiftUI
import FoundationModels

struct Msg: Identifiable {
    let id = UUID()
    var role: String
    var text: String
    var files: [URL] = []
    var streaming = false
}

struct Attach: Identifiable {
    let id = UUID()
    let url: URL
}

// 工具产出的文件，随助理回复一起显示
enum Out {
    private static let lock = NSLock()
    private static var list: [URL] = []
    static func add(_ u: [URL]) { lock.lock(); list += u; lock.unlock() }
    static func take() -> [URL] { lock.lock(); defer { lock.unlock() }; let r = list; list = []; return r }
}

@MainActor
final class Agent: ObservableObject {
    static let shared = Agent()
    @Published var msgs: [Msg] = []
    @Published var busy = false
    @Published var attachments: [Attach] = []
    @Published var convId = 0
    var lastFile: URL?
    private var task: Task<Void, Never>?

    private var saving: Bool { UserDefaults.standard.object(forKey: "saveHistory") as? Bool ?? true }

    init() { loadLatest() }

    // MARK: 对话记录
    func loadLatest() {
        if DB.shared.rows("SELECT id FROM msg WHERE conv=0 LIMIT 1").first != nil {
            let id = DB.shared.run("INSERT INTO conv(title,ts) VALUES(?,?)", ["历史对话", Date().timeIntervalSince1970])
            DB.shared.run("UPDATE msg SET conv=? WHERE conv=0", [id])
        }
        if let r = DB.shared.rows("SELECT id FROM conv ORDER BY ts DESC LIMIT 1").first { open(r.i("id")) } else { newChat() }
    }

    func newChat() {
        task?.cancel()
        convId = 0
        msgs = []
        attachments = []
        busy = false
    }

    func open(_ id: Int) {
        task?.cancel()
        busy = false
        convId = id
        attachments = []
        msgs = DB.shared.rows("SELECT role,text,files FROM msg WHERE conv=? ORDER BY id", [id]).map { r in
            var urls: [URL] = []
            if let d = r.s("files").data(using: .utf8), let list = try? JSONDecoder().decode([String].self, from: d) {
                urls = list.map { Store.abs($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            }
            return Msg(role: r.s("role"), text: r.s("text"), files: urls)
        }
    }

    func convs() -> [Row] { DB.shared.rows("SELECT id,title,ts FROM conv ORDER BY ts DESC") }

    func deleteConv(_ id: Int) {
        DB.shared.run("DELETE FROM msg WHERE conv=?", [id])
        DB.shared.run("DELETE FROM conv WHERE id=?", [id])
        if id == convId { newChat() }
    }

    func rename(_ id: Int, _ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        DB.shared.run("UPDATE conv SET title=? WHERE id=?", [t, id])
    }

    func clearAll() {
        DB.shared.run("DELETE FROM msg")
        DB.shared.run("DELETE FROM conv")
        newChat()
    }

    // 只写数据库
    private func persist(_ role: String, _ text: String, _ files: [URL]) {
        guard saving else { return }
        if convId == 0 {
            let title = role == "user" ? String(text.prefix(16)) : "新对话"
            convId = Int(DB.shared.run("INSERT INTO conv(title,ts) VALUES(?,?)", [title.isEmpty ? "文件" : title, Date().timeIntervalSince1970]))
        }
        let json = (try? JSONEncoder().encode(files.map { Store.rel($0) })).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        DB.shared.run("INSERT INTO msg(role,text,ts,conv,files) VALUES(?,?,?,?,?)", [role, text, Date().timeIntervalSince1970, convId, json])
        DB.shared.run("UPDATE conv SET ts=? WHERE id=?", [Date().timeIntervalSince1970, convId])
    }

    private func store(_ role: String, _ text: String, _ files: [URL]) {
        msgs.append(Msg(role: role, text: text, files: files))
        persist(role, text, files)
    }

    // MARK: 发送、停止、重新生成
    func start(_ text: String) {
        guard !busy else { return }
        task = Task { await self.send(text) }
    }

    func stop() { task?.cancel() }

    func regenerate() {
        guard !busy, let lastUser = msgs.last(where: { $0.role == "user" }) else { return }
        if msgs.last?.role == "assistant" {
            msgs.removeLast()
            DB.shared.run("DELETE FROM msg WHERE id=(SELECT MAX(id) FROM msg WHERE conv=? AND role='assistant')", [convId])
        }
        let t = lastUser.text
        let files = lastUser.files
        busy = true
        task = Task {
            Live.thinking(true)
            await self.respond(t, files: files)
            Live.thinking(false)
            self.busy = false
        }
    }

    func send(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = attachments.map { $0.url }
        guard !t.isEmpty || !files.isEmpty, !busy else { return }
        busy = true
        Live.thinking(true)
        attachments = []
        store("user", t, files)
        if let f = files.last { lastFile = f }
        await respond(t, files: files)
        Live.thinking(false)
        busy = false
    }

    func quick(_ t: String) async -> String {
        await send(t)
        return msgs.last?.text ?? ""
    }

    // 生成一条助理回复：先放一个空消息，模型边生成边往里填（流式）
    private func respond(_ t: String, files: [URL]) async {
        let ph = Msg(role: "assistant", text: "", files: [], streaming: true)
        msgs.append(ph)
        let mid = ph.id
        var reply = ""
        if let f = files.last, let r = await Router.convert(t, file: f) {
            reply = r.0
        } else if files.isEmpty, let r = await Router.handle(t) {
            reply = r
        } else if files.isEmpty, let r = await scriptIntent(t, mid: mid) {
            reply = r
        } else if t.isEmpty, !files.isEmpty, files.allSatisfy({ Convert.imgExt.contains($0.pathExtension.lowercased()) }) {
            reply = await Self.imageSummary(files)
        } else {
            var ctx = ""
            for f in files { ctx += await Self.describe(f) }
            reply = await ask(t.isEmpty ? "请处理我发送的文件" : t, ctx: ctx, hasFile: !files.isEmpty, mid: mid)
        }
        finish(mid, reply)
    }

    private func update(_ mid: UUID, _ text: String) {
        if let i = msgs.firstIndex(where: { $0.id == mid }) { msgs[i].text = text }
    }

    private func partial(_ mid: UUID) -> String { msgs.first(where: { $0.id == mid })?.text ?? "" }

    private func finish(_ mid: UUID, _ text: String) {
        let files = Out.take()
        let body = text.isEmpty ? "已停止。" : text
        if let i = msgs.firstIndex(where: { $0.id == mid }) {
            msgs[i].text = body
            msgs[i].files = files
            msgs[i].streaming = false
        }
        persist("assistant", body, files)
    }

    // 「做一个……脚本」：确定性处理，不交给小模型瞎猜
    private func scriptIntent(_ t: String, mid: UUID) async -> String? {
        guard t.contains("脚本") || t.contains("技能") else { return nil }
        let make = ["做一个", "做个", "写一个", "写个", "创建一个", "创建个", "生成一个", "生成个", "帮我做", "帮我写", "编一个", "弄一个"]
        guard make.contains(where: { t.contains($0) }) else { return nil }
        let banned = ["点赞", "自动点击", "模拟点击", "连点", "刷赞", "刷粉", "刷量", "自动关注", "自动评论", "自动刷", "抢单", "外挂"]
        if banned.contains(where: { t.contains($0) }) {
            return "做不到：iOS 不允许一个 App 自动点击或操作别的 App（点赞、关注、刷视频都不行），快捷指令也一样。\n脚本技能只能处理文字、读网页、查知识库，比如整理文案、提取网页要点、批量改写。想做其中一种，直接告诉我。"
        }
        update(mid, "正在编写脚本…")
        let r = await Skills.create(t) { p in
            Task { @MainActor in self.update(mid, p) }
        }
        if r.ok {
            return "已创建脚本技能「\(r.name)」，试运行结果：\n\(r.out)\n\n以后说「运行 \(r.name)」，或到 工具箱 → 脚本技能 里使用。"
        }
        return "没能生成可运行的脚本（\(r.out)）。请把需求说具体一点：输入是什么、希望输出什么。"
    }

    // MARK: 图片与文件理解
    nonisolated static func imageSummary(_ files: [URL]) async -> String {
        var parts = ["收到 \(files.count) 张图片。我能识别图中的文字和大致类别，看不到画面细节。"]
        for f in files.prefix(3) {
            let labels = OCR.labels(f)
            let text = OCR.text(f)
            if !labels.isEmpty { parts.append("类别：" + labels.joined(separator: "、")) }
            parts.append(text.isEmpty ? "图中没有识别到文字。" : "图中文字：" + String(text.prefix(300)))
        }
        parts.append("可以点输入框上方的「识别文字」「转成PDF」「转成PNG」，或直接告诉我要做什么。")
        return parts.joined(separator: "\n")
    }

    nonisolated static func describe(_ u: URL) async -> String {
        let ext = u.pathExtension.lowercased()
        if Convert.imgExt.contains(ext) {
            let t = OCR.text(u)
            let l = OCR.labels(u)
            return "\n[图片] 类别：" + (l.isEmpty ? "未知" : l.joined(separator: "、")) + "；图中文字：" + (t.isEmpty ? "无" : String(t.prefix(1200)))
        }
        if Convert.vidExt.contains(ext) { return "\n[视频] 已收到" }
        let txt = KB.shared.text(of: u)
        if txt.isEmpty { return "\n[文件] 已收到，无法读取文字" }
        if txt.count <= 1200 { return "\n[文件内容] \(txt)" }
        KB.shared.upsert(u.lastPathComponent, txt)
        return "\n[文件] 内容较长（\(txt.count) 字），已存入知识库，需要时调用 recall 检索"
    }

    // MARK: 模型
    nonisolated static func instructions() -> String {
        let concise = (UserDefaults.standard.object(forKey: "style") as? Int ?? 0) == 0
        return Evolve.prompt()
            + "\n现在是" + Sys.fmtFull(Date()) + "，时区" + TimeZone.current.identifier + "。"
            + "你是 TSTZ Bot，运行在用户 iPhone 上的中文助理。直接针对用户的问题作答，不要复述问题，信息够用时不要反问。"
            + "你看不到图片，只能依据识别出的类别和文字回答，不要说无法读取图片。"
            + (concise ? "回答要简短。" : "回答可以详细一些。")
            + "需要列表或代码时用 Markdown。不知道就直说不知道，不要编造。"
    }

    // 只在消息确实相关时才给模型工具：工具越多，小模型越容易答非所问
    nonisolated static func tools(for t: String, hasFile: Bool) -> [any Tool] {
        func has(_ k: [String]) -> Bool { k.contains { t.contains($0) } }
        var r: [any Tool] = []
        if has(["记住", "记一下", "别忘了"]) { r.append(Remember()) }
        if has(["之前", "上次", "知识库", "笔记", "资料", "我的文档", "我存的"]) { r.append(Recall()) }
        if has(["闹钟", "提醒", "日历", "日程", "会议", "定时", "叫我", "起床"]) { r += [SetAlarm(), AddReminder(), AddEvent()] }
        if hasFile || has(["转换", "转成", "转为", "压缩", "导出", "提取"]) { r.append(ConvertFile()) }
        if DB.shared.rows("SELECT name FROM skill").contains(where: { t.contains($0.s("name")) }) { r.append(RunSkill()) }
        if has(["查找文件", "读取文件", "找文件", "文档里"]) { r += [FindFile(), ReadFile()] }
        if has(["http", "网页", "网址", "链接", "新闻"]) { r.append(FetchURL()) }
        if Connectors.all().contains(where: { t.contains($0.s("name")) }) { r.append(CallConnector()) }
        return r
    }

    nonisolated static func unavailableText(_ reason: String) -> String {
        if reason.contains("appleIntelligenceNotEnabled") { return "本机模型还没开启：请到 设置 → Apple 智能与 Siri，打开 Apple 智能。" }
        if reason.contains("modelNotReady") { return "本机模型还在下载或准备中，请连上 Wi‑Fi 等几分钟再试。" }
        if reason.contains("deviceNotEligible") { return "这台设备不支持 Apple 智能，没法使用本机模型。" }
        return "本机模型暂时不可用（\(reason)）。"
    }

    // 把底层错误翻译成人话；返回 nil 表示可以重试
    nonisolated static func explain(_ err: String) -> String? {
        let low = err.lowercased()
        if low.contains("guardrail") || low.contains("refus") { return "这个话题触发了系统模型的安全限制，我没法回答。换个说法或说明正当用途再试。" }
        if low.contains("unsupportedlanguage") { return "系统模型暂不支持这种语言或地区设置，请换个说法。" }
        if low.contains("assetsunavailable") { return "本机模型资源还没准备好，请稍等几分钟再试。" }
        return nil
    }

    private func ask(_ t: String, ctx: String, hasFile: Bool, mid: UUID) async -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            return Self.unavailableText("\(reason)")
        @unknown default:
            break
        }
        let tools = Self.tools(for: t, hasFile: hasFile)
        let hist = msgs.dropLast(2).suffix(6).filter { !$0.text.isEmpty }
            .map { ($0.role == "user" ? "用户：" : "助理：") + String($0.text.prefix(200)) }
            .joined(separator: "\n")
        let names = Connectors.all().map { $0.s("name") }.joined(separator: "、")
        let extra = names.isEmpty ? "" : "\n可调用的连接器：" + names
        var lastErr = ""
        for attempt in 0..<3 {
            let session = LanguageModelSession(tools: attempt == 2 ? [] : tools, instructions: Self.instructions() + extra)
            let prompt: String
            switch attempt {
            case 0: prompt = (hist.isEmpty ? "" : "近期对话：\n\(hist)\n\n") + "用户：\(t)\(ctx)"
            case 1: prompt = "用户：\(t)" + String(ctx.prefix(300))
            default: prompt = t
            }
            do {
                var last = ""
                for try await snap in session.streamResponse(to: prompt) {
                    last = snap.content
                    update(mid, last)
                }
                if !last.isEmpty { return last }
                lastErr = "模型没有返回内容"
            } catch {
                if Task.isCancelled || error is CancellationError { return partial(mid) }
                lastErr = "\(error)"
                if let m = Self.explain(lastErr) { return m }
            }
            if Task.isCancelled { return partial(mid) }
            update(mid, "")
        }
        return "这次没能完成（\(String(lastErr.prefix(90)))）。可以点「重新生成」，或换个说法。"
    }

    func transcript(_ ms: [Msg]) -> String {
        ms.map { ($0.role == "user" ? "我：" : "TSTZ Bot：") + $0.text }.joined(separator: "\n\n")
    }
}
