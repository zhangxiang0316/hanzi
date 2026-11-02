package com.xiaoxiao.hanzi

import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.DictationLevel
import com.xiaoxiao.hanzi.logic.DictationSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import java.io.File

/**
 * 听写。
 *
 * 三档难度与 iOS `DictationLevel`、小程序 `utils/dictation.js` 语义一致。
 * 核心断言：难度只影响「显不显示底字」和「念什么」，不影响判分。
 */
class DictationTest {

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
    fun `三档难度的底字与朗读内容`() {
        assertTrue(DictationLevel.EASY.showsGhost)
        assertFalse(DictationLevel.NORMAL.showsGhost)
        assertFalse(DictationLevel.HARD.showsGhost)

        assertEquals("天空", DictationLevel.EASY.promptText("天", "天空"))
        assertEquals("天空", DictationLevel.NORMAL.promptText("天", "天空"))
        // HARD 只念字，不念词
        assertEquals("天", DictationLevel.HARD.promptText("天", "天空"))
        // 没有组词时退回念字，不能念空字符串
        assertEquals("天", DictationLevel.NORMAL.promptText("天", null))
    }

    @Test
    fun `听写只挑会写的字`() {
        val items = DictationSource.pick("1a", DictationLevel.NORMAL, 8)
        assertEquals(8, items.size)
        for (it in items) {
            // 只认不写的字（髓、嚼、蟹）要求孩子默写出来没有道理
            assertTrue("${it.ch} 是只认不写的字，不该进听写", Repo.isWriteChar(it.ch))
        }
    }

    @Test
    fun `hard 档不带词语提示`() {
        val items = DictationSource.pick("1a", DictationLevel.HARD, 5)
        for (it in items) {
            assertNull("hard 档不该带词语提示，否则等于告诉孩子答案", it.word)
        }
        val normal = DictationSource.pick("1a", DictationLevel.NORMAL, 5)
        assertTrue("normal 档应该带词语", normal.any { it.word != null })
    }

    @Test
    fun `按教材顺序取字而不是随机`() {
        // 听写是「今天学完这几课，默一遍」的场景，顺序对得上课文才有意义
        val a = DictationSource.pick("1a", DictationLevel.NORMAL, 5).map { it.ch }
        val b = DictationSource.pick("1a", DictationLevel.NORMAL, 5).map { it.ch }
        assertEquals("两次调用应给出同一批字", a, b)

        val bookOrder = Repo.bookChars("1a").filter { Repo.isWriteChar(it) }
        assertEquals("应取本册最前面的会写字", bookOrder.take(5), a)
    }

    @Test
    fun `难度 key 与显示名`() {
        assertEquals(DictationLevel.NORMAL, DictationLevel.fromKey("normal"))
        assertEquals(DictationLevel.HARD, DictationLevel.fromKey("hard"))
        assertEquals(DictationLevel.EASY, DictationLevel.fromKey("easy"))
        // 未知 key 退回默认档，不能崩
        assertEquals(DictationLevel.NORMAL, DictationLevel.fromKey("whatever"))

        assertEquals("看着写", DictationLevel.EASY.title)
        assertEquals("听词写", DictationLevel.NORMAL.title)
        assertEquals("只听字", DictationLevel.HARD.title)
    }

    @Test
    fun `会写字的数量足够撑起一轮听写`() {
        assertNotNull(Repo.meta("天"))
        val writeChars = Repo.allChars.filter { Repo.isWriteChar(it) }
        assertTrue("会写字应远超一轮的 8 个，实际 ${writeChars.size}", writeChars.size > 100)
    }

    /**
     * 曾经 `isWriteChar` 只看 `writeLesson` 非空，把 457 个「写字课在五六年级」
     * 的字（棋→6a-k6、鸦→6b-k3、氏→5a-k16）误判成本项目要求会写——
     * 于是听写会要求二年级孩子默写「鸦」。
     *
     * 修正后必须与课时的 `write` 数组并集严格一致。两种算法互相独立，
     * 任何一边偏了这条测试都会失败。
     */
    @Test
    fun `会写字集合与课时写字表并集一致`() {
        val inWriteLists = HashSet<String>()
        Repo.books.forEach { b ->
            b.lessons.forEach { lid ->
                Repo.lesson(lid)?.write?.forEach { inWriteLists.add(it) }
            }
        }
        val byMeta = Repo.allChars.filter { Repo.isWriteChar(it) }
        assertEquals("两种算法数量不一致", inWriteLists.size, byMeta.size)
        byMeta.forEach { ch ->
            assertTrue("$ch 被判为会写，却不在任何课时写字表里", inWriteLists.contains(ch))
        }
        // 总数锁死：2596 个字里 1798 个会写、798 个只认
        assertEquals(1798, byMeta.size)
        assertEquals(798, Repo.allChars.size - byMeta.size)
    }

    @Test
    fun `写字课超出本项目册次的字算只认不写`() {
        // 这几个字的 writeLesson 分别指向 6a/6b/5a/5b，本项目只做一到四年级
        listOf("棋", "鸦", "氏", "孙", "纯").forEach { ch ->
            assertFalse("$ch 的写字课在五六年级，本项目不要求会写", Repo.isWriteChar(ch))
        }
        // 一到四年级的字不受影响
        assertTrue(Repo.isWriteChar("天"))
        assertTrue(Repo.isWriteChar("匀"))  // 3b-k7，在本项目范围内
    }
}
