import XCTest
@testable import HanziCore

/// 识字量测试。
///
/// 家长最想知道的一个数字是「我家孩子认识多少字」。原来的 app 只能回答
/// 「学过多少字」——那是点过多少个字，不是认识多少。
///
/// 抽测的关键是**抽样要覆盖整册**，不能只考最基础的几个字，否则估出来的
/// 数会虚高。以及估算必须是可复现的纯函数。
///
/// 与小程序 `tests/vocab.test.mjs`、Android `VocabTest` 对应。
@MainActor
final class VocabTests: XCTestCase {

    override func setUp() {
        super.setUp()
        _ = TestRepo.make()
    }

    /// 小程序 `vocab.buildTest({seed:1})` 的输出，三端必须逐字相同
    private let goldenSeed1 =
        "八南众到旁|万单食呢奇|舰锅留福折|蒙易坦件由|橘吞阁库瓦|释智痒警呕|震兰返怖签|冠践稿絮遣"

    func testEachBookSamplesFive() {
        let t = Vocab.buildTest(seed: 20240101)
        XCTAssertEqual(Vocab.perBook, 5)
        XCTAssertEqual(t.groups.count, 8)
        XCTAssertEqual(t.total, 40)
        for g in t.groups {
            XCTAssertEqual(g.questions.count, 5, "\(g.book) 应该抽 5 个")
        }
    }

    func testSampledCharsBelongToBookAndHavePinyin() {
        let t = Vocab.buildTest(seed: 42)
        for g in t.groups {
            let inBook = Set(Repo.shared.bookChars(g.book))
            for q in g.questions {
                XCTAssertTrue(inBook.contains(q.ch), "\(q.ch) 不属于 \(g.book)")
                let py = Repo.shared.meta(q.ch)!.py
                XCTAssertGreaterThan(py.count, 1, "\(q.ch) 没有拼音")
                XCTAssertEqual(q.answer, py)
            }
        }
    }

    /// 只取前 5 个等于只考「日月水火」这种最基础的字，估出来的数会虚高
    func testSamplingCoversWholeBook() {
        let t = Vocab.buildTest(seed: 7)
        for g in t.groups {
            let all = Repo.shared.bookChars(g.book)
            let idx = g.questions.map { all.firstIndex(of: $0.ch)! }
            XCTAssertGreaterThan(idx.max()!, all.count / 2,
                                 "\(g.book) 的抽样都落在前一半")
        }
    }

    func testDifferentSeedsSampleDifferentChars() {
        let a = Vocab.buildTest(seed: 1)
        let b = Vocab.buildTest(seed: 2)
        let sa = a.groups.map { $0.questions.map(\.ch).joined() }.joined()
        let sb = b.groups.map { $0.questions.map(\.ch).joined() }.joined()
        XCTAssertNotEqual(sa, sb)
    }

    func testSameSeedIsReproducible() {
        XCTAssertEqual(dump(Vocab.buildTest(seed: 99)), dump(Vocab.buildTest(seed: 99)))
    }

    /// 三端各自实现了一份抽样+RNG，只测「同 seed 可复现」不够——
    /// 那样即使某一端的 mulberry32 写错了也能通过。这里锁死实际输出的字。
    func testSamplingMatchesGoldenValue() {
        let t = Vocab.buildTest(seed: 1)
        let got = t.groups.map { $0.questions.map(\.ch).joined() }.joined(separator: "|")
        XCTAssertEqual(got, goldenSeed1)
    }

    func testFourDistinctPinyinOptions() {
        let t = Vocab.buildTest(seed: 20240101)
        for g in t.groups {
            for q in g.questions {
                XCTAssertEqual(q.options.count, 4)
                XCTAssertTrue(q.options.contains { $0.value == q.answer })
                XCTAssertEqual(Set(q.options.map(\.value)).count, 4,
                               "\(q.ch) 的选项有重复读音")
            }
        }
    }

    /// 多音字的其他读音当干扰项会变成「有两个正确答案」
    func testPolyphoneOtherReadingsNeverDistract() {
        let t = Vocab.buildTest(seed: 5)
        for g in t.groups {
            for q in g.questions {
                let all = Set(Repo.shared.readingsOf(q.ch))
                for o in q.options where o.value != q.answer {
                    XCTAssertFalse(all.contains(o.value),
                                   "\(q.ch) 的干扰项 \(o.value) 也是它的读音")
                }
            }
        }
    }

    func testAllCorrectReachesLibraryTotal() {
        let t = Vocab.buildTest(seed: 1)
        let e = Vocab.estimate(t, answers: Array(repeating: true, count: t.total))
        XCTAssertEqual(e.size, Repo.shared.allChars.count)
        XCTAssertEqual(e.level, "4b")
        XCTAssertTrue(e.done)
    }

