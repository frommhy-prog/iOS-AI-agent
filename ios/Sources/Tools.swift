import Foundation
import FoundationModels

struct SetAlarm: Tool {
    let name = "set_alarm"
    let description = "设置系统闹钟，到点响铃，静音和专注模式下也会响"
    @Generable struct Arguments {
        @Guide(description: "距今天的天数：0今天 1明天 2后天 7一周后", .range(0...365)) var dayOffset: Int
        @Guide(description: "24小时制小时，明早十点为10，晚上八点为20", .range(0...23)) var hour: Int
        @Guide(description: "分钟", .range(0...59)) var minute: Int
        @Guide(description: "闹钟标题") var label: String
    }
    func call(arguments a: Arguments) async throws -> String {
        await Sys.alarm(a.dayOffset, a.hour, a.minute, a.label)
    }
}

struct AddReminder: Tool {
    let name = "add_reminder"
    let description = "在系统提醒事项里添加一条到点提醒"
    @Generable struct Arguments {
        @Guide(description: "提醒内容") var title: String
        @Guide(description: "距今天的天数：0今天 1明天 7一周后", .range(0...365)) var dayOffset: Int
        @Guide(description: "24小时制小时", .range(0...23)) var hour: Int
        @Guide(description: "分钟", .range(0...59)) var minute: Int
        @Guide(description: "备注，可为空") var notes: String
    }
    func call(arguments a: Arguments) async throws -> String {
        await Sys.reminder(a.title, a.dayOffset, a.hour, a.minute, a.notes)
    }
}

struct AddEvent: Tool {
    let name = "add_event"
    let description = "在系统日历里添加日程"
    @Generable struct Arguments {
        @Guide(description: "日程标题") var title: String
        @Guide(description: "距今天的天数", .range(0...365)) var dayOffset: Int
        @Guide(description: "24小时制小时", .range(0...23)) var hour: Int
        @Guide(description: "分钟", .range(0...59)) var minute: Int
        @Guide(description: "时长，分钟", .range(5...600)) var durationMinutes: Int
    }
    func call(arguments a: Arguments) async throws -> String {
        await Sys.event(a.title, a.dayOffset, a.hour, a.minute, a.durationMinutes)
    }
}

struct ScheduleTask: Tool {
    let name = "schedule_task"
    let description = "创建定时任务：到点由助理执行并用通知送达结果。可联网读取网页"
    @Generable struct Arguments {
        @Guide(description: "任务标题，通知上显示") var title: String
        @Guide(description: "到点要做的事，例如：总结今天的待办 / 播报某个网址的内容") var instruction: String
        @Guide(description: "距今天的天数", .range(0...365)) var dayOffset: Int
        @Guide(description: "24小时制小时", .range(0...23)) var hour: Int
        @Guide(description: "分钟", .range(0...59)) var minute: Int
        @Guide(description: "到点前是否需要助理先生成内容（总结、播报、建议）；纯提醒填 false") var useModel: Bool
        @Guide(description: "是否每天重复") var repeatDaily: Bool
    }
    func call(arguments a: Arguments) async throws -> String {
        guard let d = Sys.date(a.dayOffset, a.hour, a.minute) else { return "失败：时间无效" }
        var due = d
        if due <= Date() {
            if a.repeatDaily { due = due.addingTimeInterval(86400) } else { return "失败：时间已过" }
        }
        let id = Tasks.add(a.title, a.instruction, due, useModel: a.useModel, repeatDaily: a.repeatDaily)
        await Tasks.refresh()
        return "已创建定时任务#\(id)「\(a.title)」，\(Sys.fmt(due))\(a.repeatDaily ? "，每天重复" : "")。打开 App 时会提前准备内容并安排通知"
    }
}

struct Recall: Tool {
    let name = "recall"
    let description = "检索知识库（导入的文档与长期记忆）"
    @Generable struct Arguments {
        @Guide(description: "要查的内容，一句话") var query: String
    }
    func call(arguments a: Arguments) async throws -> String {
        let r = KB.shared.search(a.query)
        return r.isEmpty ? "知识库里没有相关内容" : r.joined(separator: "\n---\n")
    }
}

