// 离线渲染探针：不经过模拟器和 SwiftUI 布局，直接把汉字渲染成 PNG。
//
// 目的是回答 M0 唯一真正的问题——「strokes.json 的轮廓数据 + CoreText 字形，
// 画出来到底对不对」。把布局、导航、状态管理全部排除在外。
//
// 用法：swift render-probe.swift 天 512 out.png

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// MARK: - 复制自 HanziPad/Data/StrokeCodec.swift（保持逐字节一致）

let SCALE: Float = 6
let OP_M: UInt8 = 0, OP_L: UInt8 = 1, OP_Q: UInt8 = 2, OP_C: UInt8 = 3, OP_Z: UInt8 = 4

struct Cmd { let op: UInt8; let coords: [Float] }
struct CharStrokes { let count: Int; let strokes: [[Cmd]]; let medians: [[Float]] }

func decode(_ base64: String) throws -> CharStrokes {
    guard let data = Data(base64Encoded: base64) else { throw NSError(domain: "b64", code: 1) }
    let buf = [UInt8](data)
    var p = 0
    let ver = buf[p]; p += 1
    precondition(ver == 3, "版本不符: \(ver)")
    let n = Int(buf[p]); p += 1

    var strokes: [[Cmd]] = []
    for _ in 0..<n {
        let len = Int(buf[p]) | (Int(buf[p + 1]) << 8)
        p += 2
        let end = p + len
        var cmds: [Cmd] = []
        while p < end {
            let op = buf[p]; p += 1
            switch op {
            case OP_M, OP_L:
                cmds.append(Cmd(op: op, coords: [Float(buf[p]) * SCALE, Float(buf[p + 1]) * SCALE]))
                p += 2
            case OP_Q:
                cmds.append(Cmd(op: op, coords: [
                    Float(buf[p]) * SCALE, Float(buf[p + 1]) * SCALE,
                    Float(buf[p + 2]) * SCALE, Float(buf[p + 3]) * SCALE]))
                p += 4
            case OP_C:
                cmds.append(Cmd(op: op, coords: [
                    Float(buf[p]) * SCALE, Float(buf[p + 1]) * SCALE,
                    Float(buf[p + 2]) * SCALE, Float(buf[p + 3]) * SCALE,
                    Float(buf[p + 4]) * SCALE, Float(buf[p + 5]) * SCALE]))
                p += 6
            case OP_Z:
                cmds.append(Cmd(op: op, coords: []))
            default:
                throw NSError(domain: "op", code: Int(op))
            }
        }
        p = end
        strokes.append(cmds)
    }

    let medianCount = Int(buf[p]); p += 1
    var medians: [[Float]] = []
    for _ in 0..<medianCount {
        let ptCount = Int(buf[p]); p += 1
        var arr: [Float] = []
        for _ in 0..<ptCount {
            arr.append(Float(buf[p]) * SCALE)
            arr.append(Float(buf[p + 1]) * SCALE)
            p += 2
        }
        medians.append(arr)
    }
    return CharStrokes(count: n, strokes: strokes, medians: medians)
}

// MARK: - 绘制

let SIZE: Float = 1024
let PAD_RATIO: Float = 0.035

func buildPath(_ cmds: [Cmd], box: CGFloat) -> CGPath {
    let pad = box * CGFloat(PAD_RATIO)
    func px(_ v: Float) -> CGFloat { pad + CGFloat(v / SIZE) * (box - 2 * pad) }
    let path = CGMutablePath()
    for c in cmds {
        switch c.op {
        case OP_M: path.move(to: CGPoint(x: px(c.coords[0]), y: px(c.coords[1])))
        case OP_L: path.addLine(to: CGPoint(x: px(c.coords[0]), y: px(c.coords[1])))
        case OP_Q:
            path.addQuadCurve(
                to: CGPoint(x: px(c.coords[2]), y: px(c.coords[3])),
                control: CGPoint(x: px(c.coords[0]), y: px(c.coords[1])))
        case OP_C:
            path.addCurve(
                to: CGPoint(x: px(c.coords[4]), y: px(c.coords[5])),
                control1: CGPoint(x: px(c.coords[0]), y: px(c.coords[1])),
                control2: CGPoint(x: px(c.coords[2]), y: px(c.coords[3])))
        case OP_Z: path.closeSubpath()
        default: break
        }
    }
    return path
}

func glyphPath(_ ch: String, box: CGFloat) -> CGPath? {
    let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 1000, nil)
    var chars = Array(ch.utf16)
    var glyphs = [CGGlyph](repeating: 0, count: chars.count)
    guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count),
          let raw = CTFontCreatePathForGlyph(font, glyphs[0], nil) else { return nil }
    let em: CGFloat = 1000
    let scale = (box * 0.88) / em
    let bounds = raw.boundingBox
    var t = CGAffineTransform(
        translationX: box / 2 - bounds.midX * scale,
        y: box / 2 + bounds.midY * scale
    ).scaledBy(x: scale, y: -scale)
    return raw.copy(using: &t)
}

func render(ch: String, strokes: CharStrokes, box: Int, redGlyph: Bool, fillGlyph: Bool = false, drawStrokes: Bool = true) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: box, height: box, bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let b = CGFloat(box)
    // 背景纸色
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: b, height: b))

    // CGContext 原点在左下，翻转成左上，和 Canvas 坐标系一致
    ctx.translateBy(x: 0, y: b)
    ctx.scaleBy(x: 1, y: -1)

    // 笔画
    if drawStrokes {
        ctx.setFillColor(CGColor(red: 0.145, green: 0.2, blue: 0.176, alpha: 1))
        ctx.setShouldAntialias(true)
        for stroke in strokes.strokes {
            ctx.addPath(buildPath(stroke, box: b))
            ctx.fillPath()
        }
    }

    // CoreText 字形
    if redGlyph, let gp = glyphPath(ch, box: b) {
        ctx.addPath(gp)
        if fillGlyph {
            ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            ctx.fillPath()
        } else {
            ctx.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.7))
            ctx.setLineWidth(max(1, b / 400))
            ctx.strokePath()
        }
    }

    return ctx.makeImage()
}

// MARK: - 入口

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("用法: swift render-probe.swift <字> <边长px> <输出png>")
    exit(1)
}
let ch = args[1]
let box = Int(args[2]) ?? 512
let out = args[3]
let fillGlyph = CommandLine.arguments.contains("--fill-glyph")
let strokesOnly = CommandLine.arguments.contains("--strokes-only")

let scriptDir = URL(fileURLWithPath: args[0]).deletingLastPathComponent()
let jsonURL = scriptDir.appendingPathComponent("../HanziPad/Resources/strokes.json")
let all = try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as! [String: String]
guard let b64 = all[ch] else {
    print("没有这个字的数据: \(ch)")
    exit(1)
}
let strokes = try decode(b64)
print("\(ch): \(strokes.count) 笔, 中线 \(strokes.medians.count) 条")

guard let img = render(ch: ch, strokes: strokes, box: box, redGlyph: true, fillGlyph: fillGlyph, drawStrokes: !CommandLine.arguments.contains("--glyph-only")) else {
    print("渲染失败"); exit(1)
}
let url = URL(fileURLWithPath: out)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    print("写文件失败"); exit(1)
}
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("已写出 \(out)")
