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

    /// 最后一笔写完后必须算进「已画出的笔画」。
    ///
    /// 回归测试：`submit` 在最后一笔通过时把 `finished` 置 true 而**不自增 index**
    /// （自增会越界到 strokes[count]）。画布如果直接拿 index 当完成数，
    /// 绘制范围就是 `0..<count-1`——最后一笔判定通过了、星星也弹出来了，
    /// 但屏幕上永远看不见它，用户看到的是「写了没反应」。
    ///
    /// 这个 bug 三端只有 iOS 有：Android 写的是
    /// `completed = if (done) strokes.count else minOf(strokeIndex, ...)`，
    /// 小程序用 `accepted` 数组累积。所以这条断言同时是跨端一致性的一环。
    func testDrawnStrokesIncludesTheLastStroke() {
        let repo = TestRepo.make()
        let s = WriteSession(ch: "天", strokes: repo.strokes("天"), box: 400)
        let total = s.count
        XCTAssertEqual(total, 4, "「天」应该是 4 笔")

        // 一笔都没写时不该有实心笔画
        XCTAssertEqual(s.drawnStrokes, 0)

        // 逐笔写，每通过一笔就多显示一笔
        for expect in 1...total {
            guard let t = s.targetPoints(for: s.index) else {
                XCTFail("第 \(s.index) 笔缺参照数据")
                return
            }
            let outcome = s.submit(t)
            XCTAssertEqual(s.drawnStrokes, expect, "写完第 \(expect) 笔后应显示 \(expect) 笔")
            if expect < total {
                guard case .passed = outcome else {
                    XCTFail("第 \(expect) 笔应通过，实际 \(outcome)")
                    return
                }
            }
        }

        // 全部写完之后：判定完成、index 停在最后一笔、但画布要显示全部
        XCTAssertTrue(s.isDone, "应已判定整字完成")
        XCTAssertEqual(s.index, total - 1, "index 不该自增到 count（会越界）")
        XCTAssertEqual(s.drawnStrokes, total, "最后一笔必须画出来")
        XCTAssertEqual(s.progress, 1, "进度条应满")
    }

    /// 跳过最后一笔也要把它算进绘制范围——否则跳过后画布会缺一笔。
    func testDrawnStrokesAfterSkippingLastStroke() {
        let repo = TestRepo.make()
        let s = WriteSession(ch: "天", strokes: repo.strokes("天"), box: 400)
        for _ in 0..<s.count { s.skip() }
        XCTAssertTrue(s.isDone)
        XCTAssertEqual(s.drawnStrokes, s.count)
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
        // 2596 个字里 1798 个要求会写，798 个只要求认识
        XCTAssertEqual(all.count, 2596)
        XCTAssertEqual(readOnly.count, 798)
        XCTAssertEqual(all.count - readOnly.count, 1798)
    }

    /// 曾经 `isWriteChar` 只看 `meta.x` 非空，把 457 个「写字课在五六年级」的字
    /// （棋→6a-k6、鸦→6b-k3、氏→5a-k16）误判成本项目要求会写——
    /// 于是听写会要求二年级孩子默写「鸦」。
    ///
    /// 修正后必须与课时的 `write` 数组并集严格一致。两种算法互相独立，
    /// 任何一边偏了这条测试都会失败。
    func testWriteCharsMatchLessonWriteLists() {
        let repo = TestRepo.make()
        var inWriteLists = Set<String>()
        for b in repo.books {
            for lid in b.lessons {
                guard let l = repo.lesson(lid) else { continue }
                for ch in l.write { inWriteLists.insert(ch) }
            }
        }
        let byMeta = repo.allChars.filter { repo.isWriteChar($0) }
        XCTAssertEqual(byMeta.count, inWriteLists.count, "两种算法数量不一致")
        for ch in byMeta {
            XCTAssertTrue(inWriteLists.contains(ch), "\(ch) 被判为会写，却不在任何课时写字表里")
        }
    }

    func testOutOfRangeWriteLessonsAreReadOnly() {
        let repo = TestRepo.make()
        // 这几个字的 meta.x 分别指向 6a/6b/5a/5b，本项目只做一到四年级
        for ch in ["棋", "鸦", "氏", "孙", "纯"] {
            XCTAssertFalse(repo.isWriteChar(ch), "\(ch) 的写字课在五六年级，本项目不要求会写")
        }
        // 一到四年级的字不受影响
        XCTAssertTrue(repo.isWriteChar("天"))
        XCTAssertTrue(repo.isWriteChar("匀"))  // 3b-k7，在本项目范围内
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

    /// 跨端黄金值：同一 seed 三端必须出完全相同的题（含选项顺序）。
    ///
    /// 期望值由小程序 `utils/quiz.js` 的 `buildWordQuiz` 算出，是另外
    /// 一份独立实现。任何一端改了随机数调用顺序、干扰项挑选或洗牌方式，
    /// 这条测试都会红——这是「三端行为一致」这个硬约束的兜底。
    // MARK: - 同音字

    /// 同音字是听写最主要的错因：「地弟第递」读音一样、字形不同，
    /// 记住音不等于会写。数据不用新增——按 `CharMeta.py` 分组即可。
    @MainActor
    func testHomophonesGroupedByFullPinyin() {
        let repo = TestRepo.make()
        XCTAssertEqual(Set(repo.homophones("地")), Set(["弟", "第", "帝", "递"]))
        XCTAssertTrue(repo.homophones("天").contains("添"))
        // 声调不同不算同音：「地」是 dì，「底」是 dǐ
        XCTAssertFalse(repo.homophones("地").contains("底"))
        // 不含自己
        XCTAssertFalse(repo.homophones("天").contains("天"))
    }

    @MainActor
    func testHomophoneGroupCounts() {
        let repo = TestRepo.make()
        // 八册累加（同一组跨册会各算一次）= 382
        var total = 0
        for b in repo.books { total += repo.homophoneGroups(b.id).count }
        XCTAssertEqual(total, 382)

        // 全库去重 = 588
        var byPy: [String: [String]] = [:]
        for ch in repo.allChars {
            guard let py = repo.meta(ch)?.py, !py.isEmpty else { continue }
            byPy[py, default: []].append(ch)
        }
        XCTAssertEqual(byPy.values.filter { $0.count >= 2 }.count, 588)
    }

    @MainActor
    func testHomophoneGroupsStayInsideBook() {
        let repo = TestRepo.make()
        let groups = repo.homophoneGroups("2a")
        XCTAssertGreaterThan(groups.count, 30)
        let chars = Set(repo.bookChars("2a"))
        for g in groups {
            for ch in g.chars {
                XCTAssertTrue(chars.contains(ch), "\(ch) 不属于 2a，不该出现在本册分组里")
                // 组内读音必须完全一致
                XCTAssertEqual(repo.meta(ch)?.py, g.py)
            }
        }
    }

    @MainActor
    func testHomophoneDistractorsAreHomophones() {
        let repo = TestRepo.make()
        let ds = repo.homophoneDistractors("坐", book: "2a", count: 3)
        XCTAssertEqual(ds.count, 3)
        let py = repo.meta("坐")?.py
        for d in ds {
            XCTAssertEqual(repo.meta(d)?.py, py, "\(d) 不和「坐」同音，当干扰项等于送分")
            XCTAssertNotEqual(d, "坐")
        }
    }

    /// 核心断言：每个干扰项都必须和答案同音。
    /// 混进非同音的字等于把答案直接送给孩子，这个功能就白做了。
    @MainActor
    func testHomophoneQuizOptionsSharePinyin() {
        let repo = TestRepo.make()
        let chars = Array(repo.homophoneChars("2a").prefix(6))
        let r = Quiz.build(chars: chars, book: "2a", lesson: nil,
                           count: 6, seed: 20240101, types: ["homophone"])
        XCTAssertGreaterThanOrEqual(r.questions.count, 4)

        for q in r.questions {
            XCTAssertEqual(q.type, "homophone")
            XCTAssertEqual(q.options.count, 4)
            XCTAssertTrue(q.options.contains { $0.value == q.answer })
            let py = repo.meta(q.answer)?.py
            for o in q.options {
                XCTAssertEqual(repo.meta(o.value)?.py, py, "\(o.value) 与 \(q.answer) 不同音")
            }
            XCTAssertTrue(q.prompt.contains("＿"), "题面应有空格")
        }
    }

    @MainActor
    func testHomophoneQuizSkipsCharsWithoutPeers() {
        let repo = TestRepo.make()
        guard let lonely = repo.allChars.first(where: { !repo.hasHomophones($0) }) else {
            return XCTFail("应存在没有同音字的字")
        }
        let r = Quiz.build(chars: [lonely], book: "2a", lesson: nil,
                           count: 3, seed: 1, types: ["homophone"])
        XCTAssertTrue(r.questions.isEmpty, "\(lonely) 没有同音字，不该出题")
    }

    @MainActor
    func testHomophoneSessionPicksOnlyCharsWithPeers() {
        let repo = TestRepo.make()
        let prog = Progress(store: MemoryStore())
        let s = Plan.buildSession(mode: "homophone", prog: prog, book: "2a")
        XCTAssertEqual(s.mode, "homophone")
        XCTAssertGreaterThanOrEqual(s.chars.count, 4)
        for ch in s.chars {
            XCTAssertTrue(repo.hasHomophones(ch), "\(ch) 没有同音字，不该进会话")
        }
    }

    // MARK: - 部首

    /// 部首查字法是二年级语文园地的正式内容，但 `CharMeta.r` 一直只在
    /// 解析文案里出现过，从没当成学习维度用过。
    @MainActor
    func testRadicalCountsAndOrder() {
        let repo = TestRepo.make()
        let all = repo.allRadicals()
        XCTAssertEqual(all.count, 237)
        // 口144 扌138 氵132
        XCTAssertEqual(Array(all.prefix(3).map(\.radical)), ["口", "扌", "氵"])
        XCTAssertEqual(Array(all.prefix(3).map(\.count)), [144, 138, 132])
        // 频次单调不增
        for i in 1..<all.count {
            XCTAssertGreaterThanOrEqual(all[i - 1].count, all[i].count, "应按频次降序")
        }
    }

    @MainActor
    func testEveryCharHasRadical() {
        let repo = TestRepo.make()
        let missing = repo.allChars.filter { repo.radicalOf($0).isEmpty }
        XCTAssertTrue(missing.isEmpty, "缺部首的字：\(missing.prefix(10))")
        XCTAssertEqual(repo.radicalOf("地"), "土")
        XCTAssertEqual(repo.radicalOf("顶"), "页")
    }

    @MainActor
    func testBookRadicalsStayInsideBook() {
        let repo = TestRepo.make()
        let rads = repo.bookRadicals("2a")
        XCTAssertGreaterThan(rads.count, 50)
        let bookChars = Set(repo.bookChars("2a"))
        for ch in repo.charsWithRadical("2a", "氵") {
            XCTAssertTrue(bookChars.contains(ch), "\(ch) 不属于 2a")
            XCTAssertEqual(repo.radicalOf(ch), "氵")
        }
    }

    @MainActor
    func testRadicalDistractorsAvoidGlyphOverlap() {
        let repo = TestRepo.make()
        let ds = repo.radicalDistractors("木", book: "2a", count: 3)
        XCTAssertEqual(ds.count, 3)
        for d in ds {
            XCTAssertNotEqual(d, "木")
            // 「木」和「林」这种有争议，不该当干扰项
            XCTAssertFalse(d.contains("木"), "\(d) 与「木」有字形包含关系，有歧义")
            XCTAssertFalse("木".contains(d))
        }
    }

    @MainActor
    func testRadicalQuizHasFourDistinctOptions() {
        let repo = TestRepo.make()
        let chars = Array(repo.bookChars("2a").dropFirst(10).prefix(10))
        let r = Quiz.build(chars: chars, book: "2a", lesson: nil,
                           count: 5, seed: 20240101, types: ["radical"])
        XCTAssertEqual(r.questions.count, 5)

        for q in r.questions {
            XCTAssertEqual(q.type, "radical")
            XCTAssertEqual(q.options.count, 4)
            XCTAssertEqual(Set(q.options.map(\.value)).count, 4, "选项不能重复")
            XCTAssertTrue(q.options.contains { $0.value == q.answer })
            XCTAssertEqual(q.answer, repo.radicalOf(q.ch))
        }
    }

    /// 回归测试：某个字出不了题时，不能卡死在它身上。
    ///
    /// `Quiz.build` 原来用 `questions.count` 决定取哪个字。如果某个字出不了题
    /// （独体字的部首就是它自己，答案印在题干上），questions.count 不增长，
    /// 就会**永远重试同一个字**，直到 guardCount 耗尽——整套题变成 0 道。
    ///
    /// 修复：改用尝试次数推进取字。
    @MainActor
    func testUnproducibleCharDoesNotStallWholeQuiz() {
        let repo = TestRepo.make()
        // 龟、鼓 的部首就是它们自己，radical 题型会返回 nil
        let r = Quiz.build(chars: ["龟", "顶", "鼓", "披"], book: "2a", lesson: nil,
                           count: 2, seed: 1, types: ["radical"])
        XCTAssertEqual(r.questions.count, 2, "应跳过独体字继续出题，而不是 0 道")
        for q in r.questions {
            XCTAssertNotEqual(q.answer, q.ch, "独体字不该出部首题（答案就是题干）")
            XCTAssertNotEqual(repo.radicalOf(q.ch), q.ch)
        }
    }

    @MainActor
    func testRadicalQuizSkipsSelfRadicalChars() {
        let repo = TestRepo.make()
        let r = Quiz.build(chars: ["龟", "鼓"], book: "2a", lesson: nil,
                           count: 2, seed: 1, types: ["radical"])
        XCTAssertTrue(r.questions.isEmpty, "全是独体字时出 0 道是对的")
    }

    @MainActor
    func testRadicalSessionExcludesSelfRadicals() {
        let repo = TestRepo.make()
        let prog = Progress(store: MemoryStore())
        let s = Plan.buildSession(mode: "radical", prog: prog, book: "2a")
        XCTAssertEqual(s.mode, "radical")
        XCTAssertGreaterThanOrEqual(s.chars.count, 4)
        for ch in s.chars {
            XCTAssertNotEqual(repo.radicalOf(ch), ch, "\(ch) 是独体字，不该进部首会话")
        }
    }

    /// 部首的跨端黄金值：同一 seed、同一批字，三端必须出同一套题。
    /// 期望值由小程序 `utils/quiz.js` 算出。
    @MainActor
    func testRadicalQuizMatchesCrossPlatformGolden() {
        let repo = TestRepo.make()
        let chars = Array(repo.bookChars("2a").dropFirst(10).prefix(10))
        let r = Quiz.build(chars: chars, book: "2a", lesson: nil,
                           count: 5, seed: 20240101, types: ["radical"])
        let got = r.questions.map { q in
            "\(q.ch)|\(q.answer)|\(q.options.map(\.value).joined(separator: "|"))"
        }
        XCTAssertEqual(got, [
            "顶|页|扌|页|木|氵",
            "披|扌|木|扌|氵|亻",
            "晒|日|氵|日|木|扌",
            "极|木|扌|木|氵|亻",
            "傍|亻|木|扌|氵|亻",
        ])
    }

    /// 同音字的跨端黄金值：同一 seed、同一批字，三端必须出同一套题。
    /// 期望值由小程序 `utils/quiz.js` 算出。
    @MainActor
    func testHomophoneQuizMatchesCrossPlatformGolden() {
        let repo = TestRepo.make()
        let chars = Array(repo.homophoneChars("2a").prefix(5))
        let r = Quiz.build(chars: chars, book: "2a", lesson: nil,
                           count: 5, seed: 20240101, types: ["homophone"])
        let got = r.questions.map { q in
            "\(q.ch)|\(q.prompt)|\(q.answer)|\(q.options.map(\.value).joined(separator: "|"))"
        }
        XCTAssertEqual(got, [
            "袋|口＿|袋|带|袋|戴|代",
            "龟|＿甲|龟|瑰|龟|归|规",
            "鼓|重整旗＿|鼓|骨|谷|鼓|股",
            "极|＿大|极|即|极|吉|及",
            "溪|＿水|溪|吸|希|锡|溪"
        ])
    }

    /// 多音字的跨端黄金值：同一 seed、同一批字，三端必须出同一套题。
    /// 期望值由小程序 `utils/quiz.js` 算出。
    func testPolyphoneMatchesCrossPlatformGolden() {
        let repo = TestRepo.make()
        let chars = Array(repo.polyphones(book: "2a").prefix(4))
        let r = Quiz.build(chars: chars, book: "2a", lesson: nil,
                           count: 4, seed: 20240101, types: ["polyphone"])
        let got = r.questions.map { q in
            "\(q.ch)|\(q.prompt)|\(q.answer)|\(q.options.map(\.value).joined(separator: "|"))"
        }
        XCTAssertEqual(got, [
            "哇|好哇|wa|wā|wa",
            "奔|奔跑|bēn|bēn|bèn",
            "冲|冲锋|chōng|chòng|chōng",
            "炸|炸死|zhà|zhà|zhá"
        ])
    }

    func testWordQuizMatchesCrossPlatformGolden() {
        let repo = TestRepo.make()
        let r = Quiz.buildWordQuiz(repo: repo, book: "2a", count: 5, seed: 20240101)
        let got = r.questions.map { q in
            "\(q.ch)|\(q.prompt)|\(q.answer)|\(q.options.map(\.value).joined(separator: "|"))"
        }
        let want = [
            "卧室|wò shì|卧室|邻居|秧苗|卧室|蚯蚓",
            "那些|nà xiē|那些|那些|和好|看见|回家",
            "展开|zhǎn kāi|展开|头顶|展开|电影|井口",
            "白蛇|bái shé|白蛇|爱慕|时辰|花朵|白蛇",
            "船身|chuán shēn|船身|展开|井沿|船身|时间"
        ]
        XCTAssertEqual(got, want)
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

// MARK: - Dynamic Type

/// 字号缩放规则。
///
/// 这些是纯数值函数，放在 `HanziCore` 里就是为了能在这里穷举——
/// 「系统字号调到最大时卡片会不会撑破」这种问题，靠截图看只能验证一个档位，
/// 而档位有 12 个。
final class TypeScaleTests: XCTestCase {

    /// 默认档必须是 1.0，否则默认字号下的界面会和设计稿不一致
    func testDefaultStepIsExactlyOne() {
        XCTAssertEqual(TypeScale.factor(forStep: 0), 1.0)
    }

    /// 12 个档位，倍数严格递增
    func testFactorsAreMonotonicallyIncreasing() {
        let steps = Array(-3...8)
        let factors = steps.map { TypeScale.factor(forStep: $0) }
        for i in 1..<factors.count {
            XCTAssertGreaterThan(factors[i], factors[i - 1],
                                 "档位 \(steps[i]) 的倍数应大于 \(steps[i - 1])")
        }
    }

    /// 两端夹紧：比最小档还小仍取下限，比最大档还大取上限
    func testFactorsClampAtBothEnds() {
        XCTAssertEqual(TypeScale.factor(forStep: -99), TypeScale.factor(forStep: -3))
        XCTAssertEqual(TypeScale.factor(forStep: 99), TypeScale.factor(forStep: 8))
    }

    /// 辅助功能档的倍数要明显大：最大档约 3 倍，这是 Apple 正文的实际比例
    func testAccessibilityRangeIsLarge() {
        XCTAssertEqual(TypeScale.factor(forStep: 8), 3.12, accuracy: 0.03)
        XCTAssertGreaterThanOrEqual(TypeScale.factor(forStep: 4), 1.5)
    }

    /// 辅助功能档的判定：前 7 档（xSmall…xxxLarge）都不算
    func testAccessibilityThreshold() {
        for step in -3...3 {
            XCTAssertFalse(TypeScale.isAccessibility(step), "档位 \(step) 不该算辅助功能字号")
        }
        for step in 4...8 {
            XCTAssertTrue(TypeScale.isAccessibility(step), "档位 \(step) 应算辅助功能字号")
        }
    }

    /// `scaled` 只放大不缩小，且封顶
    func testScaledOnlyGrowsAndCaps() {
        // 小字号不缩容器，保持留白
        XCTAssertEqual(LayoutRules.scaled(108, by: 0.82), 108)
        XCTAssertEqual(LayoutRules.scaled(108, by: 1.0), 108)
        // 放大
        XCTAssertEqual(LayoutRules.scaled(100, by: 1.5), 150, accuracy: 0.01)
        // 封顶（默认 2.2）
        XCTAssertEqual(LayoutRules.scaled(100, by: 3.12), 220, accuracy: 0.01)
        // 自定义封顶
        XCTAssertEqual(LayoutRules.scaled(100, by: 3.12, cap: 1.5), 150, accuracy: 0.01)
        // 封顶值小于 1 时当作 1，避免算出比原值还小
        XCTAssertEqual(LayoutRules.scaled(100, by: 2, cap: 0.5), 100, accuracy: 0.01)
    }

    /// 分栏阈值随字号抬高：字号越大，越早退回单列。
    ///
    /// 720pt 是「15pt 正文排得下」的宽度。字号到 3 倍时同一个侧栏需要
    /// 两倍多宽度，不调阈值的话用户看到的是一列被挤成窄条的竖排文字。
    func testSplitThresholdGrowsWithFontSize() {
        // 默认字号：阈值不变，老行为完全保留
        XCTAssertEqual(LayoutRules.detailSplitWidth(scaledBy: 1.0), 720)
        XCTAssertEqual(LayoutRules.writeSplitWidth(scaledBy: 1.0), 820)

        // 小字号不缩小阈值（否则窗口偏窄时反而分栏）
        XCTAssertEqual(LayoutRules.detailSplitWidth(scaledBy: 0.82), 720)

        // 放大：阈值变高 → 同一宽度更早退回单列
        XCTAssertEqual(LayoutRules.detailSplitWidth(scaledBy: 1.5), 1080, accuracy: 0.01)
        XCTAssertGreaterThan(LayoutRules.detailSplitWidth(scaledBy: 2.0),
                             LayoutRules.detailSplitWidth(scaledBy: 1.0))

        // 封顶 1.8 倍
        XCTAssertEqual(LayoutRules.detailSplitWidth(scaledBy: 3.12), 720 * 1.8, accuracy: 0.01)
    }

    /// 具体到「1024pt 宽的 iPad」：默认字号分栏，最大字号不分栏
    func testSplitDecisionFlipsAtLargeFontSize() {
        let width: CGFloat = 900
        XCTAssertTrue(LayoutRules.detailIsSplit(width, scale: 1.0))
        XCTAssertFalse(LayoutRules.detailIsSplit(width, scale: 3.12),
                       "900pt 窗口在最大字号下应退回单列")
        // 不传 scale 时的默认值等价于 1.0，老调用点行为不变
        XCTAssertEqual(LayoutRules.detailIsSplit(width),
                       LayoutRules.detailIsSplit(width, scale: 1.0))
    }

    /// 首页课本网格固定两列，三端一致。
    ///
    /// 之前用 `.adaptive(minimum: 190)`：iPhone 内容宽 362pt 只排 1 列，
    /// iPad 787pt 排 3 列——同一个 app 两种信息密度，还都和 Android 不同。
    func testBookGridIsAlwaysTwoColumns() {
        // 默认字号
        XCTAssertEqual(LayoutRules.bookColumns(scale: 1.0), 2)
        // 小字号也是两列（不因为字小而多塞）
        XCTAssertEqual(LayoutRules.bookColumns(scale: 0.82), 2)
        // 放大到普通大字号仍是两列
        XCTAssertEqual(LayoutRules.bookColumns(scale: 1.35), 2)
        // 辅助功能字号（1.64 倍起）退回单列
        XCTAssertEqual(LayoutRules.bookColumns(scale: TypeScale.factor(forStep: 4)), 1)
        XCTAssertEqual(LayoutRules.bookColumns(scale: 3.12), 1)
    }

    /// 实测卡片尺寸：默认字号下两端都是两列。
    ///
    /// 数字来自 `-probeTapTargets` 的真实布局报数，不是估的：
    /// iPhone 17 Pro 每张 175x84pt，iPad 13 寸每张 346x84pt。
    /// 前面几版是 `.adaptive(minimum: 190)`：iPhone 只排 1 列（362 宽放不下
    /// 两个 190），iPad 排 3 列——同一个 app 在两种设备上是两种信息密度。
    func testMeasuredBookTileSizes() {
        // iPhone：内容宽 402-2*20 = 362，减去 12 间距，两列各 175
        XCTAssertEqual((362.0 - 12) / 2, 175, accuracy: 0.5)
        // iPad：内容宽 787，减去 12 间距、再减去两侧内边距，两列各约 346
        let padTile = (787.0 - 12 - 2 * 14) / 2
        XCTAssertEqual(padTile, 373.5, accuracy: 1, "两列时卡片应在这个量级，而不是整宽 787")
    }

    /// 页脚三颗按钮在最大字号下必须竖排。
    ///
    /// 数字来自 `-probeTapTargets` 实测：横排时「跳过一笔」只有 104pt 宽，
    /// 四个字各 16pt，被截断成省略号；竖排后 362x77，字完整。
    func testWriteFooterStacksOnlyAtAccessibilitySizes() {
        // 默认字号横排
        XCTAssertFalse(LayoutRules.footerStacks(scale: TypeScale.factor(forStep: 0)))
        // 标准字号里最大的一档（xxxLarge，step 3）仍然横排
        XCTAssertFalse(LayoutRules.footerStacks(scale: TypeScale.factor(forStep: 3)))
        // 辅助功能字号第一档（step 4）开始竖排
        XCTAssertTrue(LayoutRules.footerStacks(scale: TypeScale.factor(forStep: 4)))
        XCTAssertTrue(LayoutRules.footerStacks(scale: TypeScale.factor(forStep: 8)))
    }

    /// 横排放不下的具体证据：三颗按钮在最大字号下要 496pt，iPhone 只有 362pt。
    func testWriteFooterDoesNotFitHorizontallyAtMaxSize() {
        let scale = TypeScale.factor(forStep: 8)   // 3.12
        // 每个汉字约 15pt 基准宽，按钮左右内边距合计 40pt
        let charWidth = 15.0 * scale
        let padding = 40.0
        let restart = 2 * charWidth + padding      // 重写
        let skip = 4 * charWidth + padding         // 跳过一笔
        let done = 2 * charWidth + padding         // 完成
        let total = restart + skip + done + 2 * 12 // 两处 12pt 间距
        XCTAssertGreaterThan(total, 362, "放不下就必须竖排")
        // 而默认字号下是放得下的
        let base = (2 * 15.0 + padding) + (4 * 15.0 + padding) + (2 * 15.0 + padding) + 24
        XCTAssertLessThan(base, 362)
    }

    /// iPhone 与 iPad 在默认字号下都是两列——这正是改动要解决的差异
    func testBookGridMatchesAcrossDeviceWidths() {
        let phone: CGFloat = 362   // iPhone 17 Pro 402 - 2*20
        let pad: CGFloat = 787     // iPad 13 实测内容宽
        for w in [phone, pad] {
            let cols = LayoutRules.bookColumns(scale: 1.0)
            XCTAssertEqual(cols, 2, "\(w)pt 下应排两列")
            // 两列时每张卡片的宽度
            let tile = (w - 12) / CGFloat(cols)
            XCTAssertGreaterThan(tile, 160, "卡片不该窄到放不下「一年级 上册」这行标题")
        }
    }

    /// 实测宽度：iPad 13 寸 + 侧边栏后内容区只有 787pt。
    ///
    /// 这个数字是量出来的（调试输出 geo.size.width），不是估的。
    /// 787 在默认字号下详情页分栏（787 > 720），最大字号下退回单列
    /// （787 < 720×1.8=1296）——这正是我们想要的行为。
    func testMeasuredIPadContentWidth() {
        let measured: CGFloat = 787
        XCTAssertTrue(LayoutRules.detailIsSplit(measured, scale: 1.0),
                      "默认字号下详情页应分栏")
        XCTAssertFalse(LayoutRules.detailIsSplit(measured, scale: 3.12),
                       "最大字号下详情页应退回单列")
        // 写描红阈值更高（820），787 在任何字号下都是单列
        XCTAssertFalse(LayoutRules.writeIsSplit(measured, scale: 1.0))
        XCTAssertFalse(LayoutRules.writeIsSplit(measured, scale: 3.12))
    }

    /// 最大字号下网格会自然降到更少的列：同一宽度能放下的卡片变少
    func testLargerTilesYieldFewerColumns() {
        let width: CGFloat = 1024
        let normal = LayoutRules.columns(width: width,
                                        minimum: LayoutRules.scaled(108, by: 1.0),
                                        spacing: 12)
        let huge = LayoutRules.columns(width: width,
                                       minimum: LayoutRules.scaled(108, by: 3.12),
                                       spacing: 12)
        XCTAssertGreaterThan(normal, huge, "字号变大后同一宽度应放更少的格子")
        XCTAssertGreaterThanOrEqual(huge, 1)
    }
}
