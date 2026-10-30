import SwiftUI
import CoreText

/// M0 探针：只做一件事——证明汉字绘制在 iPad 上能正确跑起来。
///
/// 故意不用 NavigationSplitView：M0 要验证的是「笔画轮廓能不能画对」，
/// 导航结构留到 M5 再引入，避免把布局问题和绘制问题混在一起排查。
struct M0ProbeView: View {
    @State private var ch = "天"

    private let samples = ["天", "地", "人", "永", "国", "一", "龍", "鬱"]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            canvasPane
        }
        .background(Color(red: 0.984, green: 0.965, blue: 0.925))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("M0 验证").font(.title2.bold())
            Text("笔画轮廓 · CoreText 字形")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()

            ForEach(samples, id: \.self) { c in
                Button {
                    ch = c
                } label: {
                    HStack {
                        Text(c).font(.system(size: 24, weight: .medium))
                        Spacer()
                        if let s = Repo.strokes(c) {
                            Text("\(s.count) 笔").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("无数据").font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(c == ch ? Color(red: 0.91, green: 0.95, blue: 0.93) : Color.white)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 300)
    }

    private var canvasPane: some View {
        VStack(spacing: 16) {
            Text(ch)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color(red: 0.145, green: 0.2, blue: 0.176))

            // 固定 520pt：先把「画布尺寸由 GeometryReader 决定」这个变量去掉
            HanziCanvasView(ch: ch, box: 520)
                .frame(width: 520, height: 520)

            Text("黑＝笔画轮廓填充　红＝CoreText 字形轮廓")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 用笔画数据画字
struct HanziCanvasView: View {
    let ch: String
    let box: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let origin = CGPoint(x: 0, y: 0)

            ctx.stroke(
                Path(CGRect(x: 0, y: 0, width: box, height: box)),
                with: .color(Color(red: 0.88, green: 0.83, blue: 0.75)),
                lineWidth: 1
            )
            var cross = Path()
            cross.move(to: CGPoint(x: box / 2, y: 0))
            cross.addLine(to: CGPoint(x: box / 2, y: box))
            cross.move(to: CGPoint(x: 0, y: box / 2))
            cross.addLine(to: CGPoint(x: box, y: box / 2))
            ctx.stroke(
                cross,
                with: .color(Color(red: 0.93, green: 0.89, blue: 0.81)),
                style: StrokeStyle(lineWidth: 0.8, dash: [5, 4])
            )

            if let s = Repo.strokes(ch) {
                for stroke in s.strokes {
                    let path = Path(HanziCanvas.path(for: stroke, box: box, origin: origin))
                    ctx.fill(path, with: .color(Color(red: 0.145, green: 0.2, blue: 0.176)))
                }
            }

            if let gp = GlyphOutline.path(ch, box: box, origin: origin) {
                ctx.stroke(Path(gp), with: .color(.red.opacity(0.6)), lineWidth: 1.2)
            }
        }
    }
}

/// 用 CoreText 取汉字字形轮廓，等比放进格子。
///
/// 安卓侧这里是 `drawText` 画字体；iOS 走 outline 更可控——
/// 可以拿到真实的轮廓路径，结果页大字、底字都能复用同一套几何。
enum GlyphOutline {
    private static var font: CTFont {
        // PingFang SC 是 iOS 默认中文字体；取不到就退回系统 UI 字体
        CTFontCreateWithName("PingFangSC-Regular" as CFString, 1000, nil)
    }

    static func path(_ ch: String, box: CGFloat, origin: CGPoint) -> CGPath? {
        let f = font
        var chars = Array(ch.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        guard CTFontGetGlyphsForCharacters(f, &chars, &glyphs, chars.count) else { return nil }
        guard let g0 = glyphs.first, let raw = CTFontCreatePathForGlyph(f, g0, nil) else { return nil }

        // 以 em 方格（0..1000）为基准缩放，而不是按墨迹包围盒拉伸——
        // 否则「一」会被纵向拉满，「鬱」会被压扁，字号看起来忽大忽小
        let em: CGFloat = 1000
        let scale = (box * 0.88) / em

        let bounds = raw.boundingBox
        // 水平居中；垂直方向按字形包围盒居中（CJK 字形在 em 内并非严格居中）
        let tx = origin.x + box / 2 - bounds.midX * scale
        let ty = origin.y + box / 2 + bounds.midY * scale

        var t = CGAffineTransform(translationX: tx, y: ty)
            .scaledBy(x: scale, y: -scale)  // CoreText 的 y 轴向上，Canvas 的 y 轴向下
        return raw.copy(using: &t)
    }
}

#Preview {
    M0ProbeView()
}
