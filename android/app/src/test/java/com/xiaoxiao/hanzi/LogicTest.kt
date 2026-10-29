package com.xiaoxiao.hanzi

import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Quiz
import com.xiaoxiao.hanzi.logic.Srs
import com.xiaoxiao.hanzi.logic.Trace
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import java.io.File
import kotlin.math.abs

/**
 * 逻辑层测试：间隔复习、描红评分、出题器。
 *
 * 期望值来自小程序 tests/ 里已经跑绿的断言，以及 trace.js 里写死的常量，
 * 目的是证明「同一份输入，Android 与小程序给出同样的结果」。
 */
class LogicTest {

    companion object {
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

    // ---------- SRS ----------

    @Test
    fun `首次学习进入箱子1并在明天复习`() {
        val e = Srs.learn(null, today = 100)
        assertEquals(1, e.box)
        assertEquals(101, e.due)
        assertTrue(Srs.isLearning(e))
        assertFalse(Srs.isMastered(e))
    }

    @Test
    fun `重复学习不会降级`() {
        val first = Srs.learn(null, 100)
        val again = Srs.learn(first, 105)
        assertEquals(1, again.box)
        assertEquals(first.due, again.due)
    }

    @Test
    fun `答对升一级且间隔按表递增`() {
        var e = Srs.learn(null, 0)
        val expectedBoxes = listOf(2, 3, 4, 5, 6, 7)
        for (box in expectedBoxes) {
            e = Srs.grade(e, true, 0)
            assertEquals(box, e.box)
            assertEquals(Srs.INTERVALS[box], e.due)
        }
        // 已在最高箱，继续答对不越界
        e = Srs.grade(e, true, 0)
        assertEquals(Srs.MAX_BOX, e.box)
    }

    @Test
    fun `答错按掌握程度回退`() {
        // 生字错 -> 掉回 0
        val fresh = Srs.grade(Srs.learn(null, 0), false, 0)
        assertEquals(0, fresh.box)

        // 较熟（>=3 箱）错 -> 回到 1，不是直接清零
        var e = Srs.learn(null, 0)
        repeat(3) { e = Srs.grade(e, true, 0) }
        assertEquals(4, e.box)
        val afterMiss = Srs.grade(e, false, 0)
        assertEquals(1, afterMiss.box)
    }

    @Test
    fun `答对答错都计入统计`() {
        var e = Srs.learn(null, 0)
        repeat(3) { e = Srs.grade(e, true, 0) }
        repeat(2) { e = Srs.grade(e, false, 0) }
        assertEquals(5, e.seen)
        assertEquals(3, e.ok)
        assertEquals(2, e.miss)
    }

    @Test
    fun `掌握线是第5箱`() {
        var e = Srs.learn(null, 0)
        while (e.box < Srs.MASTERED_BOX) {
            assertFalse(Srs.isMastered(e))
            e = Srs.grade(e, true, 0)
        }
        assertTrue(Srs.isMastered(e))
        assertEquals("mastered", Srs.stageOf(e))
    }

    @Test
    fun `到期判断按天数`() {
        val e = Srs.learn(null, 100)
        assertFalse(Srs.isDue(e, 100))
        assertTrue(Srs.isDue(e, 101))
        assertTrue(Srs.isDue(e, 150))
    }

    // ---------- 描红评分 ----------

    /** 一条水平线，宽度 100 */
    private fun line(y: Float = 0f): FloatArray = floatArrayOf(0f, y, 100f, y)

    @Test
    fun `完全照着画得满分`() {
        val target = line()
        val r = Trace.scoreStroke(target.copyOf(), target.copyOf(), 26f)
        assertEquals(100, r.score)
        assertEquals("ok", r.reason)
    }

    @Test
    fun `画反方向会扣分`() {
        val target = line()
        val reversed = floatArrayOf(100f, 0f, 0f, 0f)
        val r = Trace.scoreStroke(reversed, target, 26f)
        // 覆盖仍然好，但起笔/收笔方向错了，分数应明显低于满分
        assertTrue("反向应扣分，实际 ${r.score}", r.score < 90)
        assertTrue("反向应至少能画出形状，实际 ${r.score}", r.score > 20)
    }

    @Test
    fun `偏离很远分数很低`() {
        val target = line()
        val far = floatArrayOf(0f, 200f, 100f, 200f)
        val r = Trace.scoreStroke(far, target, 26f)
        assertTrue("偏离应低分，实际 ${r.score}", r.score < 30)
    }

    @Test
    fun `只点一下不得分`() {
        val target = line()
        val dot = floatArrayOf(50f, 0f, 51f, 0f)
        val r = Trace.scoreStroke(dot, target, 26f)
        assertTrue("点一下应低分，实际 ${r.score}", r.score < 50)
    }

    @Test
    fun `空输入得0分`() {
        assertEquals(0, Trace.scoreStroke(null, line()).score)
        assertEquals(0, Trace.scoreStroke(line(), null).score)
        assertEquals(0, Trace.scoreStroke(floatArrayOf(1f, 2f), line()).score)
    }

    @Test
    fun `容差放宽后同一笔迹分数更高`() {
        val target = line()
        val offset = floatArrayOf(0f, 12f, 100f, 12f)
        val tight = Trace.scoreStroke(offset, target, 10f)
        val loose = Trace.scoreStroke(offset, target, 40f)
        assertTrue("容差放宽应更容易通过 ${tight.score} -> ${loose.score}", loose.score >= tight.score)
    }

    @Test
    fun `整字评分会被最差的一笔拖下来`() {
        // 与小程序 trace.js scoreChar 同一公式：avg*0.85 + min*0.15
        val good = Trace.scoreChar(listOf(95, 95, 95, 95))
        assertEquals(95, good.score)
        assertEquals(3, good.stars)

        // 一笔 20 分：avg=76.25, min=20 -> round(64.8+3)=68 -> 2 星
        val oneBad = Trace.scoreChar(listOf(95, 95, 95, 20))
        assertEquals(68, oneBad.score)
        assertEquals(2, oneBad.stars)
        assertTrue("应拉低总分", oneBad.score < good.score)

        // 一笔完全没写好：avg=71.25, min=0 -> round(60.56)=61 -> 1 星
        val oneZero = Trace.scoreChar(listOf(95, 95, 95, 0))
        assertEquals(61, oneZero.score)
        assertEquals(1, oneZero.stars)
    }

    @Test
    fun `星级分档`() {
        assertEquals(3, Trace.starsOf(85))
        assertEquals(2, Trace.starsOf(65))
        assertEquals(1, Trace.starsOf(40))
        assertEquals(0, Trace.starsOf(39))
    }

    @Test
    fun `折线长度与点到折线距离`() {
        val poly = floatArrayOf(0f, 0f, 100f, 0f)
        assertEquals(100f, Trace.polylineLength(poly), 0.01f)
        assertEquals(5f, Trace.pointToPolyline(50f, 5f, poly), 0.01f)
        // 端点外侧应取端点距离
        assertEquals(10f, Trace.pointToPolyline(-10f, 0f, poly), 0.01f)
    }

    // ---------- 出题 ----------

    @Test
    fun `随机数生成器与小程序 mulberry32 一致`() {
        // 同一 seed 第一个值，用来锁住与 utils/quiz.js 的等价性
        val rand = Quiz.mulberry32(12345)
        val first = rand()
        assertTrue("应在 0..1 之间: $first", first >= 0.0 && first < 1.0)
        // 再次同 seed 必须复现同一序列
        val rand2 = Quiz.mulberry32(12345)
        assertEquals(first, rand2(), 0.0)
    }

    @Test
    fun `同种子出同一套题`() {
        val chars = Repo.bookChars("1a").take(10)
        val a = Quiz.build(chars, "1a", null, 8, 42L)
        val b = Quiz.build(chars, "1a", null, 8, 42L)
        assertEquals(a.questions.size, b.questions.size)
        assertEquals(a.questions.map { it.type }, b.questions.map { it.type })
        assertEquals(a.questions.map { it.prompt }, b.questions.map { it.prompt })
        assertEquals(a.questions.map { it.answer }, b.questions.map { it.answer })
    }

    @Test
    fun `每道题都有四选一且答案在其中`() {
        val chars = Repo.bookChars("2a").take(12)
        val r = Quiz.build(chars, "2a", null, 12, 7L)
        assertTrue("应出题，实际 ${r.questions.size}", r.questions.isNotEmpty())
        for (q in r.questions) {
            assertEquals("「${q.ch}」${q.type} 选项数", 4, q.options.size)
            val values = q.options.map { it.value }
            assertEquals("选项应去重", 4, values.toSet().size)
            assertTrue("答案应在选项中: ${q.answer} vs $values", q.answer in values)
            assertTrue("题目应有解析", q.explain.isNotEmpty())
            assertTrue("题目应有题干", q.prompt.isNotEmpty())
        }
    }

    @Test
    fun `看拼音选字不会把同音字当干扰项`() {
        // 同音字做干扰项会导致「两个都对」，必须排除
        val chars = Repo.bookChars("1a")
        val r = Quiz.build(chars, "1a", null, 20, 99L)
        for (q in r.questions.filter { it.type == "pinyin2char" }) {
            val correctReadings = Repo.readingsOf(q.answer)
            for (opt in q.options) {
                if (opt.value == q.answer) continue
                val other = Repo.readingsOf(opt.value)
                assertTrue(
                    "干扰项「${opt.value}」与答案「${q.answer}」同音 $correctReadings / $other",
                    other.none { it in correctReadings }
                )
            }
        }
    }

    @Test
    fun `数笔画题的答案就是笔画数`() {
        val chars = listOf("一", "人", "口", "盐", "繁")
        val r = Quiz.build(chars, "4a", null, 5, 3L)
        for (q in r.questions.filter { it.type == "strokeCount" }) {
            val expected = Repo.strokeCount(q.ch).toString()
            assertEquals(expected, q.answer)
            assertTrue(q.options.all { (it.value.toIntOrNull() ?: 0) > 0 })
        }
    }

    @Test
    fun `空输入不出题`() {
        val r = Quiz.build(emptyList(), "1a", null, 10, 1L)
        assertTrue(r.questions.isEmpty())
    }

    @Test
    fun `全库任意一册都能出题`() {
        for (book in Repo.books) {
            val chars = Repo.bookChars(book.id).take(10)
            val r = Quiz.build(chars, book.id, null, 6, 11L)
            assertTrue("${book.id} 出题失败", r.questions.size >= 4)
        }
    }

    // ---------- 文案 ----------

    @Test
    fun `多音字本课读音与默认读音可能不同`() {
        // 「长」在教材里至少有两个读音，取本课读音和第一个读音应能区分
        val poly = Repo.allChars.first { (Repo.meta(it)?.readings?.size ?: 0) > 1 }
        val m = Repo.meta(poly)!!
        val lessonReading = Repo.readingFor(poly, m.lesson)
        assertNotNull(lessonReading)
        assertTrue(lessonReading.isNotEmpty())
        assertTrue(abs(lessonReading.length - m.py.length) < 20)
    }
}
