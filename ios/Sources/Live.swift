import ActivityKit
import Foundation

// 灵动岛 / 锁屏实时活动：思考中、闹钟与任务倒计时
enum Live {
    private static var enabled: Bool {
        (UserDefaults.standard.object(forKey: "liveOn") as? Bool ?? true) && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private static func start(kind: String, title: String, subtitle: String, end: Date?) {
        guard enabled else { return }
        Task {
            for a in Activity<BotActivityAttributes>.activities where a.attributes.kind == kind {
                await a.end(nil, dismissalPolicy: .immediate)
            }
            let st = BotActivityAttributes.ContentState(title: title, subtitle: subtitle, end: end)
            let content = ActivityContent(state: st, staleDate: (end ?? Date()).addingTimeInterval(end == nil ? 180 : 120))
            _ = try? Activity.request(attributes: BotActivityAttributes(kind: kind), content: content, pushType: nil)
        }
    }

    private static func stop(kind: String) {
        Task {
            for a in Activity<BotActivityAttributes>.activities where a.attributes.kind == kind {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    static func thinking(_ on: Bool) {
        if on { start(kind: "think", title: "TSTZ Bot", subtitle: "正在思考…", end: nil) } else { stop(kind: "think") }
    }

    static func timer(title: String, subtitle: String, end: Date) {
        start(kind: "timer", title: title, subtitle: subtitle, end: end)
    }
}
