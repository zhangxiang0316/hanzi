package com.xiaoxiao.hanzi

import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Quiz
import com.xiaoxiao.hanzi.logic.Words
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import java.io.File

/**
 * 课文词语表。
 *
 * `Lesson.words` 里有 1276 条课本词语，之前三端一次都没读过
 * （已有的「词语填空」用的是每个字自带的组词 `meta.w`，那是通用例子）。
 *
 * 与 iOS `testTextbookWordCountIs1276` 等、小程序 `tests/words.test.mjs` 对应。
 */
class WordsTest {

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
    fun `课本词语表共 1276 条且只在 2-4 年级`() {
        var total = 0
        val booksWithWords = HashSet<String>()
        Repo.books.forEach { b ->
            b.lessons.forEach { lid ->
                val l = Repo.lesson(lid) ?: return@forEach
                if (l.words.isNotEmpty()) {
                    total += l.words.size
                    booksWithWords.add(l.book)
                }
            }
        }
        assertEquals(1276, total)
        // 一年级课本没有单独的词语表，识字量还在积累——这是数据事实，不是缺失
        assertEquals(listOf("2a", "2b", "3a", "3b", "4a", "4b"), booksWithWords.sorted())
    }

    @Test
    fun `有词语表的课时直接用课本数据`() {
        val list = Words.lessonWords("2a-k1")
        assertTrue(list.isNotEmpty())
        assertTrue(list[0].fromTextbook)
        list.forEach { assertTrue("${it.word} 缺拼音", it.pinyin.isNotEmpty()) }
    }

    @Test
    fun `一年级没有词语表时用生字组词兜底`() {
        val list = Words.lessonWords("1a-s1")
        assertTrue("一年级也应有词可练", list.isNotEmpty())
        assertFalse(list[0].fromTextbook)

        val chars = Repo.lesson("1a-s1")!!.chars.toSet()
        list.forEach { w ->
            assertTrue("${w.word} 不含本课生字", w.word.any { chars.contains(it.toString()) })
        }
    }

    @Test
    fun `整册词语去重且数量合理`() {
        listOf("1a", "2a", "3b").forEach { b ->
            val list = Words.bookWords(b)
            assertTrue("$b 词语太少", list.size >= 100)
            assertEquals("$b 词语有重复", list.map { it.word }.toSet().size, list.size)
        }
    }

    @Test
    fun `看拼音选词语四个选项且答案在内`() {
        val r = Quiz.buildWordQuiz("2a", null, 8, 12345L)
        assertEquals(8, r.questions.size)

        val pinyins = HashSet<String>()
        r.questions.forEach { q ->
            assertEquals("wordPinyin", q.type)
            assertEquals("每题应有 4 个选项", 4, q.options.size)
            assertTrue("答案必须在选项里", q.options.any { it.value == q.answer })
            assertTrue("题面不能为空", q.prompt.isNotEmpty())
            // 同一轮里题面不能重复，否则结果页会看到两道一样的题
            assertTrue("重复题面：${q.prompt}", pinyins.add(q.prompt))
        }
    }

    @Test
    fun `干扰项不能和正确答案同音`() {
        val r = Quiz.buildWordQuiz("2a", null, 10, 99L)
        r.questions.forEach { q ->
            q.options.filter { it.value != q.answer }.forEach { opt ->
                // 同音词会让这题无解
                assertNotEquals(q.prompt, Words.wordPinyin(opt.value))
            }
        }
    }

    @Test
    fun `同一 seed 出同一套题`() {
        val a = Quiz.buildWordQuiz("2a", null, 6, 7L).questions.map { it.answer }
        val b = Quiz.buildWordQuiz("2a", null, 6, 7L).questions.map { it.answer }
        assertEquals(a, b)
    }

    @Test
    fun `不存在的册安全返回空`() {
        val r = Quiz.buildWordQuiz("zz", null, 10, 1L)
        assertTrue(r.questions.isEmpty())
        assertTrue(r.targets.isEmpty())
    }

    @Test
    fun `词语答错能拆成单字进错题本`() {
        // 错题本、错字重练都按单字组织，整词塞进去会让结果页取不到 meta
        val r = Quiz.buildWordQuiz("2a", null, 8, 42L)
        r.questions.forEach { q ->
            val parts = if (q.ch.length > 1 && Repo.meta(q.ch) == null)
                q.ch.map { it.toString() }.filter { Repo.meta(it) != null }
            else listOf(q.ch)
            assertTrue("${q.ch} 拆不出任何可学字", parts.isNotEmpty())
            parts.forEach { assertNotNull("$it 缺元数据", Repo.meta(it)) }
        }
    }
}
