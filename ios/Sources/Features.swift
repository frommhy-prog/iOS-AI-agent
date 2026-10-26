import Foundation

// MARK: 不需要模型的确定性回答：能力介绍、运行已有技能
// 小模型被问「你能做什么」时容易胡说，这里直接给出真实的功能清单。
enum Features {
    static let intro = """
    我是 OSVIA，住在你 iPhone 里的个人助理。能直接帮你：
    - 闹钟、提醒、日程：说「明早七点叫我起床」「每周一下午三点提醒我开会」
    - 联网搜索、读网页：问最新消息、价格、天气，或发一个链接让我总结
    - 文件与图片：转成 PDF / PNG、识别图片文字、压缩、提取音频
    - 知识库与记忆：说「记住……」，以后可以随时问我
    - 脚本技能：一句话做一个处理文字的小脚本，在 工具箱 → 脚本技能 里使用
    做不到的事：操作别的 App、代替你点击屏幕、在后台常驻运行。
    想让回答更聪明：设置 → 云端大脑，填一个免费密钥。
    """

    static func route(_ t: String) async -> String? {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = s.lowercased()

        // 能力介绍（只匹配简短的提问，避免抢走正常的长问题）
        let asks = ["你能做什么", "你会什么", "你可以做什么", "你有什么功能", "你能干什么", "你在干什么", "你是谁", "怎么用", "如何使用", "使用说明", "功能介绍",
                    "他可以做什么", "它可以做什么", "what can you do", "who are you"]
        if s.count <= 14 && asks.contains(where: { low.contains($0) }) { return intro }

        // 运行已有技能：「运行 XX」「运行 XX 内容……」
        let verbs = ["运行", "执行", "使用", "用"]
        if let v = verbs.first(where: { s.hasPrefix($0) }) {
            for row in Skills.list() {
                let name = row.s("name")
                guard !name.isEmpty, s.hasPrefix(v + name) || s.hasPrefix(v + " " + name) else { continue }
                var input = String(s.dropFirst(v.count)).trimmingCharacters(in: .whitespaces)
                input = String(input.dropFirst(name.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ，,：:\n"))
                let r = Skills.run(name, input)
                return r.0 ? r.1 : "技能「\(name)」运行失败：\(r.1)"
            }
        }
        return nil
    }
}
