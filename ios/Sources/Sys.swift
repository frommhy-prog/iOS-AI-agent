import Foundation
import AlarmKit
import EventKit
import UserNotifications
import SwiftUI

struct NoMeta: AlarmMetadata {}

enum Sys {
    static let store = EKEventStore()

    static func date(_ off: Int, _ h: Int, _ m: Int) -> Date? {
        let cal = Calendar.current
        guard let day = cal.date(byAdding: .day, value: off, to: cal.startOfDay(for: Date())) else { return nil }
        return cal.date(bySettingHour: min(max(h, 0), 23), minute: min(max(m, 0), 59), second: 0, of: day)
    }

    static func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE HH:mm"
        return f.string(from: d)
    }

    static func fmtFull(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        return f.string(from: d)
    }

    static func ensureNotif() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func notify(id: String, title: String, body: String, at d: Date, repeatDaily: Bool = false) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let comps = repeatDaily
            ? Calendar.current.dateComponents([.hour, .minute], from: d)
            : Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeatDaily)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: trig))
    }

    static func alarm(_ off: Int, _ h: Int, _ m: Int, _ label: String) async -> String {
        guard let d = date(off, h, m), d > Date() else { return "失败：时间已过或无效" }
        do {
            let mgr = AlarmManager.shared
            if mgr.authorizationState == .notDetermined { _ = try await mgr.requestAuthorization() }
            guard mgr.authorizationState == .authorized else { return "失败：未授权闹钟，请到 设置 → TSTZ Agent 允许闹钟" }
            let title = label.isEmpty ? "闹钟" : label
            let alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.fill")
            )
            let attrs = AlarmAttributes<NoMeta>(presentation: AlarmPresentation(alert: alert), tintColor: .green)
            let cfg = AlarmManager.AlarmConfiguration.alarm(schedule: .fixed(d), attributes: attrs)
            _ = try await mgr.schedule(id: UUID(), configuration: cfg)
            return "已设置闹钟：\(fmt(d))「\(title)」"
        } catch {
            return "失败：\(error.localizedDescription)"
        }
    }

    static func reminder(_ title: String, _ off: Int, _ h: Int, _ m: Int, _ notes: String) async -> String {
        guard let d = date(off, h, m) else { return "失败：时间无效" }
        do {
            guard try await store.requestFullAccessToReminders() else { return "失败：未授权提醒事项，请到 设置 → TSTZ Agent 允许" }
            let r = EKReminder(eventStore: store)
            r.title = title
            r.notes = notes
            r.calendar = store.defaultCalendarForNewReminders()
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            r.addAlarm(EKAlarm(absoluteDate: d))
            try store.save(r, commit: true)
            return "已添加提醒事项「\(title)」，\(fmt(d))"
        } catch {
            return "失败：\(error.localizedDescription)"
        }
    }

    static func event(_ title: String, _ off: Int, _ h: Int, _ m: Int, _ minutes: Int) async -> String {
        guard let d = date(off, h, m) else { return "失败：时间无效" }
        do {
            guard try await store.requestFullAccessToEvents() else { return "失败：未授权日历，请到 设置 → TSTZ Agent 允许" }
            let e = EKEvent(eventStore: store)
            e.title = title
            e.startDate = d
            e.endDate = d.addingTimeInterval(Double(max(minutes, 5)) * 60)
            e.calendar = store.defaultCalendarForNewEvents
            e.addAlarm(EKAlarm(relativeOffset: -600))
            try store.save(e, span: .thisEvent)
            return "已添加日历日程「\(title)」，\(fmt(d))"
        } catch {
            return "失败：\(error.localizedDescription)"
        }
    }
}
