import Foundation

/// 字帖导出 PDF 的版式计算。
///
/// 屏幕上「我的字帖」是一堆小方块，只能看；打印出来才是真的字帖——
/// 孩子拿铅笔在上面描，比对着屏幕用手指划有用得多。
///
/// ## 版式
///
/// 每个字一行，四格：`[范字（浓墨）][浅灰][浅灰][浅灰]`
///
/// 第一格是照着写的范字，后三格是描红格。为什么不是四格全浅：
/// 孩子在第三格就写走形了，第五格会更差，留一个对比基准很有用。
///
/// ## 一页六个字
///
/// A4 高 842pt，去掉页边距和页眉页脚剩 706pt，每行 110pt（格子 96 + 行距 14），
/// 正好 6 行。格子再小握笔的幼儿就写不开了；再大就一页五行，纸太浪费。
///
/// ## 汉字的画法
///
/// iOS 有 CoreGraphics 和 CoreText，理论上可以直接排版中文再导出 PDF。
/// 但那样输出的是**系统字体**的宋体/黑体，和我们界面上描红的范字
/// （由笔画轮廓画的）不是同一个字形——孩子照着系统字体写，笔画走向
/// 和 App 里教的不一致。
///
/// 所以这里和小程序、Android 一样：用笔顺数据画矢量路径。
/// 三端输出同一个字形，打印出来也一样。
///
/// 这个文件只放**版式计算**，不碰 CoreGraphics —— 它在 HanziCore 包里，
/// 而那个包不能依赖 UIKit/CoreGraphics（否则 swift test 跑不起来）。
/// 真正画 PDF 的部分在 App 层的 `CopybookPDFRender.swift`。
///
/// 与小程序 `utils/copybook-pdf.js`、Android `logic/CopybookPDF.kt` 版式一致。
enum CopybookLayout {

    static let pageW: CGFloat = 595.28
    static let pageH: CGFloat = 841.89
    static let margin: CGFloat = 42
    static let headerH: CGFloat = 30
    static let footerH: CGFloat = 22
    static let cell: CGFloat = 96
    static let colGap: CGFloat = 10
    static let rowGap: CGFloat = 14
    static let cols = 4
    static let rowsPerPage = 6

    /// 田字格外框
    static let colorGuide = (r: CGFloat(0.79), g: CGFloat(0.74), b: CGFloat(0.65))
    /// 田字格虚线
    static let colorGrid = (r: CGFloat(0.87), g: CGFloat(0.83), b: CGFloat(0.75))
    /// 范字
    static let colorInk = (r: CGFloat(0.145), g: CGFloat(0.2), b: CGFloat(0.176))
    /// 描红格里的字。
    ///
    /// 必须比格线明显深一点。第一版用的 #CFC7B6 和格线 #C9BDA6 只差 5 个色阶，
    /// 打印出来孩子分不清哪条是格线、哪条是该描的字。
    static let colorGhost = (r: CGFloat(0.70), g: CGFloat(0.67), b: CGFloat(0.59))
    static let colorFooter = (r: CGFloat(0.54), g: CGFloat(0.5), b: CGFloat(0.45))

    struct Cell {
        let x: CGFloat
        /// PDF 坐标（y 向上）里格子的**下边**
        let y: CGFloat
        let size: CGFloat
        /// true = 范字，false = 描红格
        let solid: Bool
    }

    struct Row {
        let ch: String
        let cells: [Cell]
    }

    struct Page {
        let rows: [Row]
    }

    /// 一行四个格子的总宽
    static var rowWidth: CGFloat { CGFloat(cols) * cell + CGFloat(cols - 1) * colGap }

    /// 排页。纯函数，不碰 CoreGraphics —— 版式对不对可以直接断言。
    static func layout(_ chars: [String]) -> [Page] {
        var pages: [Page] = []
        var i = 0
        while i < chars.count {
            let chunk = Array(chars[i..<min(i + rowsPerPage, chars.count)])
            // 横向居中：格子总宽通常小于可用宽度，靠左会显得偏
            let usableW = pageW - 2 * margin
            let x0 = margin + max(0, (usableW - rowWidth) / 2)
            let rows = chunk.enumerated().map { r, ch -> Row in
                let top = pageH - margin - headerH - CGFloat(r) * (cell + rowGap)
                let cells = (0..<cols).map { c in
                    Cell(
                        x: x0 + CGFloat(c) * (cell + colGap),
                        y: top - cell,
                        size: cell,
                        // 第一格是范字，其余是描红格
                        solid: c == 0
                    )
                }
                return Row(ch: ch, cells: cells)
            }
            pages.append(Page(rows: rows))
            i += rowsPerPage
        }
        return pages
    }

    /// 建议的文件名，分享时用
    static func fileName(_ base: String = "字帖", date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return "\(base)-\(f.string(from: date)).pdf"
    }

    /// 页眉上的日期，用 ASCII 数字
    static func dateLabel(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
