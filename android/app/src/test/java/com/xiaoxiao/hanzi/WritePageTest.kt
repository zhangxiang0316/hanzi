package com.xiaoxiao.hanzi

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Trace
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.HanziPainter
import com.xiaoxiao.hanzi.ui.HanziTheme
import com.xiaoxiao.hanzi.ui.Root
import com.xiaoxiao.hanzi.ui.Screen
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.math.abs

/**
 * 描红页的行为测试。
 *
 * 这里的用例都对应真实出现过的问题：
 *   - 写完最后一笔后，最后一笔停在虚线提示状态 → 「最后一笔写不上」
 *   - 写错时静默清空，孩子以为「写了没反应」
 *   - 只点一下会被无声忽略，而点画常常就是最后一笔
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h2400dp-xxhdpi", sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WritePageTest {

    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun state(): AppState =
        AppState(ApplicationProvider.getApplicationContext<Application>())

    /** 以画布节点像素坐标表示的一笔几何 */
    private class Geo(val box: Float, val ox: Float, val oy: Float)

    private fun geo(): Geo {
        val density = compose.activity.resources.displayMetrics.density
        val b = compose.onNodeWithTag("write-canvas").getBoundsInRoot()
        val w = (b.right - b.left).value * density
        val h = (b.bottom - b.top).value * density
        val pad = 6f * density
        return Geo(minOf(w, h) - 2 * pad, pad, pad)
    }

    /**
     * 沿某一笔的中线划过去。
     * @param noise 每个采样点的抖动幅度（px），用来模拟孩子手不稳
     */
    private fun traceStroke(ch: String, index: Int, noise: Float = 0f) {
        val g = geo()
        val pts = HanziPainter.medianPoints(Repo.strokes(ch)!!.medians[index], g.box, g.ox, g.oy)
        var seed = 1234
        fun jitter(): Float {
            seed = (seed * 1103515245 + 12345) and 0x7fffffff
            return ((seed % 10000) / 10000f - 0.5f) * 2 * noise
        }
        compose.onNodeWithTag("write-canvas").performTouchInput {
            down(Offset(pts[0] + jitter(), pts[1] + jitter()))
            var i = 2
            while (i < pts.size) {
                moveTo(Offset(pts[i] + jitter(), pts[i + 1] + jitter()))
                i += 2
            }
            up()
        }
        compose.waitForIdle()
    }

    private fun canvasBitmap(): Bitmap {
        compose.waitForIdle()
        val b = compose.onNodeWithTag("write-canvas").getBoundsInRoot()
        val d = compose.activity.resources.displayMetrics.density
        val view = compose.activity.window.decorView
        val full = Bitmap.createBitmap(
            view.width.takeIf { it > 0 } ?: 1080,
            view.height.takeIf { it > 0 } ?: 7200,
            Bitmap.Config.ARGB_8888
        )
        compose.runOnUiThread { view.draw(Canvas(full)) }
        val x = (b.left.value * d).toInt().coerceAtLeast(0)
        val y = (b.top.value * d).toInt().coerceAtLeast(0)
        val w = ((b.right - b.left).value * d).toInt().coerceAtMost(full.width - x)
        val h = ((b.bottom - b.top).value * d).toInt().coerceAtMost(full.height - y)
        return Bitmap.createBitmap(full, x, y, w, h)
    }

    private fun near(c: Int, target: Int, tol: Int) =
        abs(((c shr 16) and 0xFF) - ((target shr 16) and 0xFF)) <= tol &&
            abs(((c shr 8) and 0xFF) - ((target shr 8) and 0xFF)) <= tol &&
            abs((c and 0xFF) - (target and 0xFF)) <= tol

    private fun hasText(text: String) =
        compose.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty()

    /** 统计某一笔中点附近的墨色 / 提示色像素 */
    private fun probeCoverage(ch: String, strokeIndex: Int): Pair<Int, Int> {
        val bmp = canvasBitmap()
        val d = compose.activity.resources.displayMetrics.density
        val pad = 6f * d
        val box = bmp.width - 2 * pad
        val pts = HanziPainter.medianPoints(
            Repo.strokes(ch)!!.medians[strokeIndex], box, pad, pad
        )
        val idx = (pts.size / 2 / 2) * 2
        val cx = pts[idx].toInt()
        val cy = pts[idx + 1].toInt()
        var ink = 0
        var hint = 0
        for (dy in -12..12) for (dx in -12..12) {
            val px = (cx + dx).coerceIn(0, bmp.width - 1)
            val py = (cy + dy).coerceIn(0, bmp.height - 1)
            val c = bmp.getPixel(px, py)
            if (near(c, HanziPainter.INK, 40)) ink++
            if (near(c, HanziPainter.HINT, 22)) hint++
        }
        return ink to hint
    }

    @Test
    fun `写完最后一笔后最后一笔要变成实心墨迹`() {
        val ch = "三"
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Write(ch))
        compose.waitForIdle()

        val n = Repo.strokes(ch)!!.count
        for (i in 0 until n) traceStroke(ch, i)

        assertTrue("写完全部笔画后应出现完成卡片", hasText("再写一次"))

        val (ink, hint) = probeCoverage(ch, n - 1)
        assertTrue("最后一笔应是实心墨迹，实际 $ink", ink > 400)
        assertTrue("全部写完后不应残留虚线提示，实际 $hint", hint < 20)
    }

    @Test
    fun `每一笔都能顺利写完，不会卡在某一笔`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Write("三"))
        compose.waitForIdle()

        // setContent 只能调一次，所以同一个页面里换字继续测
        for (ch in listOf("三", "玉", "我", "小")) {
            app.nav.replace(Screen.Write(ch))
            compose.waitForIdle()

            val n = Repo.strokes(ch)!!.count
            for (i in 0 until n) traceStroke(ch, i)
            assertTrue("$ch 应该能写完 $n 笔", hasText("再写一次"))
        }
    }

    @Test
    fun `手有点抖也能把整个字写完`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Write("三"))
        compose.waitForIdle()

        for (ch in listOf("三", "玉", "我", "小", "大")) {
            app.nav.replace(Screen.Write(ch))
            compose.waitForIdle()
            val n = Repo.strokes(ch)!!.count
            // 每个采样点抖 ±6px（画布边长约 1100px，约 0.5%）
            for (i in 0 until n) traceStroke(ch, i, noise = 6f)
            assertTrue("$ch 抖动描红后仍应写完 $n 笔", hasText("再写一次"))
        }
    }

    @Test
    fun `写不达标时会说明原因而不是默默清空`() {
        val ch = "三"
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Write(ch))
        compose.waitForIdle()

        // 在画布左上角随便划一下，离第一笔很远
        compose.onNodeWithTag("write-canvas").performTouchInput {
            down(Offset(30f, 30f))
            moveTo(Offset(90f, 40f))
            moveTo(Offset(150f, 50f))
            up()
        }
        compose.waitForIdle()

        val reasons = listOf(
            "起笔的位置不对，从红色小点开始写",
            "这一笔还没有写完整，再拉长一点",
            "偏离了笔画，沿着淡淡的那一笔写",
            "再试一次，慢慢写会更准"
        )
        assertTrue(
            "写错时应给出具体原因，实际提示：${reasons.filter { hasText(it) }}",
            reasons.any { hasText(it) }
        )
        // 没有过关，就不能前进到第二笔
        assertTrue("没过关不该推进到下一笔", !hasText("第 2 笔"))
    }

    @Test
    fun `写完后退一笔要退回最后一笔而不是跳过它`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Write("三"))
        compose.waitForIdle()

        val n = Repo.strokes("三")!!.count
        for (i in 0 until n) traceStroke("三", i)
        assertTrue("应写完", hasText("再写一次"))

        compose.onNodeWithText("退一笔").performClick()
        compose.waitForIdle()

        // 退回后应停在最后一笔：头部显示「第 3 笔」，且完成卡片消失
        assertTrue("退一笔后应提示第 $n 笔", hasText("第 $n 笔"))
        assertTrue("退一笔后完成卡片应消失", !hasText("再写一次"))
    }

    @Test
    fun `只点一下会提示笔画太短`() {
        val ch = "玉"
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Write(ch))
        compose.waitForIdle()

        val g = geo()
        val pts = HanziPainter.medianPoints(Repo.strokes(ch)!!.medians[0], g.box, g.ox, g.oy)
        compose.onNodeWithTag("write-canvas").performTouchInput {
            down(Offset(pts[0], pts[1]))
            up()
        }
        compose.waitForIdle()

        assertTrue(
            "点一下应给出「太短」的提示，不能无声忽略",
            hasText("这一笔太短了")
        )
    }

    @Test
    fun `手抖和首尾内缩的描红也要能过`() {
        // 孩子认真描红但手会抖：±7px 抖动 + 首尾各内缩 10%
        val box = 1077f
        val tol = box * 0.075f
        var seed = 7
        fun rnd(): Float {
            seed = (seed * 1103515245 + 12345) and 0x7fffffff
            return (seed % 10000) / 10000f
        }
        for (ch in listOf("三", "玉", "我", "小", "大", "人")) {
            val s = Repo.strokes(ch) ?: continue
            for (i in 0 until s.count) {
                val target = HanziPainter.medianPoints(s.medians[i], box, 60f, 60f)
                val n = target.size / 2
                val i0 = (n * 0.1f).toInt().coerceAtMost(n - 2)
                val i1 = (n - 1 - (n * 0.1f).toInt()).coerceAtLeast(i0 + 1)
                val user = ArrayList<Float>()
                for (k in i0..i1) {
                    user.add(target[k * 2] + (rnd() - 0.5f) * 14f)
                    user.add(target[k * 2 + 1] + (rnd() - 0.5f) * 14f)
                }
                val r = Trace.scoreStroke(user.toFloatArray(), target, tol)
                assertTrue(
                    "$ch 第${i + 1}笔：正常描红应通过，实际 ${r.score} 分（${r.reason}）",
                    r.score >= Trace.ACCEPT
                )
            }
        }
    }
}
