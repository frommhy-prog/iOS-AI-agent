import AppIntents
import Foundation

// 这些动作会自动出现在系统「快捷指令」App 里，可配合「自动化」定时触发，也可被其他应用调用
struct AddToKB: AppIntent {
    static let title: LocalizedStringResource = "加入知识库"
    @Parameter(title: "名称") var name: String
    @Parameter(title: "内容") var text: String
    func perform() async throws -> some IntentResult {
        KB.shared.upsert(name, text)
        return .result()
    }
}

struct SearchKB: AppIntent {
    static let title: LocalizedStringResource = "检索知识库"
    @Parameter(title: "查询") var query: String
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        .result(value: KB.shared.search(query, k: 3))
    }
}

struct AskAgent: AppIntent {
    static let title: LocalizedStringResource = "询问助理"
    static let openAppWhenRun = true
    @Parameter(title: "问题") var question: String
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: await Agent.shared.quick(question))
    }
}

struct RunSkillIntent: AppIntent {
    static let title: LocalizedStringResource = "运行脚本技能"
    @Parameter(title: "技能名") var name: String
    @Parameter(title: "输入") var input: String
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: Skills.run(name, input).1)
    }
}

struct QuickReminder: AppIntent {
    static let title: LocalizedStringResource = "N 分钟后提醒"
    @Parameter(title: "分钟") var minutes: Int
    @Parameter(title: "内容") var text: String
    func perform() async throws -> some IntentResult {
        Sys.notify(id: UUID().uuidString, title: "提醒", body: text, at: Date().addingTimeInterval(Double(max(minutes, 1)) * 60))
        return .result()
    }
}

struct AgentShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskAgent(), phrases: ["Ask \(.applicationName)"], shortTitle: "询问助理", systemImageName: "sparkles")
        AppShortcut(intent: SearchKB(), phrases: ["Search \(.applicationName)"], shortTitle: "检索知识库", systemImageName: "magnifyingglass")
    }
}
