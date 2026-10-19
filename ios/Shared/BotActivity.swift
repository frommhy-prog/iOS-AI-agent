import ActivityKit
import Foundation

// 灵动岛 / 锁屏实时活动的数据，应用与扩展共用
struct BotActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var end: Date?
    }
    var kind: String
}
