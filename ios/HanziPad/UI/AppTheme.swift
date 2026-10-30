import SwiftUI

/// 设计 token，与 Android `ui/Theme.kt`、小程序 `app.wxss` 的 CSS 变量一一对应。
///
/// 三端共用同一套色值和圆角，页面里只引用语义名，不出现字面色值——
/// 这样以后调色只改一处。
enum Palette {
    static let paper = Color(hex: 0xFBF6EC)
    static let card = Color.white
    static let cardWarm = Color(hex: 0xFDF9F0)

    static let ink1 = Color(hex: 0x25332D)
    static let ink2 = Color(hex: 0x5C6B62)
    static let ink3 = Color(hex: 0x8C9A90)

    static let jade = Color(hex: 0x3E8E7E)
    static let jadeDeep = Color(hex: 0x2F7062)
    static let jadeSoft = Color(hex: 0xE8F2EE)

    static let amber = Color(hex: 0xE9A93C)
    static let amberSoft = Color(hex: 0xFDF1DC)
    static let clay = Color(hex: 0xDF6248)
    static let claySoft = Color(hex: 0xFBE8E3)

    static let line = Color(hex: 0xE9DFCD)

    /// 可点击元素的边框。
    ///
    /// `line`（#E9DFCD）与纸色背景的对比度只有 1.23:1，做分隔线没问题，
    /// 但用来画按钮边框时孩子几乎看不见边界——实测答题页的四个选项
    /// 在截图里只剩下一团模糊的浅色。这个色对比度 2.23:1，配合白底
    /// 和轻阴影，可点击的边界就清楚了。
    static let edge = Color(hex: 0xB8A583)
    static let lineSoft = Color(hex: 0xFAF5EB)
    static let track = Color(hex: 0xF4EFE4)

    /// 册次颜色，与小程序 `pages/index/index.js` 的 BOOK_COLORS 一致
    static func bookColor(_ id: String) -> Color {
        switch id {
        case "1a": return Color(hex: 0xE9A93C)
        case "1b": return Color(hex: 0xDF8A4A)
        case "2a": return Color(hex: 0x4F9E8D)
        case "2b": return Color(hex: 0x5A8FBF)
        case "3a": return Color(hex: 0x9B7FB8)
        case "3b": return Color(hex: 0xB8763F)
        case "4a": return Color(hex: 0x6F8FB8)
        case "4b": return Color(hex: 0x3F7D6A)
        default: return jade
        }
    }
}

/// 圆角与间距 token。
///
/// Android 只有一套固定 dp 值，完全没有自适应逻辑；iOS 这边因为要适配
/// iPad 从 mini 到 13 寸，字号和留白需要随尺寸走，所以做成按宽度分档。
enum Dimens {
    static let radiusCard: CGFloat = 20
    static let radiusInner: CGFloat = 14
    static let radiusPill: CGFloat = 999

    /// 页面左右留白与内容宽度都走 LayoutRules，方便单独测试
    static func pagePad(_ width: CGFloat) -> CGFloat { LayoutRules.pagePad(width) }
    static func contentMax(_ width: CGFloat) -> CGFloat { LayoutRules.contentMax(width) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// 全局字号。iPad 上比 iPhone 该大一些，但要跟 iPadOS 的动态字体共存。
enum Fonts {
    static let pageTitle = Font.system(size: 26, weight: .bold)
    static let sectionTitle = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 15)
    static let bodySmall = Font.system(size: 13)
    static let caption = Font.system(size: 12)
    static let bigChar = Font.system(size: 44, weight: .semibold)
}
