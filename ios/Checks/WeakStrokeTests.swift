import XCTest
@testable import HanziCore

/// 笔画薄弱点。
///
/// 描红判分本来就每笔都会算出「为什么不过」（起笔错 / 偏离 / 写短了），
/// 但之前只用它拼一句即时提示就丢掉了。留下来才看得出
/// 「这个字的第 2 笔你反复写不好」——比整字分数具体，也更能指导练什么。
///
/// 与 Android `WeakStrokeTest`、小程序 `tests/weak.test.mjs` 对应。
@MainActor
final class WeakStrokeTests: XCTestCase {

    private func fresh() -> HanziCore.Progress {
        let p = HanziCore.Progress(store: MemoryStore())
        p.resetAll()
        return p
    }

    /// 只错一次很正常——手抖、第一次不熟，不算薄弱点
    func testTwoFailsMakeWeak() {
        let p = fresh()
        p.recordStroke("日", index: 1, passed: false)
        XCTAssertTrue(p.weakStrokesOf("日").isEmpty)

        p.recordStroke("日", index: 1, passed: false)
        let w = p.weakStrokesOf("日")
        XCTAssertEqual(w.count, 1)
        XCTAssertEqual(w[0].index, 1)
        XCTAssertEqual(w[0].fails, 2)
        XCTAssertEqual(w[0].tries, 2)
    }

    /// 写对一次不清：蒙对一次不该前功尽弃；
    /// 而且清了之后 tries 永远等于 fails，那条门槛就成了摆设
    func testTwoConsecutivePassesClear() {
        let p = fresh()
        p.recordStroke("日", index: 1, passed: false)
        p.recordStroke("日", index: 1, passed: false)
        XCTAssertEqual(p.weakStrokesOf("日").count, 1)

        p.recordStroke("日", index: 1, passed: true)
        XCTAssertEqual(p.weakStrokesOf("日").count, 1, "写对一次不该清")

        p.recordStroke("日", index: 1, passed: true)
        XCTAssertTrue(p.weakStrokesOf("日").isEmpty, "连对两次应该移除")
    }

    func testPassThenFailResetsStreak() {
        let p = fresh()
        p.recordStroke("天", index: 0, passed: false)
        p.recordStroke("天", index: 0, passed: false)
        p.recordStroke("天", index: 0, passed: true)   // 蒙对
        p.recordStroke("天", index: 0, passed: false)  // 又错
        XCTAssertEqual(p.weakStrokesOf("天").count, 1)
        p.recordStroke("天", index: 0, passed: true)
        XCTAssertEqual(p.weakStrokesOf("天").count, 1, "连胜清零后要重新连对两次")
        p.recordStroke("天", index: 0, passed: true)
        XCTAssertTrue(p.weakStrokesOf("天").isEmpty)
    }

    func testClearOneStrokeKeepsOthers() {
        let p = fresh()
        p.recordStroke("日", index: 1, passed: false)
        p.recordStroke("日", index: 1, passed: false)
        p.recordStroke("日", index: 3, passed: false)
        p.recordStroke("日", index: 3, passed: false)
        XCTAssertEqual(p.weakStrokesOf("日").count, 2)
        p.clearWeakStroke("日", index: 1)
        let left = p.weakStrokesOf("日")
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left[0].index, 3)
    }

    /// 一个字的笔画都在同一份描红里练，按笔画列出会重复练同一个字
    func testWeakCharsDedupes() {
        let p = fresh()
        p.recordStroke("日", index: 1, passed: false)
        p.recordStroke("日", index: 1, passed: false)
        p.recordStroke("日", index: 3, passed: false)
        p.recordStroke("日", index: 3, passed: false)
        let chars = p.weakChars()
        XCTAssertEqual(chars.count, 1)
        XCTAssertEqual(chars[0].ch, "日")
    }

    func testWeakStrokesSortedByIndex() {
        let p = fresh()
        for i in [5, 1, 3] {
            p.recordStroke("罐", index: i, passed: false)
            p.recordStroke("罐", index: i, passed: false)
        }
        XCTAssertEqual(p.weakStrokesOf("罐").map { $0.index }, [1, 3, 5])
    }

    /// 失败次数多的在前；次数相同时按码点 + 笔画序号，
    /// 因为 Swift 的 sort 不保证稳定，没有 tiebreak 三端顺序会不一致
    func testAllWeakStrokesSorted() {
        let p = fresh()
        p.recordStroke("日", index: 0, passed: false)
        p.recordStroke("日", index: 0, passed: false)
        for _ in 0..<4 { p.recordStroke("天", index: 2, passed: false) }
        let all = p.allWeakStrokes()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].ch, "天")
        XCTAssertEqual(all[0].fails, 4)
        XCTAssertEqual(all[1].ch, "日")
    }

    func testNoWriteNoWeak() {
        let p = fresh()
        XCTAssertTrue(p.weakStrokesOf("字").isEmpty)
        XCTAssertFalse(p.hasWeakStrokes("字"))
        XCTAssertTrue(p.allWeakStrokes().isEmpty)
        XCTAssertTrue(p.weakChars().isEmpty)
    }

    func testResetClearsWeak() {
        let p = fresh()
        p.recordStroke("日", index: 1, passed: false)
        p.recordStroke("日", index: 1, passed: false)
        XCTAssertEqual(p.allWeakStrokes().count, 1)
        p.resetAll()
        XCTAssertTrue(p.allWeakStrokes().isEmpty)
    }

    func testClearWeakRemovesWholeChar() {
        let p = fresh()
        p.recordStroke("日", index: 1, passed: false)
        p.recordStroke("日", index: 1, passed: false)
        p.recordStroke("日", index: 3, passed: false)
        p.recordStroke("日", index: 3, passed: false)
        p.clearWeak("日")
        XCTAssertTrue(p.weakStrokesOf("日").isEmpty)
    }

    /// 薄弱点要能跨重启保留——不然「反复写不好」这件事第二天就忘了
    func testWeakSurvivesRestart() {
        let store = MemoryStore()
        let a = HanziCore.Progress(store: store)
        a.resetAll()
        a.recordStroke("日", index: 1, passed: false)
        a.recordStroke("日", index: 1, passed: false)

        let b = HanziCore.Progress(store: store)
        let w = b.weakStrokesOf("日")
        XCTAssertEqual(w.count, 1, "重启后应该还记得这一笔很弱")
        XCTAssertEqual(w[0].fails, 2)
    }

    /// 「连对两次即移除」的直接推论：还在册的记录里不可能夹着两次连续成功，
    /// 所以 tries ≤ 2*fails+1 恒成立。这也是「失败率 ≥40%」那条门槛显得多余的原因。
    func testTriesInvariant() {
        let p = fresh()
        let seq = [false, true, false, false, true, false, true, false,
                   false, true, true, false, false]
        for pass in seq { p.recordStroke("天", index: 0, passed: pass) }
        for w in p.allWeakStrokes() {
            XCTAssertLessThanOrEqual(w.tries, 2 * w.fails + 1,
                                     "t=\(w.tries) 超过了 2f+1=\(2 * w.fails + 1)")
        }
    }
}
