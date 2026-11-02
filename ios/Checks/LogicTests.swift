import XCTest
@testable import HanziCore

/// 逻辑层测试：SRS / 描红评分 / 出题。
///
/// 期望值全部照搬 Android `LogicTest.kt` 的断言，这样三端行为才是可证一致的，
/// 而不是「各自跑得通」。
@MainActor
final class LogicTests: XCTestCase {

    private var repo: Repo { TestRepo.make() }

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

    // MARK: - 多音字

    func testPolyphonesExist() {
        let repo = TestRepo.make()
        XCTAssertTrue(repo.isPolyphone("数"))
        XCTAssertFalse(repo.isPolyphone("天"))
        XCTAssertEqual(repo.allPolyphones.count, 156)
    }

    func testWordsUsingAlignsByPosition() {
        let repo = TestRepo.make()
        // 「数」读 shù 与 shǔ —— 「无数」是 shù，「数落」是 shǔ
        let shu4 = repo.wordsUsing("数", reading: "shù")
        let shu3 = repo.wordsUsing("数", reading: "shǔ")
        XCTAssertTrue(shu4.contains("无数"), "shù 应匹配到「无数」，实际 \(shu4)")
        XCTAssertTrue(shu3.contains("数落"), "shǔ 应匹配到「数落」，实际 \(shu3)")
        // 不能串音
        XCTAssertFalse(shu4.contains("数落"))
        XCTAssertFalse(shu3.contains("无数"))
    }

    func testPolyphoneQuestionHasRealWordContext() {
        let repo = TestRepo.make()
        _ = repo
        let r = Quiz.build(chars: ["乐"], book: "1a", count: 6,
                           seed: 12345, types: ["polyphone"])
        XCTAssertFalse(r.questions.isEmpty, "「乐」应该能出多音字题")
        for q in r.questions {
            XCTAssertEqual(q.type, "polyphone")
            // prompt 是用例词，必须真的包含这个字
            XCTAssertTrue(q.prompt.contains("乐"), "prompt 应是用例词，实际 \(q.prompt)")
            // 选项就是这个字自己的读音
            let opts = Set(q.options.map(\.value))
            XCTAssertTrue(opts.contains("yuè"))
            XCTAssertTrue(opts.contains("lè"))
            XCTAssertTrue(opts.contains(q.answer))
            // 解释里要列出两个读音
            XCTAssertTrue(q.explain.contains("多音字"))
        }
    }

    func testPolyphoneModeOnlyProducesPolyphoneQuestions() {
        let repo = TestRepo.make()
        _ = repo
        let prog = Progress(store: MemoryStore())
        let s = Plan.buildSession(mode: "polyphone", prog: prog, book: "1a")
        XCTAssertEqual(s.mode, "polyphone")
        XCTAssertFalse(s.chars.isEmpty)
        for ch in s.chars {
            XCTAssertTrue(repo.isPolyphone(ch), "\(ch) 不是多音字却被选进多音字模式")
        }
        let r = Quiz.build(chars: s.chars, book: "1a", count: s.count,
                           seed: 999, types: ["polyphone"])
        XCTAssertFalse(r.questions.isEmpty)
        XCTAssertTrue(r.questions.allSatisfy { $0.type == "polyphone" })
    }

    func testNormalQuizUnaffectedByPolyphoneType() {
        let repo = TestRepo.make()
        _ = repo
        // 不传 types 时题型轮转必须和以前完全一致（不含 polyphone）
        let r = Quiz.build(chars: ["天", "地", "人", "你", "我", "他"],
                           book: "1a", count: 8, seed: 12345)
        XCTAssertFalse(r.questions.isEmpty)
        XCTAssertFalse(r.questions.contains { $0.type == "polyphone" },
                       "普通闯关不应出现多音字题")
    }


    /// 三端一致性：同一个字表 + 同一个 seed，必须出完全相同的多音字题。
    ///
    /// 期望值取自小程序 `utils/quiz.js` 的实跑结果（seed=12345）。
    /// 三端各有一份独立的 mulberry32 和 shuffle，任何一处写歪这里都会红。
    func testPolyphoneMatchesMiniprogramForSameSeed() {
        let repo = TestRepo.make()
        _ = repo
        let r = Quiz.build(chars: ["乐", "数", "地", "没"], book: "1a", count: 6,
                           seed: 12345, types: ["polyphone"])
        let got = r.questions.map { "\($0.ch)|\($0.prompt)|\($0.answer)|\($0.options.map(\.value).joined(separator: "/"))" }
        let want = [
            "乐|乐曲|yuè|lè/yuè",
            "数|不可计数|shù|shǔ/shù",
            "地|地道|dì|dì/de",
            "没|没精打采|méi|méi/mò",
            "乐|欢乐|lè|yuè/lè",
            "数|不计其数|shù|shǔ/shù",
        ]
        XCTAssertEqual(got, want, "iOS 的多音字出题与小程序不一致：\n实际 \(got)\n期望 \(want)")
    }

