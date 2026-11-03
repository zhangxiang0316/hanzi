package com.xiaoxiao.hanzi

import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Plan
import com.xiaoxiao.hanzi.logic.Progress
import com.xiaoxiao.hanzi.logic.Quiz
import com.xiaoxiao.hanzi.logic.Store
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * 部首。
 *
 * 部首查字法是二年级语文园地的正式内容，但 `CharMeta.radical` 一直只在
 * 解析文案里出现过，从没当成学习维度用过。
 *
 * 237 个部首里只有 144 个是字库里的生字（能画笔顺），另外 93 个是偏旁变形
 * （亻 艹 扌 讠 纟 宀）——所以部首只以文字形式出现，不参与描红判分。
 *
 * 与 iOS `testRadicalCountsAndOrder` 等、小程序 `tests/radical.test.mjs` 对应。
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RadicalTest {

    companion object {
        @BeforeClass
        @JvmStatic
        fun load() {
            val assets = File("src/main/assets/data")
            Repo.loadFromStrings(
                File(assets, "catalog.json").readText(),
                File(assets, "meta.json").readText(),
                File(assets, "strokes.json").readText()
            )
        }
    }

    @Test
    fun `部首数量与排序`() {
        val all = Repo.allRadicals()
        assertEquals(237, all.size)
        // 口144 扌138 氵132
        assertEquals(listOf("口", "扌", "氵"), all.take(3).map { it.first })
        assertEquals(listOf(144, 138, 132), all.take(3).map { it.second })
        // 频次单调不增
        for (i in 1 until all.size) {
            assertTrue("应按频次降序", all[i - 1].second >= all[i].second)
        }
    }

    @Test
    fun `每个字都有部首`() {
        val missing = Repo.allChars.filter { Repo.radicalOf(it).isEmpty() }
        assertTrue("缺部首的字：${missing.take(10)}", missing.isEmpty())
        assertEquals("土", Repo.radicalOf("地"))
        assertEquals("页", Repo.radicalOf("顶"))
    }

    @Test
    fun `某册部首只用本册的字统计`() {
        val rads = Repo.bookRadicals("2a")
        assertTrue("2a 部首应有 50+ 个，实际 ${rads.size}", rads.size > 50)
        val bookChars = Repo.bookChars("2a").toSet()
        Repo.charsWithRadical("2a", "氵").forEach { ch ->
            assertTrue("$ch 不属于 2a", bookChars.contains(ch))
            assertEquals("氵", Repo.radicalOf(ch))
        }
    }

    @Test
    fun `部首干扰项排除字形包含关系`() {
        val ds = Repo.radicalDistractors("木", "2a", 3)
        assertEquals(3, ds.size)
        ds.forEach { d ->
            assertNotEquals("木", d)
            // 「木」和「林」这种有争议，不该当干扰项
            assertFalse("$d 与「木」有字形包含关系，有歧义", d.contains("木"))
            assertFalse("木".contains(d))
        }
    }

    @Test
    fun `部首题四个选项互不相同且答案在内`() {
        val chars = Repo.bookChars("2a").drop(10).take(10)
        val r = Quiz.build(chars, "2a", null, 5, 20240101L, listOf("radical"))
        assertEquals(5, r.questions.size)

        r.questions.forEach { q ->
            assertEquals("radical", q.type)
            assertEquals(4, q.options.size)
            assertEquals("选项不能重复", 4, q.options.map { it.value }.toSet().size)
            assertTrue("答案必须在选项里", q.options.any { it.value == q.answer })
            assertEquals(Repo.radicalOf(q.ch), q.answer)
        }
    }

    /**
     * 回归测试：某个字出不了题时，不能卡死在它身上。
     *
     * `Quiz.build` 原来用 `questions.size` 决定取哪个字。如果某个字出不了题
     * （独体字的部首就是它自己，答案印在题干上），questions.size 不增长，
     * 就会**永远重试同一个字**，直到 guard 耗尽——整套题变成 0 道。
     *
     * 修复：改用尝试次数推进取字。
     */
    @Test
    fun `出不了题的字不会卡死整套题`() {
        // 龟、鼓 的部首就是它们自己，radical 题型会返回 null
        val r = Quiz.build(listOf("龟", "顶", "鼓", "披"), "2a", null, 2, 1L, listOf("radical"))
        assertEquals("应跳过独体字继续出题，而不是 0 道", 2, r.questions.size)
        r.questions.forEach { q ->
            assertNotEquals("独体字不该出部首题（答案就是题干）", q.ch, q.answer)
            assertNotEquals(Repo.radicalOf(q.ch), q.ch)
        }
    }

    @Test
    fun `全是独体字时出 0 道是对的`() {
        val r = Quiz.build(listOf("龟", "鼓"), "2a", null, 2, 1L, listOf("radical"))
        assertTrue(r.questions.isEmpty())
    }

    @Test
    fun `部首会话排除独体字`() {
        val prog = Progress(Store(ApplicationProvider.getApplicationContext()))
        val s = Plan.buildSession("radical", prog, "2a")
        assertEquals("radical", s.mode)
        assertTrue(s.chars.size >= 4)
        s.chars.forEach { ch ->
            assertNotEquals("$ch 是独体字，不该进部首会话", Repo.radicalOf(ch), ch)
        }
    }
    /**
     * 跨端黄金值：同一 seed 三端必须出完全相同的题（含选项顺序）。
     *
     * 期望值由小程序 `utils/quiz.js` 算出；iOS 侧同名断言一致。
     */
    @Test
    fun `同 seed 三端出同一套部首题`() {
        val chars = Repo.bookChars("2a").drop(10).take(10)
        val r = Quiz.build(chars, "2a", null, 5, 20240101L, listOf("radical"))
        val got = r.questions.map {
            "${it.ch}|${it.answer}|${it.options.joinToString("|") { o -> o.value }}"
        }
        assertEquals(
            listOf(
                "顶|页|扌|页|木|氵",
                "披|扌|木|扌|氵|亻",
                "晒|日|氵|日|木|扌",
                "极|木|扌|木|氵|亻",
                "傍|亻|木|扌|氵|亻"
            ),
            got
        )
    }

}
