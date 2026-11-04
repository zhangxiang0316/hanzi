import XCTest
@testable import HanziCore

/// 数据层测试。
///
/// 期望值全部来自 Android 侧已验证的数字（2600 生字 / 2596 唯一 / 8 册 / 276 课 / 64 单元），
/// 这样两边的数据理解才是可证一致的，而不是「看起来能跑」。
@MainActor
final class RepoTests: XCTestCase {

    /// 测试用 Repo：直接读源码目录里的 Resource，不走 Bundle
    private static var _repo: Repo?

    /// 延迟初始化：@MainActor 的类不能在 class setUp 里构造
    private var repo: Repo { TestRepo.make() }

    // MARK: - 书与课

    func testEightBooks() {
        XCTAssertEqual(repo.books.count, 8)
        XCTAssertEqual(repo.books.map(\.id), ["1a", "1b", "2a", "2b", "3a", "3b", "4a", "4b"])
    }

    func testBooksHaveGradeAndTerm() {
        let b = repo.book("1a")
        XCTAssertNotNil(b)
        XCTAssertEqual(b?.grade, 1)
        XCTAssertEqual(b?.term, 1)
        XCTAssertEqual(b?.short, "一上")
        XCTAssertEqual(b?.name, "一年级上册")
    }

    func testLessonCount() {
        // catalog 里 lessons 是 276 条
        var total = 0
        for b in repo.books {
            total += b.lessons.count
        }
        XCTAssertEqual(total, 276, "总课数应为 276")
    }

    func testLessonLookup() {
        let l = repo.lesson("1a-s1")
        XCTAssertNotNil(l)
        XCTAssertEqual(l?.title, "天地人")
        XCTAssertEqual(l?.chars.first, "天")
        XCTAssertEqual(l?.no, 1)
        XCTAssertEqual(l?.unit, 1)
    }

    func testNilLessonIsNil() {
        XCTAssertNil(repo.lesson(nil))
        XCTAssertNil(repo.lesson("不存在的课"))
    }

    func testLessonLabel() {
        // "一上 · 第1课 天地人"
        let label = repo.lessonLabel("1a-s1")
        XCTAssertTrue(label.contains("一上"), "应包含册次简称，实际 \(label)")
        XCTAssertTrue(label.contains("天地人"), "应包含课题，实际 \(label)")
    }

    // MARK: - 字

    func testCharCount() {
        XCTAssertEqual(repo.charCount, 2596, "唯一字数应为 2596（2600 生字含 4 个重复）")
    }

    func testMetaOfTian() {
        guard let m = repo.meta("天") else {
            return XCTFail("「天」的元数据缺失")
        }
        XCTAssertEqual(m.py, "tiān")
        XCTAssertEqual(m.r, "大")
        XCTAssertEqual(m.s, 4)
        XCTAssertEqual(m.b, "1a")
        XCTAssertFalse(m.words.isEmpty, "应有组词")
        XCTAssertEqual(m.words.first?.w, "天空")
    }

    func testMissingChar() {
        XCTAssertFalse(repo.hasChar("")) 
        XCTAssertNil(repo.meta("𠀀"))
    }

    func testBookCharsAreDeduped() {
        let chars = repo.bookChars("1a")
        XCTAssertFalse(chars.isEmpty)
        XCTAssertEqual(chars.count, Set(chars).count, "册内生字不应重复")
        XCTAssertEqual(chars.first, "天", "应按教材顺序，第一个字是「天」")
    }

    func testBookCharsCoverStat() {
        // stat.chars 是教材标称的识字量（1a=300 ... 4b=250 这类整数），
        // 而实际字表可能多出几个漏收的字（匀/剩/训/忧/毒，共 5 个）。
        // 所以只要求「不少于标称」，不要求恰好相等——
        // 硬相等会逼着把漏收的字藏起来，那才是真的错。
        for b in repo.books {
            let actual = repo.bookChars(b.id).count
            XCTAssertGreaterThanOrEqual(actual, b.stat.chars, "\(b.id) 的字表少于标称识字量")
        }
    }

