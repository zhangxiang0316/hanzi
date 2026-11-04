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

    /**
     * 跨端黄金值：同一 seed 三端必须出完全相同的题（含选项顺序）。
     *
     * 期望值由小程序 `utils/quiz.js` 的 `buildWordQuiz` 算出，是另外
     * 一份独立实现。任何一端改了随机数调用顺序、干扰项挑选或洗牌方式，
     * 这条测试都会红——这是「三端行为一致」这个硬约束的兜底。
     */
    @Test
    fun `同 seed 三端出同一套词语题`() {
        val r = Quiz.buildWordQuiz("2a", null, 5, 20240101L)
        val got = r.questions.map { "${it.ch}|${it.prompt}|${it.answer}|${it.options.joinToString("|") { o -> o.value }}" }
        val want = listOf(
            "卧室|wò shì|卧室|邻居|秧苗|卧室|蚯蚓",
            "那些|nà xiē|那些|那些|和好|看见|回家",
            "展开|zhǎn kāi|展开|头顶|展开|电影|井口",
            "白蛇|bái shé|白蛇|爱慕|时辰|花朵|白蛇",
            "船身|chuán shēn|船身|展开|井沿|船身|时间"
        )
        assertEquals(want, got)
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

    // -----------------------------------------------------------------------
    // 词语表浏览
    //
    // 词语此前只在「看拼音选词语」的题目和课时页里露过脸，
    // 没有任何地方能从头翻一遍。以下与小程序 tests/words.test.mjs 对应。
    // -----------------------------------------------------------------------

    @Test
    fun `全库词语按册拼接，8 册都有（一年级靠派生词兜底）`() {
        val all = Words.allWords()
        // 2492 = 八册册内去重后拼接的条目数；一年级的词全部来自生字组词兜底。
        // 这个数字和数值都取自小程序侧，三端必须一致
        assertEquals(2492, all.size)
        val books = all.map { it.book }.toSet()
        assertEquals(
            listOf("1a", "1b", "2a", "2b", "3a", "3b", "4a", "4b"),
            Repo.books.map { it.id }.filter { it in books }
        )
        assertEquals(8, books.size)
    }

    @Test
    fun `一年级全是生字组词兜底，中高年级是课本词与派生词混着`() {
        // 一年级课本没有词语表，所以用每课生字的第一组词补上。
        // 但**一册里可能混合**——2a 有的课文有词语表、有的没有，
        // 所以页面不能只看 every 就下「这一册没有词语表」的结论。
        val g1 = Words.bookWords("1a")
        assertTrue("一年级也要有词可看", g1.isNotEmpty())
        assertTrue("一年级应该全是派生词", g1.all { !it.fromTextbook })

        val g2 = Words.bookWords("2a")
        assertTrue("2a 应该有真课本词", g2.any { it.fromTextbook })
        assertTrue("2a 也有派生词——混合册", g2.any { !it.fromTextbook })
        // 92 / 320，与小程序一致
        assertEquals(92, g2.count { !it.fromTextbook })
        assertEquals(320, g2.size)
    }

    @Test
    fun `全库去重后少于按册拼接的条目数`() {
        // 「旅行」在 1b 和 3a 各出一次是教材事实，分组浏览该各显示一次；
        // 但统计「有多少个词」必须全局去重
        val dup = Words.allWords().size
        val uniq = Words.uniqueWords()
        assertTrue("去重后 ${uniq.size} 应该少于 $dup", uniq.size < dup)
        assertEquals(1967, uniq.size)
        assertEquals("不能有重复的词", uniq.size, uniq.map { it.word }.toSet().size)
    }

    @Test
    fun `跨册重复的词记下所有册次`() {
        val travel = Words.uniqueWords().firstOrNull { it.word == "旅行" }
        assertNotNull("应该有「旅行」", travel)
        assertTrue("「旅行」应跨册，实际 ${travel!!.books}", travel.books.size >= 2)
        assertEquals(listOf("1b", "3a"), travel.books)
    }

    @Test
    fun `按字搜词能搜到跨册的词，且不重复`() {
        val found = Words.wordsWithChar("行")
        assertTrue("含「行」的词太少：${found.size}", found.size >= 3)
        assertTrue("每个词都要含「行」", found.all { it.word.contains("行") })
        assertEquals("搜索结果不能有重复的词", found.size, found.map { it.word }.toSet().size)
        // 跨册的「旅行」在结果里只出现一次，但册次记全了
        val travel = found.first { it.word == "旅行" }
        assertEquals(listOf("1b", "3a"), travel.books)
    }

    @Test
    fun `搜不存在的字返回空而不是报错`() {
        assertTrue(Words.wordsWithChar("").isEmpty())
        assertTrue(Words.wordsWithChar(null).isEmpty())
        assertTrue(Words.wordsWithChar("龘").isEmpty())
    }

    @Test
    fun `每个词都有拼音`() {
        val bad = Words.uniqueWords().filter { it.pinyin.isEmpty() }
        assertTrue(
            "这些词缺拼音：${bad.take(5).map { it.word }}",
            bad.isEmpty()
        )
    }

    @Test
    fun `每条词语都带课次与册次`() {
        // 页面要显示「第 N 课」，没有课次就只能显示「第 0 课」
        Words.allWords().forEach { w ->
            assertTrue("${w.word} 册次为空", w.book.isNotEmpty())
            assertTrue("${w.word} 应是本册的课", Repo.book(w.book)?.lessons?.contains(w.lesson) == true)
            assertTrue("${w.word} 没有课次", w.lessonNo > 0)
        }
    }

    @Test
    fun `派生词里有少数含字库外的字，页面要认得出`() {
        // 派生词取自每个字的组词，那些组词可能用到 2596 字之外的常用字
        // （「弓弩」的弩、「镜匣」的匣）。这类字点不进详情页，
        // 页面必须靠 Repo.hasChar 把它们置灰，而不是让用户点了以为卡住。
        val derived = Words.uniqueWords().filter { !it.fromTextbook }
        val withOutsider = derived.filter { w -> w.word.any { Repo.meta(it.toString()) == null } }

        assertEquals("数据里确实有这类词，断言要贴着现实", 19, withOutsider.size)
        val ratio = withOutsider.size.toDouble() / derived.size
        assertTrue("含字库外字的派生词占比 ${ratio * 100}% 太高了", ratio < 0.05)
        // 每个这样的词，至少有一个字能点，不至于整条都没得点
        withOutsider.forEach { w ->
            assertTrue(
                "「${w.word}」一个字都点不了",
                w.word.any { Repo.meta(it.toString()) != null }
            )
        }
    }

    @Test
    fun `词算不算学过要看每一个字`() {
        // 有一个字不认识，这个词孩子就读不出来，算「学过」是自欺欺人
        val learnedChars = setOf("看", "见")
        assertTrue(Words.learned("看见") { it in learnedChars })
        assertFalse("缺一个字就不算学过", Words.learned("看见") { it == "看" })
        assertFalse("空词不算学过", Words.learned("") { true })
    }
}
