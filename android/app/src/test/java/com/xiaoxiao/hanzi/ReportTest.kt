package com.xiaoxiao.hanzi

import com.xiaoxiao.hanzi.logic.DayUtil
import com.xiaoxiao.hanzi.logic.Progress
import com.xiaoxiao.hanzi.logic.Report
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.Date

/**
 * 学习周报。
 *
 * 周报的数字是给家长看的，算错了比不显示更糟——家长会据此判断孩子
 * 学得好不好。所以每个口径都要钉死，尤其是「没学」和「学了但没答对」
 * 这两种情况必须区分开。
 *
 * 与小程序 `tests/report.test.mjs` 一一对应，期望值取自那份测试：
 * 三端读同一套 `stats.days`，必须算出同一份周报。
 */
class ReportTest {

    /**
     * 固定的「今天」：2026-11-03，周二。
     *
     * 用周二而不是周一：周一是最容易被「周一到周日」的错误实现蒙对的一天，
     * 周二才能区分「滚动 7 天」和「本周」。
     */
    private val now: Date = Calendar.getInstance().apply {
        set(2026, Calendar.NOVEMBER, 3, 12, 0, 0)
        set(Calendar.MILLISECOND, 0)
    }.time

    private fun stat(learned: Int, answers: Int, correct: Int) =
        Progress.DayStat(learned = learned, answers = answers, correct = correct)

    /** 造一份 stats.days，offset 为负表示几天前 */
    private fun days(vararg recs: Pair<Int, Progress.DayStat>): Map<String, Progress.DayStat> {
        val out = HashMap<String, Progress.DayStat>()
        for ((offset, s) in recs) {
            out[DayUtil.todayKey(DayUtil.dateOfOffset(now, offset))] = s
        }
        return out
    }

    private fun day(offset: Int, learned: Int, answers: Int, correct: Int) =
        offset to stat(learned, answers, correct)

    @Test
    fun `取最近 7 天，最后一项是今天`() {
        val week = Report.recentDays(days(day(0, 3, 10, 8)), now)
        assertEquals(7, week.size)
        assertEquals(0, week[6].daysAgo)
        assertEquals(3, week[6].learned)
        assertEquals(6, week[0].daysAgo)
    }

    @Test
    fun `缺数据的那天算没学，不是 0 分`() {
        // 这条最容易搞错：把缺失当 0 会让家长看到「正确率 0%」
        val week = Report.recentDays(days(day(0, 3, 10, 8)), now)
        val empty = week[0]
        assertFalse("没有记录的那天不是活跃日", empty.active)
        assertNull("没答题时正确率必须是 null，不能是 0", empty.accuracy)
        assertEquals(0, empty.learned)
        assertEquals(0, empty.answers)
    }

    @Test
    fun `学了但一题没答，正确率也是 null`() {
        // 只描红不答题：有学习量，但算不出正确率
        val week = Report.recentDays(days(day(0, 2, 0, 0)), now)
        val today = week[6]
        assertTrue("学了字就算活跃", today.active)
        assertNull("没答题不能报 0%", today.accuracy)
    }

    @Test
    fun `正确率四舍五入到整数`() {
        val week = Report.recentDays(days(day(0, 1, 3, 2)), now)
        assertEquals(67, week[6].accuracy) // 66.67 → 67
    }

    @Test
    fun `星期按周一打头`() {
        // 2026-11-03 是周二
        val week = Report.recentDays(null, now)
        assertEquals("二", week[6].weekday)
        assertEquals("一", week[5].weekday)
        // 再往前一天是周日，必须排在周一之前（不是一周的第一天）
        assertEquals("日", week[4].weekday)
    }

    @Test
    fun `窗口是滚动的 7 天，不含 7 天前`() {
        val stats = days(day(0, 1, 0, 0), day(-6, 1, 0, 0), day(-7, 9, 9, 9))
        val week = Report.recentDays(stats, now)
        assertEquals(7, week.size)
        assertEquals(1, week.first().learned)
        assertEquals(2, week.sumOf { it.learned })
        // 7 天前那一天不在窗口里
        assertFalse(week.any { it.key == DayUtil.todayKey(DayUtil.dateOfOffset(now, -7)) })
    }

    @Test
    fun `汇总：学习量、答题量、正确率、活跃天数`() {
        val week = Report.recentDays(
            days(
                day(0, 3, 10, 8),
                day(-1, 5, 12, 6),
                day(-3, 2, 0, 0)
            ),
            now
        )
        val sum = Report.summarize(week)
        assertEquals(10, sum.learned)
        assertEquals(22, sum.answers)
        assertEquals(14, sum.correct)
        assertEquals(64, sum.accuracy) // 14/22 = 63.6 → 64
        assertEquals(3, sum.activeDays)
        assertFalse(sum.empty)
        assertEquals(7, sum.span)
    }

