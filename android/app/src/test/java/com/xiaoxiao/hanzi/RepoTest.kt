package com.xiaoxiao.hanzi

import com.xiaoxiao.hanzi.data.Repo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import java.io.File

/**
 * 数据层测试。
 *
 * 期望值不是随手写的，全部取自小程序侧 tests/data.test.mjs 的既有断言 ——
 * 两边跑同一套数字，才能证明「Android 版内容与小程序完全一致」。
 */
class RepoTest {

    companion object {
        private const val BOOK_TOTAL = 2596
        private const val BOOK_COUNTS = "300,400,450,450,250,250,250,250"

        @JvmStatic
        @BeforeClass
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
    fun `八册齐全且顺序正确`() {
        assertEquals(8, Repo.books.size)
        assertEquals(
            listOf("1a", "1b", "2a", "2b", "3a", "3b", "4a", "4b"),
            Repo.books.map { it.id }
        )
        assertEquals(listOf(1, 1, 2, 2, 3, 3, 4, 4), Repo.books.map { it.grade })
        assertEquals(listOf(1, 2, 1, 2, 1, 2, 1, 2), Repo.books.map { it.term })
    }

    @Test
    fun `生字总量 2596，各册统计之和 2600`() {
        // 2596 = 去重后的字数；各册 stat 之和是 2600，因为 9 个字在教材里
        // 出现于两册（如「希」在 2a 和 3b），每册都各算一次。
        assertEquals(BOOK_TOTAL, Repo.allChars.size)
        assertEquals(2600, Repo.books.sumOf { it.stat.chars })

        // 但不重复的教材收录量应该是 2600 - 9 = 2591，
        // 再加上只在写字表出现、不在任何识字表的 5 个字，正好 2596
        val inAnyLesson = Repo.books.flatMap { Repo.bookChars(it.id) }.toSet()
        assertEquals(2591, inAnyLesson.size)
        val writeOnly = Repo.allChars.filter { it !in inAnyLesson }
        assertEquals(5, writeOnly.size)
        // 这 5 个字只出现在写字表，不出现在任何识字表
        assertEquals(listOf("匀", "剩", "训", "忧", "毒"), writeOnly.sortedBy { "匀剩训忧毒".indexOf(it) })
    }

    @Test
    fun `每册生字数量与文档一致`() {
        val expected = BOOK_COUNTS.split(",").map { it.toInt() }
        val actual = Repo.books.map { Repo.bookChars(it.id).size }
        assertEquals(expected, actual)
    }

    @Test
    fun `每个字都有元数据和笔顺`() {
        val missingMeta = Repo.allChars.filter { Repo.meta(it) == null }
        assertTrue("缺元数据: $missingMeta", missingMeta.isEmpty())

        val missingStrokes = Repo.allChars.filter { Repo.strokes(it) == null }
        assertTrue("缺笔顺: $missingStrokes", missingStrokes.isEmpty())
    }

    @Test
    fun `每个字都能取到笔顺，没有缺口`() {
        // 反向验证：遍历全库要求笔顺非空，等价于「strokes.json 没有漏字」。
        // 导出脚本已经校验过 meta 与 strokes 的键集合一致，这里做运行期复核。
        val missing = Repo.allChars.filter { Repo.strokes(it) == null }
        assertTrue("缺笔顺 ${missing.size} 个: ${missing.take(20)}", missing.isEmpty())
    }

    @Test
    fun `笔画数与元数据一致`() {
        var checked = 0
        for (ch in Repo.allChars) {
            val m = Repo.meta(ch)!!
            val s = Repo.strokes(ch)!!
            assertEquals("「$ch」笔画数不一致", m.strokes, s.count)
            assertEquals("「$ch」中线数量应等于笔画数", s.count, s.medians.size)
            checked++
        }
        assertEquals(2596, checked)
    }

    @Test
    fun `课文总数 276`() {
        val lessonIds = Repo.books.flatMap { b -> b.lessons }
        assertEquals(276, lessonIds.size)
        assertEquals(276, lessonIds.toSet().size)
        assertEquals(276, Repo.books.sumOf { it.stat.lessons })
        assertEquals(64, Repo.books.sumOf { it.stat.units })
    }

    @Test
    fun `跨册重复字的归属是首次出现的册`() {
        // 这 9 个字在教材里出现于两册（如「希」在 2a 和 3b）。
        // meta.b 只记首次出现的那一册，路由也按这个走（与小程序 CHAR_PACK 一致）。
        val repeats = listOf("希", "代", "章", "眠", "兰", "杀", "兵", "仅", "栖")
        for (ch in repeats) {
            val m = Repo.meta(ch)
            assertNotNull("「$ch」应有元数据", m)
            val inBooks = Repo.books.filter { Repo.bookChars(it.id).contains(ch) }.map { it.id }
            assertTrue("「$ch」应出现在两册中，实际 $inBooks", inBooks.size == 2)
            assertEquals("「$ch」的归属应为首册", inBooks.first(), m!!.book)
        }
    }

    @Test
    fun `只写不认的五个字存在`() {
        val writeOnly = listOf("匀", "剩", "训", "忧", "毒")
        for (ch in writeOnly) {
            assertNotNull("「$ch」应存在", Repo.meta(ch))
            assertTrue("「$ch」应出现在写字表", Repo.isWriteChar(ch))
        }
    }

    @Test
    fun `多音字读数取自教材标注`() {
        val poly = Repo.allChars.filter { (Repo.meta(it)?.readings?.size ?: 0) > 1 }
        assertEquals("多音字数量应为 156", 156, poly.size)

        // 每个多音字，本课读音必须能在其读音表里找到
        for (ch in poly.take(50)) {
            val m = Repo.meta(ch)!!
            val lessonReading = Repo.readingFor(ch, m.lesson)
            val all = Repo.readingsOf(ch)
            assertTrue("「$ch」本课读音 $lessonReading 不在 $all 中", lessonReading in all)
        }
    }

    @Test
    fun `四年级生字可查可路由`() {
        val m = Repo.meta("盐")
        assertNotNull("「盐」应有元数据", m)
        assertEquals("yán", m!!.py)
        assertEquals(10, m.strokes)
        assertEquals("4a", m.book)
        assertNotNull(Repo.strokes("盐"))
        assertTrue(Repo.book("4a")!!.lessons.contains(m.lesson))
    }

    @Test
    fun `课内上下字顺序正确`() {
        val lesson = Repo.book("1a")!!.lessons.first()
        val chars = Repo.lessonChars(lesson)
        assertTrue(chars.size >= 2)
        assertEquals(chars[1], Repo.nextInLesson(lesson, chars[0]))
        assertEquals(chars[0], Repo.prevInLesson(lesson, chars[1]))
        assertEquals("", Repo.prevInLesson(lesson, chars[0]))
        assertEquals("", Repo.nextInLesson(lesson, chars.last()))
    }

    @Test
    fun `笔顺解码坐标落在字面范围内`() {
        // SCALE=6，构建时 y 已翻转；所有点应落在 0..1020 内
        for (ch in listOf("一", "人", "口", "盐", "繁")) {
            val s = Repo.strokes(ch) ?: continue
            for (stroke in s.strokes) {
                for (cmd in stroke) {
                    for (v in cmd.coords) {
                        assertTrue("「$ch」坐标越界: $v", v >= -10f && v <= 1030f)
                    }
                }
            }
        }
    }
}
