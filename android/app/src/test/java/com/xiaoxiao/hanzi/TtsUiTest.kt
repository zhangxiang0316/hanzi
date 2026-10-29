package com.xiaoxiao.hanzi

import android.app.Application
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Tts
import com.xiaoxiao.hanzi.logic.TtsEngine
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.HanziTheme
import com.xiaoxiao.hanzi.ui.Root
import com.xiaoxiao.hanzi.ui.Screen
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.util.Locale

/**
 * 朗读的界面接入。
 *
 * 用真实的 AppState + 系统 TTS，验证「按钮在、点了会调引擎、不可用时有提示」。
 * Robolectric 的 ShadowTextToSpeech 在本沙箱里 isLanguageAvailable 恒为
 * LANG_NOT_SUPPORTED，所以这里的真实引擎只会走到不可用分支 —— 正好用来
 * 验证「点了没声音时必须给提示」，而这恰恰是这类功能最容易做砸的地方。
 * 状态机的其余分支在 TtsTest 里用假引擎覆盖。
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi", sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class TtsUiTest {

    @get:Rule
    val compose = createComposeRule()

    /** 记录播报内容的假引擎，直接接进 AppState，让点击链路是真的 */
    private class Recorder {
        val spoken = mutableListOf<String>()
        var ready = false
        val tts = Tts({ cb ->
            object : TtsEngine {
                override fun speak(text: String) { spoken += text }
                override fun stop() {}
                override fun shutdown() {}
            }.also { cb(if (ready) Tts.State.READY else Tts.State.NO_CHINESE) }
        })
    }

    private fun state(): AppState {
        val app = AppState(ApplicationProvider.getApplicationContext<Application>())
        Repo.ensureLoaded(ApplicationProvider.getApplicationContext())
        return app
    }

    /** 就绪态的 AppState：点朗读应当真的把字交出去 */
    private fun readyState(rec: Recorder): AppState {
        val app = AppState(
            ApplicationProvider.getApplicationContext<Application>(),
            ttsFactory = { rec.tts }
        )
        return app
    }

    /** 找一个真的有两个字以上组词的字，单字词更能验证「读词而不是读字」 */
    private fun charWithWords(): String {
        val chars = Repo.bookChars("1a")
        return chars.first { Repo.meta(it)?.words?.any { w -> w.word.length >= 2 } == true }
    }

    @Test
    fun `详情页有朗读按钮`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Detail(charWithWords(), null))
        compose.waitForIdle()

        compose.onNodeWithTag("btn-speak").assertIsDisplayed()
        compose.onNodeWithText("朗读").assertIsDisplayed()
    }

    @Test
    fun `设备没有中文语音包时给出可见提示`() {
        // ready=false：引擎起来但报「没有中文语音包」
        val rec = Recorder()
        val app = readyState(rec)
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Detail(charWithWords(), null))
        compose.waitForIdle()

        // 提示在工具条下方，详情页较长，先滚到它
        compose.onNodeWithTag("tts-hint").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("语音包", substring = true).assertIsDisplayed()
    }

    @Test
    fun `组词可以点击朗读`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        val ch = charWithWords()
        app.nav.push(Screen.Detail(ch, null))
        compose.waitForIdle()

        val word = Repo.meta(ch)!!.words.first { it.word.length >= 2 }.word
        compose.onNodeWithTag("word-$word").assertExists()
        compose.onNodeWithTag("word-$word").performClick()
        compose.waitForIdle()
        // 点击不应崩溃；不可用时有提示兜底
        compose.onNodeWithTag("btn-speak").assertExists()
    }

    @Test
    fun `组词区有可点击的说明`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Detail(charWithWords(), null))
        compose.waitForIdle()
        compose.onNodeWithText("点一下听读音").assertIsDisplayed()
    }

    @Test
    fun `朗读不可用不会影响其他功能`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        val ch = charWithWords()
        app.nav.push(Screen.Detail(ch, null))
        compose.waitForIdle()
        app.tts.warmUp()
        compose.waitForIdle()

        // 朗读挂了，笔顺与描红入口照常
        compose.onNodeWithText("笔顺").assertIsDisplayed()
        compose.onNodeWithText("描红跟写").assertExists()
    }

    @Test
    fun `语音包可用时点击朗读会把字交给引擎`() {
        val rec = Recorder().apply { ready = true }
        val app = readyState(rec)
        compose.setContent { HanziTheme { Root(app) } }
        val ch = charWithWords()
        app.nav.push(Screen.Detail(ch, null))
        compose.waitForIdle()

        compose.onNodeWithTag("btn-speak").performClick()
        compose.waitForIdle()

        // 走的是真实点击链路：按钮 → app.tts.speak → 引擎
        assertEquals("点朗读应把当前字交给引擎", listOf(ch), rec.spoken)
    }

    @Test
    fun `语音包可用时点组词播的是词语而不是单字`() {
        val rec = Recorder().apply { ready = true }
        val app = readyState(rec)
        compose.setContent { HanziTheme { Root(app) } }
        val ch = charWithWords()
        app.nav.push(Screen.Detail(ch, null))
        compose.waitForIdle()

        val word = Repo.meta(ch)!!.words.first { it.word.length >= 2 }.word
        compose.onNodeWithTag("word-$word").performClick()
        compose.waitForIdle()

        // 多字词的读音比孤立单字准得多，这是本功能的重点
        assertEquals(listOf(word), rec.spoken)
        assertEquals("不该把整词拆成单字播", 1, rec.spoken.size)
    }

    @Test
    fun `语音包可用时不显示不可用提示`() {
        val rec = Recorder().apply { ready = true }
        val app = readyState(rec)
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Detail(charWithWords(), null))
        compose.waitForIdle()

        assertEquals(
            "就绪时不该显示不可用提示",
            0,
            compose.onAllNodesWithTag("tts-hint").fetchSemanticsNodes().size
        )
    }
}
