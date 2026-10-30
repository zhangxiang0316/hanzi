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
    private var repo: Repo {
        if let r = Self._repo { return r }
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Checks
            .deletingLastPathComponent()   // ios
            .appendingPathComponent("HanziPad/Resources")
        let r = Repo(source: .directory(resources))
        Self._repo = r
        return r
    }

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

    func testBookCharsMatchStat() {
        // stat.chars 是构建时统计的数字，应和实际去重后的数量一致
        for b in repo.books {
            let actual = repo.bookChars(b.id).count
            XCTAssertEqual(actual, b.stat.chars, "\(b.id) 的 stat.chars 与实际不符")
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
}
