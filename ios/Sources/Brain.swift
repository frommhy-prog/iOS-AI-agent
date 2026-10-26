import Foundation

// MARK: 云端大脑的「思考 → 调用工具 → 回答」循环
// 模型要么直接回答，要么只输出一行 <tool>{"name":…,"args":{…}}</tool>；这里执行工具，把结果交回模型，最多 4 轮。
// 闹钟、提醒、日程这类「做事」的工具执行后直接用确定性的结果回复，不再让模型转述，避免说错。
@MainActor
enum Brain {
    struct Turn {
        let role: String
        let text: String
    }

    static let toolDoc = """
    可用工具（需要时才调用，一次只调用一个）：
    - web_search {"q":"搜索词"}：联网搜索。最新消息、新闻、价格、天气、你没把握的事实，先用它再回答
    - read_url {"url":"网址"}：读取网页正文
    - set_alarm {"time":"yyyy-MM-dd'T'HH:mm","title":"标题","repeat":"none|daily|weekly"}：设置会响铃的闹钟
    - add_reminder {"time":"yyyy-MM-dd'T'HH:mm","title":"内容","repeat":"none|daily|weekly"}：添加提醒事项
    - add_event {"time":"yyyy-MM-dd'T'HH:mm","title":"标题"}：添加日历日程
    - search_memory {"q":"关键词"}：查找用户的知识库和记忆
    - remember {"text":"内容"}：记住一条信息
    - run_skill {"name":"技能名","input":"输入内容"}：运行用户已有的脚本技能
    调用格式：整条回复只输出 <tool>{"name":"工具名","args":{…}}</tool>，不要输出别的文字。时间必须换算成上面的绝对时间格式。
    """

    static func system() -> String {
        let concise = (UserDefaults.standard.object(forKey: "style") as? Int ?? 0) == 0
        var s = "你是 \(Brand.name)，运行在用户 iPhone 上的个人助理（搜索·思考·行动）。" + L10n.replyDirective + "\n"
        s += "现在是" + Sys.fmtFull(Date()) + "，时区" + TimeZone.current.identifier + "。\n"
        s += "原则：先直接给结论，再补充必要说明；只回答当前这一个问题，不要复述问题；没有把握就说不确定，不要编造；用户要你做的事（闹钟、提醒、日程、记忆）直接用工具完成。"
        s += concise ? "回答控制在 150 字以内。" : "回答可以详细一些，条理清楚。"
        s += "需要列表或代码时用 Markdown。\n"
        s += "你做不到的事要直说：不能操作别的 App、不能代替用户点击屏幕、不能在后台常驻运行。\n"
        s += toolDoc
        let names = Skills.list().map { $0.s("name") }
        if !names.isEmpty { s += "\n已有的脚本技能：" + names.prefix(12).joined(separator: "、") }
        let p = Evolve.prompt()
        if p != Evolve.defaultPrompt { s += "\n用户偏好补充：" + String(p.prefix(300)) }
        return s
    }

