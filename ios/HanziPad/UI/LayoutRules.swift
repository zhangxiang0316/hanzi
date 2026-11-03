import Foundation
import CoreGraphics

/// 自适应布局的判定规则。
///
/// 抽成纯函数是有原因的：这些阈值决定页面在什么宽度下换布局，
/// 而 iPadOS 26 起应用是窗口化的，用户可以拖到任意宽度——
/// 靠截图验证「某个宽度下长什么样」成本极高且不可靠。
/// 把规则本身做成可测的，就能穷举边界值。
enum LayoutRules {

    /// 详情页从单列切成左右分栏的宽度阈值
    static let detailSplitWidth: CGFloat = 720

    /// 描红页从单列切成「画布 + 侧栏」的阈值（画布本身要够大，所以更高）
    static let writeSplitWidth: CGFloat = 820

    /// 首页课本网格的最小卡片宽
    static let bookTileMin: CGFloat = 190
    /// 生字网格的最小卡片宽
    static let charTileMin: CGFloat = 108

    /// 分栏阈值也要随字号放大。
    ///
    /// 720 是「文字在 15pt 下排得下」的宽度；字号到 3 倍时，同一个侧栏
    /// 需要两倍多的宽度才不至于每行只剩三四个字。不跟着调的话，
    /// 大字号用户看到的是一列被挤成窄条的竖排文字。
    ///
    /// 封顶 1.8 倍：再大就该直接放弃分栏、回到单列（单列永远能读）。
    static func detailSplitWidth(scaledBy scale: CGFloat) -> CGFloat {
        detailSplitWidth * min(max(scale, 1), 1.8)
    }
    static func writeSplitWidth(scaledBy scale: CGFloat) -> CGFloat {
        writeSplitWidth * min(max(scale, 1), 1.8)
    }

    static func detailIsSplit(_ width: CGFloat, scale: CGFloat = 1) -> Bool {
        width > detailSplitWidth(scaledBy: scale)
    }
    static func writeIsSplit(_ width: CGFloat, scale: CGFloat = 1) -> Bool {
        width > writeSplitWidth(scaledBy: scale)
    }

    /// 自适应网格在某宽度下能放几列
    static func columns(width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        guard width > 0, minimum > 0 else { return 1 }
        // SwiftUI 的 .adaptive 按 floor((w + spacing) / (min + spacing)) 排布
        let n = Int(((width + spacing) / (minimum + spacing)).rounded(.down))
        return max(1, n)
    }

    /// 页面两侧留白
    static func pagePad(_ width: CGFloat) -> CGFloat {
        if width < 500 { return 20 }
        if width < 800 { return 28 }
        return 36
    }

    /// 正文最大宽度（超过就居中，避免一行太长难读）
    static func contentMax(_ width: CGFloat) -> CGFloat {
        width < 700 ? width : 760
    }

    /// 首页课本网格的列数：固定两列，与 Android 的 `chunked(2)`、
    /// 小程序的 `calc(50% - 12rpx)` 保持一致。
    ///
    /// 之前用的是 `.adaptive(minimum: 190)`，结果三端各不相同：
    /// iPhone 上算下来只排 1 列（内容宽 362pt，放不下两个 190），
    /// iPad 上排 3 列。同一个 app 在两种设备上是两种信息密度。
    ///
    /// 辅助功能字号下退回单列：两列时卡片只有 175pt 宽，
    /// 3 倍大的字塞不进去，硬排两列等于把字挤没。
    static func bookColumns(scale: CGFloat) -> Int {
        scale >= TypeScale.factor(forStep: 4) ? 1 : 2
    }

    /// 大字号下容器要跟着一起长，否则文字撑破格子。
    ///
    /// 只放大、不缩小（缩小时留白不变更稳），并且封顶——辅助字号下
    /// 卡片宽度会长到 2 倍出头，再多就没有意义了，反而一屏放不下一个字。
    static func scaled(_ base: CGFloat, by scale: CGFloat, cap: CGFloat = 2.2) -> CGFloat {
        base * min(max(scale, 1), max(cap, 1))
    }

    /// 侧边栏在各宽度下应不应该常驻。
    ///
    /// 窗口特别窄时 NavigationSplitView 会自动折叠侧边栏，
    /// 这里只是给页面一个「可用宽度是否紧张」的判断依据。
    static func sidebarCollapsed(_ width: CGFloat) -> Bool { width < 560 }
}

/// Dynamic Type 档位 → 布局放大倍数。
///
/// 为什么不直接用 `DynamicTypeSize`：`LayoutRules` 在 `HanziCore` 测试包里，
/// 那个包刻意不依赖 SwiftUI/UIKit，好在 macOS 上直接跑测试。所以这里只认
/// 一个整数档位（-3…5，对应 xSmall…accessibility5），由界面层做映射。
///
/// 倍数取自 Apple 正文（`.body`）在各档位的实际放大比例：默认档 1.0，
/// 辅助功能最大档约 3.1 倍。布局用同一套数，文字和容器才一起长。
enum TypeScale {
    /// xSmall 起算，共 12 档（standard 7 + accessibility 5）
    static func factor(forStep step: Int) -> CGFloat {
        switch step {
        case ...(-3): return 0.82
        case -2: return 0.88
        case -1: return 0.94
        case 0: return 1.0
        case 1: return 1.12
        case 2: return 1.23
        case 3: return 1.35
        case 4: return 1.64
        case 5: return 1.95
        case 6: return 2.35
        case 7: return 2.76
        default: return 3.12
        }
    }

    /// 是否属于辅助功能大字号（此时该把多列布局降成单列）
    static func isAccessibility(_ step: Int) -> Bool { step >= 4 }
}