    func testOrphanCharsAreRecovered() {
        // 这 5 个字在 meta 里指向某课、也在该课写字表里，却没进识字表。
        // 会写必然会认，所以它们必须能被找到，否则在 App 里根本看不到。
        for ch in ["匀", "剩", "训", "忧", "毒"] {
            // 它们不属于任何一册的识字表（那正是这 5 个字的特殊之处），
            // 但必须进全字表——否则出题、描红都取不到
            XCTAssertTrue(repo.allChars.contains(ch), "\(ch) 应在全字表里")
            XCTAssertTrue(repo.writeOnlyChars.contains(ch), "\(ch) 应被识别为仅写字表字")
        }
    }

    func testAllCharsInOrderHasNoDuplicate() {
        let all = repo.allCharsInOrder()
        XCTAssertEqual(all.count, Set(all).count, "全部字列表不应有重复")
    }

    // MARK: - 多音字

    func testPolyphoneReadings() {
        // 「地」在 1a-s1 读 dì，在 1a-k4 读 de
        let readings = repo.readingsOf("地")
        XCTAssertTrue(readings.contains("dì"), "应包含 dì，实际 \(readings)")
        XCTAssertTrue(readings.contains("de"), "应包含 de，实际 \(readings)")
    }

    func testReadingForLesson() {
        XCTAssertEqual(repo.readingFor("地", lessonId: "1a-s1"), "dì")
        XCTAssertEqual(repo.readingFor("地", lessonId: "1a-k4"), "de")
    }

    func testReadingForUnknownLessonFallsBack() {
        // 课次对不上时回退到默认读音，而不是返回空串
        XCTAssertEqual(repo.readingFor("地", lessonId: "不存在的课"), "dì")
    }

    func testSingleReadingChar() {
        XCTAssertEqual(repo.readingsOf("天"), ["tiān"])
        XCTAssertEqual(repo.readingDetails("天").count, 1)
    }

    // MARK: - 会写的字

    func testWriteChar() {
        // 「天」的 x 字段是 1a-k4，属于会写字
        XCTAssertTrue(repo.isWriteChar("天"))
    }

    func testWriteCharsAreSubset() {
        // 每册的会写字应当是该册生字的子集
        for b in repo.books {
            let all = Set(repo.bookChars(b.id))
            let write = repo.bookChars(b.id).filter { repo.isWriteChar($0) }
            for ch in write {
                XCTAssertTrue(all.contains(ch), "\(ch) 是会写字但不在本册生字里")
            }
        }
    }

    // MARK: - 前后导航

    func testNextPrevInLesson() {
        let chars = repo.lessonChars("1a-s1")
        guard chars.count >= 2 else { return XCTFail("1a-s1 应至少有两个字") }
        XCTAssertEqual(repo.nextInLesson("1a-s1", chars[0]), chars[1])
        XCTAssertEqual(repo.prevInLesson("1a-s1", chars[1]), chars[0])
    }

    func testNextPrevAtBoundary() {
        let chars = repo.lessonChars("1a-s1")
        guard let first = chars.first, let last = chars.last else { return XCTFail("无字") }
        XCTAssertEqual(repo.prevInLesson("1a-s1", first), "", "第一个字没有前一个")
        XCTAssertEqual(repo.nextInLesson("1a-s1", last), "", "最后一个字没有后一个")
    }

    // MARK: - 笔顺

    func testStrokesDecode() {
        guard let s = repo.strokes("天") else {
            return XCTFail("「天」的笔顺缺失")
        }
        XCTAssertEqual(s.count, 4, "「天」是 4 笔")
        XCTAssertEqual(s.strokes.count, 4)
        XCTAssertEqual(s.medians.count, 4, "每一笔都应有一条中线")
    }

    /// 这个测试守住 M0 发现的缩放 bug：解码后的坐标应落在 0..1024 的坐标系里。
    /// 如果又写成了「除以 SCALE」，包围盒会缩到 20 像素左右。
    func testStrokeCoordinatesAreInHanziSpace() {
        for ch in ["天", "地", "人", "永", "國"] where repo.strokes(ch) != nil {
            guard let s = repo.strokes(ch) else { continue }
            for (i, stroke) in s.strokes.enumerated() {
                let path = HanziCanvas.path(for: stroke, box: 1024, origin: .zero)
                let bb = path.boundingBox
                XCTAssertGreaterThan(bb.width, 50, "\(ch) 第 \(i) 笔的宽度过小：\(bb.width)")
                XCTAssertLessThanOrEqual(bb.maxX, 1100, "\(ch) 第 \(i) 笔超出字格：\(bb.maxX)")
                XCTAssertLessThanOrEqual(bb.maxY, 1100, "\(ch) 第 \(i) 笔超出字格：\(bb.maxY)")
            }
        }
    }