    // 返回 nil：云端不可用，调用方改用本机模型。返回空串：被用户停止。
    static func ask(history: [Turn], user: String, ctx: String,
                    status: @escaping (String) -> Void,
                    onText: @escaping (String) -> Void) async -> String? {
        guard CloudLLM.ready else { return nil }
        var msgs: [[String: String]] = [["role": "system", "content": system()]]
        for h in history { msgs.append(["role": h.role, "content": h.text]) }
        msgs.append(["role": "user", "content": user + ctx])

        for round in 0..<4 {
            let text: String
            do {
                text = try await CloudLLM.stream(msgs, maxTokens: 1000, temperature: 0.4) { t in
                    let head = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    // 以 <tool 开头的是工具调用，不显示给用户
                    if head.hasPrefix("<tool") || "<tool>".hasPrefix(head) { return }
                    onText(t)
                }
            } catch {
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return "" }
                CloudLLM.lastError = error.localizedDescription
                return round == 0 ? nil : L10n.tr("云端出错：") + error.localizedDescription
            }
            guard let call = parseTool(text) else {
                if text.isEmpty {
                    CloudLLM.lastError = "模型没有返回内容"
                    return round == 0 ? nil : L10n.tr("这次没能完成，可以点「重新生成」。")
                }
                return text
            }
            let res = await run(call.0, call.1, status: status)
            if res.final { return L10n.tr(res.text) }
            msgs.append(["role": "assistant", "content": text])
            let more = round >= 2 ? "（现在不要再调用工具，直接回答用户。）" : "请据此回答用户的问题；资料不足时可再调用一次工具。"
            msgs.append(["role": "user", "content": "工具结果：\n" + res.text + "\n" + more])
        }
        return L10n.tr("这次没能完成，可以换个说法再试。")
    }

    static func parseTool(_ t: String) -> (String, [String: Any])? {
        guard let r = t.range(of: "<tool>") else { return nil }
        let rest = t[r.upperBound...]
        guard let a = rest.firstIndex(of: "{"), let b = rest.lastIndex(of: "}"), a < b,
              let d = String(rest[a...b]).data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let name = j["name"] as? String else { return nil }
        return (name, (j["args"] as? [String: Any]) ?? [:])
    }

    private static func when(_ a: [String: Any]) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        guard let s = a["time"] as? String else { return nil }
        return f.date(from: String(s.prefix(16)))
    }

    private static func rep(_ a: [String: Any]) -> Int {
        let r = a["repeat"] as? String
        return r == "daily" ? 1 : (r == "weekly" ? 7 : 0)
    }

    // 返回（结果文字，是否直接作为最终回复）
    private static func run(_ name: String, _ a: [String: Any], status: (String) -> Void) async -> (text: String, final: Bool) {
        let title = ((a["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "web_search":
            status("正在联网搜索…")
            Live.set(.searching)
            let hits = await WebSearch.search((a["q"] as? String) ?? "")
            return (hits.isEmpty ? "没有搜到结果（可能网络不通或搜索词太偏）。" : WebSearch.format(hits), false)
        case "read_url":
            status("正在读取网页…")
            Live.set(.searching)
            guard let s = a["url"] as? String, let u = URL(string: s), u.scheme == "http" || u.scheme == "https" else { return ("网址不正确。", false) }
            let page = await Agent.fetchPage(u)
            return (page.isEmpty ? "网页没有读到内容。" : page, false)
        case "search_memory":
            let hits = KB.shared.search((a["q"] as? String) ?? "", k: 4)
            return (hits.isEmpty ? "知识库和记忆里没有相关内容。" : hits.map { "- " + String($0.prefix(300)) }.joined(separator: "\n"), false)
        case "remember":
            let t = ((a["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return ("没有要记的内容。", false) }
            KB.shared.add("记忆", t)
            return ("好的，已经记住了。", true)
        case "run_skill":
            let n = (a["name"] as? String) ?? ""
            let r = Skills.run(n, (a["input"] as? String) ?? "")
            return (r.0 ? r.1 : "技能「\(n)」运行失败：\(r.1)", false)
        case "set_alarm", "add_reminder", "add_event":
            guard let d = when(a) else { return ("时间格式不对，请用 yyyy-MM-dd'T'HH:mm 重新调用。", false) }
            status("正在设置…")
            Live.set(.working)
            let soon = d.timeIntervalSinceNow > 0 && d.timeIntervalSinceNow < 8 * 3600
            switch name {
            case "set_alarm":
                let label = title.isEmpty ? "闹钟" : String(title.prefix(20))
                let r = await Sys.alarm(d, label, rep: rep(a))
                if r.hasPrefix("闹钟已设置"), soon { Live.timer(title: label, subtitle: "闹钟", end: d) }
                return (r, true)
            case "add_reminder":
                let label = title.isEmpty ? "提醒" : String(title.prefix(40))
                let r = await Sys.reminder(label, d, rep: rep(a))
                if r.hasPrefix("提醒已设置"), soon { Live.timer(title: label, subtitle: "提醒", end: d) }
                return (r, true)
            default:
                return (await Sys.event(title.isEmpty ? "日程" : String(title.prefix(30)), d), true)
            }
        default:
            return ("没有「\(name)」这个工具。", false)
        }
    }
}
