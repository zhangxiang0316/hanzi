package com.xiaoxiao.hanzi.logic

/**
 * Leitner 间隔复习。
 *
 * 与小程序 utils/srs.js 逐行对应：箱子 0-7 对应复习间隔 0/1/2/4/7/15/30/60 天。
 * 保持纯函数，方便直接用 JVM 单测对比两边行为。
 */
object Srs {
    val INTERVALS = intArrayOf(0, 1, 2, 4, 7, 15, 30, 60)
    val MAX_BOX = INTERVALS.size - 1
    const val MASTERED_BOX = 5

    /** 一个字的学习状态。字段含义与小程序 progress 条目一致，便于迁移旧数据 */
    data class Entry(
        val box: Int = 0,
        val seen: Int = 0,
        val ok: Int = 0,
        val miss: Int = 0,
        val due: Int = 0,
        val last: Int = 0,
        val known: Boolean = false
    )

    fun isDue(entry: Entry?, today: Int): Boolean = entry != null && entry.due <= today

    fun isMastered(entry: Entry?): Boolean = entry != null && entry.box >= MASTERED_BOX

    fun isLearning(entry: Entry?): Boolean = entry != null && entry.box >= 1

    /** 第一次学习：进入箱子 1，明天复习。重复调用不会降级 */
    fun learn(entry: Entry?, today: Int): Entry {
        if (entry != null && entry.box >= 1) return entry
        val e = entry ?: Entry()
        return e.copy(box = 1, due = today + INTERVALS[1], last = today)
    }

    /** 答题评分：答对升一箱，答错回退（已较熟的字退到 1，生字退到 0） */
    fun grade(entry: Entry?, correct: Boolean, today: Int): Entry {
        val e = entry ?: Entry()
        val box = if (correct) {
            minOf(MAX_BOX, e.box + 1)
        } else {
            if (e.box >= 3) 1 else 0
        }
        return e.copy(
            seen = e.seen + 1,
            ok = if (correct) e.ok + 1 else e.ok,
            miss = if (correct) e.miss else e.miss + 1,
            box = box,
            due = today + INTERVALS[box],
            last = today
        )
    }

    /** 直接标记「已认识」（用于快速跳过已掌握的字） */
    fun markKnown(entry: Entry?, today: Int): Entry {
        val e = entry ?: Entry()
        val box = maxOf(e.box, 4)
        return e.copy(box = box, due = today + INTERVALS[box], last = today, known = true)
    }

    fun stageOf(entry: Entry?): String = when {
        entry == null -> "new"
        entry.box >= MASTERED_BOX -> "mastered"
        entry.box >= 1 -> "learning"
        else -> "weak"
    }

    val STAGE_LABEL = mapOf(
        "new" to "未学",
        "weak" to "待巩固",
        "learning" to "学习中",
        "mastered" to "已掌握"
    )
}
