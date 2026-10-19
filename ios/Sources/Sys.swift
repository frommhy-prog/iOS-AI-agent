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

    // 今天 / 明天 / 后天 / M月d日 周X + 时间
    static func friendly(_ d: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 99
        let t = DateFormatter()
        t.dateFormat = "HH:mm"
        let time = t.string(from: d)
        switch days {
        case 0: return "今天 \(time)"
        case 1: return "明天 \(time)"
        case 2: return "后天 \(time)"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月d日 EEE"
            return "\(f.string(from: d)) \(time)"
        }
    }

    static func repText(_ rep: Int) -> String { rep == 1 ? "每天" : rep == 7 ? "每周" : "" }

    static func ensureNotif() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    // rep：0 一次，1 每天，7 每周
    static func notify(id: String, title: String, body: String, at d: Date, rep: Int = 0) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let cal = Calendar.current
        let comps: DateComponents
        switch rep {
        case 1: comps = cal.dateComponents([.hour, .minute], from: d)
        case 7: comps = cal.dateComponents([.weekday, .hour, .minute], from: d)
        default: comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        }
        let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: rep > 0)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: trig))
    }

    static func weekdays(_ rep: Int, _ d: Date) -> [Locale.Weekday] {
        let all: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        if rep == 1 { return all }
        let w = Calendar.current.component(.weekday, from: d)
        return [all[min(max(w - 1, 0), 6)]]
    }

    static func alarm(_ d: Date, _ label: String, rep: Int = 0) async -> String {
        guard rep > 0 || d > Date() else { return "这个时间已经过了，换一个时间试试。" }
        do {
            let mgr = AlarmManager.shared
            if mgr.authorizationState == .notDetermined { _ = try await mgr.requestAuthorization() }
            guard mgr.authorizationState == .authorized else { return "没有闹钟权限，请到 设置 → TSTZ Bot 里允许闹钟。" }
            let title = label.isEmpty ? "闹钟" : label
            let alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.fill")
            )
            let attrs = AlarmAttributes<NoMeta>(presentation: AlarmPresentation(alert: alert), tintColor: .green)
            let schedule: Alarm.Schedule
            if rep > 0 {
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                schedule = .relative(Alarm.Schedule.Relative(
                    time: Alarm.Schedule.Relative.Time(hour: c.hour ?? 8, minute: c.minute ?? 0),
                    repeats: .weekly(weekdays(rep, d))
                ))
            } else {
                schedule = .fixed(d)
            }
            let cfg = AlarmManager.AlarmConfiguration.alarm(schedule: schedule, attributes: attrs)
            let id = UUID()
            _ = try await mgr.schedule(id: id, configuration: cfg)
            DB.shared.run("INSERT OR REPLACE INTO alarm(id,label,due,rep) VALUES(?,?,?,?)", [id.uuidString, title, d.timeIntervalSince1970, rep])
            return "闹钟已设置：\(rep > 0 ? repText(rep) + " " : "")\(friendly(d))「\(title)」，到点会响铃。"
        } catch {
            return "闹钟设置失败：\(error.localizedDescription)"
        }
    }

    static func cancelAlarm(_ id: String) {
        if let u = UUID(uuidString: id) { try? AlarmManager.shared.cancel(id: u) }
        DB.shared.run("DELETE FROM alarm WHERE id=?", [id])
    }

    static func reminder(_ title: String, _ d: Date, rep: Int = 0, notes: String = "") async -> String {
        guard rep > 0 || d > Date() else { return "这个时间已经过了，换一个时间试试。" }
        var inReminders = false
        do {
            if try await store.requestFullAccessToReminders() {
                let r = EKReminder(eventStore: store)
                r.title = title
                r.notes = notes
                r.calendar = store.defaultCalendarForNewReminders()
                r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
                r.addAlarm(EKAlarm(absoluteDate: d))
                if rep > 0 {
                    r.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: rep == 1 ? .daily : .weekly, interval: 1, end: nil))
                }
                try store.save(r, commit: true)
                inReminders = true
            }
        } catch {}
        Sys.notify(id: "remind-\(UUID().uuidString)", title: "提醒", body: title, at: d, rep: rep)
        return "提醒已设置：\(rep > 0 ? repText(rep) + " " : "")\(friendly(d))「\(title)」" + (inReminders ? "，已写入系统提醒事项。" : "，将以通知提醒你。")
    }

    static func event(_ title: String, _ d: Date, minutes: Int = 60) async -> String {
        guard d > Date() else { return "这个时间已经过了，换一个时间试试。" }
        do {
            guard try await store.requestFullAccessToEvents() else { return "没有日历权限，请到 设置 → TSTZ Bot 里允许日历。" }
            let e = EKEvent(eventStore: store)
            e.title = title
            e.startDate = d
            e.endDate = d.addingTimeInterval(Double(max(minutes, 5)) * 60)
            e.calendar = store.defaultCalendarForNewEvents
            e.addAlarm(EKAlarm(relativeOffset: -600))
            try store.save(e, span: .thisEvent)
            return "日程已添加：\(friendly(d))「\(title)」，提前 10 分钟提醒。"
        } catch {
            return "日程添加失败：\(error.localizedDescription)"
        }
    }
}
