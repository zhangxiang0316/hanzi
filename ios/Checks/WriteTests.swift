import XCTest
@testable import HanziCore

/// 描红会话的判定逻辑。
///
/// 这些测试都在"画布坐标"上工作：给定画布边长，用中线坐标造一条
/// 沿目标笔画的笔迹，看状态机怎么反应。不依赖任何 UI。
@MainActor
final class WriteTests: XCTestCase {

    private var repo: Repo { TestRepo.make() }

    /// 理想笔迹：沿第 i 笔中线走一遍（含首尾）
    private func perfectTrace(_ session: WriteSession, _ i: Int) -> [Float] {
        session.targetPoints(for: i) ?? []
    }

    /// 造一条沿目标笔画的平滑笔迹，长度足够
    private func session(_ ch: String = "天", box: CGFloat = 400) -> WriteSession {
        WriteSession(ch: ch, strokes: repo.strokes(ch), box: box)
    }

    // MARK: - 基本流程

    func testStartsWithFirstStroke() {
        let s = session()
        XCTAssertEqual(s.index, 0)
        XCTAssertFalse(s.isDone)
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s.progress, 0)
    }

    func testPerfectTracePassesEveryStroke() {
        let s = session()
        for i in 0..<s.count {
            let target = perfectTrace(s, i)
            XCTAssertGreaterThanOrEqual(target.count, 4, "第 \(i + 1) 笔中线点数不足")
            let outcome = s.submit(target)
            if i < s.count - 1 {
                XCTAssertEqual(outcome, .passed(index: i, score: 100),
                               "第 \(i + 1) 笔照着画应满分")
                XCTAssertEqual(s.index, i + 1)
            } else {
                XCTAssertEqual(outcome, .finished(score: 100, stars: 3))
                XCTAssertTrue(s.isDone)
                XCTAssertEqual(s.finalScore, 100)
                XCTAssertEqual(s.finalStars, 3)
            }
        }
    }

    func testTooShortStrokeDoesNotConsumeIndex() {
        let s = session()
        // 一个几乎不动的点
        let outcome = s.submit([10, 10, 11, 10])
        XCTAssertEqual(outcome, .tooShort)
        XCTAssertEqual(s.index, 0, "太短不应该消耗笔画")
        XCTAssertTrue(s.message.contains("太短"))
        XCTAssertFalse(s.isDone)
    }

    func testEmptyInputIsTooShort() {
        let s = session()
        XCTAssertEqual(s.submit([]), .tooShort)
        XCTAssertEqual(s.index, 0)
    }

    func testFarOffStrokeIsRejectedAndKeepsIndex() {
        let s = session()
        // 一条够长但完全在格子外的横线
        let far: [Float] = [0, 380, 400, 380]
        let outcome = s.submit(far)
        guard case .rejected(let reason) = outcome else {
            return XCTFail("应被拒绝，实际 \(outcome)")
        }
        XCTAssertFalse(reason.isEmpty, "拒绝时必须给出原因")
        XCTAssertEqual(s.index, 0, "不通过应停在原地重写")
        XCTAssertTrue(s.scores.isEmpty, "不通过不应计入分数")
    }

    func testReversedDirectionIsRejectedOrLow() {
        let s = session()
        let target = perfectTrace(s, 0)
        // 反向写：覆盖没问题，但起笔收笔反了
        var reversed: [Float] = []
        var k = target.count - 2
        while k >= 0 {
            reversed.append(target[k])
            reversed.append(target[k + 1])
            k -= 2
        }
        let outcome = s.submit(reversed)
        // 反向通常仍能通过（形似），但分数明显低于 100
        if case .passed(_, let score) = outcome {
            XCTAssertLessThan(score, 100, "反向应扣分")
        }
    }

    // MARK: - 收笔

    func testLastStrokeFinishesAndScores() {
        let s = session("一", box: 400)
        XCTAssertEqual(s.count, 1)
        let outcome = s.submit(perfectTrace(s, 0))
        guard case .finished(let score, let stars) = outcome else {
            return XCTFail("单笔字应一笔写完，实际 \(outcome)")
        }
        XCTAssertEqual(score, 100)
        XCTAssertEqual(stars, 3)
        XCTAssertTrue(s.isDone)
        XCTAssertEqual(s.progress, 1)
    }

    func testSubmitAfterFinishIsRejected() {
        let s = session("一", box: 400)
        _ = s.submit(perfectTrace(s, 0))
        let outcome = s.submit([0, 0, 100, 0])
        XCTAssertEqual(outcome, .rejected(reason: "已经写完了"))
    }

    // MARK: - 跳过

    func testSkipAdvancesWithoutScore() {
        let s = session()
        s.skip()
        XCTAssertEqual(s.index, 1)
        XCTAssertEqual(s.scores, [0], "跳过的笔记为 0 分")
        XCTAssertFalse(s.isDone)
    }

    func testSkippingAllFinishesWithZeroStars() {
        let s = session()
        for _ in 0..<s.count { s.skip() }
        XCTAssertTrue(s.isDone)
        XCTAssertEqual(s.finalStars, 0, "全跳过不应该有星")
        XCTAssertEqual(s.finalScore, 0)
    }

    func testSkipDoesNotAdvanceWhenDone() {
        let s = session("一", box: 400)
        _ = s.submit(perfectTrace(s, 0))
        let before = s.scores
        s.skip()
        XCTAssertEqual(s.scores, before, "写完后跳过不应改变分数")
    }

    // MARK: - 重来

    func testRestartClearsEverything() {
        let s = session()
        _ = s.submit(perfectTrace(s, 0))
        s.skip()
        XCTAssertEqual(s.index, 2)
        s.restart()
        XCTAssertEqual(s.index, 0)
        XCTAssertTrue(s.scores.isEmpty)
        XCTAssertFalse(s.isDone)
        XCTAssertEqual(s.message, "")
    }

    // MARK: - 几何

    func testToleranceScalesWithBox() {
        let small = session("天", box: 200)
        let large = session("天", box: 800)
        XCTAssertEqual(small.tolerance, 15, accuracy: 0.01)
        XCTAssertEqual(large.tolerance, 60, accuracy: 0.01)
        // 边长翻四倍，容差也应翻四倍——手感与屏幕尺寸无关
        XCTAssertEqual(large.tolerance / small.tolerance, 4, accuracy: 0.001)
    }

    func testUpdateBoxOnlyOnRealChange() {
        let s = session("天", box: 400)
        s.updateBox(400.2)
        XCTAssertEqual(s.box, 400, "微小抖动不应改变几何")
        s.updateBox(500)
        XCTAssertEqual(s.box, 500)
    }

    func testTargetPointsAreInCanvasCoordinates() {
        let s = session("天", box: 400)
        let pad = HanziCanvas.pad(of: 400)
        for i in 0..<s.count {
            guard let pts = s.targetPoints(for: i) else { return XCTFail("缺中线") }
            for k in stride(from: 0, to: pts.count, by: 2) {
                XCTAssertGreaterThanOrEqual(CGFloat(pts[k]), pad - 1, "x 越界")
                XCTAssertLessThanOrEqual(CGFloat(pts[k]), 400 - pad + 1, "x 越界")
                XCTAssertGreaterThanOrEqual(CGFloat(pts[k + 1]), pad - 1, "y 越界")
                XCTAssertLessThanOrEqual(CGFloat(pts[k + 1]), 400 - pad + 1, "y 越界")
            }
        }
    }

    func testTargetPointsNilForOutOfRangeIndex() {
        let s = session("天", box: 400)
        XCTAssertNil(s.targetPoints(for: -1))
        XCTAssertNil(s.targetPoints(for: 99))
    }

    // MARK: - 平滑

    func testSmoothingKeepEndpoints() {
        let pts: [Float] = [0, 0, 10, 12, 20, 8, 30, 14, 40, 0]
        let out = StrokeSmoothing.smooth(pts)
        XCTAssertEqual(out.count, pts.count)
        XCTAssertEqual(out[0], pts[0], "起点必须不动")
        XCTAssertEqual(out[1], pts[1], "起点必须不动")
        XCTAssertEqual(out[out.count - 2], pts[pts.count - 2], "末点必须不动")
        XCTAssertEqual(out[out.count - 1], pts[pts.count - 1], "末点必须不动")
    }

    func testSmoothingReducesJitter() {
        // 真实手指采样是密集的：3px 一个点，叠加 ±2px 抖动
        var pts: [Float] = []
        for i in 0..<60 {
            pts.append(Float(i) * 3)
            pts.append(i % 2 == 0 ? 2 : -2)
        }
        let before = jitter(pts)
        let after = jitter(StrokeSmoothing.smooth(pts))
        XCTAssertLessThan(after, before, "平滑应减少抖动")
    }

    /// 稀疏输入不该被平滑——平均会把拐角切掉，白白改变笔画形状。
    /// 阈值依据：笔顺中线只有 6-20 个点，真实手指采样有上百点。
    func testSparseInputIsNotSmoothed() {
        // 间距 10px > 阈值 8px
        var pts: [Float] = []
        for i in 0..<10 {
            pts.append(Float(i) * 10)
            pts.append(i % 2 == 0 ? 3 : -3)
        }
        XCTAssertEqual(StrokeSmoothing.smooth(pts), pts,
                       "稀疏输入应原样返回，不能被切角")
    }

    func testAverageSpacing() {
        let pts: [Float] = [0, 0, 10, 0, 20, 0]
        XCTAssertEqual(StrokeSmoothing.averageSpacing(pts), 10, accuracy: 0.001)
        XCTAssertEqual(StrokeSmoothing.averageSpacing([1, 2]), 0, accuracy: 0.001)
    }

    /// 平滑后的完美笔迹必须仍然满分——这是自适应阈值的意义所在
    func testSmoothingDoesNotCostPointsOnPerfectTrace() {
        let s = session("天", box: 400)
        for i in 0..<s.count {
            guard let target = s.targetPoints(for: i) else { return XCTFail("缺中线") }
            let smoothed = StrokeSmoothing.smooth(target)
            XCTAssertEqual(smoothed, target, "沿中线的笔迹不该被平滑改动")
        }
    }

    /// 相邻点 y 差的绝对值之和，作为抖动程度的度量
    private func jitter(_ pts: [Float]) -> Float {
        var sum: Float = 0
        var i = 3
        while i < pts.count {
            sum += abs(pts[i] - pts[i - 2])
            i += 2
        }
        return sum
    }

    func testSmoothingShortInputUnchanged() {
        let pts: [Float] = [0, 0, 10, 10]
        XCTAssertEqual(StrokeSmoothing.smooth(pts), pts)
    }

    func testSmoothingPreservesStraightLine() {
        // 直线上的点不该被平滑改坏
        var pts: [Float] = []
        for i in 0..<10 {
            pts.append(Float(i) * 10)
            pts.append(0)
        }
        let out = StrokeSmoothing.smooth(pts)
        for i in 0..<10 {
            XCTAssertEqual(out[i * 2 + 1], 0, accuracy: 0.001, "直线被平滑变形了")
        }
    }

    // MARK: - 去重

    func testDedupeDropsClosePoints() {
        // 前三个点挤在 1px 内，应被合并
        let pts: [Float] = [0, 0, 0.5, 0, 1, 0, 50, 0]
        let out = StrokeSmoothing.dedupe(pts, minDist: 1.5)
        XCTAssertLessThan(out.count, pts.count)
        XCTAssertEqual(out[0], 0)
        XCTAssertEqual(out[1], 0)
    }

    func testDedupeKeepsLastPoint() {
        let pts: [Float] = [0, 0, 50, 0, 50.5, 0]
        let out = StrokeSmoothing.dedupe(pts, minDist: 1.5)
        XCTAssertEqual(out[out.count - 2], 50.5, "末点必须保留，收笔参与评分")
        XCTAssertEqual(out[out.count - 1], 0)
    }

    func testDedupeShortInputUnchanged() {
        let pts: [Float] = [1, 2]
        XCTAssertEqual(StrokeSmoothing.dedupe(pts), pts)
    }

    // MARK: - 提示文案

    func testReasonTextCoversAllReasons() {
        for r in ["start", "off", "short", "empty", "unknown"] {
            let text = WriteSession.reasonText(r)
            XCTAssertFalse(text.isEmpty, "\(r) 应有提示文案")
            XCTAssertTrue(text.contains("写") || text.contains("笔") || text.contains("线"),
                          "\(r) 的文案要能指导孩子怎么做：\(text)")
        }
    }
}
