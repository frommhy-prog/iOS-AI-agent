import Foundation
import UIKit

// 分享对话链接：把对话发到自己的 Cloudflare Worker（tstz-share），拿回一个可打开的网页链接，有效期 90 天。
// 网页的文字语言跟随应用当前语言（把 lang 一起发给服务）。
enum ShareService {
    static var base: String {
        UserDefaults.standard.string(forKey: "shareBase") ?? "https://tstz-share.from-mhy.workers.dev"
    }

    static func publish(title: String, msgs: [Msg]) async -> (URL?, String) {
        guard let api = URL(string: base + "/api/share") else { return (nil, L10n.tr("链接服务地址无效")) }
        let items: [[String: String]] = msgs.suffix(60).map { m in
            ["role": m.role, "text": String((m.text.isEmpty ? "[文件]" : m.text).prefix(4000))]
        }
        guard !items.isEmpty else { return (nil, L10n.tr("没有可分享的内容")) }
        let payload: [String: Any] = ["title": String(title.prefix(40)), "brand": Brand.name, "lang": L10n.code, "msgs": items]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return (nil, L10n.tr("内容编码失败")) }
        var req = URLRequest(url: api)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 429 { return (nil, L10n.tr("今天生成的链接太多了，明天再试")) }
            guard code == 200,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let s = j["url"] as? String, let u = URL(string: s) else { return (nil, L10n.f("链接服务返回异常（{}）", "\(code)")) }
            return (u, "")
        } catch {
            return (nil, L10n.f("连不上链接服务：{}", error.localizedDescription))
        }
    }
}
