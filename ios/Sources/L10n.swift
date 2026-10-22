import SwiftUI
import Translation
import FoundationModels

struct AppLang: Identifiable, Hashable {
    let code: String      // 应用内语言代码
    let native: String    // 语言自己的名字
    let locale: String    // 日期、语音识别、朗读用的地区代码
    let english: String   // 告诉模型「用什么语言回答」
    let apple: String     // 系统翻译框架用的语言标识
    var rtl = false
    var id: String { code }
}

// 语言服务：界面文字、通知、灵动岛、分享页、语音识别、朗读、模型回答、日期格式都从这里取当前语言。
// 源码里的文字仍然是简体中文，显示时按当前语言查表（tr），查不到就原样显示。
enum L10n {
    static let langs: [AppLang] = [
        AppLang(code: "zh-Hans", native: "简体中文", locale: "zh-CN", english: "Simplified Chinese", apple: "zh-Hans"),
        AppLang(code: "zh-Hant", native: "繁體中文", locale: "zh-TW", english: "Traditional Chinese", apple: "zh-Hant"),
        AppLang(code: "en", native: "English", locale: "en-US", english: "English", apple: "en"),
        AppLang(code: "ja", native: "日本語", locale: "ja-JP", english: "Japanese", apple: "ja"),
        AppLang(code: "ko", native: "한국어", locale: "ko-KR", english: "Korean", apple: "ko"),
        AppLang(code: "es", native: "Español", locale: "es-ES", english: "Spanish", apple: "es"),
        AppLang(code: "fr", native: "Français", locale: "fr-FR", english: "French", apple: "fr"),
        AppLang(code: "de", native: "Deutsch", locale: "de-DE", english: "German", apple: "de"),
        AppLang(code: "pt", native: "Português (Brasil)", locale: "pt-BR", english: "Brazilian Portuguese", apple: "pt-BR"),
        AppLang(code: "it", native: "Italiano", locale: "it-IT", english: "Italian", apple: "it"),
        AppLang(code: "ru", native: "Русский", locale: "ru-RU", english: "Russian", apple: "ru"),
        AppLang(code: "tr", native: "Türkçe", locale: "tr-TR", english: "Turkish", apple: "tr"),
        AppLang(code: "vi", native: "Tiếng Việt", locale: "vi-VN", english: "Vietnamese", apple: "vi"),
        AppLang(code: "th", native: "ไทย", locale: "th-TH", english: "Thai", apple: "th"),
        AppLang(code: "id", native: "Bahasa Indonesia", locale: "id-ID", english: "Indonesian", apple: "id"),
        AppLang(code: "ar", native: "العربية", locale: "ar-SA", english: "Arabic", apple: "ar", rtl: true),
        AppLang(code: "hi", native: "हिन्दी", locale: "hi-IN", english: "Hindi", apple: "hi")
    ]

    private static let lock = NSLock()
    private static var _code = "zh-Hans"
    private static var memo: [String: String] = [:]
    private static var caches: [String: [String: String]] = [:]
    private static var compiled: [String: [(NSRegularExpression, String)]] = [:]

    // MARK: 当前语言
    // 首次安装：没有保存过设置就设为「跟随系统」
    static func bootstrap() {
        if UserDefaults.standard.object(forKey: "appLang") == nil { UserDefaults.standard.set("system", forKey: "appLang") }
        reload()
    }

    static var setting: String { UserDefaults.standard.string(forKey: "appLang") ?? "system" }

    static func systemCode() -> String {
        for p in Locale.preferredLanguages {
            let l = p.lowercased()
            if l.hasPrefix("zh") {
                return (l.contains("hant") || l.contains("-tw") || l.contains("-hk") || l.contains("-mo")) ? "zh-Hant" : "zh-Hans"
            }
            let base = String(l.prefix(2))
            if langs.contains(where: { $0.code == base }) { return base }
        }
        return "en"
    }

