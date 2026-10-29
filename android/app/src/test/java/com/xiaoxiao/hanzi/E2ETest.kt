package com.xiaoxiao.hanzi

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.HanziTheme
import com.xiaoxiao.hanzi.ui.HanziPainter
import com.xiaoxiao.hanzi.ui.Root
import com.xiaoxiao.hanzi.ui.Screen
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * 端到端冒烟：真实手势走完「学一个字」的完整链路。
 *
 * 覆盖的都是纯函数单测覆盖不到的地方：手势坐标 → 画布坐标 → 评分 → 存档。
 * 小程序版本里「描红写完却不判分 / 坐标对不上」是真实发生过的 bug。
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi", sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class E2ETest {

    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun state(): AppState {
        val app = ApplicationProvider.getApplicationContext<Application>()
        return AppState(app)
    }

    @Test
    fun `描红写完一笔会判分并存档`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Write("一"))
        compose.waitForIdle()

        val strokes = Repo.strokes("一")!!
        assertEquals("「一」应只有一笔", 1, strokes.count)

        // 画布在首屏以下，先滚动到可见；否则触摸点会落在窗口外被丢弃
        compose.onNodeWithTag("write-canvas").performScrollTo()
        compose.waitForIdle()

        val bounds = compose.onNodeWithTag("write-canvas").getBoundsInRoot()
        val density = compose.activity.resources.displayMetrics.density
        // 画布区域（dp）→ 像素；Canvas 有 6dp 内边距，HanziPainter 在内部再居中
        val boxDp = minOf(bounds.right - bounds.left, bounds.bottom - bounds.top).value
        val boxPx = boxDp * density - 12 * density

        // 目标笔画的起终点（1024 坐标系），换算到画布像素
        val median = strokes.medians[0]
        val pts = HanziPainter.medianPoints(median, boxPx, 0f, 0f)
        assertTrue("「一」应有中线", pts.size >= 4)

        // performTouchInput 的坐标是「相对该节点左上角的像素」，
        // 与页面里 PointerInputChange.position 同一单位，直接用 pts（px）即可。
        // 画布有 6dp 内边距，田字格从那里开始。
        val padPx = 6f * density

        // 沿中线划过，模拟真实落笔
        compose.onNodeWithTag("write-canvas").performTouchInput {
            val x0 = pts[0] + padPx
            val y0 = pts[1] + padPx
            val x1 = pts[pts.size - 2] + padPx
            val y1 = pts[pts.size - 1] + padPx
            down(Offset(x0, y0))
            // 中间多点采样，模拟连续拖动
            for (t in 1..8) {
                val f = t / 9f
                moveTo(Offset(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f))
            }
            moveTo(Offset(x1, y1))
            up()
        }
        compose.waitForIdle()

        // 一笔写完 -> 应该弹出结果卡并写入成绩
        val record = app.progress.writeRecord("一")
        assertNotNull("描红成绩应已存档", record)
        assertTrue("描红次数应 >= 1", record!!.tries >= 1)
        compose.onNodeWithText("再写一次").assertExists()
    }

    @Test
    fun `点我认识它了会写入学习进度`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Detail("人", null))
        compose.waitForIdle()

        assertTrue("初始未学", !app.progress.hasLearned("人"))
        // 按钮在首屏以下，先滚动到可见
        compose.onNodeWithText("我认识它了").performScrollTo().performClick()
        compose.waitForIdle()

        assertTrue("点击后应标记为已学", app.progress.hasLearned("人"))
        // 按钮文案变成已学会
        compose.onNodeWithText("已学会 ✓").assertExists()
    }

    @Test
    fun `完整走一遍 首页到单元到课到详情`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        compose.waitForIdle()

        val book = Repo.book("1a")!!
        val lessonId = book.lessons.first()
        val lesson = Repo.lesson(lessonId)!!

        app.nav.push(Screen.Unit("1a"))
        compose.waitForIdle()
        app.nav.push(Screen.Lesson(lessonId))
        compose.waitForIdle()
        val firstChar = lesson.chars.first()
        app.nav.push(Screen.Detail(firstChar, lessonId))
        compose.waitForIdle()

        // 三级页面都在栈里，可以一路返回
        assertEquals(4, app.nav.size())
        assertTrue(app.nav.back())
        assertTrue(app.nav.back())
        assertTrue(app.nav.back())
        assertEquals(1, app.nav.size())

        compose.onNodeWithText("跟课本学").assertExists()
    }

    @Test
    fun `答对题会推进复习箱`() {
        val app = state()
        val ch = Repo.bookChars("1a").first()
        app.progress.learn(ch)
        val boxBefore = app.progress.entry(ch)!!.box

        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Quiz("free", "1a", null))
        compose.waitForIdle()

        // 直接走数据层验证评分入口（UI 上点哪个选项取决于随机出题）
        app.progress.grade(ch, true, null)
        assertEquals("答对应升一箱", boxBefore + 1, app.progress.entry(ch)!!.box)
        assertTrue(app.progress.todayStats().answers >= 1)
    }

    @Test
    fun `错题的次数会累积并在答对后递减`() {
        val app = state()
        val ch = Repo.bookChars("1a").first()
        app.progress.learn(ch)
        app.progress.grade(ch, false, null)
        app.progress.grade(ch, false, null)

        assertEquals("应进错题本", 1, app.progress.wrongCount())
        assertEquals(2, app.progress.wrongList().first().n)

        app.progress.grade(ch, true, null)
        assertEquals("答对一次应减一次", 1, app.progress.wrongList().first().n)
    }
}
