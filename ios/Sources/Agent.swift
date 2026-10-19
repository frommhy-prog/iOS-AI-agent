import Foundation
import SwiftUI
import FoundationModels

struct Msg: Identifiable {
    let id = UUID()
    var role: String
    var text: String
    var files: [URL] = []
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
        convId = 0
        msgs = []
        attachments = []
    }

    func open(_ id: Int) {
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

    func clearAll() {
        DB.shared.run("DELETE FROM msg")
        DB.shared.run("DELETE FROM conv")
        newChat()
    }

    private func store(_ role: String, _ text: String, _ files: [URL]) {
        msgs.append(Msg(role: role, text: text, files: files))
        guard saving else { return }
        if convId == 0 {
            let title = role == "user" ? String(text.prefix(16)) : "新对话"
            convId = Int(DB.shared.run("INSERT INTO conv(title,ts) VALUES(?,?)", [title.isEmpty ? "文件" : title, Date().timeIntervalSince1970]))
        }
        let json = (try? JSONEncoder().encode(files.map { Store.rel($0) })).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        DB.shared.run("INSERT INTO msg(role,text,ts,conv,files) VALUES(?,?,?,?,?)", [role, text, Date().timeIntervalSince1970, convId, json])
        DB.shared.run("UPDATE conv SET ts=? WHERE id=?", [Date().timeIntervalSince1970, convId])
    }

    // MARK: 发送
    func send(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = attachments.map { $0.url }
        guard !t.isEmpty || !files.isEmpty, !busy else { return }
        busy = true
        Live.thinking(true)
        attachments = []
        store("user", t, files)
        if let f = files.last { lastFile = f }
        var reply = ""
        if let f = files.last, let r = await Router.convert(t, file: f) {
            reply = r.0
        } else if files.isEmpty, let r = await Router.handle(t) {
            reply = r
        } else if t.isEmpty, !files.isEmpty, files.allSatisfy({ Convert.imgExt.contains($0.pathExtension.lowercased()) }) {
            reply = await Self.imageSummary(files)
        } else {
            var ctx = ""
            for f in files { ctx += await Self.describe(f) }
            reply = await ask(t.isEmpty ? "请处理我发送的文件" : t, ctx: ctx, hasFile: !files.isEmpty)
        }
        store("assistant", reply, Out.take())
        Live.thinking(false)
        busy = false
    }

    func quick(_ t: String) async -> String {
        await send(t)
        return msgs.last?.text ?? ""
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
        parts.append("可以点下方「识别文字」「转成PDF」「转成PNG」，或直接告诉我要做什么。")
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
            + "你看不到图片，只能依据识别出的类别和文字回答，不要说无法读取图片。"
            + (concise ? "回答要简短。" : "回答可以详细一些。")
            + "不要在回答里出现代码或技术术语。"
    }

    nonisolated static func tools(for t: String, hasFile: Bool) -> [any Tool] {
        func has(_ k: [String]) -> Bool { k.contains { t.contains($0) } }
        var r: [any Tool] = [Recall(), Remember()]
        if has(["闹钟", "提醒", "日历", "日程", "会议", "定时", "每天", "明天", "后天", "叫我", "起床"]) { r += [SetAlarm(), AddReminder(), AddEvent()] }
        if hasFile || has(["转换", "转成", "转为", "压缩", "导出", "提取"]) { r.append(ConvertFile()) }
        if has(["脚本", "技能", "运行"]) { r.append(RunSkill()) }
        if has(["文件", "读取", "查找", "文档"]) { r += [FindFile(), ReadFile()] }
        if has(["http", "网页", "网址", "链接", "新闻", "搜索"]) { r.append(FetchURL()) }
        if has(["快捷指令", "Scriptable", "scriptable", "连接", "调用"]) { r.append(CallConnector()) }
        return r
    }

    private func ask(_ t: String, ctx: String, hasFile: Bool) async -> String {
        let tools = Self.tools(for: t, hasFile: hasFile)
        let hist = msgs.suffix(7).dropLast().map { ($0.role == "user" ? "用户：" : "助理：") + String($0.text.prefix(120)) }.joined(separator: "\n")
        let names = Connectors.all().map { $0.s("name") }.joined(separator: "、")
        let extra = names.isEmpty ? "" : "\n可调用的连接器：" + names
        for attempt in 0..<2 {
            let session = LanguageModelSession(tools: tools, instructions: Self.instructions() + extra)
            let prompt = attempt == 0
                ? (hist.isEmpty ? "" : "近期对话：\n\(hist)\n\n") + "用户：\(t)\(ctx)"
                : "用户：\(t)" + String(ctx.prefix(300))
            do {
                return try await session.respond(to: prompt).content
            } catch {
                let msg = "\(error)"
                if attempt == 1 || !msg.contains("xceed") { return "这次没能完成，请换个说法再试一次。" }
            }
        }
        return "这次没能完成，请换个说法再试一次。"
    }

    func transcript(_ ms: [Msg]) -> String {
        ms.map { ($0.role == "user" ? "我：" : "TSTZ Bot：") + $0.text }.joined(separator: "\n\n")
    }
}
