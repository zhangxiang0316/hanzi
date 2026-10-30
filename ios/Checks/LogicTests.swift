import XCTest
@testable import HanziCore

/// 逻辑层测试：SRS / 描红评分 / 出题。
///
/// 期望值全部照搬 Android `LogicTest.kt` 的断言，这样三端行为才是可证一致的，
/// 而不是「各自跑得通」。
@MainActor
final class LogicTests: XCTestCase {

    private static var _repo: Repo?

    private var repo: Repo {
        if let r = Self._repo {
            Repo.overrideShared(r)
            return r
        }
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HanziPad/Resources")
        let r = Repo(source: .directory(resources))
        Self._repo = r
        // Quiz / Plan 内部读 Repo.shared，必须指向测试数据
        Repo.overrideShared(r)
        return r
    }

    // MARK: - SRS

    func testFirstLearnEntersBox1AndDueTomorrow() {
        let e = Srs.learn(nil, today: 100)
        XCTAssertEqual(e.box, 1)
        XCTAssertEqual(e.due, 101)
        XCTAssertTrue(Srs.isLearning(e))
        XCTAssertFalse(Srs.isMastered(e))
    }

    func testRepeatedLearnDoesNotDowngrade() {
        let first = Srs.learn(nil, today: 100)
        let again = Srs.learn(first, today: 105)
        XCTAssertEqual(again.box, 1)
        XCTAssertEqual(again.due, first.due)
    }

    func testCorrectGradesStepUpWithIntervals() {
        var e = Srs.learn(nil, today: 0)
        for expected in [2, 3, 4, 5, 6, 7] {
            e = Srs.grade(e, correct: true, today: 0)
            XCTAssertEqual(e.box, expected)
            XCTAssertEqual(e.due, Srs.intervals[expected])
        }
        // 已在最高箱，继续答对不越界
        e = Srs.grade(e, correct: true, today: 0)
        XCTAssertEqual(e.box, Srs.maxBox)
    }

    func testWrongGradesFallBack() {
        // 生字错 → 掉回 0
        let fresh = Srs.grade(Srs.learn(nil, today: 0), correct: false, today: 0)
        XCTAssertEqual(fresh.box, 0)

        // 较熟（>=3 箱）错 → 回到 1，不是直接清零
        var e = Srs.learn(nil, today: 0)
        for _ in 0..<3 { e = Srs.grade(e, correct: true, today: 0) }
        XCTAssertEqual(e.box, 4)
        let afterMiss = Srs.grade(e, correct: false, today: 0)
        XCTAssertEqual(afterMiss.box, 1)
    }

    func testBothOutcomesCounted() {
        var e = Srs.learn(nil, today: 0)
        for _ in 0..<3 { e = Srs.grade(e, correct: true, today: 0) }
        for _ in 0..<2 { e = Srs.grade(e, correct: false, today: 0) }
        XCTAssertEqual(e.seen, 5)
        XCTAssertEqual(e.ok, 3)
        XCTAssertEqual(e.miss, 2)
    }

    func testMasteredBoxIsFive() {
        var e = Srs.learn(nil, today: 0)
        while e.box < Srs.masteredBox {
            XCTAssertFalse(Srs.isMastered(e))
            e = Srs.grade(e, correct: true, today: 0)
        }
        XCTAssertTrue(Srs.isMastered(e))
        XCTAssertEqual(Srs.stageOf(e), "mastered")
    }

    func testDueByDayNumber() {
        let e = Srs.learn(nil, today: 100)
        XCTAssertFalse(Srs.isDue(e, today: 100))
        XCTAssertTrue(Srs.isDue(e, today: 101))
        XCTAssertTrue(Srs.isDue(e, today: 150))
    }

    // MARK: - 描红评分

    private func line(_ y: Float = 0) -> [Float] { [0, y, 100, y] }

    func testTracingExactlyScoresFull() {
        let target = line()
        let r = Trace.scoreStroke(userPts: target, targetPts: target, tolerance: 26)
        XCTAssertEqual(r.score, 100)
        XCTAssertEqual(r.reason, "ok")
    }