    @Test
    fun `整周没学是 empty`() {
        val sum = Report.summarize(Report.recentDays(null, now))
        assertTrue(sum.empty)
        assertEquals(0, sum.activeDays)
        assertNull(sum.accuracy)
        assertNull(sum.best)
    }

    @Test
    fun `「最好的一天」按学习量取，打破平手看答题量`() {
        val week = Report.recentDays(
            days(
                day(0, 3, 4, 4),
                day(-2, 8, 2, 2)
            ),
            now
        )
        val sum = Report.summarize(week)
        assertEquals(11, sum.learned)
        assertEquals(8, sum.best!!.learned)
    }

    @Test
    fun `学习量相同时「最好的一天」取答题多的那天`() {
        // 两个都是 5 个字，但昨天答了 12 题、今天只答 3 题
        val week = Report.recentDays(
            days(
                day(0, 5, 3, 3),
                day(-1, 5, 12, 10)
            ),
            now
        )
        val sum = Report.summarize(week)
        assertEquals(5, sum.best!!.learned)
        assertEquals(12, sum.best!!.answers)
        assertEquals(1, sum.best!!.daysAgo)
    }

    @Test
    fun `「最好的一天」只在活跃的日子里挑`() {
        val week = Report.recentDays(days(day(-2, 0, 3, 3)), now)
        val sum = Report.summarize(week)
        assertNotNull(sum.best)
        assertEquals(2, sum.best!!.daysAgo)
        // 没学的那几天不能被选成「最好的一天」
        assertEquals(3, sum.best!!.answers)
    }

    @Test
    fun `headline 对空周不说「正确率」这种空话`() {
        val sum = Report.summarize(Report.recentDays(null, now))
        assertTrue(Report.headline(sum).contains("还没开始"))
    }

    @Test
    fun `headline 满勤和不满勤措辞不同`() {
        val full = Report.summarize(
            Report.recentDays(
                days(*(0 downTo -6).map { day(it, 1, 0, 0) }.toTypedArray()),
                now
            )
        )
        assertEquals(7, full.activeDays)
        assertTrue("满勤要说七天", Report.headline(full).contains("七天"))

        val six = Report.summarize(
            Report.recentDays(
                days(*(0 downTo -5).map { day(it, 1, 0, 0) }.toTypedArray()),
                now
            )
        )
        assertEquals(6, six.activeDays)
        assertTrue(Report.headline(six).contains("很稳"))

        val two = Report.summarize(
            Report.recentDays(days(day(0, 1, 0, 0), day(-1, 1, 0, 0)), now)
        )
        assertTrue(Report.headline(two).contains("明天再来一次"))
    }

    @Test
    fun `advice 会指出有几天没学`() {
        val week = Report.recentDays(days(day(0, 3, 10, 9), day(-1, 2, 5, 4)), now)
        val tips = Report.advice(Report.summarize(week), week)
        val text = tips.joinToString("|") { it.text }
        assertTrue("要说出缺了几天：$text", text.contains("5 天没有学习记录"))
    }

    @Test
    fun `advice 正确率高时说扎实`() {
        val week = Report.recentDays(days(day(0, 3, 10, 9)), now)
        val tips = Report.advice(Report.summarize(week), week)
        assertTrue("90% 应说扎实", tips.any { it.tone == "good" && it.text.contains("扎实") })
    }

    @Test
    fun `advice 正确率低时建议放慢`() {
        val week = Report.recentDays(days(day(0, 6, 20, 8)), now)
        val tips = Report.advice(Report.summarize(week), week)
        assertTrue("40% 应建议放慢", tips.any { it.tone == "tip" && it.text.contains("放慢") })
    }

    @Test
    fun `advice 正确率中等时不夸也不叹`() {
        // 14/20 = 70% → 落在 plain 档（65~84）
        val week = Report.recentDays(days(day(0, 3, 20, 14)), now)
        val tips = Report.advice(Report.summarize(week), week)
        val acc = tips.first { it.text.contains("正确率") }
        assertEquals("plain", acc.tone)
        assertTrue(acc.text, acc.text.contains("70%"))
    }

    @Test
    fun `advice 在空周只给一句话，不刷屏`() {
        val week = Report.recentDays(null, now)
        val tips = Report.advice(Report.summarize(week), week)
        assertEquals(1, tips.size)
        assertTrue(tips[0].text.contains("还没有学习记录"))
    }