    static func reload() {
        let s = setting
        let c = s == "system" ? systemCode() : (langs.contains { $0.code == s } ? s : "en")
        let cache = loadCache(c)
        lock.lock()
        _code = c
        memo.removeAll()
        caches[c] = cache
        compiled[c] = nil
        lock.unlock()
    }

    static var code: String { lock.lock(); defer { lock.unlock() }; return _code }
    static var info: AppLang { langs.first { $0.code == code } ?? langs[2] }
    static var locale: Locale { Locale(identifier: info.locale) }
    static var rtl: Bool { info.rtl }
    static var isChinese: Bool { code == "zh-Hans" }
    static var cjkStyle: Bool { code == "zh-Hans" || code == "zh-Hant" || code == "ja" }
    static var currentName: String {
        if setting == "system" { return tr("跟随系统") + " · " + (langs.first { $0.code == systemCode() }?.native ?? "English") }
        return info.native
    }
    static var colon: String { cjkStyle ? "：" : ": " }

    // 一组内容的连接符：中日文用逗号「、」，其他语言用「, 」
    static func list(_ items: [String]) -> String { items.joined(separator: cjkStyle ? "、" : ", ") }

    // MARK: 语言服务：本机模型、语音
    static func modelSupports(_ code: String) -> Bool {
        guard let l = langs.first(where: { $0.code == code }) else { return false }
        return SystemLanguageModel.default.supportsLocale(Locale(identifier: l.locale))
    }

    // 告诉本机模型用哪种语言回答；模型不支持该语言时回退到英语
    static var replyDirective: String {
        let c = code
        if c == "zh-Hans" { return "使用简体中文回答。" }
        let name = modelSupports(c) ? info.english : (modelSupports("en") ? "English" : "Simplified Chinese")
        return "Always reply in \(name)."
    }

    // MARK: 翻译
    private static func hasCJK(_ s: String) -> Bool {
        for u in s.unicodeScalars where (u.value >= 0x4E00 && u.value <= 0x9FFF) || (u.value >= 0x3400 && u.value <= 0x4DBF) { return true }
        return false
    }

    static func tr(_ s: String) -> String {
        guard hasCJK(s) else { return s }
        lock.lock()
        defer { lock.unlock() }
        let c = _code
        let k = c + "\u{1}" + s
        if let m = memo[k] { return m }
        var out = translate(s, c, segments: true)
        if out.contains("TSTZ Bot") { out = out.replacingOccurrences(of: "TSTZ Bot", with: Brand.name) }
        if s.count <= 300 {
            if memo.count > 4000 { memo.removeAll() }
            memo[k] = out
        }
        return out
    }

    // 带 {} 占位的模板：先翻译模板，再把参数按顺序填进去
    static func f(_ key: String, _ args: String...) -> String { fill(tr(key), args) }

    private static let ph = try! NSRegularExpression(pattern: "\\{(\\d*)\\}")

