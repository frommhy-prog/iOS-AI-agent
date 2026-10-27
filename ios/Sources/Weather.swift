import Foundation

// MARK: 天气：Open-Meteo（免费、无需密钥，所有用户通用）。先按城市名查经纬度，再取当前天气和三天预报。
// 确定性回答，不经过模型，所以不会编造；查不到时返回 nil，由调用方改走联网搜索。
enum Weather {
    static let words = ["天气", "气温", "温度", "下雨", "下雪", "冷不冷", "热不热", "带伞", "穿什么", "穿多少", "几度", "降温", "升温"]

    static func desc(_ c: Int) -> String {
        switch c {
        case 0: return "晴"
        case 1: return "大部晴朗"
        case 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "有雾"
        case 51, 53, 55: return "毛毛雨"
        case 56, 57, 66, 67: return "冻雨"
        case 61, 80: return "小雨"
        case 63, 81: return "中雨"
        case 65, 82: return "大雨"
        case 71, 85: return "小雪"
        case 73, 86: return "中雪"
        case 75: return "大雪"
        case 77: return "雪粒"
        case 95: return "雷暴"
        case 96, 99: return "雷暴伴冰雹"
        default: return "天气不明"
        }
    }

    // 从一句话里取出城市名：去掉时间词、疑问词、天气词，剩下的就是地名
    static func city(from t: String) -> String {
        var s = t
        let junk = ["今天", "明天", "后天", "今日", "明日", "今早", "明早", "今晚", "明晚", "今夜", "早上", "晚上", "上午", "下午", "中午", "傍晚", "夜里",
                    "现在", "目前", "这几天", "这两天", "最近", "未来", "本周", "周末", "怎么样", "怎样", "如何", "好不好", "请问", "帮我", "帮忙",
                    "我想知道", "想知道", "告诉我", "查一下", "查查", "查询", "看看", "看一下", "看下", "会不会", "要不要", "有没有", "多少度", "几度",
                    "冷不冷", "热不热", "下雨", "下雪", "带伞", "穿什么", "穿多少", "天气预报", "天气", "气温", "温度", "预报", "降温", "升温",
                    "我这边", "我这里", "这边", "这里", "那边", "当地", "本地", "一下", "怎么", "什么", "还是", "是否", "需要",
                    "吗", "呢", "啊", "吧", "的", "我", "查", "会", "有", "？", "?", "，", ",", "。", "！", "!", " "]
        for j in junk.sorted(by: { $0.count > $1.count }) { s = s.replacingOccurrences(of: j, with: "") }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count <= 8 ? s : ""
    }

    private static func json(_ s: String) async -> [String: Any]? {
        guard let u = URL(string: s) else { return nil }
        var r = URLRequest(url: u)
        r.timeoutInterval = 10
        guard let (d, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    private static func num(_ x: Any?) -> Double? { (x as? NSNumber)?.doubleValue }

    // day：0 今天，1 明天，2 后天（决定要不要先报当前实况）
    static func report(city: String, day: Int = 0) async -> String? {
        guard let enc = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let g = await json("https://geocoding-api.open-meteo.com/v1/search?name=\(enc)&count=1&language=zh&format=json"),
              let first = (g["results"] as? [[String: Any]])?.first,
              let lat = num(first["latitude"]), let lon = num(first["longitude"]) else { return nil }
        let name = (first["name"] as? String) ?? city
        let url = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=3"
        guard let w = await json(url), let daily = w["daily"] as? [String: Any],
              let codes = daily["weather_code"] as? [Any],
              let maxs = daily["temperature_2m_max"] as? [Any],
              let mins = daily["temperature_2m_min"] as? [Any] else { return nil }
        let rain = (daily["precipitation_probability_max"] as? [Any]) ?? []

        var lines: [String] = []
        if day == 0, let cur = w["current"] as? [String: Any], let t = num(cur["temperature_2m"]) {
            var s = "\(name) 现在 \(Int(t.rounded()))°C"
            if let f = num(cur["apparent_temperature"]) { s += "（体感 \(Int(f.rounded()))°C）" }
            s += "，" + desc(Int(num(cur["weather_code"]) ?? -1))
            if let h = num(cur["relative_humidity_2m"]) { s += "，湿度 \(Int(h))%" }
            if let v = num(cur["wind_speed_10m"]) { s += "，风速 \(Int(v.rounded())) km/h" }
            lines.append(s + "。")
        } else {
            lines.append("\(name) 天气预报：")
        }
        let labels = ["今天", "明天", "后天"]
        var tip = ""
        for i in 0..<min(3, codes.count, maxs.count, mins.count) {
            guard let hi = num(maxs[i]), let lo = num(mins[i]) else { continue }
            var s = "- \(labels[i]) \(Int(lo.rounded()))~\(Int(hi.rounded()))°C，" + desc(Int(num(codes[i]) ?? -1))
            if i < rain.count, let p = num(rain[i]) {
                s += "，降水概率 \(Int(p))%"
                if i == day, p >= 50 { tip = "建议带伞。" }
            }
            if i == day {
                if hi >= 33 { tip += "天气炎热，注意防暑。" }
                else if lo <= 5 { tip += "天气偏冷，注意保暖。" }
            }
            lines.append(s)
        }
        if !tip.isEmpty { lines.append(tip) }
        lines.append("（数据：Open-Meteo）")
        return lines.joined(separator: "\n")
    }

    // 「北京天气」「明天要带伞吗」：直接查，不交给模型
    static func route(_ t: String) async -> String? {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count <= 40, words.contains(where: { s.contains($0) }) else { return nil }
        let stored = DB.shared.kv("weather.city") ?? ""
        let typed = city(from: s)
        let day = s.contains("后天") ? 2 : (s.contains("明") ? 1 : 0)
        if !typed.isEmpty, let r = await report(city: typed, day: day) {
            DB.shared.setKV("weather.city", typed)
            return r
        }
        if !stored.isEmpty, let r = await report(city: stored, day: day) { return r }
        if typed.isEmpty && stored.isEmpty { return "想查哪个城市的天气？比如「北京天气」。查过一次后，只说「天气」就会用上次的城市。" }
        return nil
    }
}
