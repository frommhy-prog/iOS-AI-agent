import Foundation

// MARK: 本机大模型的「思考 → 工具 → 回答」循环
// 与云端大脑同一套 <tool>{"name":…,"args":{…}}</tool> 约定，但只开放搜索、读网页、知识库、技能这几个，最多 3 轮。
// 闹钟、提醒、日程不在这里：它们由 Router 和 Agent.localIntent 确定性处理，小模型不碰。
@MainActor
enum LocalBrain {
    static func toolDoc(skills: [String]) -> String {
        var l: [String] = [
            "你可以调用下面的工具，一次只调用一个：",
            "- web_search {\"q\":\"搜索词\"}：联网搜索",
            "- read_url {\"url\":\"网址\"}：读取网页正文",
            "- search_memory {\"q\":\"关键词\"}：查用户的知识库和记忆"
        ]
        if !skills.isEmpty {
            l.append("- run_skill {\"name\":\"技能名\",\"input\":\"输入内容\"}：运行用户已有的脚本技能（可用：" + skills.joined(separator: "、") + "）")
        }
        l.append("调用格式：整条回复只输出 <tool>{\"name\":\"工具名\",\"args\":{…}}</tool>，不要有别的文字。")
        l.append("只有这几类问题才调用工具：最新消息、新闻、价格、天气、比分，你不确定的具体事实（人名、数据、版本号），用户明确要求联网查。写作、翻译、计算、代码、闲聊、常识一律直接回答，不要调用工具。")
        return l.joined(separator: "\n")
    }

    // 返回最终回复；被用户停止返回空串；出错返回错误说明
    static func ask(instructions: String, history: [Brain.Turn], user: String, tools: Bool,
                    status: @escaping (String) -> Void,
                    onText: @escaping (String) -> Void) async -> String {
        var ins = instructions
        if tools {
            let skills = Skills.list().map { $0.s("name") }.filter { !$0.isEmpty && user.contains($0) }
            ins += "\n" + toolDoc(skills: skills)
        }
        var turns: [(role: String, text: String)] = history.map { (role: $0.role, text: $0.text) }
        var prompt = user
        let rounds = tools ? 3 : 1
        for round in 0..<rounds {
            let text: String
            do {
                text = try await LocalLLM.shared.generate(instructions: ins, prompt: prompt, maxTokens: 900, temperature: 0.4, history: turns) { t in
                    if tools {
                        let head = t.trimmingCharacters(in: .whitespacesAndNewlines)
                        // 以 <tool 开头的是工具调用，不显示给用户
                        if head.hasPrefix("<tool") || "<tool>".hasPrefix(head) { return }
                    }
                    onText(t)
                }
            } catch {
                if Task.isCancelled || error is CancellationError { return "" }
                return L10n.f("本地模型出错：{}", String(error.localizedDescription.prefix(120)))
            }
            if !tools { return text }
            guard let call = Brain.parseTool(text) else {
                // 工具调用格式写坏了：让它直接回答，只重试一次
                if text.contains("<tool"), round < rounds - 1 {
                    turns.append((role: "user", text: prompt))
                    turns.append((role: "assistant", text: String(text.prefix(300))))
                    prompt = "（工具调用的格式不对。现在不要调用工具，直接回答用户刚才的问题。）"
                    continue
                }
                return text
            }
            let res = await run(call.0, call.1, status: status)
            if res.final { return L10n.tr(res.text) }
            turns.append((role: "user", text: prompt))
            turns.append((role: "assistant", text: text))
            let more = round >= rounds - 2 ? "（现在不要再调用工具，直接回答用户的问题。）" : "请据此回答用户的问题；资料不足时可以再调用一次工具。"
            prompt = "工具结果：\n" + res.text + "\n" + more
        }
        return L10n.tr("这次没能完成，可以换个说法再试。")
    }

    // 返回（结果文字，是否直接作为最终回复）
    private static func run(_ name: String, _ a: [String: Any], status: (String) -> Void) async -> (text: String, final: Bool) {
        switch name {
        case "web_search":
            status("正在联网搜索…")
            Live.set(.searching)
            let hits = await WebSearch.search((a["q"] as? String) ?? "")
            return (hits.isEmpty ? "没有搜到结果（可能网络不通或搜索词太偏）。" : String(WebSearch.format(hits).prefix(3000)), false)
        case "read_url":
            status("正在读取网页…")
            Live.set(.searching)
            guard let s = a["url"] as? String, let u = URL(string: s), u.scheme == "http" || u.scheme == "https" else { return ("网址不正确。", false) }
            let page = await Agent.fetchPage(u)
            return (page.isEmpty ? "网页没有读到内容。" : page, false)
        case "search_memory":
            let hits = KB.shared.search((a["q"] as? String) ?? "", k: 4)
            return (hits.isEmpty ? "知识库和记忆里没有相关内容。" : hits.map { "- " + String($0.prefix(300)) }.joined(separator: "\n"), false)
        case "run_skill":
            let n = (a["name"] as? String) ?? ""
            let r = Skills.run(n, (a["input"] as? String) ?? "")
            return (r.0 ? r.1 : "技能「\(n)」运行失败：\(r.1)", false)
        default:
            return ("没有「\(name)」这个工具，请直接回答。", false)
        }
    }
}
