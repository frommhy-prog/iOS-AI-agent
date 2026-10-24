import Foundation
import UserNotifications
import FoundationModels

// 定时任务：计算与送达分离。打开 App 时提前生成内容，到点由系统通知准时送达。
enum Tasks {
    // rep：0 一次，1 每天，7 每周
    @discardableResult
    static func add(_ title: String, _ instr: String, _ due: Date, useModel: Bool, rep: Int) -> Int64 {
        DB.shared.run(
            "INSERT INTO task(title,instr,due,use_model,rep,result,state,notified) VALUES(?,?,?,?,?,?,0,0)",
            [title, instr, due.timeIntervalSince1970, useModel ? 1 : 0, rep, ""]
        )
    }

    static func list() -> [Row] { DB.shared.rows("SELECT * FROM task ORDER BY state, due") }

    static func remove(_ id: Int) {
        DB.shared.run("DELETE FROM task WHERE id=?", [id])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["task-\(id)"])
    }

    static func alarms() -> [Row] { DB.shared.rows("SELECT * FROM alarm ORDER BY due") }

    // 任务内容用当前应用语言生成（通知里显示的就是这段文字）。本地大模型可用就用它，否则用系统模型
    static func gen(_ instr: String) async -> String {
        let ins = "你是个人助理。直接输出任务结果，简洁，不超过120字，不要出现代码。需要资料时先调用工具。" + L10n.replyDirective + "当前时间：" + Sys.fmtFull(Date())
        if let r = await LLM.complete(instructions: ins, prompt: instr, maxTokens: 300, temperature: 0.4) { return r }
        let s = LanguageModelSession(tools: [Recall(), FetchURL()], instructions: ins)
        return (try? await s.respond(to: instr).content) ?? ""
    }

    // 返回本次处理的任务数
    @discardableResult
    static func refresh() async -> Int {
        await Sys.ensureNotif()
        let now = Date().timeIntervalSince1970
        var n = 0
        for r in DB.shared.rows("SELECT * FROM task WHERE state=0 ORDER BY due") {
            let id = r.i("id")
            let due = r.d("due")
            let useModel = r.i("use_model") == 1
            let rep = r.i("rep")
            var result = r.s("result")
            if useModel && result.isEmpty && due - now < 48 * 3600 {
                result = await gen(r.s("instr"))
                DB.shared.run("UPDATE task SET result=? WHERE id=?", [result, id])
            }
            let body = String((result.isEmpty ? r.s("instr") : result).prefix(160))
            if due > now {
                let pureRepeat = rep > 0 && !useModel
                Sys.notify(id: "task-\(id)", title: r.s("title"), body: body, at: Date(timeIntervalSince1970: due), rep: pureRepeat ? rep : 0)
                DB.shared.run("UPDATE task SET notified=1 WHERE id=?", [id])
                if due - now < 8 * 3600 { Live.timer(title: r.s("title"), subtitle: "定时任务", end: Date(timeIntervalSince1970: due)) }
                n += 1
            } else {
                if r.i("notified") == 0 {
                    Sys.notify(id: "task-\(id)", title: "补跑：" + r.s("title"), body: body, at: Date().addingTimeInterval(2))
                }
                if rep > 0 {
                    var next = due
                    while next <= now { next += Double(rep) * 86400 }
                    DB.shared.run("UPDATE task SET due=?, result='', notified=0 WHERE id=?", [next, id])
                } else {
                    DB.shared.run("UPDATE task SET state=1 WHERE id=?", [id])
                }
            }
        }
        return n
    }
}

// 进化：增量提炼长期事实入知识库，并谨慎地改写系统提示（版本化，可回滚），每次都留下记录
enum Evolve {
    static let defaultPrompt = "你是用户的私人助理，回答简洁直接，使用简体中文。需要记住的信息调用 remember；需要回忆或查资料调用 recall。涉及文件转换的请求必须调用对应工具完成，不要编造结果。"

    static func prompt() -> String {
        DB.shared.rows("SELECT body FROM prompt ORDER BY ver DESC LIMIT 1").first?.s("body") ?? defaultPrompt
    }

    static func versions() -> [Row] { DB.shared.rows("SELECT ver, body, ts FROM prompt ORDER BY ver DESC LIMIT 8") }

    @discardableResult
    static func saveVersion(_ body: String) -> Int {
        Int(DB.shared.run("INSERT INTO prompt(body,ts) VALUES(?,?)", [body, Date().timeIntervalSince1970]))
    }

    static func lastTime() -> Date? {
        guard let s = DB.shared.kv("evolve.time"), let t = Double(s) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    static func log() -> [Row] { DB.shared.rows("SELECT id, ts, summary, facts, ver FROM evo ORDER BY id DESC LIMIT 30") }

    // 一次性生成：本地大模型优先，其次系统模型
    private static func ask(_ ins: String, _ prompt: String) async -> String? {
        if let r = await LLM.complete(instructions: ins, prompt: prompt, maxTokens: 400, temperature: 0.2) { return r }
        return try? await LanguageModelSession(instructions: ins).respond(to: prompt).content
    }

    // 返回本次进化的摘要
    @discardableResult
    static func run(force: Bool = false) async -> String {
        let last = Int(DB.shared.kv("evolve.last") ?? "0") ?? 0
        let rows = DB.shared.rows("SELECT id, role, text FROM msg WHERE id > ? ORDER BY id LIMIT 20", [last])
        guard rows.count >= (force ? 2 : 6), let maxId = rows.last?.i("id") else {
            return force ? "还没有足够的新对话可供进化。" : ""
        }
        let logs = String(rows.map { $0.s("role") + ": " + String($0.s("text").prefix(150)) }.joined(separator: "\n").suffix(1200))
        guard let facts = await ask("反思引擎，只输出结果，不闲聊", "提炼不超过5条关于用户的长期事实或偏好，每行一条；没有就只输出“无”：\n" + logs) else {
            return force ? "进化时模型没有返回结果，稍后再试。" : ""
        }
        var learned: [String] = []
        if facts.count > 3 && facts != "无" {
            KB.shared.add("进化提炼", facts)
            learned = facts.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        DB.shared.setKV("evolve.last", String(maxId))
        DB.shared.setKV("evolve.time", String(Date().timeIntervalSince1970))
        var ver = 0
        var promptNote = "提示词保持不变"
        if rows.count >= 12 {
            let ask = "根据对话中暴露的缺陷改进系统提示，不超过300字，必须保留“remember”“recall”两个工具名，只输出新提示。\n当前提示：\n" + prompt() + "\n对话：\n" + logs
            if let p = await Self.ask("你是提示词工程师", ask),
               p.contains("remember"), p.contains("recall"), p.count < 600 {
                ver = saveVersion(p)
                promptNote = "系统提示已更新到第 \(ver) 版"
            }
        }
        let summary = "分析了 \(rows.count) 条新对话；新增 \(learned.count) 条记忆；\(promptNote)"
        DB.shared.run("INSERT INTO evo(ts,summary,facts,ver) VALUES(?,?,?,?)", [Date().timeIntervalSince1970, summary, learned.joined(separator: "\n"), ver])
        return summary
    }
}
