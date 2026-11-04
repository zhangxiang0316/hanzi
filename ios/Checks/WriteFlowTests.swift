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

// MARK: - 换字：session 必须跟着字换

/// 「上一个字 / 下一个字」换字后，session 必须重建。
///
/// 这是 iOS 独有的 bug：SwiftUI 在同一个导航层位置上复用视图身份，所以
/// `pushReplacing` 换掉栈顶 route 后，`@State` 里的 WriteSession 会活下来，
/// 画布停在原来那个字上，而标题、拼音、笔画数都已经跟着新字变了。
///
/// 修复是两层：`navigationDestination` 上加 `.id(r.ch)` 换视图身份，
/// 视图内部再用 `liveSession` 挡「session 和字对不上」的中间态。
/// 下面的用例锁住这两层各自的语义。
@MainActor
final class WriteStepTests: XCTestCase {

    /// Repo 必须由 TestSupport 建一次，否则读 Bundle.main 会失败
    private var repo: Repo { TestRepo.make() }

    func testSessionCarriesItsOwnChar() {
        // session 自带字，这是 liveSession 能判断「配不配对」的前提
        let s = WriteSession(ch: "天", strokes: repo.strokes("天"), box: 400)
        XCTAssertEqual(s.ch, "天")
    }

    func testNextSessionIsADifferentObject() {
        let a = WriteSession(ch: "天", strokes: repo.strokes("天"), box: 400)
        let b = WriteSession(ch: "地", strokes: repo.strokes("地"), box: 400)
        XCTAssertFalse(a === b, "换字必须新建 session，不能复用")
        XCTAssertNotEqual(a.ch, b.ch)
    }

    func testNewSessionStartsFromFirstStroke() {
        // 换了字却接着上一个字的笔画进度，孩子会发现自己从第 3 笔开始写
        let a = WriteSession(ch: "天", strokes: repo.strokes("天"), box: 400)
        if !a.isDone, let t = a.targetPoints(for: a.index) { _ = a.submit(t) }
        let b = WriteSession(ch: "你", strokes: repo.strokes("你"), box: 400)
        XCTAssertEqual(b.index, 0, "新字的笔画进度必须从 0 开始")
        XCTAssertTrue(b.scores.isEmpty, "新字不该继承上一个字的得分")
    }

    func testStrokesAreTheNewCharsStrokes() {
        // 画布画的是 session.strokes，不是 ch——这就是「字没换」的根因
        let tian = WriteSession(ch: "天", strokes: repo.strokes("天"), box: 400)
        let ni = WriteSession(ch: "你", strokes: repo.strokes("你"), box: 400)
        XCTAssertNotEqual(tian.strokes?.count, ni.strokes?.count,
                          "天 和 你 的笔画数不同，拿错 session 一定看得出来")
    }

    func testPrevNextRoundTrip() {
        // 天 → 下一个 是 地；地 → 上一个 回到 天
        let lesson = repo.meta("天")?.lesson
        let next = repo.nextInLesson(lesson, "天")
        XCTAssertEqual(next, "地")
        XCTAssertEqual(repo.prevInLesson(lesson, next), "天")
    }

    func testEdgeOfLessonReturnsEmpty() {
        // 课时首尾没有上一个/下一个，按钮应该是隐藏的而不是跳到别处
        let first = repo.lessonChars("1a-s1").first!
        let last = repo.lessonChars("1a-s1").last!
        XCTAssertEqual(repo.prevInLesson("1a-s1", first), "")
        XCTAssertEqual(repo.nextInLesson("1a-s1", last), "")
    }
}
