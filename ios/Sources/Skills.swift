import Foundation
import JavaScriptCore
import FoundationModels

@Generable
struct SkillDraft {
    @Guide(description: "技能名，4到8个汉字") var name: String
    @Guide(description: "一句话用途") var desc: String
    @Guide(description: "测试用的示例输入，一个简短字符串") var sample: String
    @Guide(description: "JavaScript 函数源码，形式 function(input){ ... return 字符串; }") var code: String
}

// 只放行一次：超时和正常结束谁先到谁生效
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// 脚本技能：自然语言描述 → 自动生成 → 自动测试运行 → 失败自动修复 → 保存。运行用系统自带的 JavaScriptCore。
// 生成代码优先用云端大脑（已填密钥时）和本地大模型（已下载时），否则用系统自带模型。
enum Skills {
    static let rules = """
    你是 JavaScript 工程师。只写纯 JavaScript（ES5 语法），不要使用 setTimeout、Promise、async、await、require、import、fetch、document、window。
    代码必须是单个函数表达式：function(input){ ... return 结果字符串; }，input 是用户传入的字符串。
    只能使用字符串、数组、对象、Math、Date、JSON、正则。
    需要联网读取网页文字时调用同步函数 fetchText(url)；需要查询知识库时调用 kbSearch(关键词)，返回字符串数组。
    必须有返回值，返回字符串。不要输出解释。
    """

    static func list() -> [Row] { DB.shared.rows("SELECT name, desc, ts FROM skill ORDER BY ts DESC") }

    static func remove(_ name: String) {
        DB.shared.run("DELETE FROM skill WHERE name=?", [name])
        DB.shared.run("DELETE FROM chunk WHERE doc IN (SELECT id FROM doc WHERE name=?)", ["技能:" + name])
        DB.shared.run("DELETE FROM doc WHERE name=?", ["技能:" + name])
    }

    static func save(_ name: String, _ desc: String, _ code: String) {
        DB.shared.run("INSERT OR REPLACE INTO skill(name,desc,code,ts) VALUES(?,?,?,?)", [name, desc, code, Date().timeIntervalSince1970])
        KB.shared.upsert("技能:" + name, desc + "（用 run_skill 调用：" + name + "）")
    }

    static func clean(_ code: String) -> String {
        var c = code
        for f in ["```javascript", "```js", "```JavaScript", "```"] { c = c.replacingOccurrences(of: f, with: "") }
        c = c.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.hasSuffix(";") { c.removeLast() }
        return c
    }

    // 返回（是否成功，输出或人话报错）
    static func runCode(_ code: String, _ input: String) -> (Bool, String) {
        guard let ctx = JSContext() else { return (false, "脚本环境创建失败") }
        var err = ""
        ctx.exceptionHandler = { _, e in err = e?.toString() ?? "" }
        ctx.evaluateScript("var console={log:function(){},error:function(){}};var setTimeout=function(f){try{f()}catch(e){};return 0};var setInterval=function(){return 0};var window={};")
        let kb: @convention(block) (String) -> [String] = { KB.shared.search($0, k: 3) }
        let get: @convention(block) (String) -> String = { u in
            guard let url = URL(string: u), let d = try? Data(contentsOf: url) else { return "" }
            return String(decoding: d.prefix(20000), as: UTF8.self)
        }
        ctx.setObject(kb, forKeyedSubscript: "kbSearch" as NSString)
        ctx.setObject(get, forKeyedSubscript: "fetchText" as NSString)
        ctx.evaluateScript("var skill = (\(code));")
        if !err.isEmpty { return (false, friendly(err)) }
        let r = ctx.objectForKeyedSubscript("skill")?.call(withArguments: [input])
        if !err.isEmpty { return (false, friendly(err)) }
        let out = (r == nil || r!.isUndefined || r!.isNull) ? "" : (r!.toString() ?? "")
        return out.isEmpty ? (false, "脚本没有返回结果") : (true, out)
    }