    func testPolyphoneNoDuplicatePromptUntilWordsRunOut() {
        let repo = TestRepo.make()
        // 「乐」的用例词是有限的（乐器/乐曲/快乐/欢乐）。题数没超过可用词数时，
        // 绝不能出现重复题面；超过了就必然重复，那时允许重复但仍是同一批词。
        let available = repo.polyphoneCases("乐")
            .flatMap(\.words)
            .count
        XCTAssertGreaterThan(available, 1, "「乐」应该有多个用例词")

        let r = Quiz.build(chars: ["乐"], book: "1a", count: available,
                           seed: 777, types: ["polyphone"])
        let prompts = r.questions.map(\.prompt)
        XCTAssertEqual(Set(prompts).count, prompts.count,
                       "可用词还有富余时出现了重复题面：\(prompts)")

        // 词用完之后允许重复，但每道题的答案都必须是「乐」的真实读音之一
        let more = Quiz.build(chars: ["乐"], book: "1a", count: available + 3,
                              seed: 777, types: ["polyphone"])
        let valid = Set(repo.readingsOf("乐"))
        for q in more.questions {
            XCTAssertTrue(valid.contains(q.answer), "答案 \(q.answer) 不是「乐」的读音")
        }
    }


    // MARK: - 听写

    func testDictationLevelsDifferInPromptAndGhost() {
        // 三档的核心区别就两条：显示不显示底字、念什么
        XCTAssertTrue(DictationLevel.easy.showsGhost)
        XCTAssertFalse(DictationLevel.normal.showsGhost)
        XCTAssertFalse(DictationLevel.hard.showsGhost)

        XCTAssertEqual(DictationLevel.easy.promptText(ch: "天", word: "天空"), "天空")
        XCTAssertEqual(DictationLevel.normal.promptText(ch: "天", word: "天空"), "天空")
        // hard 只念字，不念词
        XCTAssertEqual(DictationLevel.hard.promptText(ch: "天", word: "天空"), "天")
        // 没有组词时退回念字，不能念空字符串
        XCTAssertEqual(DictationLevel.normal.promptText(ch: "天", word: nil), "天")
    }

    func testDictationPicksWriteCharsOnly() {
        let repo = TestRepo.make()
        let items = DictationSource.pick(book: "1a", level: .normal, limit: 8)
        XCTAssertEqual(items.count, 8)
        for it in items {
            // 听写只挑「会写」的字：只认不写的字（髓、嚼、蟹）要求默写没道理
            XCTAssertTrue(repo.isWriteChar(it.ch),
                          "\(it.ch) 是只认不写的字，不该进听写")
        }
    }

    func testDictationHardLevelHasNoWordHint() {
        let repo = TestRepo.make()
        _ = repo
        let items = DictationSource.pick(book: "1a", level: .hard, limit: 5)
        for it in items {
            XCTAssertNil(it.word, "hard 档不该带词语提示，否则等于告诉孩子答案")
        }
        let normal = DictationSource.pick(book: "1a", level: .normal, limit: 5)
        XCTAssertTrue(normal.contains { $0.word != nil }, "normal 档应该带词语")
    }

    func testDictationPlanAdvancesAndScores() {
        let plan = DictationPlan(level: .normal, items: [
            .init(ch: "天", word: "天空"),
            .init(ch: "地", word: "地方"),
        ])
        XCTAssertEqual(plan.index, 0)
        XCTAssertEqual(plan.current?.ch, "天")

        plan.record(ch: "天", score: 90)
        plan.advance()
        XCTAssertEqual(plan.current?.ch, "地")

        plan.record(ch: "地", score: 70)
        plan.advance()
        XCTAssertTrue(plan.isDone)
        XCTAssertNil(plan.current)

        XCTAssertEqual(plan.averageScore, 80)
        // 80 分对应 2 颗星（85 才是 3 颗）
        XCTAssertEqual(plan.stars, 2)
    }

