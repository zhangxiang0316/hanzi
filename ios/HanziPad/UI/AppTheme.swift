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

    /// 第五种强调色，用于「多音字」这类新入口。
    /// 刻意与 jade/clay/amber 拉开色相，避免和第 1~4 张卡片撞色。
    static let sky = Color(hex: 0x5B8DB8)
    static let skySoft = Color(hex: 0xE8F0F7)

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

/// 字号描述：只记「设计稿上的基准字号」，真正渲染时按 Dynamic Type 缩放。
///
/// 为什么不直接用 `Font.system(size:)`：那个 API 返回的是**绝对字号**，
/// 系统设置里把字体调到「特大」甚至辅助功能大字号，它一个像素都不会动。
/// 带孩子的家长里有一批是老人，这个 app 又满屏是小号字（12pt 的注释、
/// 13pt 说明），对他们来说等于不可用。
///
/// 所以字号拆成两层：`FontSpec` 描述设计意图，`ScaledFontModifier`
/// 用 `@ScaledMetric` 换算成当前系统字号下的实际值。基准值仍是设计稿的
/// 那套数，默认字号下像素级不变，放大时才跟着系统走。
struct FontSpec: Equatable {
    /// 设计稿上的基准字号
    let size: CGFloat
    let weight: Font.Weight
    /// 按哪个语义字号缩放。同一套视觉层级里，小字用 `.footnote`、
    /// 正文用 `.body`，缩放曲线才和系统一致（小字放大得更快）。
    let style: Font.TextStyle
    /// 上限。装饰用 1.4，内容大字用 2.2（跟容器同步），
    /// 正文（小于 28pt）一律不设——限制正文放大就是在拒绝需要它的人。
    let maxScale: CGFloat?
    /// 数字等宽：读秒、百分比、笔画数这类会跳动的数字不加这个会在
    /// 变化时左右抖动。
    var monospacedDigits: Bool = false

    init(_ size: CGFloat, _ weight: Font.Weight = .regular,
         _ style: Font.TextStyle = .body, maxScale: CGFloat? = nil) {
        self.size = size
        self.weight = weight
        self.style = style
        self.maxScale = maxScale
    }
}

/// 全局字号。
///
/// iPad 上比 iPhone 该大一些，同时跟 iPadOS 的动态字体共存。
/// 页面里只引用语义名；需要一次性字号的地方用 `Fonts.s(...)`，
/// **不要再出现 `.font(.system(size:))`**——那是绝对字号，不跟随系统设置。
enum Fonts {
    static let pageTitle = FontSpec(26, .bold, .largeTitle)
    static let sectionTitle = FontSpec(17, .semibold, .headline)
    static let body = FontSpec(15, .regular, .body)
    static let bodySmall = FontSpec(13, .regular, .footnote)
    static let caption = FontSpec(12, .regular, .caption)

    /// 描红页/详情页那个大字。
    ///
    /// 封顶 2.2 而不是 1.6：这是**内容**不是装饰，用大字号的用户就是要看清它。
    /// 上限只跟容器保持一致（LayoutRules.scaled 的默认封顶也是 2.2），
    /// 再往上字会撑破卡片，但不会拒绝放大。
    static let bigChar = FontSpec(44, .semibold, .largeTitle, maxScale: 2.2)

    /// 一次性字号。等价于 `Font.system(size:weight:)` 的语义化写法。
    static func s(_ size: CGFloat, _ weight: Font.Weight = .regular,
                  _ style: Font.TextStyle = .body, maxScale: CGFloat? = nil) -> FontSpec {
        FontSpec(size, weight, style, maxScale: maxScale)
    }

    /// 纯装饰用的 emoji / 贴纸。封顶 1.4 倍，避免把卡片撑变形。
    static func decoration(_ size: CGFloat) -> FontSpec {
        FontSpec(size, .regular, .body, maxScale: 1.4)
    }
}

extension FontSpec {
    /// 数字等宽，供 `FontSpec` 链式调用（对应 `Font.monospacedDigit()`）
    func monospacedDigit() -> FontSpec {
        var copy = self
        copy.monospacedDigits = true
        return copy
    }
}

// MARK: - Dynamic Type 档位

extension DynamicTypeSize {
    /// 映射到 `TypeScale` 的整数档位（-3…8）
    var step: Int {
        switch self {
        case .xSmall: return -3
        case .small: return -2
        case .medium: return -1
        case .large: return 0
        case .xLarge: return 1
        case .xxLarge: return 2
        case .xxxLarge: return 3
        case .accessibility1: return 4
        case .accessibility2: return 5
        case .accessibility3: return 6
        case .accessibility4: return 7
        case .accessibility5: return 8
        @unknown default: return 0
        }
    }

    /// 布局放大倍数：网格最小宽、图标容器等按这个走
    var layoutScale: CGFloat { TypeScale.factor(forStep: step) }

    /// 辅助功能字号下把多列降成单列
    var isAccessibility: Bool { TypeScale.isAccessibility(step) }
}

// MARK: - 让 .font() 接受 FontSpec

/// 把 `FontSpec` 换算成当前 Dynamic Type 下的实际字号。
///
/// 核心是 `@ScaledMetric`：它读环境里的字号档位，字号变了 SwiftUI 会
/// 重新求值 body，于是整个界面自动跟着走。手写 `UIFontMetrics` 也能算，
/// 但那样不会在设置变化时重新渲染——必须靠属性包装器。
private struct ScaledFontModifier: ViewModifier {
    let spec: FontSpec
    @ScaledMetric private var scaledSize: CGFloat

    init(spec: FontSpec) {
        self.spec = spec
        _scaledSize = ScaledMetric(wrappedValue: spec.size, relativeTo: spec.style)
    }

    func body(content: Content) -> some View {
        let base = Font.system(size: font.size, weight: spec.weight)
        content.font(spec.monospacedDigits ? base.monospacedDigit() : base)
    }

    /// 放大倍数 = 缩放后 / 基准。`maxScale` 只对装饰生效。
    private var font: (size: CGFloat, scale: CGFloat) {
        guard spec.size > 0 else { return (spec.size, 1) }
        let raw = scaledSize / spec.size
        guard let cap = spec.maxScale, raw > cap else { return (scaledSize, raw) }
        return (spec.size * cap, cap)
    }
}

extension View {
    /// `.font(Fonts.body)` —— 跟随 Dynamic Type 的字号。
    ///
    /// 重载而不是改名，是为了让已有的 66 处 `.font(Fonts.xxx)` 不用动。
    func font(_ spec: FontSpec) -> some View {
        modifier(ScaledFontModifier(spec: spec))
    }
}
