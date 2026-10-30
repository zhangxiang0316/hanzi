import Foundation
import CoreGraphics

/// 汉字画布渲染参数，与 Android `HanziPainter` 对齐。
///
/// 坐标系统：Make Me a Hanzi 的 1024×1024 方格，构建时 y 已翻转成屏幕坐标。
/// 画布上把 0..1024 线性映射到这个方格，四周留 PAD 边距。
enum HanziCanvas {
    static let size: Float = 1024
    /// 字形在格子里留一点边距，避免笔画贴死边框
    static let padRatio: Float = 0.035

    /// 每一笔的书写时长（毫秒），与小程序 / Android 保持一致
    static let perStrokeMs: Double = 620
    /// 笔与笔之间的停顿，留出「看清这一笔」的时间
    static let strokeGapMs: Double = 140

    static func pad(of box: CGFloat) -> CGFloat { box * CGFloat(padRatio) }

    /// 把 0..1024 的字形坐标映射到画布坐标
    static func px(_ v: Float, box: CGFloat) -> CGFloat {
        let pad = pad(of: box)
        return pad + CGFloat(v / size) * (box - 2 * pad)
    }

    /// 构造某一笔的轮廓路径（用于填充实心笔画）
    static func path(for cmds: [StrokeCodec.Cmd], box: CGFloat, origin: CGPoint) -> CGPath {
        let p = CGMutablePath()
        for c in cmds {
            let x = c.coords.count > 0 ? origin.x + px(c.coords[0], box: box) : 0
            let y = c.coords.count > 1 ? origin.y + px(c.coords[1], box: box) : 0
            switch c.op {
            case StrokeCodec.opM:
                p.move(to: CGPoint(x: x, y: y))
            case StrokeCodec.opL:
                p.addLine(to: CGPoint(x: x, y: y))
            case StrokeCodec.opQ:
                p.addQuadCurve(
                    to: CGPoint(x: origin.x + px(c.coords[2], box: box),
                                y: origin.y + px(c.coords[3], box: box)),
                    control: CGPoint(x: x, y: y)
                )
            case StrokeCodec.opC:
                p.addCurve(
                    to: CGPoint(x: origin.x + px(c.coords[4], box: box),
                                y: origin.y + px(c.coords[5], box: box)),
                    control1: CGPoint(x: x, y: y),
                    control2: CGPoint(x: origin.x + px(c.coords[2], box: box),
                                      y: origin.y + px(c.coords[3], box: box))
                )
            case StrokeCodec.opZ:
                p.closeSubpath()
            default:
                break
            }
        }
        return p
    }
}