    func testAllWrongStopsAtFirstBook() {
        let t = Vocab.buildTest(seed: 1)
        let e = Vocab.estimate(t, answers: Array(repeating: false, count: t.total))
        XCTAssertEqual(e.size, 0)
        XCTAssertEqual(e.stopBook, "1a")
        XCTAssertEqual(e.answered, 5, "第一册问完就该停")
    }

    func testOnlyFirstBookStopsAtSecond() {
        let t = Vocab.buildTest(seed: 1)
        var answers: [Bool] = []
        for g in t.groups {
            answers.append(contentsOf: Array(repeating: g.book == "1a", count: g.questions.count))
        }
        let e = Vocab.estimate(t, answers: answers)
        XCTAssertEqual(e.stopBook, "1b")
        // 1a 满分 → 300 字左右
        XCTAssertTrue((251...300).contains(e.size), "估算 \(e.size) 不合理")
        XCTAssertEqual(e.level, "1a")
    }

    /// 停下的册次之后是还没学到的部分，按更低比例折算会把估算压成没意义的数
    func testBooksAfterStopAreNotCounted() {
        let t = Vocab.buildTest(seed: 3)
        let e = Vocab.estimate(t, answers: Array(repeating: false, count: t.total))
        for g in e.groups where g.book != "1a" {
            XCTAssertFalse(g.counted, "\(g.book) 不该被计入")
            XCTAssertEqual(g.contribution, 0)
        }
    }

    func testUnaskedBooksAreNotCounted() {
        let t = Vocab.buildTest(seed: 8)
        let e = Vocab.estimate(t, answers: Array(repeating: true, count: 7))
        XCTAssertFalse(e.done)
        XCTAssertEqual(e.answered, 7)
        let g2a = e.groups.first { $0.book == "2a" }!
        XCTAssertEqual(g2a.asked, 0)
        XCTAssertEqual(g2a.contribution, 0)
    }

    func testEstimateScalesWithRate() {
        let t = Vocab.buildTest(seed: 4)
        var answers: [Bool] = []
        for g in t.groups {
            for i in 0..<g.questions.count { answers.append(i < 3) }
        }
        let e = Vocab.estimate(t, answers: answers)
        XCTAssertEqual(e.stopBook, "", "六成不该提前停")
        let total = Repo.shared.allChars.count
        XCTAssertTrue(e.size > total / 2 && e.size < total * 3 / 4,
                      "六成正确率估出 \(e.size)/\(total)，不合理")
    }

    func testSizeLabelRounds() {
        XCTAssertEqual(Vocab.sizeLabel(0), "0")
        XCTAssertEqual(Vocab.sizeLabel(45), "45")
        XCTAssertEqual(Vocab.sizeLabel(712), "约 700")
        XCTAssertEqual(Vocab.sizeLabel(760), "约 800")
        XCTAssertEqual(Vocab.sizeLabel(2596), "约 2600")
    }

    func testVerdictTiersIncrease() {
        let marks = [200, 600, 1200, 2000, 2596]
        let texts = marks.map { Vocab.verdict($0) }
        for i in 1..<marks.count {
            XCTAssertNotEqual(texts[i], texts[i - 1], "\(marks[i]) 和 \(marks[i - 1]) 的评价一样")
        }
        // 不足 100 字统一算「刚开始」——0 字和 50 字对家长没有区分意义
        XCTAssertEqual(Vocab.verdict(0), Vocab.verdict(50))
        XCTAssertTrue(Vocab.verdict(50).contains("刚"))
        XCTAssertTrue(Vocab.verdict(2596).contains("章节书"))
    }

    func testVocabSizePersists() {
        let store = MemoryStore()
        let prog = Progress(store: store)
        prog.resetAll()
        XCTAssertEqual(prog.vocabSize, 0)
        prog.setVocabSize(712)
        XCTAssertEqual(prog.vocabSize, 712)
        // 0 不覆盖已有结果
        prog.setVocabSize(0)
        XCTAssertEqual(prog.vocabSize, 712)
        prog.resetAll()
    }

    func testVocabSizeIsolatedPerProfile() {
        let store = MemoryStore()
        let pm = ProfileManager(store: store)
        let prog = Progress(store: store)
        prog.resetAll()
        prog.setVocabSize(800)

        let p = pm.add("弟弟")!
        pm.setActive(p.id)
        prog.reload()
        XCTAssertEqual(prog.vocabSize, 0, "弟弟不该看到哥哥的测试结果")

        pm.setActive("")
        prog.reload()
        XCTAssertEqual(prog.vocabSize, 800)
        prog.resetAll()
    }

    private func dump(_ t: Vocab.Test) -> String {
        t.groups.map { g in
            g.questions.map { q in q.ch + q.options.map(\.value).joined(separator: ",") }.joined()
        }.joined(separator: "|")
    }
}
