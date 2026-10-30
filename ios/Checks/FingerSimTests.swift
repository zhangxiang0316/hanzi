import XCTest
@testable import HanziCore

/// 模拟真实手指采样，走「手势 onEnded」那条完全相同的处理链路：
/// 采样 → `StrokeSmoothing.smooth` → `dedupe` → `submit`。
///
/// 为什么需要：`PerfectTraceTests` 直接把中线喂给 `submit`，绕过了平滑与去重。
/// 而真机上多出来的正是这两步——点画只有 2-3 个中线点、长度二三十像素，
/// 平滑和去重完全可能把仅有的几个点吃掉。
@MainActor
final class FingerSimTests: XCTestCase {

    /// 沿中线按固定像素间距采样，模拟手指在屏幕上滑动产生的触点流
    private func fingerSamples(_ target: [Float], spacing: CGFloat) -> [Float] {
        guard target.count >= 4 else { return target }
        var out: [Float] = [target[0], target[1]]
        var i = 2
        var carry: CGFloat = 0
        var ax = CGFloat(target[0]), ay = CGFloat(target[1])
        while i < target.count {
            let bx = CGFloat(target[i]), by = CGFloat(target[i + 1])
            let seg = hypot(bx - ax, by - ay)
            if seg <= 0 { i += 2; continue }
            var travelled = carry
            while travelled + spacing <= seg {
                travelled += spacing
                let t = travelled / seg
                out.append(Float(ax + (bx - ax) * t))
                out.append(Float(ay + (by - ay) * t))
            }
            carry = seg - travelled
            ax = bx; ay = by
            i += 2
        }
        if out.count >= 2 {
            let lx = target[target.count - 2], ly = target[target.count - 1]
            if hypot(CGFloat(out[out.count - 2] - lx), CGFloat(out[out.count - 1] - ly)) > 0.5 {
                out.append(lx); out.append(ly)
            }
        }
        return out
    }

    /// 走 onEnded 的同款链路
    private func onStrokeEnd(_ raw: [Float]) -> [Float] {
        StrokeSmoothing.dedupe(StrokeSmoothing.smooth(raw))
    }

    /// 用手指采样完整个字，返回卡住的信息（nil 表示写完）
    private func runFinger(ch: String, box: CGFloat, spacing: CGFloat) -> String? {
        let r = TestRepo.make()
        guard let st = r.strokes(ch), st.count > 0 else { return "无笔顺数据" }
        let s = WriteSession(ch: ch, strokes: st, box: box)
        var guardCount = 0
        while !s.isDone && guardCount < 60 {
            guardCount += 1
            let i = s.index
            guard let t = s.targetPoints(for: i) else { return "第\(i + 1)笔无中线" }
            let raw = fingerSamples(t, spacing: spacing)
            let pts = onStrokeEnd(raw)
            let before = s.index
            let out = s.submit(pts)
            if case .finished = out { return nil }
            if case .rejected(let why) = out, s.index == before {
                return "第\(i + 1)/\(st.count)笔被拒(\(why)) 采样\(raw.count / 2)点→去重后\(pts.count / 2)点"
            }
            if case .tooShort = out, s.index == before {
                return "第\(i + 1)/\(st.count)笔太短 采样\(raw.count / 2)点→去重后\(pts.count / 2)点"
            }
        }
        return s.isDone ? nil : "超过 60 步没写完"
    }

    /// 手指间距 2px（正常书写速度）——全量扫
    func testFingerSpacing2AllChars() {
        let chars = TestRepo.make().allCharsWithStrokes()
        XCTAssertGreaterThan(chars.count, 2500)
        var failed: [(String, String)] = []
        for ch in chars {
            if let why = runFinger(ch: ch, box: 400, spacing: 2) { failed.append((ch, why)) }
        }
        if !failed.isEmpty {
            let sample = failed.prefix(12).map { "\($0.0): \($0.1)" }.joined(separator: "\n")
            XCTFail("\(failed.count)/\(chars.count) 个字用手指采样写不完：\n\(sample)")
        }
    }

    /// 手指间距 1px（写得慢，采样密）——去重会更激进
    func testFingerSpacing1AllChars() {
        let chars = TestRepo.make().allCharsWithStrokes()
        var failed: [(String, String)] = []
        for ch in chars {
            if let why = runFinger(ch: ch, box: 400, spacing: 1) { failed.append((ch, why)) }
        }
        if !failed.isEmpty {
            let sample = failed.prefix(12).map { "\($0.0): \($0.1)" }.joined(separator: "\n")
            XCTFail("\(failed.count)/\(chars.count) 个字在 1px 采样下写不完：\n\(sample)")
        }
    }

    /// 手机画布尺寸下（iPhone 17 Pro 约 362pt）
    func testFingerOnPhoneCanvas() {
        for ch in ["天", "玉", "主", "太", "心", "小", "永", "水"] {
            if let why = runFinger(ch: ch, box: 362, spacing: 2) {
                XCTFail("「\(ch)」在手机画布上写不完：\(why)")
            }
        }
    }
}