    static func run(_ name: String, _ input: String) -> (Bool, String) {
        guard let code = DB.shared.rows("SELECT code FROM skill WHERE name=?", [name]).first?.s("code"), !code.isEmpty else { return (false, "没有找到这个技能") }
        return runCode(code, input)
    }

    // 在后台线程运行并限时：脚本死循环或网络很慢时不会卡住界面，超时就放弃等待
    static func runAsync(_ name: String, _ input: String, timeout: Double = 12) async -> (Bool, String) {
        await withCheckedContinuation { (c: CheckedContinuation<(Bool, String), Never>) in
            let once = Once()
            DispatchQueue.global(qos: .userInitiated).async {
                let r = Skills.run(name, input)
                if once.claim() { c.resume(returning: r) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.claim() { c.resume(returning: (false, "脚本运行超时（超过 \(Int(timeout)) 秒），已放弃等待。")) }
            }
        }
    }

    typealias Draft = (name: String, desc: String, sample: String, code: String)

    // 大模型（云端或本地）：用分段格式而不是 JSON，多行代码不会因为转义出错
    static func parseDraft(_ t: String) -> Draft? {
        guard let cr = t.range(of: "CODE:") else { return nil }
        let head = String(t[..<cr.lowerBound])
        let code = String(t[cr.upperBound...])
        func field(_ k: String) -> String {
            guard let r = head.range(of: k + ":") else { return "" }
            let rest = head[r.upperBound...]
            let line = rest.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            return line.trimmingCharacters(in: .whitespaces)
        }
        let name = field("NAME")
        let desc = field("DESC")
        let sample = field("SAMPLE")
        guard !name.isEmpty, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (name, desc.isEmpty ? name : desc, sample, code)
    }

    private static func localDraft(_ spec: String, _ last: String, _ err: String, _ attempt: Int) async -> Draft? {
        var prompt = "需求：" + spec + "\n\n严格按下面的格式输出，不要输出别的：\nNAME: 技能名（4到8个汉字）\nDESC: 一句话用途\nSAMPLE: 测试用的示例输入\nCODE:\nfunction(input){ ... return 字符串; }"
        if attempt > 1 { prompt += "\n\n上次的代码：\n" + last + "\n运行结果：" + err + "\n请修复后重新按格式输出。" }
        guard let text = await LLM.complete(instructions: rules, prompt: prompt, maxTokens: 900, temperature: 0.2) else { return nil }
        return parseDraft(text)
    }

    // 创建并运行：最多尝试 3 次，失败时把错误交还模型修复
    static func create(_ spec: String, progress: @escaping (String) -> Void) async -> (name: String, ok: Bool, out: String) {
        var last = ""
        var err = ""
        let local = await LLM.localAvailable()
        for attempt in 1...3 {
            progress(attempt == 1 ? "正在编写脚本…" : "正在修复脚本（第 \(attempt) 次尝试）…")
            var draft: Draft?
            if local {
                draft = await localDraft(spec, last, err, attempt)
            } else {
                var prompt = "需求：" + spec
                if attempt > 1 { prompt += "\n上次的代码：\n" + last + "\n运行结果：" + err + "\n请修复后重新输出。" }
                let s = LanguageModelSession(instructions: rules)
                if let g = try? await s.respond(to: prompt, generating: SkillDraft.self).content {
                    draft = (g.name, g.desc, g.sample, g.code)
                }
            }
            guard let d = draft else {
                err = "模型没有返回内容"
                continue
            }
            last = clean(d.code)
            progress("正在测试运行…")
            let (ok, out) = runCode(last, d.sample)
            if ok {
                save(d.name, d.desc, last)
                return (d.name, true, out)
            }
            err = out
        }
        return ("", false, err)
    }

    // 导入电脑上写好的技能包：[{"name","desc","code"}]
    static func importPack(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        struct S: Decodable { let name: String; let desc: String; let code: String }
        let list = (try? JSONDecoder().decode([S].self, from: Data(contentsOf: url))) ?? []
        list.forEach { save($0.name, $0.desc, $0.code) }
    }
}