    func testDictationEmptyPlanIsSafe() {
        let plan = DictationPlan(level: .normal, items: [])
        XCTAssertTrue(plan.isDone)
        XCTAssertNil(plan.current)
        XCTAssertNil(plan.averageScore)
        XCTAssertEqual(plan.stars, 0)
    }

    func testHideGhostSessionStillScores() {
        let repo = TestRepo.make()
        // 隐藏底字不改变判分：用完美笔迹写，分数必须和有底字时一样
        let withGhost = WriteSession(ch: "天", strokes: repo.strokes("天"),
                                     box: 400, hideGhost: false)
        let noGhost = WriteSession(ch: "天", strokes: repo.strokes("天"),
                                   box: 400, hideGhost: true)
        var a: [Int] = []
        var b: [Int] = []
        while !withGhost.isDone, let t = withGhost.targetPoints(for: withGhost.index) {
            _ = withGhost.submit(t)
        }
        while !noGhost.isDone, let t = noGhost.targetPoints(for: noGhost.index) {
            _ = noGhost.submit(t)
        }
        a.append(withGhost.finalScore)
        b.append(noGhost.finalScore)
        XCTAssertEqual(a, b, "隐藏底字不该影响判分")
    }


    // MARK: - 我的字帖

    func testWriteRecordsSortByRecentThenScore() {
        let prog = Progress(store: MemoryStore())
        prog.saveWrite("天", score: 90)
        prog.saveWrite("地", score: 50)
        prog.saveWrite("人", score: 90)

        let all = prog.allWriteRecords()
        XCTAssertEqual(all.count, 3)
        // 同一天写的按分数降序，同分的按字稳定排序（保证可复现）
        XCTAssertEqual(all.map { $0.ch }, ["人", "天", "地"])
        XCTAssertEqual(all.first?.record.best, 90)
    }

    func testWriteStarsHistogram() {
        let prog = Progress(store: MemoryStore())
        // 85/65/40 是星级门槛：>=85 三星、>=65 两星、>=40 一星
        prog.saveWrite("甲", score: 90)   // 3 星
        prog.saveWrite("乙", score: 85)   // 3 星
        prog.saveWrite("丙", score: 70)   // 2 星
        prog.saveWrite("丁", score: 39)   // 0 星

        let h = prog.writeStarsHistogram()
        XCTAssertEqual(h[3], 2)
        XCTAssertEqual(h[2], 1)
        XCTAssertEqual(h[1], 0)
        XCTAssertEqual(h[0], 1)
        XCTAssertEqual(prog.writeCount, 4)
    }

    func testWriteHistogramEmptyIsAllZero() {
        let prog = Progress(store: MemoryStore())
        let h = prog.writeStarsHistogram()
        // 四个档位都要有键：页面上直接取值画四格，缺键会读到 nil 变成空白
        for k in 0...3 { XCTAssertEqual(h[k], 0) }
        XCTAssertEqual(prog.writeCount, 0)
        XCTAssertTrue(prog.allWriteRecords().isEmpty)
    }


    // MARK: - 只认不写的字

    func testReadOnlyCharCount() {
        let repo = TestRepo.make()
        let all = repo.allChars
        let readOnly = all.filter { !repo.isWriteChar($0) }
        // 教材自带「会写」区分：2596 个字里 341 个只要求认识
        XCTAssertEqual(all.count, 2596)
        XCTAssertEqual(readOnly.count, 341)
        XCTAssertEqual(all.count - readOnly.count, 2255)
    }

    func testTypicalReadOnlyChars() {
        let repo = TestRepo.make()
        // 典型只认字：髓（4a）、嚼（3a）、蟹（2a）
        for ch in ["髓", "嚼", "蟹"] {
            XCTAssertFalse(repo.isWriteChar(ch), "\(ch) 不该要求会写")
            // 但仍然有笔顺数据，能描红——只是课标不要求
            XCTAssertNotNil(repo.strokes(ch), "\(ch) 应有笔顺数据")
        }
        XCTAssertTrue(repo.isWriteChar("天"))
    }


    // MARK: - 课文词语表

    func testTextbookWordCountIs1276() {
        let repo = TestRepo.make()
        // lessons[*].words 共 1276 条，之前三端一次都没读过
        var total = 0
        var booksWithWords = Set<String>()
        for b in repo.books {
            for lid in b.lessons {
                guard let l = repo.lesson(lid) else { continue }
                if !l.words.isEmpty {
                    total += l.words.count
                    booksWithWords.insert(l.book)
                }
            }
        }
        XCTAssertEqual(total, 1276)
        // 一年级课本没有单独的词语表，识字量还在积累——这是数据事实，不是缺失
        XCTAssertEqual(booksWithWords, ["2a", "2b", "3a", "3b", "4a", "4b"])
    }

