import XCTest
@testable import HanziCore

/// 不变量：**用完美笔迹（严格沿中线）写任何一个字，都必须能写完。**
///
/// 这条测试是针对「描红最后一笔写不上」写的。只要某一笔在手势层之下
/// 无法被接受（参照数据缺失、太短闸门、判定过严），这里就会报出来，
/// 而不需要人手一个个字去试。
///
/// 注意它测的是**状态机**：绕过 `DragGesture`，直接调 `submit`。
/// 所以它绿了不代表手指能写上去——那由手势层的测试负责。
@MainActor
final class PerfectTraceTests: XCTestCase {

    /// 完美笔迹：直接把中线转成画布坐标喂进去
    private func perfectStroke(_ s: WriteSession, _ i: Int) -> [Float] {
        var pts = s.targetPoints(for: i) ?? []
        // 中线点可能很稀疏（最少的只有 2 个 → 4 个 float），正好卡在边界上
        if pts.count < 4 { return [] }
        return pts
    }

    /// 逐笔提交完美笔迹，返回 (是否写完, 每一步的 outcome 描述)
    private func runPerfect(ch: String, box: CGFloat) -> (finished: Bool, log: [String]) {
        let repo = TestRepo.make()
        let strokes = repo.strokes(ch)
        guard let strokes, strokes.count > 0 else { return (false, ["没有笔顺数据"]) }
        let s = WriteSession(ch: ch, strokes: strokes, box: box)
        var log: [String] = []
        var guardCount = 0
        while !s.isDone && guardCount < 40 {
            guardCount += 1
            let i = s.index
            let pts = perfectStroke(s, i)
            let before = s.index
            let out = s.submit(pts)
            switch out {
            case .passed(let idx, let score):
                log.append("第\(idx + 1)笔 过 \(score)")
            case .finished(let score, let stars):
                log.append("第\(i + 1)笔 完 \(score)分\(stars)星")
                return (true, log)
            case .rejected(let r):
                log.append("第\(i + 1)笔 拒(\(r)) score=\(s.scores.count)")
                if s.index == before { return (false, log) }
            case .tooShort:
                log.append("第\(i + 1)笔 太短")
                if s.index == before { return (false, log) }
            }
        }
        return (s.isDone, log)
    }

    /// 「天」——用户最容易复现的字，最后一笔是长捺
    func testPerfectTian() {
        let r = runPerfect(ch: "天", box: 400)
        XCTAssertTrue(r.finished, "「天」完美笔迹写不完：\(r.log.joined(separator: " → "))")
    }

    /// 最后一笔是「点」的字（点画最容易触发太短闸门）
    func testPerfectCharsEndingWithDot() {
        _ = TestRepo.make()
        // 心/太/犬/小/办的最后一笔都是点
        for ch in ["心", "太", "犬", "小", "办", "火", "水", "永", "求", "义"] {
            guard TestRepo.make().strokes(ch) != nil else { continue }
            let r = runPerfect(ch: ch, box: 400)
            XCTAssertTrue(r.finished,
                          "「\(ch)」完美笔迹写不完：\(r.log.joined(separator: " → "))")
        }
    }

    /// 全量：2596 个有笔顺数据的字，一个都不能卡住
    ///
    /// 这是最硬的一条。只要任何一个字在完美输入下写不完，
    /// 说明该字的中线数据或判定链路有问题，用户必然会遇到。
    func testEveryCharacterCompletesWithPerfectStrokes() {
        let chars = TestRepo.make().allCharsWithStrokes()
        XCTAssertGreaterThan(chars.count, 2500, "有笔顺数据的字太少：\(chars.count)")
        var failed: [(String, String)] = []
        for ch in chars {
            let r = runPerfect(ch: ch, box: 400)
            if !r.finished { failed.append((ch, r.log.joined(separator: " → "))) }
        }
        if !failed.isEmpty {
            let sample = failed.prefix(10)
                .map { "\($0.0): \($0.1)" }
                .joined(separator: "\n")
            XCTFail("\(failed.count) 个字用完美笔迹写不完：\n\(sample)")
        }
    }

    /// 画布尺寸不影响结论：完美笔迹在最小/最大画布上也必须写完
    func testPerfectStrokesAtExtremeCanvasSizes() {
        for box in [CGFloat(280), 400, 560] {
            let r = runPerfect(ch: "天", box: box)
            XCTAssertTrue(r.finished, "box=\(box) 写不完：\(r.log.joined(separator: " → "))")
        }
    }
}