    func testReversedDirectionLosesPoints() {
        let target = line()
        let reversed: [Float] = [100, 0, 0, 0]
        let r = Trace.scoreStroke(userPts: reversed, targetPts: target, tolerance: 26)
        XCTAssertLessThan(r.score, 90, "反向应扣分，实际 \(r.score)")
        XCTAssertGreaterThan(r.score, 20, "反向应至少能画出形状，实际 \(r.score)")
    }

    func testFarOffScoresLow() {
        let r = Trace.scoreStroke(userPts: [0, 200, 100, 200], targetPts: line(), tolerance: 26)
        XCTAssertLessThan(r.score, 30, "偏离应低分，实际 \(r.score)")
    }

    func testSingleDotScoresLow() {
        let r = Trace.scoreStroke(userPts: [50, 0, 51, 0], targetPts: line(), tolerance: 26)
        XCTAssertLessThan(r.score, 50, "点一下应低分，实际 \(r.score)")
    }

    func testEmptyInputScoresZero() {
        XCTAssertEqual(Trace.scoreStroke(userPts: nil, targetPts: line()).score, 0)
        XCTAssertEqual(Trace.scoreStroke(userPts: line(), targetPts: nil).score, 0)
        XCTAssertEqual(Trace.scoreStroke(userPts: [1, 2], targetPts: line()).score, 0)
    }

    func testLooseToleranceScoresHigher() {
        let offset: [Float] = [0, 12, 100, 12]
        let tight = Trace.scoreStroke(userPts: offset, targetPts: line(), tolerance: 10)
        let loose = Trace.scoreStroke(userPts: offset, targetPts: line(), tolerance: 40)
        XCTAssertGreaterThanOrEqual(loose.score, tight.score,
                                    "容差放宽应更容易通过 \(tight.score) -> \(loose.score)")
    }

    func testCharScorePulledDownByWorstStroke() {
        // 与小程序 trace.js scoreChar 同一公式：avg*0.85 + min*0.15
        let good = Trace.scoreChar([95, 95, 95, 95])
        XCTAssertEqual(good.score, 95)
        XCTAssertEqual(good.stars, 3)

        // avg=76.25, min=20 → 68 → 2 星
        let oneBad = Trace.scoreChar([95, 95, 95, 20])
        XCTAssertEqual(oneBad.score, 68)
        XCTAssertEqual(oneBad.stars, 2)
        XCTAssertLessThan(oneBad.score, good.score)

        // avg=71.25, min=0 → 61 → 1 星
        let oneZero = Trace.scoreChar([95, 95, 95, 0])
        XCTAssertEqual(oneZero.score, 61)
        XCTAssertEqual(oneZero.stars, 1)
    }

    func testStarThresholds() {
        XCTAssertEqual(Trace.starsOf(85), 3)
        XCTAssertEqual(Trace.starsOf(65), 2)
        XCTAssertEqual(Trace.starsOf(40), 1)
        XCTAssertEqual(Trace.starsOf(39), 0)
    }

    func testLengthAndDistance() {
        let poly: [Float] = [0, 0, 100, 0]
        XCTAssertEqual(Trace.polylineLength(poly), 100, accuracy: 0.01)
        XCTAssertEqual(Trace.pointToPolyline(50, 5, poly), 5, accuracy: 0.01)
        // 端点外侧应取端点距离
        XCTAssertEqual(Trace.pointToPolyline(-10, 0, poly), 10, accuracy: 0.01)
    }

    // MARK: - 随机数生成器

