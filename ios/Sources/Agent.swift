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
    var lastFile: URL?

    init() {
        let rows = Array(DB.shared.rows("SELECT role,text FROM msg ORDER BY id DESC LIMIT 30").reversed())
        msgs = rows.map { Msg(role: $0.s("role"), text: $0.s("text")) }
        if msgs.isEmpty {
            msgs = [Msg(role: "assistant", text: "我是你的私人助理，模型在手机本地运行，使用时联网。\n可以直接说：\n· 明早十点叫我起床\n· 一周后下午三点提醒我交报告\n· 每天早上8点总结我的待办\n· 把这张图转成 PDF\n也能粘贴、发图片、发文件、语音输入。")]
        }
    }

    func send(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = attachments.map { $0.url }
        guard !t.isEmpty || !files.isEmpty, !busy else { return }
        busy = true
        attachments = []
        msgs.append(Msg(role: "user", text: t, files: files))
        DB.shared.run("INSERT INTO msg(role,text,ts) VALUES(?,?,?)", ["user", t, Date().timeIntervalSince1970])
        var ctx = ""
        for f in files { ctx += await Self.describe(f) }
        if let f = files.last { lastFile = f }
        let reply = await ask(t.isEmpty ? "请处理我发送的文件" : t, ctx: ctx, hasFile: !files.isEmpty)
        msgs.append(Msg(role: "assistant", text: reply, files: Out.take()))
        DB.shared.run("INSERT INTO msg(role,text,ts) VALUES(?,?,?)", ["assistant", reply, Date().timeIntervalSince1970])
        busy = false
    }

    func quick(_ t: String) async -> String {
        await send(t)
        return msgs.last?.text ?? ""
    }

    nonisolated static func describe(_ u: URL) async -> String {
        let ext = u.pathExtension.lowercased()
        let name = u.lastPathComponent
        if Convert.imgExt.contains(ext) {
            let t = OCR.text(u)
            return "\n[图片 \(name)] " + (t.isEmpty ? "未识别到文字" : "识别文字：" + String(t.prefix(1200)))
        }
        if Convert.vidExt.contains(ext) { return "\n[视频 \(name)] 已收到" }
        let txt = KB.shared.text(of: u)
        if txt.isEmpty { return "\n[文件 \(name)] 已收到，无法读取文字" }
        if txt.count <= 1200 { return "\n[文件 \(name)] 内容：\(txt)" }
        KB.shared.upsert(name, txt)
        return "\n[文件 \(name)] 内容较长（\(txt.count) 字），已存入知识库，需要时调用 recall 检索"
    }

    nonisolated static func instructions() -> String {
        Evolve.prompt()
            + "\n现在是" + Sys.fmtFull(Date()) + "，时区" + TimeZone.current.identifier
            + "。时间类请求必须调用工具完成，用 dayOffset（0今天/1明天/2后天/7一周后）与24小时制 hour、minute 表示，不要自己编造结果。"
    }

    // 按关键词挑选本轮工具，控制在 4096 上下文以内
    nonisolated static func tools(for t: String, hasFile: Bool) -> [any Tool] {
        func has(_ k: [String]) -> Bool { k.contains { t.contains($0) } }
        var r: [any Tool] = [Recall(), Remember()]
        if has(["闹钟", "提醒", "日历", "日程", "会议", "定时", "任务", "每天", "每周", "明天", "后天", "小时后", "分钟后", "天后", "周后", "叫我", "起床", "几点"]) {
            r += [SetAlarm(), AddReminder(), AddEvent(), ScheduleTask()]
        }
        if hasFile || has(["转换", "转成", "转为", "压缩", "导出", "提取", "pdf", "PDF", "png", "jpg", "mp4", "csv"]) { r.append(ConvertFile()) }
        if has(["脚本", "技能", "自动化", "代码", "JS", "js"]) { r += [SaveSkill(), RunSkill()] }
        if has(["文件", "读取", "查找", "打开", "文档"]) { r += [FindFile(), ReadFile()] }
        if has(["http", "网页", "网址", "链接", "新闻", "搜索"]) { r.append(FetchURL()) }
        return r
    }

    private func ask(_ t: String, ctx: String, hasFile: Bool) async -> String {
        let tools = Self.tools(for: t, hasFile: hasFile)
        let hist = msgs.suffix(7).dropLast().map { ($0.role == "user" ? "用户：" : "助理：") + String($0.text.prefix(120)) }.joined(separator: "\n")
        for attempt in 0..<2 {
            let session = LanguageModelSession(tools: tools, instructions: Self.instructions())
            let prompt = attempt == 0
                ? (hist.isEmpty ? "" : "近期对话：\n\(hist)\n\n") + "用户：\(t)\(ctx)"
                : "用户：\(t)" + String(ctx.prefix(300))
            do {
                return try await session.respond(to: prompt).content
            } catch {
                let msg = "\(error)"
                if attempt == 1 || !msg.contains("xceed") { return "出错：\(error.localizedDescription)" }
            }
        }
        return "出错"
    }
}