    @Test
    fun `advice 学习量和正确率都高时提醒往下走`() {
        val week = Report.recentDays(days(*(0 downTo -4).map { day(it, 8, 12, 11) }.toTypedArray()), now)
        val sum = Report.summarize(week)
        assertEquals(40, sum.learned)
        val tips = Report.advice(sum, week)
        assertTrue(tips.any { it.text.contains("识字量测试") })
    }

    @Test
    fun `柱状图比例归一到 0 到 1，且只看学习量不埋没复习日`() {
        // 只复习不学新字的那天，柱子不能是空的
        val week = Report.withRatios(
            Report.recentDays(
                days(
                    day(0, 0, 40, 36),
                    day(-1, 10, 0, 0)
                ),
                now
            )
        )
        val today = week[6]
        assertTrue("复习日算活跃", today.active)
        assertTrue("只复习的日子柱子不能是 0", today.ratio > 0)
        // 两个都是 10 分（40 题按 4 题折算 1 个字），比例都拉满
        assertEquals(1.0, today.ratio, 0.001)
        assertEquals(1.0, week[5].ratio, 0.001)
    }

    @Test
    fun `有活动但量很小时给最小高度，否则柱子看不见`() {
        val week = Report.withRatios(
            Report.recentDays(
                days(
                    day(0, 100, 0, 0),
                    day(-1, 1, 0, 0)
                ),
                now
            )
        )
        assertTrue("1 个字相对 100 个字，也得看得见", week[5].ratio >= 0.08)
        assertEquals(1.0, week[6].ratio, 0.001)
    }

    @Test
    fun `全空时比例是 0，不会除零`() {
        val week = Report.withRatios(Report.recentDays(null, now))
        week.forEach { assertEquals(0.0, it.ratio, 0.0) }
    }

    @Test
    fun `build 一次给齐页面要的东西`() {
        val r = Report.build(days(day(0, 3, 10, 8)), now)
        assertEquals(7, r.week.size)
        assertNotNull(r.sum)
        assertTrue(r.headline.isNotEmpty())
        assertTrue(r.advice.isNotEmpty())
        // 页面直接拿去用：比例已经算好
        assertEquals(1.0, r.week[6].ratio, 0.001)
    }

    /**
     * 结论的**逐字**黄金值。
     *
     * 这四条字符串是从小程序 `pages/report/report.js` 的 `verdictOf` 直接跑
     * 出来的原文。Android 把 verdict 挪进了纯逻辑层（好测），但输出必须一字
     * 不差——家长在两个端看到的同一周周报，措辞不一样就是不专业。
     */
    @Test
    fun `结论的文案与小程序逐字一致`() {
        // a) 空周
        val empty = Report.summarize(Report.recentDays(null, now))
        assertEquals("这周还没有学习记录", Report.verdict(empty))

        // b) 只学了字、一题没答（activeDays 由学习量推出）
        val b = Report.summarize(
            Report.recentDays(days(day(0, 3, 0, 0), day(-1, 2, 0, 0)), now)
        )
        assertEquals("这周认识 5 个字，来了 2 天", Report.verdict(b))
        assertNull("这里本来就没答题", b.accuracy)

        // c) 学了，也答题了
        val c = Report.summarize(
            Report.recentDays(days(day(0, 3, 10, 8), day(-1, 2, 0, 0)), now)
        )
        assertEquals("这周认识 5 个字，答题 10 道，来了 2 天", Report.verdict(c))

        // d) 三项都有值
        val d = Report.summarize(
            Report.recentDays(
                days(
                    day(0, 9, 20, 18),
                    day(-1, 6, 10, 9),
                    day(-2, 4, 6, 5),
                    day(-3, 2, 3, 3),
                    day(-4, 2, 2, 1)
                ),
                now
            )
        )
        assertEquals("这周认识 23 个字，答题 41 道，来了 5 天", Report.verdict(d))
    }

    @Test
    fun `结论描述做了什么，不评价孩子`() {
        val week = Report.recentDays(days(day(0, 3, 10, 8), day(-1, 2, 0, 0)), now)
        val sum = Report.summarize(week)
        val verdict = Report.verdict(sum)
        assertTrue(verdict, verdict.contains("认识 5 个字"))
        assertTrue(verdict, verdict.contains("答题 10 道"))
        assertTrue(verdict, verdict.contains("来了 2 天"))
        assertEquals("tip", Report.verdictTone(sum)) // 只来了 2 天

        val empty = Report.summarize(Report.recentDays(null, now))
        assertEquals("这周还没有学习记录", Report.verdict(empty))
        assertEquals("plain", Report.verdictTone(empty))
    }
}
