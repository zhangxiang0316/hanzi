import CoreGraphics
import CoreText
import Foundation

/// 字帖 PDF 渲染，基于 CoreGraphics。
///
/// 版式计算在 `HanziCore.CopybookLayout`（可单测），这里只负责画。
/// 拆开的原因：HanziCore 包不能依赖 CoreGraphics，否则 `swift test` 起不来。
///
/// ## 为什么不用 CoreText 排中文
///
/// iOS 有 CoreText，理论上可以直接把汉字当文字排版再导出 PDF。但那样输出的
/// 是**系统字体**的字形，和我们界面上描红的范字（由笔画轮廓画的）不是同一个
/// 字形——孩子照着系统字体写，笔画走向和 App 里教的不一致。
///
/// 所以和小程序、Android 一样：用笔顺数据画矢量路径。三端同一个字形。
///
/// 与小程序 `utils/copybook-pdf.js`、Android `logic/CopybookPDF.kt` 对应。
@MainActor
enum CopybookPDF {

    typealias Cell = CopybookLayout.Cell
    typealias Row = CopybookLayout.Row

    struct Result {
        let data: Data
        let pages: Int
        let drawn: [String]
        let skipped: [String]
    }

    /// 画一个田字格：外框实线 + 十字虚线
    private static func drawGrid(_ ctx: CGContext, _ c: Cell) {
        let guide = CopybookLayout.colorGuide
        ctx.setStrokeColor(red: guide.r, green: guide.g, blue: guide.b, alpha: 1)
        ctx.setLineWidth(0.6)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.stroke(CGRect(x: c.x, y: c.y, width: c.size, height: c.size))

        // 十字虚线，留 2pt 内缩，别和外框粘在一起
        let grid = CopybookLayout.colorGrid
        ctx.setStrokeColor(red: grid.r, green: grid.g, blue: grid.b, alpha: 1)
        ctx.setLineWidth(0.45)
        ctx.setLineDash(phase: 0, lengths: [3, 2.5])
        let midX = c.x + c.size / 2
        let midY = c.y + c.size / 2
        ctx.beginPath()
        ctx.move(to: CGPoint(x: midX, y: c.y + 2))
        ctx.addLine(to: CGPoint(x: midX, y: c.y + c.size - 2))
        ctx.move(to: CGPoint(x: c.x + 2, y: midY))
        ctx.addLine(to: CGPoint(x: c.x + c.size - 2, y: midY))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
    }

    /// 把字的笔画轮廓加进当前路径。调用方负责 setFillColor + fillPath。
    ///
    /// 坐标要翻转：笔画数据是 y 向下（0-1024），PDF 是 y 向上。
    private static func addGlyph(_ ctx: CGContext, _ strokes: [[StrokeCodec.Cmd]], _ c: Cell,
                                 padRatio: CGFloat = 0.05) {
        let pad = c.size * padRatio
        let inner = c.size - 2 * pad
        func toX(_ v: Float) -> CGFloat { c.x + pad + (CGFloat(v) / 1024) * inner }
        func toY(_ v: Float) -> CGFloat { c.y + pad + (1 - CGFloat(v) / 1024) * inner }

        for cmds in strokes {
            ctx.beginPath()
            for cmd in cmds {
                let p = cmd.coords
                switch cmd.op {
                case StrokeCodec.opM:
                    ctx.move(to: CGPoint(x: toX(p[0]), y: toY(p[1])))
                case StrokeCodec.opL:
                    ctx.addLine(to: CGPoint(x: toX(p[0]), y: toY(p[1])))
                case StrokeCodec.opQ:
                    ctx.addQuadCurve(to: CGPoint(x: toX(p[2]), y: toY(p[3])),
                                     control: CGPoint(x: toX(p[0]), y: toY(p[1])))
                case StrokeCodec.opC:
                    ctx.addCurve(to: CGPoint(x: toX(p[4]), y: toY(p[5])),
                                 control1: CGPoint(x: toX(p[0]), y: toY(p[1])),
                                 control2: CGPoint(x: toX(p[2]), y: toY(p[3])))
                case StrokeCodec.opZ:
                    ctx.closePath()
                default:
                    break
                }
            }
            // 每一笔单独填充：笔画之间有重叠，合成一条路径用 evenodd 会挖洞
            ctx.fillPath()
        }
    }