    func testLessonWordsUseTextbookWhenAvailable() {
        let repo = TestRepo.make()
        let list = repo.lessonWords("2a-k1")
        XCTAssertFalse(list.isEmpty)
        XCTAssertTrue(list[0].fromTextbook)
        // 都带拼音
        for w in list {
            XCTAssertFalse(w.pinyin.isEmpty, "\(w.word) 缺拼音")
        }
    }

    func testLessonWordsFallBackForGradeOne() {
        let repo = TestRepo.make()
        // 一年级没有词语表，要用本课生字的组词兜底，不能返回空
        let list = repo.lessonWords("1a-s1")
        XCTAssertFalse(list.isEmpty, "一年级也应有词可练")
        XCTAssertFalse(list[0].fromTextbook)

        let lesson = repo.lesson("1a-s1")
        let chars = Set(lesson?.chars ?? [])
        for w in list {
            XCTAssertTrue(w.word.contains(where: { chars.contains(String($0)) }),
                          "\(w.word) 不含本课生字")
        }
    }

    func testBookWordsAreDeduped() {
        let repo = TestRepo.make()
        for b in ["1a", "2a", "3b"] {
            let list = repo.bookWords(b)
            XCTAssertGreaterThanOrEqual(list.count, 100, "\(b) 词语太少")
            XCTAssertEqual(Set(list.map(\.word)).count, list.count, "\(b) 词语有重复")
        }
    }

    func testWordQuizHasFourOptionsAndAnswerIncluded() {
        let repo = TestRepo.make()
        let r = Quiz.buildWordQuiz(repo: repo, book: "2a", count: 8, seed: 12345)
        XCTAssertEqual(r.questions.count, 8)

        var pinyins = Set<String>()
        for q in r.questions {
            XCTAssertEqual(q.type, "wordPinyin")
            XCTAssertEqual(q.options.count, 4, "每题应有 4 个选项")
            XCTAssertTrue(q.options.contains { $0.value == q.answer }, "答案必须在选项里")
            XCTAssertFalse(q.prompt.isEmpty)
            // 同一轮里题面不能重复，否则结果页会看到两道一样的题
            XCTAssertTrue(pinyins.insert(q.prompt).inserted, "重复题面：\(q.prompt)")
        }
    }

    func testWordQuizDistractorsAreNotHomophones() {
        let repo = TestRepo.make()
        let r = Quiz.buildWordQuiz(repo: repo, book: "2a", count: 10, seed: 99)
        for q in r.questions {
            for opt in q.options where opt.value != q.answer {
                // 干扰项不能和正确答案同音，否则这题无解
                XCTAssertNotEqual(repo.wordPinyin(opt.value), q.prompt)
            }
        }
    }

    func testWordQuizIsDeterministic() {
        let repo = TestRepo.make()
        let a = Quiz.buildWordQuiz(repo: repo, book: "2a", count: 6, seed: 7)
            .questions.map(\.answer)
        let b = Quiz.buildWordQuiz(repo: repo, book: "2a", count: 6, seed: 7)
            .questions.map(\.answer)
        XCTAssertEqual(a, b)
    }

    func testWordQuizEmptyBookIsSafe() {
        let repo = TestRepo.make()
        let r = Quiz.buildWordQuiz(repo: repo, book: "zz", count: 10, seed: 1)
        XCTAssertTrue(r.questions.isEmpty)
        XCTAssertTrue(r.targets.isEmpty)
    }

    func testWordQuizAnswersSplitIntoLearnableChars() {
        let repo = TestRepo.make()
        // 错题本、错字重练都按单字组织，整词塞进去会让结果页取不到 meta
        let r = Quiz.buildWordQuiz(repo: repo, book: "2a", count: 8, seed: 42)
        for q in r.questions {
            let parts = q.ch.count > 1 && repo.meta(q.ch) == nil
                ? q.ch.map(String.init).filter { repo.meta($0) != nil }
                : [q.ch]
            XCTAssertFalse(parts.isEmpty, "\(q.ch) 拆不出任何可学字")
            for ch in parts {
                XCTAssertNotNil(repo.meta(ch), "\(ch) 缺元数据")
            }
        }
    }

}