    func testStrokeCountMatchesMeta() {
        // meta 里的笔画数应与笔顺数据的笔数一致
        var checked = 0
        for ch in repo.allCharsInOrder().prefix(300) {
            guard let m = repo.meta(ch), let s = repo.strokes(ch) else { continue }
            XCTAssertEqual(s.count, m.s, "「\(ch)」的笔画数不一致：meta=\(m.s)，笔顺=\(s.count)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 200, "应校验到足够多的字")
    }

    func testStrokeCoverage() {
        // 生字应当都有笔顺数据
        let missing = repo.allCharsInOrder().filter { repo.strokes($0) == nil }
        XCTAssertTrue(missing.isEmpty, "\(missing.count) 个字缺少笔顺：\(missing.prefix(10))")
    }

    func testStrokesCached() {
        // 同一个字两次取到的是同一次解码结果（缓存生效）
        let a = repo.strokes("永")
        let b = repo.strokes("永")
        XCTAssertNotNil(a)
        XCTAssertEqual(a?.count, b?.count)
    }

    // MARK: - 册次统计

    func testBookStats() {
        let stat = repo.bookStat("1a")
        XCTAssertGreaterThan(stat.chars, 0)
        XCTAssertGreaterThan(stat.lessons, 0)
        XCTAssertGreaterThan(stat.units, 0)
        XCTAssertEqual(repo.book("1a")?.units.count, stat.units)
        XCTAssertEqual(repo.book("1a")?.lessons.count, stat.lessons)
    }

    func testDefaultBook() {
        XCTAssertEqual(repo.defaultBook(), "1a")
    }

    func testEdition() {
        XCTAssertTrue(repo.edition.contains("统编"), "册次版本应是统编版，实际 \(repo.edition)")
    }

    // MARK: - 词语表浏览
    //
    // 词语此前只在「看拼音选词语」的题目和课时页里露过脸，没有任何地方能
    // 从头翻一遍。对应小程序 `tests/words.test.mjs` 末尾那组。
    //
    // 这里钉死两个数：按册拼接 2492 条、全局去重 1967 个词。它们和小程序
    // 完全一致——去重粒度一旦写错（比如全局只留一份去分组），这两个数就会漂。

    func testBookWordEntriesAreDedupedWithinBook() {
        // 册内不能重复，否则一册里同一个词会出现两次
        for b in repo.books {
            let entries = repo.bookWordEntries(b.id)
            let words = entries.map(\.word)
            XCTAssertEqual(Set(words).count, words.count, "\(b.id) 册内词语重复")
            // 词本身必须属于这一册的课时
            XCTAssertTrue(entries.allSatisfy { repo.lesson($0.lesson)?.book == b.id })
        }
    }

    func testAllWordEntriesCountIs2492AndUniqueIs1967() {
        let all = repo.allWordEntries()
        let uniq = repo.uniqueWords()
        XCTAssertEqual(all.count, 2492, "按册拼接的条目数")
        XCTAssertEqual(uniq.count, 1967, "全局去重后的词数")
        XCTAssertLessThan(uniq.count, all.count, "跨册重复的词必须真的存在")
        let words = uniq.map(\.word)
        XCTAssertEqual(Set(words).count, words.count, "全局去重后不能有重复")
    }

    func testEveryBookHasWordsIncludingGrade1() {
        // 一年级课本没有词语表，但有生字组词兜底——页面不能对一年级显示空白
        for b in repo.books {
            XCTAssertGreaterThan(repo.bookWordEntries(b.id).count, 100,
                                 "\(b.id) 应该有一百个以上的词")
        }
    }

    func testGrade1WordsAreAllDerived() {
        // 一年级**全部**是派生词（课本没有词语表）
        let g1 = repo.bookWordEntries("1a")
        XCTAssertTrue(g1.allSatisfy(\.derived), "1a 应该全是生字组词")

        // 2a 是混合册：有的课文有词语表，有的没有
        let g2 = repo.bookWordEntries("2a")
        XCTAssertTrue(g2.contains { !$0.derived }, "2a 应该有真课本词")
        XCTAssertTrue(g2.contains(where: \.derived), "2a 也有派生词——混合册")
    }

    func testDerivedWordComesFromLessonChars() {
        // 兜底词取自本课生字的组词，所以每个派生词必须含本课某个生字
        for w in repo.bookWordEntries("1a") {
            let lesson = repo.lesson(w.lesson)!
            XCTAssertTrue(w.derived, "\(w.lesson) 的「\(w.word)」应该是派生词")
            XCTAssertTrue(w.chars.contains { lesson.chars.contains($0) },
                          "「\(w.word)」应含 \(w.lesson) 的某个生字")
        }
    }

    /// 保留的是**最早**出现的那一册/课，不是最后一课，也不是任取一课
    func testUniqueWordKeepsFirstBookAndLesson() {
        var first: [String: String] = [:]
        for b in repo.books {
            for w in repo.bookWordEntries(b.id) where first[w.word] == nil {
                first[w.word] = w.lesson
            }
        }
        for w in repo.uniqueWords() {
            XCTAssertEqual(w.lesson, first[w.word], "「\(w.word)」应记在最早出现的课时")
        }
    }

    func testCrossBookWordRecordsAllBooks() {
        // 「旅行」在 1b 和 3a 都出现，是教材事实
        let travel = repo.uniqueWords().first { $0.word == "旅行" }
        XCTAssertNotNil(travel)
        XCTAssertGreaterThanOrEqual(travel!.books.count, 2,
                                    "「旅行」应跨册，实际 \(travel!.books)")
        // 去重后原册次顺序保留，主册仍是第一个
        XCTAssertEqual(travel!.book, travel!.books.first)
    }

    func testWordEntryCarriesBookAndLessonContext() {
        let entry = repo.bookWordEntries("2a").first!
        let lesson = repo.lesson(entry.lesson)
        XCTAssertEqual(entry.unit, lesson?.unit)
        XCTAssertEqual(entry.lessonNo, lesson?.no)
        XCTAssertEqual(entry.book, lesson?.book)
        XCTAssertEqual(entry.chars.joined(), entry.word)
    }

    /// 派生词里有少数撞上字库外的字（弓弩的弩、镜匣的匣），页面据此置灰。
    /// 这类词占比必须很低，且每个词至少有一个字能点。
    func testSomeDerivedWordsContainCharsOutsideLibrary() {
        let derived = repo.uniqueWords().filter(\.derived)
        let outsider = derived.filter { $0.missing > 0 }
        XCTAssertGreaterThan(outsider.count, 0, "数据里确实有这类词，断言要贴着现实")
        let ratio = Double(outsider.count) / Double(derived.count)
        XCTAssertLessThan(ratio, 0.05,
                          "含字库外字的派生词占比 \(ratio * 100)% 太高了")
        for w in outsider {
            XCTAssertTrue(w.chars.contains { repo.hasChar($0) },
                          "「\(w.word)」一个字都点不了")
        }
        XCTAssertEqual(outsider.count, 19, "和小程序数出来的一致")
    }

    func testWordsWithCharFindsCrossBookWordsWithoutDuplicates() {
        let found = repo.wordsWithChar("行")
        XCTAssertGreaterThanOrEqual(found.count, 3, "含「行」的词太少：\(found.count)")
        // 「银行」和「行走」的「行」读音不同，搜字应该都列出来
        XCTAssertTrue(found.allSatisfy { $0.chars.contains("行") })
        // 搜索结果若不去重，「旅行」会出现两次
        let words = found.map(\.word)
        XCTAssertEqual(Set(words).count, words.count, "搜索结果不能有重复")
        XCTAssertTrue(found.contains { $0.books.count > 1 }, "「行」应该跨册出现")
    }

    func testUnknownOrEmptyWordQueryReturnsEmpty() {
        XCTAssertTrue(repo.wordsWithChar("").isEmpty)
        XCTAssertTrue(repo.wordsWithChar("龘").isEmpty)
    }

    func testEveryWordHasPinyin() {
        let bad = repo.uniqueWords().filter { $0.pinyin.isEmpty }
        XCTAssertTrue(bad.isEmpty, "这些词缺拼音：\(bad.prefix(5).map(\.word))")
    }
}
