import SwiftUI
import CoreText

/// 汉字画布渲染引擎，与 Android `HanziPainter.kt` 对应。
///
/// 与 Android 的关键差别：**底字（描红参照）也用笔画轮廓画，而不是画字体**。
/// 实测「天」的笔画轮廓与 PingFang 字形只重叠 70%——前者是楷体骨架、后者是黑体，
/// 笔形和字重都不同。如果用字体画底字，孩子照着写出来的形状和判分用的中线对不上，
/// 会出现「明明照着写的却判我错」。
enum HanziDraw {

    // 与 Android 同一套配色
    static let ink = Color(red: 0.145, green: 0.2, blue: 0.176)      // #25332D
    static let ghost = Color(red: 0.812, green: 0.78, blue: 0.714)   // #CFC7B6
    static let hint = Color(red: 0.561, green: 0.769, blue: 0.722)   // #8FC4B8
    static let accent = Color(red: 0.243, green: 0.557, blue: 0.494) // #3E8E7E
    static let border = Color(red: 0.878, green: 0.835, blue: 0.753) // #E0D5C0
    static let dashLine = Color(red: 0.933, green: 0.89, blue: 0.816) // #EEE3D0

    /// 田字格：外框 + 虚线十字
    static func drawGrid(_ ctx: inout GraphicsContext, box: CGFloat, origin: CGPoint) {
        let rect = CGRect(x: origin.x + 0.5, y: origin.y + 0.5,
                          width: box - 1, height: box - 1)
        ctx.stroke(Path(rect), with: .color(border), lineWidth: 2)

        var mid = Path()
        mid.move(to: CGPoint(x: origin.x + box / 2, y: origin.y + box * 0.06))
        mid.addLine(to: CGPoint(x: origin.x + box / 2, y: origin.y + box * 0.94))
        mid.move(to: CGPoint(x: origin.x + box * 0.06, y: origin.y + box / 2))
        mid.addLine(to: CGPoint(x: origin.x + box * 0.94, y: origin.y + box / 2))
        ctx.stroke(mid, with: .color(dashLine),
                   style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
    }

    /// 中线折线（已缩放到画布坐标），扁平存放
    static func medianPoints(_ median: [Float], box: CGFloat, origin: CGPoint) -> [CGFloat] {
        var out: [CGFloat] = []
        out.reserveCapacity(median.count)
        var i = 0
        while i + 1 < median.count {
            out.append(origin.x + HanziCanvas.px(median[i], box: box))
            out.append(origin.y + HanziCanvas.px(median[i + 1], box: box))
            i += 2
        }
        return out
    }

    static func polylineLength(_ pts: [CGFloat]) -> CGFloat {
        var len: CGFloat = 0
        var i = 2
        while i < pts.count {
            let dx = pts[i] - pts[i - 2]
            let dy = pts[i + 1] - pts[i - 1]
            len += (dx * dx + dy * dy).squareRoot()
            i += 2
        }
        return len
    }

    static func tracePath(_ pts: [CGFloat]) -> Path {
        var p = Path()
        guard pts.count >= 2 else { return p }
        p.move(to: CGPoint(x: pts[0], y: pts[1]))
        var i = 2
        while i < pts.count {
            p.addLine(to: CGPoint(x: pts[i], y: pts[i + 1]))
            i += 2
        }
        return p
    }

    /// 整字用笔画轮廓填充（未写的部分不画）
    static func fillChar(
        _ ctx: inout GraphicsContext,
        _ data: StrokeCodec.CharStrokes,
        box: CGFloat,
        origin: CGPoint,
        color: Color = ink,
        upTo: Int? = nil
    ) {
        let limit = upTo ?? data.count
        for i in 0..<min(limit, data.count) {
            let path = Path(HanziCanvas.path(for: data.strokes[i], box: box, origin: origin))
            ctx.fill(path, with: .color(color))
        }
    }

    /// 只画轮廓（底字、未写的笔）
    static func outlineChar(
        _ ctx: inout GraphicsContext,
        _ data: StrokeCodec.CharStrokes,
        box: CGFloat,
        origin: CGPoint,
        color: Color,
        lineWidth: CGFloat,
        from: Int = 0
    ) {
        for i in from..<data.count {
            let path = Path(HanziCanvas.path(for: data.strokes[i], box: box, origin: origin))
            ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }

    /// 淡灰底字：用笔画轮廓画出来，而不是画字体。
    ///
    /// 这样底字和判分中线是同一套几何——孩子照着描，描的就是被判分的那一笔。
    static func drawGhostChar(
        _ ctx: inout GraphicsContext,
        _ data: StrokeCodec.CharStrokes,
        box: CGFloat,
        origin: CGPoint,
        color: Color = ghost
    ) {
        // 浅色实心填充比描边更像字帖的淡灰底字，也比描边省事
        fillChar(&ctx, data, box: box, origin: origin, color: color)
    }

    /// 画静态字：已写好的笔画实心，未写的笔画用浅色轮廓。
    ///
    /// - Parameters:
    ///   - completed: 已经写完的笔画数
    ///   - partial: 当前这一笔写到 0-1 之间的进度
    static func drawStrokes(
        _ ctx: inout GraphicsContext,
        _ data: StrokeCodec.CharStrokes,
        box: CGFloat,
        origin: CGPoint,
        completed: Int? = nil,
        partial: CGFloat = 0,
        inkColor: Color = ink,
        showGhost: Bool = true
    ) {
        let done = completed ?? data.count
        for i in 0..<data.count {
            let path = Path(HanziCanvas.path(for: data.strokes[i], box: box, origin: origin))

            if i < done {
                ctx.fill(path, with: .color(inkColor))
            } else if i == done && partial > 0 {
                // 当前笔：裁剪到笔画轮廓内，用粗线沿中线推进。
                // 这是小程序和 Android 都用过的做法——直接画中线会溢出笔画边界，
                // 看起来像一根香肠而不是正在写的笔锋。
                var layer = ctx
                layer.clip(to: path)
                let pts = medianPoints(data.medians[i], box: box, origin: origin)
                let len = polylineLength(pts)
                layer.stroke(
                    tracePath(pts),
                    with: .color(inkColor),
                    style: StrokeStyle(
                        lineWidth: max(box * 0.22, 18),
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [max(len * partial, 0.1), len + 10]
                    )
                )
            } else if showGhost {
                ctx.stroke(path, with: .color(hint.opacity(0.55)),
                           lineWidth: max(box * 0.006, 1))
            }
        }
    }

    /// 高亮某一笔
    static func drawStrokeHighlight(
        _ ctx: inout GraphicsContext,
        _ data: StrokeCodec.CharStrokes,
        index: Int,
        box: CGFloat,
        origin: CGPoint,
        color: Color = accent
    ) {
        guard index >= 0 && index < data.count else { return }
        let path = Path(HanziCanvas.path(for: data.strokes[index], box: box, origin: origin))
        ctx.fill(path, with: .color(color.opacity(0.85)))
    }

    /// 笔画序号 + 起点圆点
    static func drawStrokeNumbers(
        _ ctx: inout GraphicsContext,
        _ data: StrokeCodec.CharStrokes,
        box: CGFloat,
        origin: CGPoint,
        onlyIndex: Int = -1,
        color: Color = accent
    ) {
        for i in 0..<data.count {
            if onlyIndex >= 0 && i != onlyIndex { continue }
            let m = data.medians[i]
            guard m.count >= 2 else { continue }
            let x = origin.x + HanziCanvas.px(m[0], box: box)
            let y = origin.y + HanziCanvas.px(m[1], box: box)
            let r = max(box * 0.045, 7)

            let circle = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            ctx.fill(circle, with: .color(color))

            // 数字用字号跟随圆点，居中
            let text = Text("\(i + 1)")
                .font(.system(size: r * 1.15, weight: .bold))
                .foregroundStyle(.white)
            ctx.draw(text, at: CGPoint(x: x, y: y), anchor: .center)
        }
    }

    /// 用系统字体的字形轮廓（结果页大字、图标位）
    ///
    /// 一般场合优先用 `fillChar`（笔画轮廓），只在拿不到笔顺数据时退回这里。
    static func drawGlyphChar(
        _ ctx: inout GraphicsContext,
        ch: String,
        box: CGFloat,
        origin: CGPoint,
        color: Color = ink
    ) {
        guard let gp = GlyphOutline.path(ch, box: box, origin: origin) else { return }
        ctx.fill(Path(gp), with: .color(color))
    }
}

/// 用 CoreText 取汉字字形轮廓，等比放进格子。
///
/// 以 em 方格（0..1000）为基准缩放，而不是按墨迹包围盒拉伸——
/// 否则「一」会被纵向拉满、「鬱」会被压扁，字号看起来忽大忽小。
enum GlyphOutline {
    private static let em: CGFloat = 1000

    private static var font: CTFont {
        // 楷体优先，回退到苹方。iOS 自带 Kaiti SC。
        for name in ["KaitiSC-Regular", "STKaiti", "PingFangSC-Regular"] {
            let f = CTFontCreateWithName(name as CFString, 1000, nil)
            let actual = CTFontCopyPostScriptName(f) as String
            if actual.lowercased().contains("kaiti") || name == "PingFangSC-Regular" {
                return f
            }
        }
        return CTFontCreateWithName("PingFangSC-Regular" as CFString, 1000, nil)
    }

    static func path(_ ch: String, box: CGFloat, origin: CGPoint) -> CGPath? {
        let f = font
        var chars = Array(ch.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        guard CTFontGetGlyphsForCharacters(f, &chars, &glyphs, chars.count),
              let raw = CTFontCreatePathForGlyph(f, glyphs[0], nil)
        else { return nil }

        let scale = (box * 0.88) / em
        let bounds = raw.boundingBox
        let tx = origin.x + box / 2 - bounds.midX * scale
        let ty = origin.y + box / 2 + bounds.midY * scale

        var t = CGAffineTransform(translationX: tx, y: ty)
            .scaledBy(x: scale, y: -scale) // CoreText 的 y 轴向上，Canvas 的 y 轴向下
        return raw.copy(using: &t)
    }
}
