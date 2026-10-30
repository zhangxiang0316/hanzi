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

    static func detailIsSplit(_ width: CGFloat) -> Bool { width > detailSplitWidth }
    static func writeIsSplit(_ width: CGFloat) -> Bool { width > writeSplitWidth }

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

    /// 侧边栏在各宽度下应不应该常驻。
    ///
    /// 窗口特别窄时 NavigationSplitView 会自动折叠侧边栏，
    /// 这里只是给页面一个「可用宽度是否紧张」的判断依据。
    static func sidebarCollapsed(_ width: CGFloat) -> Bool { width < 560 }
}
