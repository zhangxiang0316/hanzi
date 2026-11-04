package com.xiaoxiao.hanzi.logic

import java.util.Date

/**
 * 学习周报：把 `stats.days` 里逐日攒下的数据变成家长看得懂的报告。
 *
 * ## 为什么值得单独做一页
 *
 * `stats.days` 从第一个版本起就在逐日记录 `{learned, answers, correct}`，
 * 但它只被「活跃天数」一个徽章间接用过一次——数据一直在攒，从来没被读过。
 * 对家长来说，「今天学了几个字」在首页能看到，「这一周怎么样」看不到，
 * 而那才是他们真正关心的粒度。
 *
 * ## 为什么是「最近 7 天」而不是「本周一到周日」
 *
 * 日历周有个很难受的副作用：周一早上打开，整周几乎全是空的，看起来像
 * 「什么都没做」。滚动 7 天永远是「最近这一周」，任何时候打开都有意义。
 *
 * 代价是同一个字可能被算进两周，但周报是给家长看趋势的，不是做账。
 *
 * ## 数据可能缺失
 *
 * 用户可能中间几天没用，`stats.days` 里就没有那天的键——**不能当成 0 分**，
 * 要区分「那天没学」和「那天学了但没答对」。所以缺的天填 `active = false`，
 * 而不是 `accuracy = 0`。
 *
 * 与小程序 `utils/report.js`、iOS `Logic/Report.swift` 的口径严格一致。
 */
object Report {

    /** 一周按周一→周日排，和家长的习惯一致（而不是周日打头） */
    val WEEKDAYS = listOf("一", "二", "三", "四", "五", "六", "日")

    /**
     * 一天。
     *
     * [accuracy] 为 null 表示「没答题」——不是 0%。这是整份报告里最容易
     * 搞错、也最要紧的一条：显示 0% 会让家长以为孩子全答错了。
     *
     * [ratio] 只有经过 [withRatios] 之后才有意义，是柱状图的高度比例。
     */
    data class Day(
        val key: String,
        val daysAgo: Int,
        val weekday: String,
        val date: String,
        val learned: Int,
        val answers: Int,
        val correct: Int,
        val accuracy: Int?,
        val active: Boolean,
        val ratio: Double = 0.0
    )

    /** 一周的汇总 */
    class Summary(
        val learned: Int,
        val answers: Int,
        val correct: Int,
        val accuracy: Int?,
        val activeDays: Int,
        val span: Int,
        val best: Day?,
        val empty: Boolean
    )

    /** 给家长的一条分析；[tone] 取 good / tip / plain */
    data class Advice(val tone: String, val text: String)

    /** 整份周报 */
    class Built(
        val week: List<Day>,
        val sum: Summary,
        val headline: String,
        val advice: List<Advice>
    )

    /**
     * 取最近 [span] 天的逐日数据，从最早到最近，最后一项一定是今天。
     *
     * [daysStats] 就是 `stats.days` 的形状：`{ '2026-11-03': DayStat }`。
     * `daysAgo` 是「几天前」，0 = 今天；不用负偏移是为了避开 `-0` 这类坑。
     */
    fun recentDays(
        daysStats: Map<String, Progress.DayStat>?,
        now: Date = Date(),
        span: Int = 7
    ): List<Day> {
        val n = if (span > 0) span else 7
        val out = ArrayList<Day>(n)
        // 从 n-1 天前走到今天，保证最后一项是今天
        for (i in n - 1 downTo 0) {
            val d = DayUtil.dateOfOffset(now, -i)
            val key = DayUtil.todayKey(d)
            val rec = daysStats?.get(key)
            val learned = rec?.learned ?: 0
            val answers = rec?.answers ?: 0
            val correct = rec?.correct ?: 0
            out.add(
                Day(
                    key = key,
                    daysAgo = i,
                    weekday = WEEKDAYS[DayUtil.weekdayIndexMonFirst(d)],
                    date = DayUtil.dateLabel(d),
                    learned = learned,
                    answers = answers,
                    correct = correct,
                    // 一题没答时不算准确率——记成 0% 会让家长以为全错
                    accuracy = if (answers > 0) Math.round(correct.toDouble() / answers * 100).toInt() else null,
                    active = learned > 0 || answers > 0
                )
            )
        }
        return out
    }

    /** 汇总一周。 */
    fun summarize(week: List<Day>?): Summary {
        val list = week ?: emptyList()
        var learned = 0
        var answers = 0
        var correct = 0
        var activeDays = 0
        var best: Day? = null

        for (d in list) {
            learned += d.learned
            answers += d.answers
            correct += d.correct
            if (d.active) activeDays += 1
            // 「最好的一天」按学习量算，答题量作为平手时的次序。
            // 只在活跃的日子里挑：没学的那天 learned 是 0，本来也赢不了，
            // 但显式判断一下，语义才和「最好的一天」这个说法对得上。
            val b = best
            if (d.active && (b == null || d.learned > b.learned
                    || (d.learned == b.learned && d.answers > b.answers))
            ) {
                best = d
            }
        }

        return Summary(
            learned = learned,
            answers = answers,
            correct = correct,
            // 整周没答题就没有准确率，不是 0%
            accuracy = if (answers > 0) Math.round(correct.toDouble() / answers * 100).toInt() else null,
            activeDays = activeDays,
            span = list.size,
            best = best,
            // 完全没动过的一周要能被识别出来，好给一句鼓励而不是一张空表
            empty = learned == 0 && answers == 0
        )
    }

