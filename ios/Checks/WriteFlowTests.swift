import XCTest
@testable import HanziCore

/// 全链路测试：模拟「手指划过 → 平滑 → 去重 → 判定」，
/// 也就是 `WriteCanvas` 的 `onEnded` 里做的事情。
///
/// 与 WriteTests 的区别：那边直接喂中线，这边先经过平滑和去重，
/// 能抓到「平滑把关卡磨坏」这类问题——比如端点被挪动导致起笔判定失败。
@MainActor
final class WriteFlowTests: XCTestCase {

    private var repo: Repo { TestRepo.make() }

    /// 完全复刻 WriteCanvas.onEnded 的处理
    private func commit(_ session: WriteSession, _ raw: [Float]) -> WriteSession.Outcome {
        let pts = StrokeSmoothing.smooth(raw)
        let clean = StrokeSmoothing.dedupe(pts)
        return session.submit(clean)
    }

    /// 给中线加轻微抖动，模拟真实手指
    private func jittered(_ pts: [Float], amplitude: Float) -> [Float] {
        var out = pts
        var i = 0
        var seed: UInt32 = 12345
        while i < out.count {
            seed = seed &* 1664525 &+ 1013904223
            let r = Float(seed % 1000) / 1000 - 0.5
            out[i] += r * amplitude
            i += 2
        }
        return out
    }

    func testPerfectTraceThroughSmoothingScoresFull() {
        let s = WriteSession(ch: "天", strokes: repo.strokes("天"), box: 400)
        for i in 0..<s.count {
            guard let target = s.targetPoints(for: i) else { return XCTFail("缺中线") }
            let outcome = commit(s, target)
            if i < s.count - 1 {
                XCTAssertEqual(outcome, .passed(index: i, score: 100),
                               "第 \(i + 1) 笔经过平滑后仍应满分")
            } else {
                XCTAssertEqual(outcome, .finished(score: 100, stars: 3))
            }
        }
    }

    /// 手指有点抖也要能通过——这是最低要求，否则孩子写不出来
    func testJitteredTraceStillPasses() {
        let s = WriteSession(ch: "天", strokes: repo.strokes("天"), box: 400)
        for i in 0..<s.count {
            guard let target = s.targetPoints(for: i) else { return XCTFail("缺中线") }
            let noisy = jittered(target, amplitude: 6)   // 400px 画布上抖 6px
            let outcome = commit(s, noisy)
            switch outcome {
            case .passed, .finished:
                break
            default:
                XCTFail("第 \(i + 1) 笔抖动 6px 应该能通过，实际 \(outcome)")
            }
        }
    }

    /// 抖动过大就该拒绝——判定不能松到「乱画也算」
    func testHugeJitterIsRejected() {
        let s = WriteSession(ch: "天", strokes: repo.strokes("天"), box: 400)
        guard let target = s.targetPoints(for: 0) else { return XCTFail("缺中线") }
        let wild = jittered(target, amplitude: 120)   // 远超容差
        let outcome = commit(s, wild)
        if case .passed(_, let score) = outcome {
            XCTAssertLessThan(score, 70, "乱画不应该拿高分，实际 \(score)")
        }
    }

    /// 平滑不能把短笔画磨成「太短」
    func testSmoothingDoesNotShrinkStrokeBelowMinimum() {
        // 「一」是一条横线，最短；用真实笔画验证
        let s = WriteSession(ch: "一", strokes: repo.strokes("一"), box: 400)
        guard let target = s.targetPoints(for: 0) else { return XCTFail("缺中线") }
        let outcome = commit(s, target)
        XCTAssertEqual(outcome, .finished(score: 100, stars: 3),
                       "横线经平滑后不应被判太短或失分")
    }

    /// 小画布（iPad 分栏窄时）也要能写
    func testWorksOnSmallCanvas() {
        for box in [180, 240, 320, 480, 800] as [CGFloat] {
            let s = WriteSession(ch: "十", strokes: repo.strokes("十"), box: box)
            for i in 0..<s.count {
                guard let target = s.targetPoints(for: i) else { return XCTFail("缺中线") }
                let outcome = commit(s, target)
                switch outcome {
                case .passed(_, let score):
                    XCTAssertEqual(score, 100, "box=\(box) 第\(i + 1)笔")
                case .finished(let score, _):
                    XCTAssertEqual(score, 100, "box=\(box) 整字")
                default:
                    XCTFail("box=\(box) 第 \(i + 1) 笔失败：\(outcome)")
                }
            }
        }
    }

    /// 整字全对给 3 星，每笔 60 分左右给 1-2 星，能区分优劣
    func testStarLevelsDistinguishQuality() {
        XCTAssertEqual(Trace.scoreChar([100, 100, 100, 100]).stars, 3)
        XCTAssertEqual(Trace.scoreChar([70, 70, 70, 70]).stars, 2)
        XCTAssertEqual(Trace.scoreChar([45, 45, 45, 45]).stars, 1)
        XCTAssertEqual(Trace.scoreChar([20, 20, 20, 20]).stars, 0)
    }
}
