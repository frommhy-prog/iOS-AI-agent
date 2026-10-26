import SwiftUI
import UIKit

// 统一的外观：全部使用 iOS 系统颜色，浅色、深色由系统自动切换，不再有任何自定义色值（没有色差）。
enum Brand {
    // 应用名 OSVIA，品牌语「Search · Think · Act」
    static let name = "OSVIA"
    static let tagline = "搜索 · 思考 · 行动"

    // 强调色：浅色模式为黑，深色模式为白（系统 label）；放在它上面的文字用 onAccent
    static let accent = Color(UIColor.label)
    static let onAccent = Color(UIColor.systemBackground)
    // 对话页、侧栏的底色
    static let bg = Color(UIColor.systemBackground)
    // 设置、任务等分组页面的底色，卡片用 card（与系统「设置」App 相同的层次）
    static let page = Color(UIColor.systemGroupedBackground)
    static let card = Color(UIColor.secondarySystemGroupedBackground)
    static let userBubble = Color(UIColor.tertiarySystemFill)
    static let codeBg = Color(UIColor.secondarySystemBackground)
    static let line = Color(UIColor.separator)
    static let ink = Color(UIColor.label)
    static let sub = Color(UIColor.secondaryLabel)
    static let serif = Font.system(size: 17, design: .serif)
}
