import XCTest
@testable import HanziCore

/// 字帖选字。
///
/// 这块的价值全在「按什么顺序挑、挑出来标什么」上：来源优先级排错，
/// 孩子会先看到不着急练的字；去重没保持首次出现顺序，字帖的排版会跳。
///
/// 与小程序 `tests/copybook-pick.test.mjs` 对应。iOS 侧不测 `available`：
/// 笔画数据整包在 app 里，任何字都能画出来。
final class CopybookPickTests: XCTestCase {

    func testMergeDedupesAndKeepsFirstOrder() {
        let m = CopybookPick.merge([
            .init("天", .lesson),
            .init("地", .wrong),
            .init("天", .stars),
        ])
        XCTAssertEqual(m.map(\.ch), ["天", "地"])
        XCTAssertEqual(m[0].froms, [.lesson, .stars])
    }

    func testMergeIgnoresEmptyCharsAndDuplicateSources() {
        let m = CopybookPick.merge([
            .init("", .wrong),
            .init("天", .lesson),
            .init("天", .lesson),
        ])
        XCTAssertEqual(m.map(\.ch), ["天"])
        XCTAssertEqual(m[0].froms, [.lesson], "同一个来源重复命中只记一次")
    }

    func testSourceLabelsFollowPriorityOrder() {
        let d = CopybookPick.decorate(CopybookPick.merge([
            .init("天", .stars),
            .init("天", .lesson),
            .init("天", .wrong),
        ]))
        XCTAssertEqual(d[0].froms, [.wrong, .lesson, .stars])
        XCTAssertEqual(d[0].fromText, "错题 · 课时 · 低分")
    }

    func testWeakSitsBetweenWrongAndLesson() {
        let d = CopybookPick.decorate(CopybookPick.merge([
            .init("天", .stars),
            .init("天", .lesson),
            .init("天", .weak),
            .init("天", .wrong),
        ]))
        XCTAssertEqual(d[0].froms, [.wrong, .weak, .lesson, .stars])
        XCTAssertEqual(d[0].fromText, "错题 · 笔画弱 · 课时 · 低分")
    }

    func testEmptyInputsDoNotCrash() {
        XCTAssertEqual(CopybookPick.merge([]), [])
        XCTAssertEqual(CopybookPick.build().items, [])
        XCTAssertEqual(CopybookPick.build().readyCount, 0)
        XCTAssertEqual(CopybookPick.build().missingCount, 0)
    }

    func testStarsFilterKeepsOnlyThatTier() {
        let records = [
            CopybookPick.Record(ch: "天", stars: 1),
            CopybookPick.Record(ch: "地", stars: 3),
            CopybookPick.Record(ch: "人", stars: 1),
        ]
        let out = CopybookPick.fromStars(records, stars: 1)
        XCTAssertEqual(out.map(\.ch), ["天", "人"])
    }

    func testWrongComesBeforeLesson() {
        let out = CopybookPick.build(
            lessonChars: ["天", "地", "人"],
            wrongChars: ["人"]
        )
        XCTAssertEqual(out.items[0].ch, "人", "「人」是错题，排在前面")
        XCTAssertTrue(out.items[0].fromText.contains("错题"))
    }

    func testLessonCharsStayInTextbookOrder() {
        let out = CopybookPick.build(lessonChars: ["天", "地", "人"])
        XCTAssertEqual(out.items.map(\.ch), ["天", "地", "人"])
    }

    func testAllFourSourcesTogether() {
        let out = CopybookPick.build(
            lessonChars: ["天", "地"],
            records: [CopybookPick.Record(ch: "他", stars: 0)],
            wrongChars: ["你"],
            weakChars: ["我"],
            stars: 0
        )
        XCTAssertEqual(out.items.map(\.ch).sorted(), ["他", "你", "天", "地", "我"].sorted())
        XCTAssertEqual(out.readyCount, 5, "iOS 上每个字都可导")
        XCTAssertEqual(out.missingCount, 0)
    }

    func testStarsSourceIsIgnoredWhenStarsIsNil() {
        let out = CopybookPick.build(
            records: [CopybookPick.Record(ch: "他", stars: 0)]
        )
        XCTAssertTrue(out.items.isEmpty, "没勾「低分字」时不能把写过的字混进来")
    }

    func testSameCharFromSeveralSourcesGetsCombinedLabel() {
        let out = CopybookPick.build(
            lessonChars: ["天"],
            records: [CopybookPick.Record(ch: "天", stars: 2)],
            wrongChars: ["天"],
            weakChars: ["天"],
            stars: 2
        )
        XCTAssertEqual(out.items.count, 1)
        XCTAssertEqual(out.items[0].fromText, "错题 · 笔画弱 · 课时 · 低分")
    }
}