struct Remember: Tool {
    let name = "remember"
    let description = "把一条长期事实或偏好存入知识库"
    @Generable struct Arguments {
        @Guide(description: "要记住的事实") var text: String
    }
    func call(arguments a: Arguments) async throws -> String {
        KB.shared.add("记忆", a.text)
        return "已记住"
    }
}

struct FetchURL: Tool {
    let name = "fetch_url"
    let description = "联网读取网页文字，用于查资料、总结网页"
    @Generable struct Arguments {
        @Guide(description: "完整网址，以 http 或 https 开头") var url: String
    }
    func call(arguments a: Arguments) async throws -> String {
        guard let u = URL(string: a.url), ["http", "https"].contains(u.scheme ?? "") else { return "失败：网址无效" }
        var req = URLRequest(url: u)
        req.timeoutInterval = 20
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_6 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        do {
            let (d, _) = try await URLSession.shared.data(for: req)
            var s = String(decoding: d.prefix(300_000), as: UTF8.self)
            s = s.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
            s = s.replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
            s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            return String(s.prefix(1500))
        } catch {
            return "失败：\(error.localizedDescription)"
        }
    }
}

struct ConvertFile: Tool {
    let name = "convert_file"
    let description = "把用户最近发送的文件转换成目标格式，结果会作为文件返回给用户"
    @Generable struct Arguments {
        @Guide(description: "目标格式：jpg png heic pdf txt csv json md html tsv mp4 mov m4a，或「压缩」") var target: String
    }
    func call(arguments a: Arguments) async throws -> String {
        guard let u = await MainActor.run(body: { Agent.shared.lastFile }) else { return "失败：还没有文件，请先发送或选择文件" }
        do {
            let outs = try await Convert.run(u, to: a.target)
            Out.add(outs)
            return "转换完成：" + outs.map { $0.lastPathComponent }.joined(separator: "，")
        } catch {
            return "失败：" + error.localizedDescription
        }
    }
}

struct FindFile: Tool {
    let name = "find_file"
    let description = "在用户授权的文件夹与已导入文件里按文件名查找"
    @Generable struct Arguments {
        @Guide(description: "文件名关键词") var keyword: String
    }
    func call(arguments a: Arguments) async throws -> String {
        let r = Folders.shared.find(a.keyword)
        return r.isEmpty ? "没找到。可在「知识库」页授权文件夹" : r.map { $0.lastPathComponent }.joined(separator: "\n")
    }
}

struct ReadFile: Tool {
    let name = "read_file"
    let description = "读取授权文件夹或已导入文件里某个文件的文字内容"
    @Generable struct Arguments {
        @Guide(description: "文件名（可只写关键词）") var name: String
    }
    func call(arguments a: Arguments) async throws -> String {
        guard let u = Folders.shared.find(a.name).first else { return "没找到该文件" }
        let ok = u.startAccessingSecurityScopedResource()
        defer { if ok { u.stopAccessingSecurityScopedResource() } }
        let t = KB.shared.text(of: u)
        if t.isEmpty { return "该文件无法读取文字" }
        if t.count > 1500 { KB.shared.upsert(u.lastPathComponent, t); return String(t.prefix(1500)) + "\n…（内容较长，已存入知识库，可用 recall 检索）" }
        return t
    }
}

struct SaveSkill: Tool {
    let name = "save_skill"
    let description = "保存可复用的 JS 脚本技能。code 为 function(input){...} 形式并返回字符串；可调用 kbSearch(q)、fetchText(url)"
    @Generable struct Arguments {
        @Guide(description: "技能名") var name: String
        @Guide(description: "一句话用途") var desc: String
        @Guide(description: "JS 函数源码") var code: String
    }
    func call(arguments a: Arguments) async throws -> String {
        Skills.save(a.name, a.desc, a.code)
        return "已保存技能「\(a.name)」"
    }
}

struct RunSkill: Tool {
    let name = "run_skill"
    let description = "运行已保存的脚本技能"
    @Generable struct Arguments {
        @Guide(description: "技能名") var name: String
        @Guide(description: "输入文本") var input: String
    }
    func call(arguments a: Arguments) async throws -> String {
        Skills.run(a.name, a.input)
    }
}