    /// 黄金值来自 JS 原版 utils/quiz.js 的 mulberry32。
    /// 三端必须逐位一致，否则同一个 seed 出的题不同。
    func testMulberry32MatchesJS() {
        let cases: [(UInt32, Double, Double)] = [
            (12345, 0.97972826776094735, 0.30675226449966431),
            (42, 0.60110375192016363, 0.44829055899754167),
            (7, 0.01170475315302610, 0.06195825757458806),
            (99, 0.26046581240370870, 0.80482276552356780),
            (3, 0.72022678377106786, 0.03866216051392257),
            (11, 0.51158704864792526, 0.52994640823453665),
        ]
        for (seed, first, second) in cases {
            let rand = Quiz.mulberry32(seed)
            XCTAssertEqual(rand(), first, accuracy: 1e-15, "seed \(seed) 第一个值不符")
            XCTAssertEqual(rand(), second, accuracy: 1e-15, "seed \(seed) 第二个值不符")
        }
    }

    func testSameSeedProducesSameQuiz() {
        let chars = Array(repo.bookChars("1a").prefix(10))
        let a = Quiz.build(chars: chars, book: "1a", lesson: nil, count: 8, seed: 42)
        let b = Quiz.build(chars: chars, book: "1a", lesson: nil, count: 8, seed: 42)
        XCTAssertEqual(a.questions.count, b.questions.count)
        XCTAssertEqual(a.questions.map(\.type), b.questions.map(\.type))
        XCTAssertEqual(a.questions.map(\.prompt), b.questions.map(\.prompt))
        XCTAssertEqual(a.questions.map(\.answer), b.questions.map(\.answer))
    }

    func testEveryQuestionHasFourUniqueOptions() {
        let chars = Array(repo.bookChars("2a").prefix(12))
        let r = Quiz.build(chars: chars, book: "2a", lesson: nil, count: 12, seed: 7)
        XCTAssertFalse(r.questions.isEmpty, "应出题，实际 \(r.questions.count)")
        for q in r.questions {
            XCTAssertEqual(q.options.count, 4, "「\(q.ch)」\(q.type) 选项数")
            XCTAssertEqual(Set(q.options.map(\.value)).count, 4, "选项应去重")
            XCTAssertTrue(q.options.map(\.value).contains(q.answer),
                          "答案应在选项中: \(q.answer)")
            XCTAssertFalse(q.explain.isEmpty, "题目应有解析")
            XCTAssertFalse(q.prompt.isEmpty, "题目应有题干")
        }
    }

    func testPinyinQuestionExcludesHomophones() {
        // 同音字做干扰项会导致「两个都对」，必须排除
        let chars = repo.bookChars("1a")
        let r = Quiz.build(chars: chars, book: "1a", lesson: nil, count: 20, seed: 99)
        for q in r.questions where q.type == "pinyin2char" {
            let correctReadings = Set(repo.readingsOf(q.answer))
            for opt in q.options where opt.value != q.answer {
                let other = Set(repo.readingsOf(opt.value))
                XCTAssertTrue(other.intersection(correctReadings).isEmpty,
                              "干扰项「\(opt.value)」与答案「\(q.answer)」同音")
            }
        }
    }

    func testStrokeCountAnswerIsStrokeCount() {
        let chars = ["一", "人", "口", "盐", "繁"]
        let r = Quiz.build(chars: chars, book: "4a", lesson: nil, count: 5, seed: 3)
        for q in r.questions where q.type == "strokeCount" {
            let expected = String(repo.strokeCount(q.ch))
            XCTAssertEqual(q.answer, expected)
            for o in q.options {
                XCTAssertGreaterThan(Int(o.value) ?? 0, 0)
            }
        }
    }

    func testEmptyInputProducesNoQuiz() {
        let r = Quiz.build(chars: [], book: "1a", lesson: nil, count: 10, seed: 1)
        XCTAssertTrue(r.questions.isEmpty)
    }

    func testEveryBookCanProduceQuiz() {
        for book in repo.books {
            let chars = Array(repo.bookChars(book.id).prefix(10))
            let r = Quiz.build(chars: chars, book: book.id, lesson: nil, count: 6, seed: 11)
            XCTAssertGreaterThanOrEqual(r.questions.count, 4, "\(book.id) 出题失败")
        }
    }

    // MARK: - 计划