    /// 小号页眉文字。只用 ASCII（日期和页码），所以不需要中文字体。
    private static func drawSmallText(_ ctx: CGContext, _ s: String, x: CGFloat, y: CGFloat) {
        let col = CopybookLayout.colorFooter
        let attrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica" as CFString, 8.5, nil),
            .foregroundColor: CGColor(red: col.r, green: col.g, blue: col.b, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: s, attributes: attrs)
        )
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }

    /// 生成 PDF。
    ///
    /// - Parameter strokeFor: 取笔画数据，拿不到返回 nil（会被跳过并报回来）。
    ///   没有默认值：`Repo.shared` 是 MainActor 的，而默认参数在非隔离
    ///   上下文求值，写成默认参数会编译不过。
    static func build(_ chars: [String],
                      strokeFor: (String) -> StrokeCodec.CharStrokes?,
                      dateLabel: String = "") -> Result {
        let pages = CopybookLayout.layout(chars)
        let data = NSMutableData()
        // A4 用 72dpi 的 point：595 x 842
        var mediaBox = CGRect(x: 0, y: 0, width: CopybookLayout.pageW,
                              height: CopybookLayout.pageH)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Result(data: Data(), pages: 0, drawn: [], skipped: [])
        }

        var drawn: [String] = []
        var skipped: [String] = []

        for (idx, page) in pages.enumerated() {
            ctx.beginPDFPage(nil)

            // 页眉：只有日期和页码
            drawSmallText(ctx,
                          "\(dateLabel)        \(idx + 1) / \(pages.count)",
                          x: CopybookLayout.pageW - CopybookLayout.margin - 96,
                          y: CopybookLayout.pageH - CopybookLayout.margin - 14)

            for row in page.rows {
                let glyph = strokeFor(row.ch)
                for c in row.cells {
                    drawGrid(ctx, c)
                    if let g = glyph {
                        // 田字格画完再填字，否则虚线会压在字上面
                        let col = c.solid ? CopybookLayout.colorInk : CopybookLayout.colorGhost
                        ctx.setFillColor(red: col.r, green: col.g, blue: col.b, alpha: 1)
                        addGlyph(ctx, g.strokes, c)
                    }
                }
                if glyph != nil { drawn.append(row.ch) }
                else if !skipped.contains(row.ch) { skipped.append(row.ch) }
            }

            // 页脚：一行极细的分隔线，视觉上收住版面
            let grid = CopybookLayout.colorGrid
            ctx.setStrokeColor(red: grid.r, green: grid.g, blue: grid.b, alpha: 1)
            ctx.setLineWidth(0.4)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: CopybookLayout.margin,
                                 y: CopybookLayout.margin + CopybookLayout.footerH - 8))
            ctx.addLine(to: CGPoint(x: CopybookLayout.pageW - CopybookLayout.margin,
                                    y: CopybookLayout.margin + CopybookLayout.footerH - 8))
            ctx.strokePath()

            ctx.endPDFPage()
        }
        ctx.closePDF()

        return Result(data: data as Data, pages: pages.count, drawn: drawn, skipped: skipped)
    }

    /// 建议的文件名，分享时用
    static func fileName(_ base: String = "字帖", date: Date = Date()) -> String {
        CopybookLayout.fileName(base, date: date)
    }

    /// 页眉上的日期，用 ASCII 数字
    static func dateLabel(_ date: Date = Date()) -> String {
        CopybookLayout.dateLabel(date)
    }
}
