import Foundation
import JavaScriptCore

// 脚本技能：JS 存库，用系统自带 JavaScriptCore 运行。新增能力不需要重新编译或重签。
enum Skills {
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

    static func run(_ name: String, _ input: String) -> String {
        guard let code = DB.shared.rows("SELECT code FROM skill WHERE name=?", [name]).first?.s("code"), !code.isEmpty else { return "技能不存在" }
        guard let ctx = JSContext() else { return "脚本环境创建失败" }
        var err = ""
        ctx.exceptionHandler = { _, e in err = e?.toString() ?? "" }
        let kb: @convention(block) (String) -> [String] = { KB.shared.search($0, k: 3) }
        let get: @convention(block) (String) -> String = { u in
            guard let url = URL(string: u), let d = try? Data(contentsOf: url) else { return "" }
            return String(decoding: d.prefix(20000), as: UTF8.self)
        }
        ctx.setObject(kb, forKeyedSubscript: "kbSearch" as NSString)
        ctx.setObject(get, forKeyedSubscript: "fetchText" as NSString)
        ctx.evaluateScript("var skill = (\(code));")
        let r = ctx.objectForKeyedSubscript("skill")?.call(withArguments: [input])
        return err.isEmpty ? (r?.toString() ?? "") : "脚本错误：" + err
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