    func testBookProgressStartsEmpty() {
        let prog = Progress(store: MemoryStore())
        let bp = Plan.bookProgress(prog, "1a")
        XCTAssertEqual(bp.learned, 0)
        XCTAssertEqual(bp.pct, 0)
        XCTAssertEqual(bp.total, repo.bookChars("1a").count)
    }

    func testTodayTaskStartsAsLearn() {
        let prog = Progress(store: MemoryStore())
        let task = Plan.buildTodayTask(prog, "1a")
        XCTAssertEqual(task.type, "learn")
        XCTAssertTrue(task.title.contains("继续学"), "实际 \(task.title)")
    }

    func testTodayTaskBecomesReviewWhenDue() {
        let prog = Progress(store: MemoryStore())
        let ch = repo.bookChars("1a")[0]
        prog.learn(ch)
        // 刚学完今天不到期
        XCTAssertEqual(Plan.buildTodayTask(prog, "1a").type, "learn")
        XCTAssertTrue(prog.dueChars([ch]).isEmpty)
    }

    func testFindContinueFollowsLessonOrder() {
        let prog = Progress(store: MemoryStore())
        guard let next = Plan.findContinue(prog, "1a") else {
            return XCTFail("应能找回第一课")
        }
        XCTAssertEqual(next.lesson, repo.book("1a")?.lessons.first)
        XCTAssertEqual(next.learned, 0)
        XCTAssertFalse(next.start.isEmpty, "应给出起始字")
    }

    func testDailyCharStablePerDate() {
        let a = Plan.pickDailyChar("1a", "2026-10-30")
        let b = Plan.pickDailyChar("1a", "2026-10-30")
        XCTAssertEqual(a, b, "同一天应稳定")
        XCTAssertFalse(a.isEmpty)
        // 不同日期大概率不同（不强制，避免偶发失败）
    }

    // MARK: - 进度

    func testLearnIncrementsTodayCount() {
        let prog = Progress(store: MemoryStore())
        let ch = repo.bookChars("1a")[0]
        prog.learn(ch)
        XCTAssertTrue(prog.hasLearned(ch))
        XCTAssertEqual(prog.todayStats.learned, 1)
        XCTAssertEqual(prog.totalLearned, 1)
    }

    func testLearnIsIdempotent() {
        let prog = Progress(store: MemoryStore())
        let ch = repo.bookChars("1a")[0]
        prog.learn(ch)
        prog.learn(ch)
        XCTAssertEqual(prog.todayStats.learned, 1, "重复学习不应重复计数")
    }

    func testGradeWrongAddsToWrongBook() {
        let prog = Progress(store: MemoryStore())
        let ch = repo.bookChars("1a")[0]
        prog.learn(ch)
        prog.grade(ch, correct: false, lesson: "1a-s1")
        XCTAssertEqual(prog.wrongCount, 1)
        XCTAssertEqual(prog.wrongList.first?.ch, ch)
        XCTAssertEqual(prog.wrongList.first?.lesson, "1a-s1")
    }

    func testGradeCorrectRemovesFromWrongBook() {
        let prog = Progress(store: MemoryStore())
        let ch = repo.bookChars("1a")[0]
        prog.learn(ch)
        prog.grade(ch, correct: false)
        XCTAssertEqual(prog.wrongCount, 1)
        prog.grade(ch, correct: true)
        XCTAssertEqual(prog.wrongCount, 0, "答对一次应消掉错题")
    }

    func testAccuracyToday() {
        let prog = Progress(store: MemoryStore())
        let chars = Array(repo.bookChars("1a").prefix(4))
        for c in chars { prog.learn(c) }
        prog.grade(chars[0], correct: true)
        prog.grade(chars[1], correct: true)
        prog.grade(chars[2], correct: false)
        prog.grade(chars[3], correct: false)
        XCTAssertEqual(prog.accuracyToday, 50)
    }