    static func fill(_ v: String, _ args: [String]) -> String {
        guard v.contains("{") else { return v }
        let ns = v as NSString
        var out = ""
        var last = 0
        var seq = 0
        for m in ph.matches(in: v, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let d = ns.substring(with: m.range(at: 1))
            var idx = seq
            if d.isEmpty { seq += 1 } else { idx = (Int(d) ?? 1) - 1 }
            if idx >= 0 && idx < args.count { out += args[idx] }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    private static func chain(_ c: String) -> [String] {
        if c == "en" { return ["en"] }
        if c == "zh-Hant" { return ["zh-Hant"] }
        return [c, "en"]
    }

    private static func table(_ c: String) -> [String: String] {
        c == "en" ? L10nTable.en : (caches[c] ?? [:])
    }

    private static func templates(_ c: String) -> [(NSRegularExpression, String)] {
        if let t = compiled[c] { return t }
        var out: [(NSRegularExpression, String)] = []
        for (k, v) in table(c) where k.contains("{}") {
            let pat = "^" + k.components(separatedBy: "{}").map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "(.+?)") + "$"
            if let re = try? NSRegularExpression(pattern: pat, options: [.dotMatchesLineSeparators]) { out.append((re, v)) }
        }
        out.sort { $0.0.pattern.count > $1.0.pattern.count }
        compiled[c] = out
        return out
    }

    private static func translate(_ s: String, _ c: String, segments: Bool) -> String {
        if c == "zh-Hans" { return s }
        for t in chain(c) {
            if let v = table(t)[s] { return v }
            if s.count <= 300 {
                let ns = s as NSString
                for (re, v) in templates(t) {
                    guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { continue }
                    var caps: [String] = []
                    for i in 1..<m.numberOfRanges { caps.append(translate(ns.substring(with: m.range(at: i)), c, segments: false)) }
                    return fill(v, caps)
                }
            }
        }
        if segments, let v = bySentence(s, c) { return v }
        return s
    }

    // 多句文字按「。」和换行拆开逐句翻译；开头的表情符号保留
    private static func bySentence(_ s: String, _ c: String) -> String? {
        guard s.contains("。") || s.contains("\n"), s.count <= 3000 else { return nil }
        let stop = c == "zh-Hant" || c == "ja" ? "。" : ". "
        var out = ""
        var seg = ""
        var changed = false
        func flush(_ delim: String) {
            var prefix = ""
            var core = Substring(seg)
            while let ch = core.first, ch.unicodeScalars.allSatisfy({ ($0.properties.isEmoji && $0.value > 0x2000) || $0.properties.isWhitespace || $0.value == 0xFE0F }) {
                prefix.append(ch)
                core = core.dropFirst()
            }
            let coreS = String(core)
            if coreS.isEmpty || !hasCJK(coreS) {
                out += seg + delim
            } else {
                let t = translate(coreS, c, segments: false)
                if t != coreS {
                    changed = true
                    out += prefix + t + (delim == "。" ? stop : delim)
                } else {
                    out += seg + delim
                }
            }
            seg = ""
        }
        for ch in s {
            if ch == "。" { flush("。") } else if ch == "\n" { flush("\n") } else { seg.append(ch) }
        }
        if !seg.isEmpty { flush("") }
        guard changed else { return nil }
        return out.trimmingCharacters(in: .whitespaces)
    }

    // MARK: 译文缓存（系统翻译的结果）
    private static func cacheURL(_ c: String) -> URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("l10n", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent(c + ".json")
    }

    private static func loadCache(_ c: String) -> [String: String] {
        guard c != "en", c != "zh-Hans",
              let d = try? Data(contentsOf: cacheURL(c)),
              let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        return m
    }

    static func saveCache(_ c: String, _ m: [String: String]) {
        if let d = try? JSONEncoder().encode(m) { try? d.write(to: cacheURL(c), options: .atomic) }
        lock.lock()
        caches[c] = m
        compiled[c] = nil
        memo.removeAll()
        lock.unlock()
    }

    static func cacheCopy(_ c: String) -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return caches[c] ?? [:]
    }

    // 还没有译文的键（英文表里有的都翻译）
    static func missingKeys(_ c: String) -> [String] {
        let have = cacheCopy(c)
        return L10nTable.en.keys.filter { have[$0] == nil }.sorted()
    }

    // 模板里的 {} 换成 QZ1、QZ2…，避免翻译时被改坏；返回占位个数
    static func mask(_ k: String) -> (String, Int) {
        var n = 0
        var out = ""
        var rest = Substring(k)
        while let r = rest.range(of: "{}") {
            n += 1
            out += rest[..<r.lowerBound] + "QZ\(n)"
            rest = rest[r.upperBound...]
        }
        out += rest
        return (out, n)
    }

    static func unmask(_ t: String, _ n: Int) -> String? {
        var s = t
        if n > 0 {
            for i in 1...n {
                guard s.components(separatedBy: "QZ\(i)").count == 2 else { return nil }
                s = s.replacingOccurrences(of: "QZ\(i)", with: "{\(i)}")
            }
        }
        return s
    }
}

func tr(_ s: String) -> String { L10n.tr(s) }
