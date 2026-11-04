import XCTest
@testable import HanziCore

/// 学习周报。
///
/// 周报的数字是给家长看的，算错了比不显示更糟——家长会据此判断孩子
/// 学得好不好。所以每个口径都要钉死，尤其是「没学」和「学了但没答对」
/// 这两种情况必须区分开。
///
/// 与小程序 `tests/report.test.mjs` 逐条对应。
final class ReportTests: XCTestCase {

    /// 和小程序测试同一个基准日：2026-11-03 是周二
    private let now = ReportTests.date(2026, 11, 3)

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y
        c.month = m
        c.day = d
        // 取正午而不是零点：夏令时切换日的零点可能不存在或被跳过
        c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: c)!
    }

    /// 造一份 `days` 统计，offset 为负表示几天前
    private func days(_ list: [(offset: Int, learned: Int, answers: Int, correct: Int)]) -> [String: Report.DayStat] {
        var out: [String: Report.DayStat] = [:]
        for it in list {
            out[DayUtil.dayKeyOf(it.offset, from: now)] = Report.DayStat(
                learned: it.learned, answers: it.answers, correct: it.correct
            )
        }
        return out
    }

    // MARK: - 取数

    func testRecentWindowEndsToday() {
        let week = Report.recentDays(days([(0, 3, 10, 8)]), now: now)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week[6].daysAgo, 0, "最后一项必须是今天")
        XCTAssertEqual(week[6].learned, 3)
        XCTAssertEqual(week[0].daysAgo, 6)
        XCTAssertEqual(week[6].key, DayUtil.todayKey(now))
    }

    /// 这条最容易搞错：把缺失当 0 会让家长看到「正确率 0%」
    func testMissingDayIsInactiveNotZeroPercent() {
        let week = Report.recentDays(days([(0, 3, 10, 8)]), now: now)
        let empty = week[0]
        XCTAssertFalse(empty.active)
        XCTAssertNil(empty.accuracy, "没答题时正确率必须是 nil，不能是 0")
        XCTAssertEqual(empty.learned, 0)
        XCTAssertEqual(empty.answers, 0)
    }

    /// 只描红不答题：有学习量，但算不出正确率
    func testStudiedButNoAnswersHasNilAccuracy() {
        let week = Report.recentDays(days([(0, 2, 0, 0)]), now: now)
        let today = week[6]
        XCTAssertTrue(today.active, "学了字就算活跃")
        XCTAssertNil(today.accuracy, "没答题不能报 0%")
    }

    func testAccuracyRoundsToWholePercent() {
        let week = Report.recentDays(days([(0, 1, 3, 2)]), now: now)
        XCTAssertEqual(week[6].accuracy, 67, "66.67 → 67")
    }

    func testWeekdaysStartOnMonday() {
        // 2026-11-03 是周二
        let week = Report.recentDays(nil, now: now)
        XCTAssertEqual(week[6].weekday, "二")
        XCTAssertEqual(week[5].weekday, "一")
        XCTAssertEqual(week[0].weekday, "三", "6 天前是上周三")
    }

    func testSpanIsConfigurable() {
        let week = Report.recentDays(nil, span: 3, now: now)
        XCTAssertEqual(week.count, 3)
        XCTAssertEqual(week.last?.daysAgo, 0)
        XCTAssertEqual(week.first?.daysAgo, 2)
    }

    // MARK: - 汇总

    func testSummarySumsAndRate() {
        let week = Report.recentDays(days([
            (0, 3, 10, 8),
            (-1, 5, 12, 6),
            (-3, 2, 0, 0),
        ]), now: now)
        let sum = Report.summarize(week)
        XCTAssertEqual(sum.learned, 10)
        XCTAssertEqual(sum.answers, 22)
        XCTAssertEqual(sum.correct, 14)
        XCTAssertEqual(sum.accuracy, 64, "14/22 = 63.6 → 64")
        XCTAssertEqual(sum.activeDays, 3)
        XCTAssertFalse(sum.empty)
        XCTAssertEqual(sum.span, 7)
    }

    func testEmptyWeekIsEmpty() {
        let sum = Report.summarize(Report.recentDays(nil, now: now))
        XCTAssertTrue(sum.empty)
        XCTAssertEqual(sum.activeDays, 0)
        XCTAssertNil(sum.accuracy)
        XCTAssertNil(sum.best)
    }

    func testBestDayIsByLearned() {
        let week = Report.recentDays(days([
            (0, 3, 4, 4),
            (-2, 8, 2, 2),
        ]), now: now)
        let sum = Report.summarize(week)
        XCTAssertEqual(sum.learned, 11)
        XCTAssertEqual(sum.best?.learned, 8, "学习量最多的那天")
    }

    func testBestDayTieBreaksByAnswers() {
        let week = Report.recentDays(days([
            (0, 3, 4, 4),
            (-2, 3, 9, 8),
        ]), now: now)
        let sum = Report.summarize(week)
        XCTAssertEqual(sum.best?.learned, 3)
        XCTAssertEqual(sum.best?.answers, 9, "学习量平手时答题量多的优先")
        XCTAssertEqual(sum.best?.daysAgo, 2)
    }

    func testBestDayKeepsFirstWhenStillTied() {
        let week = Report.recentDays(days([
            (-2, 3, 4, 4),
            (0, 3, 4, 4),
        ]), now: now)
        let sum = Report.summarize(week)
        XCTAssertEqual(sum.best?.daysAgo, 2, "完全平手时保留更早遇到的那天，和 JS 一致")
    }

    // MARK: - headline

    func testHeadlineForEmptyWeek() {
        let sum = Report.summarize(Report.recentDays(nil, now: now))
        XCTAssertTrue(Report.headline(sum).contains("还没开始"))
    }

    func testHeadlineFullWeek() {
        let full = Report.summarize(Report.recentDays(
            days((0...6).map { (-$0, 1, 0, 0) }), now: now
        ))
        XCTAssertEqual(full.activeDays, 7)
        XCTAssertTrue(Report.headline(full).contains("七天"))
    }

    func testHeadlineWordingTracksActiveDays() {
        func sum(active: Int) -> Report.Summary {
            let list = (0..<active).map { (-$0, 1, 0, 0) }
            return Report.summarize(Report.recentDays(days(list), now: now))
        }
        XCTAssertTrue(Report.headline(sum(active: 6)).contains("6 天，很稳"))
        XCTAssertTrue(Report.headline(sum(active: 4)).contains("4 天，继续保持"))
        XCTAssertTrue(Report.headline(sum(active: 2)).contains("明天再来一次"))
    }

    // MARK: - advice

    func testAdvicePointsOutMissingDays() {
        let week = Report.recentDays(days([
            (0, 3, 10, 9),
            (-1, 2, 5, 4),
        ]), now: now)
        let tips = Report.advice(Report.summarize(week), week: week)
        let text = tips.map(\.text).joined(separator: "|")
        XCTAssertTrue(text.contains("5 天没有学习记录"), text)
    }

    func testAdviceGoodToneWhenAccurate() {
        let week = Report.recentDays(days([(0, 3, 10, 9)]), now: now)
        let tips = Report.advice(Report.summarize(week), week: week)
        XCTAssertTrue(tips.contains { $0.tone == .good && $0.text.contains("扎实") })
    }

    func testAdvicePlainToneAtMidAccuracy() {
        // 2/3 = 67%，落在 65~85 之间
        let week = Report.recentDays(days([(0, 1, 3, 2)]), now: now)
        let tips = Report.advice(Report.summarize(week), week: week)
        XCTAssertTrue(tips.contains { $0.tone == .plain && $0.text.contains("没记牢") })
    }

    func testAdviceSuggestsSlowingDownWhenInaccurate() {
        let week = Report.recentDays(days([(0, 6, 20, 8)]), now: now)
        let tips = Report.advice(Report.summarize(week), week: week)
        XCTAssertTrue(tips.contains { $0.tone == .tip && $0.text.contains("放慢") })
    }

    func testAdviceForEmptyWeekIsOneLine() {
        let week = Report.recentDays(nil, now: now)
        let tips = Report.advice(Report.summarize(week), week: week)
        XCTAssertEqual(tips.count, 1, "空周不刷屏")
    }

    func testAdviceSuggestsVocabTestWhenVolumeAndAccuracyAreHigh() {
        // 35 个字、正确率 90%：两条好的建议 + 一条「往下走」
        let week = Report.recentDays(days([
            (0, 20, 10, 9),
            (-1, 15, 10, 9),
        ]), now: now)
        let tips = Report.advice(Report.summarize(week), week: week)
        XCTAssertTrue(tips.contains { $0.text.contains("识字量测试") })
    }

    func testAdviceAveragePerActiveDay() {
        let week = Report.recentDays(days([
            (0, 3, 0, 0),
            (-1, 4, 0, 0),
        ]), now: now)
        let tips = Report.advice(Report.summarize(week), week: week)
        XCTAssertTrue(tips.contains { $0.text.contains("平均每天 3.5 个") }, "7/2 = 3.5")
    }

    // MARK: - 柱状图

    /// 只复习不学新字的那天，柱子不能是空的
    func testReviewOnlyDayGetsVisibleBar() {
        let week = Report.withRatios(Report.recentDays(days([
            (0, 0, 40, 36),
            (-1, 10, 0, 0),
        ]), now: now))
        let today = week[6]
        XCTAssertTrue(today.active, "复习日算活跃")
        XCTAssertGreaterThan(today.ratio, 0, "只复习的日子柱子不能是 0")
        XCTAssertEqual(today.ratio, 1, accuracy: 0.0001)
    }

    func testTinyActiveDayKeepsMinimumHeight() {
        let week = Report.withRatios(Report.recentDays(days([
            (0, 100, 0, 0),
            (-1, 1, 0, 0),
        ]), now: now))
        XCTAssertEqual(week[5].ratio, 0.08, accuracy: 0.0001,
                       "1 个字相对 100 个字，也得看得见")
    }

    func testEmptyWeekRatiosAreZeroNoDivideByZero() {
        let week = Report.withRatios(Report.recentDays(nil, now: now))
        for d in week {
            XCTAssertEqual(d.ratio, 0)
        }
        XCTAssertFalse(week.map(\.ratio).contains { $0.isNaN || $0.isInfinite })
    }

    func testInactiveDayHasZeroRatioEvenInBusyWeek() {
        let week = Report.withRatios(Report.recentDays(days([(0, 5, 0, 0)]), now: now))
        XCTAssertEqual(week[0].ratio, 0, "没学的那天不能有柱子")
    }

    // MARK: - build

    func testBuildGivesEverythingThePageNeeds() {
        let r = Report.build(days([(0, 3, 10, 8)]), now: now)
        XCTAssertEqual(r.week.count, 7)
        XCTAssertEqual(r.sum.learned, 3)
        XCTAssertFalse(r.headline.isEmpty)
        XCTAssertFalse(r.advice.isEmpty)
        XCTAssertEqual(r.week.last!.ratio, 1, accuracy: 0.0001,
                       "3 个字 / max(3, 3) —— 10 道题折算 3")
    }
}