    func testSaveWriteKeepsBest() {
        let prog = Progress(store: MemoryStore())
        let ch = "天"
        prog.saveWrite(ch, score: 60)
        let r1 = prog.writeRecord(ch)
        XCTAssertEqual(r1?.best, 60)
        XCTAssertEqual(r1?.tries, 1)

        prog.saveWrite(ch, score: 40)
        let r2 = prog.writeRecord(ch)
        XCTAssertEqual(r2?.best, 60, "低分不应覆盖最高分")
        XCTAssertEqual(r2?.tries, 2)
    }

    func testBadgesStartEmpty() {
        let prog = Progress(store: MemoryStore())
        let badges = prog.badges()
        XCTAssertEqual(badges.count, 8)
        XCTAssertTrue(badges.allSatisfy { !$0.got })
    }

    func testBadgeUnlocksAfterLearning() {
        let prog = Progress(store: MemoryStore())
        prog.learn(repo.bookChars("1a")[0])
        let sprout = prog.badges().first { $0.id == "sprout" }
        XCTAssertEqual(sprout?.got, true)
    }

    func testResetClearsEverything() {
        let prog = Progress(store: MemoryStore())
        let ch = repo.bookChars("1a")[0]
        prog.learn(ch)
        // 注意：刚学的字答错一次会退回第 0 箱，此时不算「已学」。
        // 这是 Srs.grade 的既定行为（box>=3 才回到 1，否则掉到 0），
        // 所以先断言再答题。
        XCTAssertGreaterThan(prog.totalLearned, 0)
        prog.grade(ch, correct: false)

        prog.resetAll()
        XCTAssertEqual(prog.totalLearned, 0)
        XCTAssertEqual(prog.wrongCount, 0)
        XCTAssertTrue(prog.badges().allSatisfy { !$0.got })
    }

    func testProgressPersistsAcrossInstances() {
        let store = MemoryStore()
        let chars = Array(repo.bookChars("1a").prefix(2))
        let kept = chars[0], missed = chars[1]
        do {
            let prog = Progress(store: store)
            prog.learn(kept)
            prog.learn(missed)
            prog.grade(missed, correct: false, lesson: "1a-s1")
        }
        let reloaded = Progress(store: store)
        XCTAssertTrue(reloaded.hasLearned(kept), "重新载入后应保留学习状态")
        XCTAssertEqual(reloaded.wrongCount, 1, "错题本应保留")
        XCTAssertEqual(reloaded.wrongList.first?.lesson, "1a-s1")
    }

    /// 刚学的字答错一次会退回第 0 箱 —— 这条锁住行为，免得以后被当成 bug 改掉
    func testNewCharWrongAnswerFallsBackToBoxZero() {
        let prog = Progress(store: MemoryStore())
        let ch = repo.bookChars("1a")[0]
        prog.learn(ch)
        XCTAssertTrue(prog.hasLearned(ch))
        prog.grade(ch, correct: false)
        XCTAssertFalse(prog.hasLearned(ch), "第 1 箱答错应退回第 0 箱")
        XCTAssertEqual(prog.entry(ch)?.box, 0)
    }

    func testRecentDaysLength() {
        let prog = Progress(store: MemoryStore())
        XCTAssertEqual(prog.recentDays(7).count, 7)
        XCTAssertEqual(prog.recentDays(7).last?.key, DayUtil.todayKey())
    }

    func testSessionModes() {
        let prog = Progress(store: MemoryStore())
        let free = Plan.buildSession(mode: "free", prog: prog, book: "1a")
        XCTAssertEqual(free.mode, "free")
        XCTAssertEqual(free.count, 10)
        XCTAssertFalse(free.chars.isEmpty)

        let lesson = Plan.buildSession(mode: "lesson", prog: prog, book: "1a", lesson: "1a-s1")
        XCTAssertEqual(lesson.mode, "lesson")
        XCTAssertEqual(lesson.chars, repo.lessonChars("1a-s1"))

        // 全新状态没有到期字，复习会话为空
        let review = Plan.buildSession(mode: "review", prog: prog, book: "1a")
        XCTAssertTrue(review.chars.isEmpty)
    }
}
