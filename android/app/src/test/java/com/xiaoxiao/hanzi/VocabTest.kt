package com.xiaoxiao.hanzi

import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Quiz
import com.xiaoxiao.hanzi.logic.Vocab
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 识字量测试。
 *
 * 家长最想知道的一个数字是「我家孩子认识多少字」。原来的 app 只能回答
 * 「学过多少字」——那是点过多少个字，不是认识多少。
 *
 * 抽测的关键是**抽样要覆盖整册**，不能只考最基础的几个字，否则估出来的
 * 数会虚高。以及估算必须是可复现的纯函数。
 *
 * 与小程序 `tests/vocab.test.mjs`、iOS `Checks/VocabTests.swift` 对应，
 * 黄金值 `sum(sample(seed=1))` 三端必须完全一致。
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class VocabTest {

    companion object {
        /**
         * Repo 是单例，别的测试类可能已经用 4 参数的版本加载过。
         * 这里每次都重载一次，避免「单独跑绿、全量跑红」。
         */
        @BeforeClass
        @JvmStatic
        fun load() {
            val assets = java.io.File("src/main/assets/data")
            Repo.loadFromStrings(
                java.io.File(assets, "catalog.json").readText(),
                java.io.File(assets, "meta.json").readText(),
                java.io.File(assets, "strokes.json").readText(),
                java.io.File(assets, "similar.json").readText()
            )
        }

        /** 小程序 `vocab.buildTest({seed:1})` 的输出，三端必须一致 */
        private const val GOLDEN_SEED_1 =
            "八南众到旁|万单食呢奇|舰锅留福折|蒙易坦件由|橘吞阁库瓦|释智痒警呕|震兰返怖签|冠践稿絮遣"
    }

    @Test
    fun `每册抽 5 个字，八册共 40 题`() {
        val t = Vocab.buildTest(seed = 20240101)
        assertEquals(5, Vocab.PER_BOOK)
        assertEquals(8, t.groups.size)
        assertEquals(40, t.total)
        t.groups.forEach { assertEquals("${it.book} 应该抽 5 个", 5, it.questions.size) }
    }

    @Test
    fun `抽出来的字都有拼音，且在本册内`() {
        val t = Vocab.buildTest(seed = 42)
        for (g in t.groups) {
            val inBook = Repo.bookChars(g.book).toHashSet()
            for (q in g.questions) {
                assertTrue("${q.ch} 不属于 ${g.book}", inBook.contains(q.ch))
                val py = Repo.meta(q.ch)!!.py
                assertTrue("${q.ch} 没有拼音", py.length > 1)
                assertEquals(py, q.answer)
            }
        }
    }

    @Test
    fun `抽样覆盖整册，不是只取前几个字`() {
        // 只取前 5 个等于只考「日月水火」这种最基础的字，估出来的数会虚高
        val t = Vocab.buildTest(seed = 7)
        for (g in t.groups) {
            val all = Repo.bookChars(g.book)
            val idx = g.questions.map { all.indexOf(it.ch) }
            assertTrue(
                "${g.book} 的抽样都落在前一半（最大下标 ${idx.max()}/${all.size}）",
                idx.max() > all.size * 0.5
            )
        }
    }

    @Test
    fun `每次抽样的字不同`() {
        val a = Vocab.buildTest(seed = 1)
        val b = Vocab.buildTest(seed = 2)
        val sa = a.groups.joinToString("") { g -> g.questions.joinToString("") { it.ch } }
        val sb = b.groups.joinToString("") { g -> g.questions.joinToString("") { it.ch } }
        assertNotEquals(sa, sb)
    }

    @Test
    fun `同一个 seed 出同一套题`() {
        val a = Vocab.buildTest(seed = 99)
        val b = Vocab.buildTest(seed = 99)
        assertEquals(dump(a), dump(b))
    }

    /**
     * 黄金值：和小程序 `vocab.buildTest({seed:1})` 抽出来的字必须逐字相同。
     *
     * 三端都自己实现了一份抽样+RNG，只测「同 seed 可复现」是不够的——
     * 那样即使 Android 的 mulberry32 写错了也能通过。这里锁定实际输出的字。
     */
    @Test
    fun `抽样结果与小程序逐字一致`() {
        val t = Vocab.buildTest(seed = 1)
        val got = t.groups.joinToString("|") { g -> g.questions.joinToString("") { it.ch } }
        assertEquals(GOLDEN_SEED_1, got)
    }

    @Test
    fun `每题 4 个选项，答案在其中，干扰项读音各不相同`() {
        val t = Vocab.buildTest(seed = 20240101)
        for (g in t.groups) {
            for (q in g.questions) {
                assertEquals(4, q.options.size)
                assertTrue(q.options.any { it.value == q.answer })
                assertEquals("${q.ch} 的选项有重复读音", 4, q.options.map { it.value }.toSet().size)
            }
        }
    }

    @Test
    fun `多音字的其他读音不会当干扰项`() {
        val t = Vocab.buildTest(seed = 5)
        for (g in t.groups) {
            for (q in g.questions) {
                val all = Repo.readingsOf(q.ch)
                for (o in q.options) {
                    if (o.value == q.answer) continue
                    assertFalse("${q.ch} 的干扰项 ${o.value} 也是它的读音", all.contains(o.value))
                }
            }
        }
    }

    @Test
    fun `全对时估算等于字库总量`() {
        val t = Vocab.buildTest(seed = 1)
        val e = Vocab.estimate(t, List(t.total) { true })
        assertEquals(Repo.allChars.size, e.size)
        assertEquals("4b", e.level)
        assertTrue(e.done)
    }

    @Test
    fun `全错时估算为 0，且第一册就停下`() {
        val t = Vocab.buildTest(seed = 1)
        val e = Vocab.estimate(t, List(t.total) { false })
        assertEquals(0, e.size)
        assertEquals("1a", e.stopBook)
        assertEquals("第一册问完就该停", 5, e.answered)
    }

    @Test
    fun `只认识第一册时，停在第二册`() {
        val t = Vocab.buildTest(seed = 1)
        val answers = ArrayList<Boolean>()
        for (g in t.groups) {
            repeat(g.questions.size) { answers.add(g.book == "1a") }
        }
        val e = Vocab.estimate(t, answers)
        assertEquals("1b", e.stopBook)
        // 1a 满分 → 300 字左右
        assertTrue("估算 ${e.size} 不合理", e.size in 251..300)
        assertEquals("1a", e.level)
    }

    @Test
    fun `停在某册后，后面的册次一律不计`() {
        val t = Vocab.buildTest(seed = 3)
        val e = Vocab.estimate(t, List(t.total) { false })
        for (g in e.groups.filter { it.book != "1a" }) {
            assertFalse("${g.book} 不该被计入", g.counted)
            assertEquals(0, g.contribution)
        }
    }

    @Test
    fun `答题进行中：没问到的册次不计`() {
        val t = Vocab.buildTest(seed = 8)
        val e = Vocab.estimate(t, List(7) { true })
        assertFalse(e.done)
        assertEquals(7, e.answered)
        val g2a = e.groups.first { it.book == "2a" }
        assertEquals(0, g2a.asked)
        assertEquals(0, g2a.contribution)
    }

    @Test
    fun `估算值随答对比例线性变化`() {
        val t = Vocab.buildTest(seed = 4)
        // 每册都对 3/5，保证不会提前停
        val answers = ArrayList<Boolean>()
        for (g in t.groups) {
            for (i in g.questions.indices) answers.add(i < 3)
        }
        val e = Vocab.estimate(t, answers)
        assertEquals("六成不该提前停", "", e.stopBook)
        val total = Repo.allChars.size
        assertTrue(
            "六成正确率估出 ${e.size}/$total，不合理",
            e.size > total * 0.5 && e.size < total * 0.75
        )
    }

    @Test
    fun `sizeLabel 报约到百位`() {
        assertEquals("0", Vocab.sizeLabel(0))
        assertEquals("45", Vocab.sizeLabel(45))
        assertEquals("约 700", Vocab.sizeLabel(712))
        assertEquals("约 800", Vocab.sizeLabel(760))
        assertEquals("约 2600", Vocab.sizeLabel(2596))
    }

    @Test
    fun `verdict 分档：数字越大档位越高`() {
        val marks = listOf(200, 600, 1200, 2000, 2596)
        val texts = marks.map { Vocab.verdict(it) }
        for (i in 1 until marks.size) {
            assertNotEquals("${marks[i]} 和 ${marks[i - 1]} 的评价一样", texts[i], texts[i - 1])
        }
        // 不足 100 字统一算「刚开始」——0 字和 50 字对家长没有区分意义
        assertEquals(Vocab.verdict(0), Vocab.verdict(50))
        assertTrue(Vocab.verdict(50).contains("刚"))
        assertTrue(Vocab.verdict(2596).contains("章节书"))
    }

    @Test
    fun `识字量记进设置`() {
        val store = com.xiaoxiao.hanzi.logic.Store(
            androidx.test.core.app.ApplicationProvider.getApplicationContext()
        )
        store.clearAll()
        val prog = com.xiaoxiao.hanzi.logic.Progress(store)
        prog.resetAll()
        assertEquals(0, prog.vocabSize())
        prog.setVocabSize(712)
        assertEquals(712, prog.vocabSize())
        // 0 不覆盖已有结果
        prog.setVocabSize(0)
        assertEquals(712, prog.vocabSize())
        prog.resetAll()
    }

    @Test
    fun `识字量按档案隔离`() {
        val store = com.xiaoxiao.hanzi.logic.Store(
            androidx.test.core.app.ApplicationProvider.getApplicationContext()
        )
        store.clearAll()
        store.writeJsonUnscoped("profiles", org.json.JSONObject())
        val pm = com.xiaoxiao.hanzi.logic.ProfileManager(store)
        val prog = com.xiaoxiao.hanzi.logic.Progress(store)
        prog.resetAll()
        prog.setVocabSize(800)

        val p = pm.add("弟弟")!!
        pm.setActive(p.id)
        prog.reload()
        assertEquals("弟弟不该看到哥哥的测试结果", 0, prog.vocabSize())

        pm.setActive("")
        prog.reload()
        assertEquals(800, prog.vocabSize())
        prog.resetAll()
    }

    private fun dump(t: Vocab.Test): String =
        t.groups.joinToString("|") { g ->
            g.questions.joinToString("") { q -> q.ch + q.options.joinToString(",") { it.value } }
        }

}
