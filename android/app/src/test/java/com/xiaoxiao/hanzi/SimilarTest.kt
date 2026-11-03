package com.xiaoxiao.hanzi

import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Plan
import com.xiaoxiao.hanzi.logic.Progress
import com.xiaoxiao.hanzi.logic.Quiz
import com.xiaoxiao.hanzi.logic.Store
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * 形近字辨析。
 *
 * 与同音字正好互补：同音字考「音一样，写哪个」（袋/带），
 * 形近字考「长得像，别混」（未/末、天/夫）。这两个是低年级错字的两个主因。
 *
 * 表不是人工标注的，是用笔顺数据算出来的（scripts/build-similar.mjs）。
 * 所以这里既要保证算法质量（该收的收到、不该收的没混进来），
 * 也要锁住生成结果不随环境漂移。
 *
 * 与 iOS `testSimilarCharsCoverTypicalConfusions` 等、
 * 小程序 `tests/similar.test.mjs` 对应。
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SimilarTest {

    companion object {
        @BeforeClass
        @JvmStatic
        fun load() {
            val assets = File("src/main/assets/data")
            Repo.loadFromStrings(
                File(assets, "catalog.json").readText(),
                File(assets, "meta.json").readText(),
                File(assets, "strokes.json").readText(),
                File(assets, "similar.json").readText()
            )
        }
    }

    /** 这些是语文老师会点名讲的对子，一个都不能漏 */
    @Test
    fun `形近字收录了低年级最典型的混淆对`() {
        val mustHave = listOf(
            "日" to "目", "天" to "夫", "木" to "术", "大" to "太",
            "未" to "末", "己" to "已", "土" to "士", "鸟" to "乌",
            "人" to "入", "木" to "本", "牛" to "午", "白" to "自"
        )
        for ((a, b) in mustHave) {
            assertTrue(
                "$a 的形近字里应该有 $b，实际是 ${Repo.similarChars(a).joinToString("")}",
                Repo.similarChars(a).contains(b)
            )
            // 关系必须对称
            assertTrue("$b 的形近字里应该有 $a", Repo.similarChars(b).contains(a))
        }
    }

    /**
     * 每一个候选对都必须笔画数相同或差 1——差两笔以上的字，
     * 孩子数一遍笔画就能分开，不构成混淆。
     */
    @Test
    fun `形近字笔画数相差不超过一`() {
        for (ch in Repo.allSimilarChars().take(400)) {
            val sc = Repo.meta(ch)?.strokes ?: continue
            for (other in Repo.similarChars(ch)) {
                val so = Repo.meta(other)?.strokes ?: continue
                assertTrue(
                    "$ch($sc 画) 与 $other($so 画) 笔画数差太多",
                    Math.abs(so - sc) <= 1
                )
            }
        }
    }

    @Test
    fun `形近字不会把字自己列进去`() {
        for (ch in Repo.allSimilarChars()) {
            assertFalse("$ch 的形近字里出现了自己", Repo.similarChars(ch).contains(ch))
        }
    }

    /**
     * 覆盖率是生成算法参数的直接后果，改动脚本时会变——
     * 变了就要重新看一眼样本质量，所以锁死。
     */
    @Test
    fun `形近字规模`() {
        assertEquals(2569, Repo.allSimilarChars().size)
        for (ch in Repo.allSimilarChars()) {
            assertTrue(Repo.similarChars(ch).size <= 5)
        }
        // 一到二年级四册都要有足够的题源，否则练习入口常年是灰的
        for (b in listOf("1a", "1b", "2a", "2b")) {
            val n = Repo.bookSimilarChars(b).size
            assertTrue("$b 只有 $n 个形近字，组不出一套像样的题", n >= 60)
        }
    }

    /** 干扰项必须真的是形近字，否则孩子扫一眼就能排除，练不到辨析 */
    @Test
    fun `形近字题的干扰项都是形近字`() {
        val r = Quiz.build(
            listOf("天", "大", "本", "术", "日", "目"), "1a", null, 6, 20240101L,
            listOf("similar")
        )
        assertTrue(r.questions.size >= 4)
        for (q in r.questions) {
            assertEquals("similar", q.type)
            assertEquals(4, q.options.size)
            assertTrue(q.options.any { it.value == q.answer })
            for (o in q.options) {
                if (o.value == q.answer) continue
                assertTrue(
                    "${o.value} 不是 ${q.ch} 的形近字",
                    Repo.similarChars(q.ch).contains(o.value)
                )
            }
        }
    }

    @Test
    fun `形近字题的答案一定在选项里`() {
        for (seed in listOf(1L, 42L, 20240101L)) {
            val r = Quiz.build(
                listOf("天", "大", "本", "术", "日", "目"), "1a", null, 6, seed,
                listOf("similar")
            )
            for (q in r.questions) {
                assertTrue(
                    "seed=$seed 的 ${q.ch} 题答案不在选项里",
                    q.options.any { it.value == q.answer }
                )
            }
        }
    }

    @Test
    fun `形近字模式能组出一套完整的题`() {
        val prog = Progress(Store(ApplicationProvider.getApplicationContext()))
        val s = Plan.buildSession("similar", prog, "2a")
        assertEquals("similar", s.mode)
        assertTrue(s.chars.size >= 4)
        for (ch in s.chars) {
            assertTrue("$ch 没有形近字却被选进形近字练习", Repo.hasSimilar(ch))
        }
    }

    /**
     * 跨端黄金值：同一 seed 三端必须出完全相同的题（含选项顺序）。
     *
     * 期望值由小程序 `utils/quiz.js` 算出；iOS 侧同名断言一致。
     * 光有 RNG 黄金值不够——它只证明随机数发生器一致，不证明**调用顺序**一致。
     */
    @Test
    fun `同 seed 三端出同一套形近字题`() {
        val chars = Repo.bookSimilarChars("2a").take(5)
        val r = Quiz.build(chars, "2a", null, 5, 20240101L, listOf("similar"))
        val got = r.questions.map {
            "${it.ch}|${it.prompt}|${it.options.joinToString("") { o -> o.value }}"
        }
        assertEquals(
            listOf(
                "塘|水＿|填塘塔搭",
                "脑|呆头呆＿|掘脑柱恼",
                "袋|＿子|紫柴袋装",
                "灰|＿白|东灰发灵",
                "哇|好＿|佳桂咕哇"
            ),
            got
        )
    }
}