    /**
     * 给孩子看的一句话。
     *
     * 有意写得短、可读完：周报的读者是家长，但这句是念给孩子听的。
     * 不用「正确率 87%」这种数字，孩子对它没有感觉。
     */
    fun headline(sum: Summary): String = when {
        sum.empty -> "这周还没开始，今天写一个字就开张啦"
        sum.activeDays >= 7 -> "整整七天没断过，太厉害了"
        sum.activeDays >= 5 -> "这周来了 ${sum.activeDays} 天，很稳"
        sum.activeDays >= 3 -> "这周来了 ${sum.activeDays} 天，继续保持"
        else -> "这周来了 ${sum.activeDays} 天，明天再来一次就更好"
    }

    /**
     * 给家长的分析。比 [headline] 具体，可以提数字。
     *
     * 空周只给一句：一屏全是「这周 0 个字」只会让家长觉得被指责，
     * 而不是被帮到。
     */
    fun advice(sum: Summary, week: List<Day>?): List<Advice> {
        val out = ArrayList<Advice>()
        val list = week ?: emptyList()

        if (sum.empty) {
            out.add(Advice("plain", "这一周还没有学习记录。每天 5 分钟，先从「每日任务」开始。"))
            return out
        }

        if (sum.learned > 0) {
            val avg = if (sum.activeDays > 0) {
                // 一位小数就够，家长不需要 3.4285 这种数字
                "，平均每天 ${oneDecimal(sum.learned.toDouble() / sum.activeDays)} 个"
            } else {
                ""
            }
            out.add(Advice("good", "这周认识了 ${sum.learned} 个字$avg。"))
        }

        val acc = sum.accuracy
        if (acc != null) {
            out.add(
                when {
                    acc >= 85 -> Advice("good", "答题正确率 $acc%，很扎实。")
                    acc >= 65 -> Advice("plain", "答题正确率 $acc%，还有几个字没记牢。")
                    else -> Advice("tip", "答题正确率 $acc%，建议放慢速度，多复习几次再往下学。")
                }
            )
        }

        // 中断过就说中断——这是家长最需要知道的，不然一周下来会以为孩子天天在学
        val missing = list.count { !it.active }
        if (missing > 0 && missing < list.size) {
            out.add(
                Advice(
                    "plain",
                    "有 $missing 天没有学习记录。每天固定一个时间学，比一次学很久有用。"
                )
            )
        }

        // 学习量和正确率都在高位时，提醒往下走
        if (sum.learned >= 35 && acc != null && acc >= 85) {
            out.add(Advice("good", "进度和正确率都不错，可以试试「识字量测试」看看现在到了多少。"))
        }

        return out
    }

    /**
     * 把一周的数值缩到 0~1，给柱状图用。
     *
     * 按学习量和答题量的较大者归一：只看学习量的话，
     * 「今天复习了 30 道题」会画成一根空柱子。
     *
     * 有活动但数值很小时给个最小高度（0.08），否则柱子是 0 像素看不见。
     */
    fun withRatios(week: List<Day>?): List<Day> {
        val list = week ?: emptyList()
        var peak = 0.0
        for (d in list) {
            peak = maxOf(peak, d.learned.toDouble(), Math.ceil(d.answers / 4.0))
        }
        return list.map { d ->
            val v = maxOf(d.learned.toDouble(), Math.ceil(d.answers / 4.0))
            val ratio = if (peak == 0.0) 0.0 else maxOf(v / peak, if (d.active) 0.08 else 0.0)
            // 留两位小数，界面直接当百分比用，不必再格式化
            d.copy(ratio = Math.round(ratio * 100) / 100.0)
        }
    }

    /** 一次算好整份周报，页面直接渲染就够。 */
    fun build(
        daysStats: Map<String, Progress.DayStat>?,
        now: Date = Date(),
        span: Int = 7
    ): Built {
        val week = withRatios(recentDays(daysStats, now, span))
        val sum = summarize(week)
        return Built(week, sum, headline(sum), advice(sum, week))
    }

    // ---------- 页面用的结论（小程序放在页面里，这里也收进纯逻辑好测） ----------

    /**
     * 一句话结论。
     *
     * 家长翻周报先扫结论；数字是佐证，不该是第一眼看到的东西。
     * 措辞只描述**做了什么**，不评价孩子——「这周学了 23 个字」比
     * 「学习不够努力」有用得多。
     */
    fun verdict(sum: Summary): String {
        if (sum.empty) return "这周还没有学习记录"
        val parts = ArrayList<String>()
        if (sum.learned > 0) parts.add("认识 ${sum.learned} 个字")
        if (sum.answers > 0) parts.add("答题 ${sum.answers} 道")
        if (sum.activeDays > 0) parts.add("来了 ${sum.activeDays} 天")
        return "这周" + parts.joinToString("，")
    }

    /** 结论的口气：good / tip / plain */
    fun verdictTone(sum: Summary): String {
        if (sum.empty) return "plain"
        val acc = sum.accuracy
        if (sum.activeDays >= 5 && (acc == null || acc >= 80)) return "good"
        if (sum.activeDays <= 2) return "tip"
        return "plain"
    }

    /** 保留一位小数，整数时不带 `.0`——「平均每天 3 个」比「3.0 个」自然 */
    private fun oneDecimal(v: Double): String {
        val r = Math.round(v * 10) / 10.0
        return if (r == Math.floor(r)) r.toInt().toString() else r.toString()
    }
}
