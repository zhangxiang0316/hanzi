package com.xiaoxiao.hanzi

import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Plan
import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.logic.Progress
import com.xiaoxiao.hanzi.logic.Store
import com.xiaoxiao.hanzi.logic.Quiz
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
 * 多音字。
 *
 * 数据来自 meta.json 的 `rd` 字段：每个读音都标了它出现在哪一课。
 * 用例词靠「本字在词中的位置」与「拼音音节位置」对齐来反推，
 * 不能用「拼音里出现过该音节」——同一个词里另一个字恰好同音时会串。
 *
 * 这几个断言与 iOS `LogicTests` 里的多音字用例一一对应。
 */
@RunWith(RobolectricTestRunner::class)
// sdk=34 与 AppUiTest 一致：SDK 36 的 Robolectric 沙箱要求 Java 21，本机是 17
@Config(sdk = [34])
class PolyphoneTest {

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
    fun `多音字总数是 156`() {
        assertEquals(156, Repo.allPolyphones().size)
    }

    @Test
    fun `识别多音字`() {
        assertTrue(Repo.isPolyphone("数"))
        assertTrue(Repo.isPolyphone("地"))
        assertTrue(Repo.isPolyphone("乐"))
        assertFalse(Repo.isPolyphone("天"))
    }

    @Test
    fun `用例词按位置对齐不会串音`() {
        // 「数」读 shù 与 shǔ —— 「无数」是 shù，「数落」是 shǔ
        val shu4 = Repo.wordsUsing("数", "shù")
        val shu3 = Repo.wordsUsing("数", "shǔ")
        assertTrue("shù 应匹配到「无数」，实际 $shu4", shu4.contains("无数"))
        assertTrue("shǔ 应匹配到「数落」，实际 $shu3", shu3.contains("数落"))
        assertFalse("「数落」不该被算成 shù", shu4.contains("数落"))
        assertFalse("「无数」不该被算成 shǔ", shu3.contains("无数"))
    }

    @Test
    fun `每个多音字都至少有一个读音能配到用例`() {
        val gaps = Repo.allPolyphones().filter { ch ->
            Repo.polyphoneCases(ch).none { it.second.isNotEmpty() }
        }
        assertTrue("这些多音字配不到任何用例词：$gaps", gaps.isEmpty())
    }

    @Test
    fun `多音字题有真实词语境且选项是本字读音`() {
        val r = Quiz.build(listOf("乐"), book = "1a", count = 6, seed = 12345,
            types = listOf("polyphone"))
        assertTrue("「乐」应该能出多音字题", r.questions.isNotEmpty())
        for (q in r.questions) {
            assertEquals("polyphone", q.type)
            assertTrue("prompt 应是用例词，实际 ${q.prompt}", q.prompt.contains("乐"))
            val opts = q.options.map { it.value }.toSet()
            assertTrue(opts.contains("yuè"))
            assertTrue(opts.contains("lè"))
            assertTrue(opts.contains(q.answer))
            assertTrue(q.explain.contains("多音字"))
        }
    }

    @Test
    fun `多音字模式只出多音字题`() {
        val prog = Progress(Store(ApplicationProvider.getApplicationContext()))
        val s = Plan.buildSession("polyphone", prog, "1a")
        assertEquals("polyphone", s.mode)
        assertTrue(s.chars.isNotEmpty())
        for (ch in s.chars) {
            assertTrue("$ch 不是多音字却被选进多音字模式", Repo.isPolyphone(ch))
        }
        val r = Quiz.build(s.chars, "1a", null, s.count, 999, types = listOf("polyphone"))
        assertTrue(r.questions.isNotEmpty())
        assertTrue(r.questions.all { it.type == "polyphone" })
    }

    @Test
    fun `普通闯关不出现多音字题`() {
        // 不传 types 时题型轮转必须和以前完全一致（不含 polyphone）
        val r = Quiz.build(listOf("天", "地", "人", "你", "我", "他"),
            book = "1a", count = 8, seed = 12345)
        assertTrue(r.questions.isNotEmpty())
        assertTrue("普通闯关不应出现多音字题",
            r.questions.none { it.type == "polyphone" })
    }

    @Test
    fun `例句优先选低年级的词`() {
        // 「数落」里「落」是三上才学的字，一年级孩子看不懂；
        // 排序后应优先给整词都在本册或更早的用例。
        val cases = Repo.polyphoneCases("数")
        for ((_, words) in cases) {
            if (words.size < 2) continue
            val ranks = words.map { Repo.wordRank(it) }
            assertEquals("用例词没有按难度排序：$words", ranks.sorted(), ranks)
        }
    }

    /**
     * 三端一致性：同一个字表 + 同一个 seed，必须出完全相同的多音字题。
     *
     * 期望值取自小程序 `utils/quiz.js` 的实跑结果（seed=12345）。
     * 三端各有一份独立的 mulberry32 和 shuffle，任何一处写歪这里都会红。
     */
    @Test
    fun `多音字出题与小程序逐题一致`() {
        val r = Quiz.build(listOf("乐", "数", "地", "没"), book = "1a", count = 6,
            seed = 12345, types = listOf("polyphone"))
        val got = r.questions.map { "${it.ch}|${it.prompt}|${it.answer}|${it.options.joinToString("/") { o -> o.value }}" }
        val want = listOf(
            "乐|乐曲|yuè|lè/yuè",
            "数|不可计数|shù|shǔ/shù",
            "地|地道|dì|dì/de",
            "没|没精打采|méi|méi/mò",
            "乐|欢乐|lè|yuè/lè",
            "数|不计其数|shù|shǔ/shù"
        )
        assertEquals("Android 的多音字出题与小程序不一致：\n实际 $got\n期望 $want", want, got)
    }

    @Test
    fun `可用词还有富余时不出现重复题面`() {
        val available = Repo.polyphoneCases("乐").sumOf { it.second.size }
        assertTrue("「乐」应该有多个用例词", available > 1)

        val r = Quiz.build(listOf("乐"), book = "1a", count = available,
            seed = 777, types = listOf("polyphone"))
        val prompts = r.questions.map { it.prompt }
        assertEquals("可用词还有富余时出现了重复题面：$prompts", prompts.toSet().size, prompts.size)

        // 词用完之后允许重复，但每道题的答案都必须是「乐」的真实读音之一
        val more = Quiz.build(listOf("乐"), book = "1a", count = available + 3,
            seed = 777, types = listOf("polyphone"))
        val valid = Repo.readingsOf("乐").toSet()
        for (q in more.questions) {
            assertTrue("答案 ${q.answer} 不是「乐」的读音", valid.contains(q.answer))
        }
    }

}
