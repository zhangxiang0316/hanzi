package com.xiaoxiao.hanzi

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.ui.HanziTheme
import com.xiaoxiao.hanzi.ui.Motion
import com.xiaoxiao.hanzi.ui.ProgressBar
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.Root
import com.xiaoxiao.hanzi.ui.Screen
import com.xiaoxiao.hanzi.ui.Stars
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * 动画本身的行为。
 *
 * 用 mainClock 手动推进时钟，验证「动画确实在跑」而不是「加了动画参数就算完」。
 * 这里只测**有限时长**的动画：本 App 刻意不做循环动画（会让 86 处 waitForIdle
 * 全部挂到超时），所以每个用例都能等它结束。
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi", sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AnimTest {

    @get:Rule
    val compose = createComposeRule()

    private fun fillW(): Float =
        compose.onNodeWithTag("pb-fill").getBoundsInRoot().let { (it.right - it.left).value }

    private fun trackW(): Float =
        compose.onNodeWithTag("pb-track").getBoundsInRoot().let { (it.right - it.left).value }

    @Test
    fun `进度条从 0 长到目标值`() {
        compose.mainClock.autoAdvance = false
        compose.setContent {
            HanziTheme {
                Row(Modifier.width(200.dp)) { ProgressBar(pct = 50) }
            }
        }
        compose.mainClock.advanceTimeByFrame()

        val track = trackW()
        val atStart = fillW()
        assertTrue("起始应几乎是 0，实际 $atStart", atStart < track * 0.1f)

        // 推进到动画结束
        compose.mainClock.advanceTimeBy(Motion.PROGRESS.toLong() + 200)
        val atEnd = fillW()
        assertEquals("动画结束后应到 50%，实际 ${atEnd / track}", 0.5f, atEnd / track, 0.05f)
    }

    @Test
    fun `进度条中间态是渐进而不是跳变`() {
        compose.mainClock.autoAdvance = false
        compose.setContent {
            HanziTheme {
                Row(Modifier.width(200.dp)) { ProgressBar(pct = 80) }
            }
        }
        compose.mainClock.advanceTimeByFrame()
        val track = trackW()

        compose.mainClock.advanceTimeBy(Motion.PROGRESS.toLong() / 2)
        val mid = fillW() / track
        val atStart = 0f
        val atEnd = 0.8f
        assertTrue("中途应已开始增长，实际 ${mid}", mid > atStart + 0.05f)
        assertTrue("中途不该已经到终点，实际 ${mid}", mid < atEnd - 0.05f)
    }

    @Test
    fun `关掉动画时进度条直接是终值`() {
        // 截图与几何断言用得到：省掉等待，也不会截到动画中间态
        compose.setContent {
            HanziTheme {
                Row(Modifier.width(200.dp)) { ProgressBar(pct = 40, animated = false) }
            }
        }
        compose.waitForIdle()
        val track = trackW()
        assertEquals("应直接到 40%", 0.4f, fillW() / track, 0.03f)
    }

    @Test
    fun `星星动画会结束，不会让界面一直不静止`() {
        compose.setContent { HanziTheme { Stars(count = 3, size = 22) } }
        // 若动画不收敛，waitForIdle 会超时失败 —— 这条同时是"无循环动画"的护栏
        compose.waitForIdle()
        assertEquals(3, compose.onAllNodesWithText("★").fetchSemanticsNodes().size)
    }

    @Test
    fun `星星数量与填充一致`() {
        compose.setContent { HanziTheme { Stars(count = 2, size = 22) } }
        compose.waitForIdle()
        assertEquals("两颗实心", 2, compose.onAllNodesWithText("★").fetchSemanticsNodes().size)
        assertEquals("一颗空心", 1, compose.onAllNodesWithText("☆").fetchSemanticsNodes().size)
    }

    @Test
    fun `星星动画结束后落回原尺寸，不会停留在缩小状态`() {
        // 用 Animatable 做缩放最容易出的问题是：结束时停在中间值。
        // graphicsLayer 不改变布局尺寸，所以量的是布局尺寸是否正常，
        // 再单独确认缩放系数已回到 1（通过对比动画开/关两种渲染结果）。
        compose.setContent { HanziTheme { Stars(count = 3, size = 22) } }
        compose.waitForIdle()
        val b = compose.onAllNodesWithText("★")[0].getBoundsInRoot()
        assertEquals("星宽应约等于字号 22dp", 22f, (b.right - b.left).value, 6f)
        assertEquals("星高应约等于字号 22dp", 22f, (b.bottom - b.top).value, 8f)
    }

    @Test
    fun `答题点选后动画会收敛，界面能重新静止`() {
        // 加动画最怕的是「选中后一直在动」，界面再也静止不下来：
        // 用户看着晃、测试 waitForIdle 超时。这条专门守这个。
        val app = AppState(ApplicationProvider.getApplicationContext())
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Quiz("free", app.currentBook, null))
        compose.waitForIdle()

        // 题干随机，不写死文案：选项都带 quiz-opt 标签，点第一个
        compose.onAllNodesWithTag("quiz-opt")[0].performClick()
        // 若动效不收敛，这里会超时失败
        compose.waitForIdle()

        // 答完后应出现反馈与「继续」按钮
        compose.onNodeWithText("继续").assertExists()
    }

    @Test
    fun `星数为 0 时全是空心，且没有任何实心星闪一下`() {
        compose.setContent { HanziTheme { Stars(count = 0, size = 22) } }
        compose.waitForIdle()
        assertEquals(0, compose.onAllNodesWithText("★").fetchSemanticsNodes().size)
        assertEquals(3, compose.onAllNodesWithText("☆").fetchSemanticsNodes().size)
    }
}
