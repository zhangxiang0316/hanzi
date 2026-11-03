package com.xiaoxiao.hanzi

import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Plan
import com.xiaoxiao.hanzi.logic.Progress
import com.xiaoxiao.hanzi.logic.Quiz
import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.logic.Store
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.junit.Test
import java.io.File

/**
 * 同音字辨析。
 *
 * 同音字是听写最主要的错因：「地弟第递」读音一样、字形不同，
 * 记住音不等于会写。数据不用新增——`CharMeta.py` 按读音分组就能得到。
 *
 * 与多音字互补：多音字练「一个字有几个音」，同音字练「一个音有几个字」。
 *
 * 与 iOS `testHomophonesGroupedByFullPinyin` 等、小程序 `tests/homophone.test.mjs` 对应。
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HomophoneTest {

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
    fun `同音字按完整拼音含声调分组`() {
        assertEquals(setOf("弟", "第", "帝", "递"), Repo.homophones("地").toSet())
        assertTrue(Repo.homophones("天").contains("添"))
        // 声调不同不算同音：「地」是 dì，「底」是 dǐ
        assertFalse(Repo.homophones("地").contains("底"))
        // 不含自己
        assertFalse(Repo.homophones("天").contains("天"))
    }

    @Test
    fun `同音字组规模与分布`() {
        // 八册累加（同一组跨册会各算一次）= 382
        val total = Repo.books.sumOf { Repo.homophoneGroups(it.id).size }
        assertEquals(382, total)

        // 全库去重 = 588
        val byPy = HashMap<String, MutableList<String>>()
        Repo.allChars.forEach { ch ->
            val py = Repo.meta(ch)?.py ?: return@forEach
            if (py.isEmpty()) return@forEach
            byPy.getOrPut(py) { ArrayList() }.add(ch)
        }
        assertEquals(588, byPy.values.count { it.size >= 2 })
    }

    @Test
    fun `某册的同音字组只用本册的字`() {
        val groups = Repo.homophoneGroups("2a")
        assertTrue("2a 同音字组应超过 30，实际 ${groups.size}", groups.size > 30)
        val chars = Repo.bookChars("2a").toSet()
        groups.forEach { (py, list) ->
            list.forEach { ch ->
                assertTrue("$ch 不属于 2a，不该出现在本册分组里", chars.contains(ch))
                assertEquals("组内读音必须一致", py, Repo.meta(ch)?.py)
            }
        }
    }

    @Test
    fun `干扰项必须同音`() {
        val ds = Repo.homophoneDistractors("坐", "2a", 3)
        assertEquals(3, ds.size)
        val py = Repo.meta("坐")?.py
        ds.forEach { d ->
            assertEquals("$d 不和「坐」同音，当干扰项等于送分", py, Repo.meta(d)?.py)
            assertNotEquals("坐", d)
        }
    }

    @Test
    fun `同音字题选项全部同音且答案在内`() {
        val chars = Repo.homophoneChars("2a").take(6)
        val r = Quiz.build(chars, "2a", null, 6, 20240101L, listOf("homophone"))
        assertTrue("应出至少 4 题，实际 ${r.questions.size}", r.questions.size >= 4)

        r.questions.forEach { q ->
            assertEquals("homophone", q.type)
            assertEquals(4, q.options.size)
            assertTrue("答案必须在选项里", q.options.any { it.value == q.answer })
            // 核心断言：每个干扰项都必须和答案同音，否则这道题就白出了
            val py = Repo.meta(q.answer)?.py
            q.options.forEach { o ->
                assertEquals("${o.value} 与 ${q.answer} 不同音", py, Repo.meta(o.value)?.py)
            }
            assertTrue("题面应有空格", q.prompt.contains("＿"))
        }
    }

    @Test
    fun `没有同音伙伴的字不出同音字题`() {
        val lonely = Repo.allChars.firstOrNull { !Repo.hasHomophones(it) }
        assertTrue("应存在没有同音字的字", lonely != null)
        val r = Quiz.build(listOf(lonely!!), "2a", null, 3, 1L, listOf("homophone"))
        assertTrue("$lonely 没有同音字，不该出题", r.questions.isEmpty())
    }

    @Test
    fun `同音字会话只挑有同音伙伴的字`() {
        val prog = Progress(Store(ApplicationProvider.getApplicationContext()))
        val s = Plan.buildSession("homophone", prog, "2a")
        assertEquals("homophone", s.mode)
        assertTrue(s.chars.size >= 4)
        s.chars.forEach { ch ->
            assertTrue("$ch 没有同音字，不该进会话", Repo.hasHomophones(ch))
        }
    }
    /**
     * 跨端黄金值：同一 seed 三端必须出完全相同的题（含选项顺序）。
     *
     * 期望值由小程序 `utils/quiz.js` 算出；iOS 侧同名断言一致。
     * 光有 RNG 黄金值不够——它只证明随机数发生器一致，不证明**调用顺序**一致。
     */
    @Test
    fun `同 seed 三端出同一套同音字题`() {
        val chars = Repo.homophoneChars("2a").take(5)
        val r = Quiz.build(chars, "2a", null, 5, 20240101L, listOf("homophone"))
        val got = r.questions.map {
            "${it.ch}|${it.prompt}|${it.answer}|${it.options.joinToString("|") { o -> o.value }}"
        }
        assertEquals(
            listOf(
                "袋|口＿|袋|带|袋|戴|代",
                "龟|＿甲|龟|瑰|龟|归|规",
                "鼓|重整旗＿|鼓|骨|谷|鼓|股",
                "极|＿大|极|即|极|吉|及",
                "溪|＿水|溪|吸|希|锡|溪"
            ),
            got
        )
    }

}
