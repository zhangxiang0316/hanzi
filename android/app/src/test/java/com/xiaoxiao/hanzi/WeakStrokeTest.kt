package com.xiaoxiao.hanzi

import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.logic.Progress
import com.xiaoxiao.hanzi.logic.Store
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 笔画薄弱点。
 *
 * 描红判分本来就每笔都会算出「为什么不过」（起笔错 / 偏离 / 写短了），
 * 但之前只用它拼一句即时提示就丢掉了。留下来才看得出
 * 「这个字的第 2 笔你反复写不好」——比整字分数具体，也更能指导练什么。
 *
 * 与 iOS `testWeakStrokesTwoFails` 等、小程序 `tests/weak.test.mjs` 对应。
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WeakStrokeTest {

    private lateinit var prog: Progress

    @Before
    fun setUp() {
        prog = Progress(Store(ApplicationProvider.getApplicationContext()))
        prog.resetAll()
    }

    @Test
    fun `失败两次才算薄弱笔画`() {
        // 只错一次很正常——手抖、第一次不熟，不算薄弱点
        prog.recordStroke("日", 1, false)
        assertTrue(prog.weakStrokesOf("日").isEmpty())

        prog.recordStroke("日", 1, false)
        val w = prog.weakStrokesOf("日")
        assertEquals(1, w.size)
        assertEquals(1, w[0].index)
        assertEquals(2, w[0].fails)
    }

    @Test
    fun `连续写对两次才算练好`() {
        prog.recordStroke("日", 1, false)
        prog.recordStroke("日", 1, false)
        assertEquals(1, prog.weakStrokesOf("日").size)

        // 写对一次不清：蒙对一次不该前功尽弃
        prog.recordStroke("日", 1, true)
        assertEquals(1, prog.weakStrokesOf("日").size)

        prog.recordStroke("日", 1, true)
        assertTrue(prog.weakStrokesOf("日").isEmpty())
    }

    @Test
    fun `蒙对一次又写错，连胜归零`() {
        prog.recordStroke("天", 0, false)
        prog.recordStroke("天", 0, false)
        prog.recordStroke("天", 0, true)   // 蒙对
        prog.recordStroke("天", 0, false)  // 又错
        assertEquals(1, prog.weakStrokesOf("天").size)
        prog.recordStroke("天", 0, true)
        assertEquals("连胜清零后要重新连对两次", 1, prog.weakStrokesOf("天").size)
        prog.recordStroke("天", 0, true)
        assertTrue(prog.weakStrokesOf("天").isEmpty())
    }

    @Test
    fun `同一字多个薄弱笔画时练习列表只出现一次`() {
        // 一个字的笔画都在同一份描红里练，按笔画列出会重复练同一个字
        prog.recordStroke("日", 1, false)
        prog.recordStroke("日", 1, false)
        prog.recordStroke("日", 3, false)
        prog.recordStroke("日", 3, false)
        val chars = prog.weakChars()
        assertEquals(1, chars.size)
        assertEquals("日", chars[0].ch)
    }

    @Test
    fun `薄弱笔画按序号升序`() {
        for (i in listOf(5, 1, 3)) {
            prog.recordStroke("罐", i, false)
            prog.recordStroke("罐", i, false)
        }
        // 每个笔画各记两次失败
        assertEquals(listOf(1, 3, 5), prog.weakStrokesOf("罐").map { it.index })
    }

    @Test
    fun `全部薄弱点按失败次数降序`() {
        prog.recordStroke("日", 0, false)
        prog.recordStroke("日", 0, false)
        repeat(4) { prog.recordStroke("天", 2, false) }
        val all = prog.allWeakStrokes()
        assertEquals(2, all.size)
        assertEquals("天", all[0].ch)
        assertEquals(4, all[0].fails)
    }

    @Test
    fun `清空学习记录会一起清掉薄弱点`() {
        prog.recordStroke("日", 1, false)
        prog.recordStroke("日", 1, false)
        assertEquals(1, prog.allWeakStrokes().size)
        prog.resetAll()
        assertTrue(prog.allWeakStrokes().isEmpty())
    }

    @Test
    fun `没有写过的字没有薄弱点`() {
        assertTrue(prog.weakStrokesOf("字").isEmpty())
        assertFalse(prog.hasWeakStrokes("字"))
        assertTrue(prog.allWeakStrokes().isEmpty())
        assertTrue(prog.weakChars().isEmpty())
    }

    @Test
    fun `记录里尝试次数不超过 2×失败+1`() {
        // 「连对两次即移除」的直接推论：还在册的记录里不可能夹着两次连续成功
        val seq = listOf(
            false, true, false, false, true, false, true, false,
            false, true, true, false, false
        )
        for (pass in seq) prog.recordStroke("天", 0, pass)
        for (w in prog.allWeakStrokes()) {
            assertTrue(
                "t=${w.tries} 超过了 2f+1=${2 * w.fails + 1}",
                w.tries <= 2 * w.fails + 1
            )
        }
    }
}
