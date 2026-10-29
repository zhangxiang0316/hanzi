package com.xiaoxiao.hanzi

import com.xiaoxiao.hanzi.logic.Tts
import com.xiaoxiao.hanzi.logic.TtsEngine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 朗读状态机。
 *
 * Robolectric 的 ShadowTextToSpeech 永远返回 LANG_NOT_SUPPORTED 且从不回调初始化，
 * 所以真实引擎只能覆盖「不可用」这一条分支。状态机的其余分支用假引擎测，
 * 这样「就绪前点击」「不可用不重试」「释放后不再播」这些容易出错的地方才真的被覆盖。
 */
class TtsTest {

    /** 假引擎：记录播过什么，可以手动决定何时、以什么状态完成初始化 */
    private class FakeEngine : TtsEngine {
        val spoken = mutableListOf<String>()
        var stopCount = 0
        var shutdownCount = 0

        override fun speak(text: String) {
            spoken += text
        }

        override fun stop() {
            stopCount++
        }

        override fun shutdown() {
            shutdownCount++
        }
    }

    private class Harness {
        val engine = FakeEngine()
        var ready: ((Tts.State) -> Unit)? = null
        var created = 0
        val tts = Tts({ cb ->
            created++
            ready = cb
            engine
        })

        /** 模拟引擎初始化完成；没建过引擎就先建一个 */
        fun complete(state: Tts.State) {
            if (ready == null) tts.warmUp()
            ready!!.invoke(state)
        }
    }

    @Test
    fun `就绪前点击会把文本存下来，就绪后补播`() {
        val h = Harness()
        h.tts.speak("日")
        assertEquals("还没就绪，此时不该播", 0, h.engine.spoken.size)

        h.complete(Tts.State.READY)
        assertEquals(listOf("日"), h.engine.spoken)
    }

    @Test
    fun `就绪前连点多次只播最后一句`() {
        val h = Harness()
        h.tts.speak("日")
        h.tts.speak("月")
        h.complete(Tts.State.READY)
        assertEquals("排队念一串会让孩子以为卡了，应该只播最后一次", listOf("月"), h.engine.spoken)
    }

    @Test
    fun `就绪后点击直接播`() {
        val h = Harness()
        h.tts.warmUp()
        h.complete(Tts.State.READY)
        h.tts.speak("人")
        assertEquals(listOf("人"), h.engine.spoken)
    }

    @Test
    fun `没有中文语音包时进入 NO_CHINESE 且不补播`() {
        val h = Harness()
        h.tts.speak("日")
        h.complete(Tts.State.NO_CHINESE)
        assertEquals(Tts.State.NO_CHINESE, h.tts.state)
        assertEquals("不可用时不该播", 0, h.engine.spoken.size)
        assertTrue(h.tts.unavailable)
    }

    @Test
    fun `不可用时再点不会反复尝试`() {
        val h = Harness()
        h.complete(Tts.State.NO_CHINESE)
        repeat(3) { h.tts.speak("日") }
        assertEquals(0, h.engine.spoken.size)
        assertEquals("不该重新造引擎", 1, h.created)
    }

    @Test
    fun `引擎起不来时进入 FAILED`() {
        val h = Harness()
        h.complete(Tts.State.FAILED)
        assertEquals(Tts.State.FAILED, h.tts.state)
        assertTrue(h.tts.unavailable)
    }

    @Test
    fun `空文本与空白文本直接忽略`() {
        val h = Harness()
        h.complete(Tts.State.READY)
        h.tts.speak("")
        h.tts.speak("   ")
        h.tts.speak("\n\t ")
        assertEquals(0, h.engine.spoken.size)
    }

    @Test
    fun `文本两端空白会被去掉`() {
        val h = Harness()
        h.complete(Tts.State.READY)
        h.tts.speak("  日  ")
        assertEquals(listOf("日"), h.engine.spoken)
    }

    @Test
    fun `同一个引擎只初始化一次`() {
        val h = Harness()
        h.tts.warmUp()
        h.tts.warmUp()
        h.tts.speak("日")
        assertEquals(1, h.created)
    }

    @Test
    fun `初始化重复回调不会重复播`() {
        val h = Harness()
        h.tts.speak("日")
        h.complete(Tts.State.READY)
        h.ready!!.invoke(Tts.State.READY)
        h.ready!!.invoke(Tts.State.READY)
        assertEquals(1, h.engine.spoken.size)
    }

    @Test
    fun `shutdown 会释放引擎并回到 IDLE`() {
        val h = Harness()
        h.complete(Tts.State.READY)
        h.tts.shutdown()
        assertEquals(1, h.engine.shutdownCount)
        assertEquals(Tts.State.IDLE, h.tts.state)
        assertFalse(h.tts.unavailable)
    }

    @Test
    fun `shutdown 后再点击会重建引擎，不会用到已释放的`() {
        val h = Harness()
        h.complete(Tts.State.READY)
        h.tts.shutdown()
        h.tts.speak("日")
        assertEquals("释放后应重新造引擎", 2, h.created)
        h.complete(Tts.State.READY)
        assertEquals(listOf("日"), h.engine.spoken)
    }

    @Test
    fun `stop 清掉待播文本`() {
        val h = Harness()
        h.tts.speak("日")
        h.tts.stop()
        h.complete(Tts.State.READY)
        assertEquals("被 stop 掉的待播内容不该在就绪后冒出来", 0, h.engine.spoken.size)
    }

    @Test
    fun `状态变化会通知界面重组`() {
        var changes = 0
        val engine = FakeEngine()
        var ready: ((Tts.State) -> Unit)? = null
        val tts = Tts({ cb -> ready = cb; engine }) { changes++ }

        tts.warmUp()
        assertEquals("IDLE 没变，不该通知", 0, changes)
        ready!!.invoke(Tts.State.READY)
        assertEquals("变成 READY 通知一次", 1, changes)
        ready!!.invoke(Tts.State.READY)
        assertEquals("状态没变不该重复通知", 1, changes)
    }

    @Test
    fun `提示文案：正常时不显示，异常时都有交代`() {
        assertNull("正常状态不该显示提示", Tts.unavailableHint(Tts.State.READY))
        assertNull("还没初始化完不该闪一下提示", Tts.unavailableHint(Tts.State.IDLE))
        assertNotNull("没有中文语音包必须有提示", Tts.unavailableHint(Tts.State.NO_CHINESE))
        assertNotNull("引擎失败必须有提示", Tts.unavailableHint(Tts.State.FAILED))
        // 两种不可用的说法要能区分，否则用户不知道该怎么办
        assertTrue(
            Tts.unavailableHint(Tts.State.NO_CHINESE) != Tts.unavailableHint(Tts.State.FAILED)
        )
        assertTrue(
            "没有语音包时应告诉用户去哪装",
            Tts.unavailableHint(Tts.State.NO_CHINESE)!!.contains("语音包")
        )
    }
}
