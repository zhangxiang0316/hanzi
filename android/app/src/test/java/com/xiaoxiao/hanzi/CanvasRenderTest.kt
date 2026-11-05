package com.xiaoxiao.hanzi

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.HanziColors
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
 * 画布渲染验证：把页面画进 Bitmap，直接检查像素。
 *
 * 光靠「节点存在」证明不了「汉字真的画出来了」——
 * 小程序阶段就出现过坐标翻转、路径丢失、笔顺定格错位这类问题，
 * 但它们都不会让语义树报错。这里用像素颜色兜底。
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi", sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CanvasRenderTest {

    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun state(): AppState =
        AppState(ApplicationProvider.getApplicationContext<Application>())

    private fun capture(): Bitmap {
        compose.waitForIdle()
        val view = compose.activity.window.decorView
        val w = if (view.width > 0) view.width else 1080
        val h = if (view.height > 0) view.height else 2400
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        compose.runOnUiThread { view.draw(Canvas(bmp)) }
        return bmp
    }

    private fun colorCount(bmp: Bitmap, target: Int, tol: Int = 12): Int {
        val tr = (target shr 16) and 0xFF
        val tg = (target shr 8) and 0xFF
        val tb = target and 0xFF
        var n = 0
        // 隔行取样，够用且快
        var y = 0
        while (y < bmp.height) {
            var x = 0
            while (x < bmp.width) {
                val c = bmp.getPixel(x, y)
                if (abs(((c shr 16) and 0xFF) - tr) <= tol &&
                    abs(((c shr 8) and 0xFF) - tg) <= tol &&
                    abs((c and 0xFF) - tb) <= tol
                ) n++
                x += 2
            }
            y += 2
        }
        return n
    }

    @Test
    fun `认识这个字的画布真的画出了汉字与田字格`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        // 注意：Compose 测试里 Thread.sleep 不会推进动画时钟，
        // 必须用 mainClock 手动把时间往前拨，否则笔顺动画一帧都不会走。
        // 且必须先完成首帧，LaunchedEffect 才会启动。
        app.nav.push(Screen.Detail("永", null))
        compose.waitForIdle()
        compose.mainClock.advanceTimeBy(HanziPainter.PER_STROKE_MS * 12)
        compose.waitForIdle()

        val bmp = capture()

        // 只统计画布节点内部，避免把页面文字的颜色也算进来
        val bounds = compose.onNodeWithTag("detail-canvas").getBoundsInRoot()
        val d = compose.activity.resources.displayMetrics.density
        val ink = countInRect(
            bmp,
            (bounds.left.value * d).toInt(),
            (bounds.top.value * d).toInt(),
            ((bounds.right - bounds.left).value * d).toInt(),
            ((bounds.bottom - bounds.top).value * d).toInt(),
            HanziPainter.INK, tol = 40
        )
        // 永 5 笔写完，实心笔画应占相当面积
        assertTrue("画布内应画出墨色笔画，实际像素 $ink", ink > 5000)

        // 田字格边框与提示色也应在
        val hint = colorCount(bmp, HanziPainter.HINT, tol = 25)
        assertTrue("应画出未写笔画的提示线/格子，实际 $hint", hint > 100)

        // 背景是米色纸，不是纯白
        val paper = colorCount(bmp, 0xFBF6EC, tol = 4)
        assertTrue("背景应为米色纸，实际 $paper", paper > 1000)
    }

    /** 在指定矩形内统计某个颜色的像素数 */
    private fun countInRect(
        bmp: Bitmap, x0: Int, y0: Int, w: Int, h: Int, color: Int, tol: Int
    ): Int {
        val tr = (color shr 16) and 0xFF
        val tg = (color shr 8) and 0xFF
        val tb = color and 0xFF
        var n = 0
        var y = y0.coerceAtLeast(0)
        val yEnd = minOf(y0 + h, bmp.height)
        while (y < yEnd) {
            var x = x0.coerceAtLeast(0)
            val xEnd = minOf(x0 + w, bmp.width)
            while (x < xEnd) {
                val c = bmp.getPixel(x, y)
                if (abs(((c shr 16) and 0xFF) - tr) <= tol &&
                    abs(((c shr 8) and 0xFF) - tg) <= tol &&
                    abs((c and 0xFF) - tb) <= tol
                ) n++
                x += 2
            }
            y += 2
        }
        return n
    }

    @Test
    fun `笔迹不会上下倒置`() {
        // 汉字重心：上半部的墨量应少于下半部（撇捺展开在下），
        // 若坐标翻转了，这个关系会反过来。用「人」验证最直观。
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        // 直接在离屏 Bitmap 上跑绘制，绕开页面布局，只验证坐标是否正确。
        // 用「二」：上横短、下横长，如果 y 被翻转，长横会跑到上面去。
        val strokes = Repo.strokes("二")!!
        val size = 400
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        canvas.drawColor(0xFFFFFFFF.toInt())
        HanziPainter.drawStrokes(canvas, strokes, size.toFloat(), 0f, 0f, completed = strokes.count)

        // 逐行统计墨色像素的水平跨度
        val inkColor = HanziPainter.INK
        val tr = (inkColor shr 16) and 0xFF
        val tg = (inkColor shr 8) and 0xFF
        val tb = inkColor and 0xFF
        val rowSpan = IntArray(size) { 0 }
        for (y in 0 until size) {
            var minX = -1
            var maxX = -1
            for (x in 0 until size) {
                val c = bmp.getPixel(x, y)
                if (abs(((c shr 16) and 0xFF) - tr) <= 40 &&
                    abs(((c shr 8) and 0xFF) - tg) <= 40 &&
                    abs((c and 0xFF) - tb) <= 40
                ) { if (minX < 0) minX = x; maxX = x }
            }
            rowSpan[y] = if (minX < 0) 0 else maxX - minX
        }

        val widths = rowSpan.filter { it > 20 }
        assertTrue("应画出两横，实际有效行 ${widths.size}", widths.size > 10)

        val half = size / 2
        val topMax = (0 until half).maxOf { rowSpan[it] }
        val bottomMax = (half until size).maxOf { rowSpan[it] }
        assertTrue(
            "「二」的长横应在下方（上 $topMax / 下 $bottomMax），若反转说明 y 翻转丢失",
            bottomMax > topMax
        )
    }

    @Test
    fun `描红画布有底字与田字格`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Write("一"))
        compose.waitForIdle()

        val bmp = capture()
        // 描红底色用 GHOST（淡灰）画底字
        val ghost = colorCount(bmp, HanziPainter.GHOST, tol = 18)
        assertTrue("应画出淡灰底字，实际 $ghost", ghost > 200)
    }

    @Test
    fun `卡片是白底而不是透明`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        Thread.sleep(200)
        val bmp = capture()
        val white = colorCount(bmp, 0xFFFFFF, tol = 3)
        assertTrue("卡片应为白色，实际 $white", white > 5000)
    }

    @Test
    fun `主题色出现在主按钮上`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        Thread.sleep(200)
        val bmp = capture()
        // 首页「今日任务」卡是玉色渐变
        val jade = colorCount(bmp, 0x3E8E7E, tol = 30)
        assertTrue("应出现玉色主按钮/卡片，实际 $jade", jade > 300)
        // 反向确认：页面没有大面积纯黑（白底白字的反面就是黑底黑字之类）
        val black = colorCount(bmp, 0x000000, tol = 6)
        assertTrue("不应出现大片纯黑，实际 $black", black < 20000)
    }
}

/**
 * 详情页笔画格：画出的是笔形，不是空白格。
 *
 * 「节点存在」证明不了「这一笔画出来了」——格子空着也满足所有布局断言。
 * 之前笔画表是数字圆点，数字当然是渲染出来的；改成画笔形后，
 * 如果 drawSingleStroke 的坐标或颜色传错，格子会变成一片空白而测试全绿。
 *
 * 做法：把页面画进 Bitmap，在笔画格区域内数墨色像素。
 * ink1 = #25332D，笔画外的底色是 cardWarm #FDF9F0，两者差异很大。
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h2400dp-xxhdpi", sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class StrokeGlyphRenderTest {

    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun state(): AppState =
        AppState(ApplicationProvider.getApplicationContext<Application>())

    private fun capture(): Bitmap {
        compose.waitForIdle()
        val view = compose.activity.window.decorView
        val w = if (view.width > 0) view.width else 1080
        val h = if (view.height > 0) view.height else 2400
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        compose.runOnUiThread { view.draw(Canvas(bmp)) }
        return bmp
    }

    /** 在给定矩形里数「接近墨色」的像素 */
    private fun inkPixels(bmp: Bitmap, l: Int, t: Int, r: Int, b: Int): Int {
        val target = 0x25332D
        val tr = (target shr 16) and 0xFF
        val tg = (target shr 8) and 0xFF
        val tb = target and 0xFF
        var n = 0
        for (y in maxOf(0, t) until minOf(bmp.height, b)) {
            for (x in maxOf(0, l) until minOf(bmp.width, r)) {
                val c = bmp.getPixel(x, y)
                if (abs(((c shr 16) and 0xFF) - tr) <= 40 &&
                    abs(((c shr 8) and 0xFF) - tg) <= 40 &&
                    abs((c and 0xFF) - tb) <= 40
                ) n++
            }
        }
        return n
    }

    private fun rectOf(tag: String): android.graphics.Rect {
        val b = compose.onNodeWithTag(tag).getBoundsInRoot()
        val d = compose.activity.resources.displayMetrics.density
        return android.graphics.Rect(
            (b.left.value * d).toInt(), (b.top.value * d).toInt(),
            (b.right.value * d).toInt(), (b.bottom.value * d).toInt()
        )
    }

    @Test
    fun `笔画格里真的画出了笔形`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        // 「三」三笔，每格都应是可辨认的横
        app.nav.push(Screen.Detail("三", null))
        compose.waitForIdle()

        val bmp = capture()
        val cells = (0..2).map { rectOf("stroke-cell-$it") }
        val inkEach = cells.map { inkPixels(bmp, it.left, it.top, it.right, it.bottom) }

        inkEach.forEachIndexed { i, n ->
            // 一格 44dp @xxhdpi 约 132px 见方，一笔横画至少几百个墨点
            assertTrue(
                "第 ${i + 1} 个笔画格只有 $n 个墨色像素，几乎是空白——" +
                    "笔形没画出来（drawSingleStroke 的坐标或颜色可能传错了）",
                n >= 100
            )
        }
    }

    @Test
    fun `不同的笔画格画的是不同的笔`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        // 「三」三横长度不同，三格的墨点数不该完全一样
        app.nav.push(Screen.Detail("三", null))
        compose.waitForIdle()

        val bmp = capture()
        val inkEach = (0..2).map {
            val r = rectOf("stroke-cell-$it")
            inkPixels(bmp, r.left, r.top, r.right, r.bottom)
        }
        assertTrue(
            "三格墨点数完全相同 $inkEach，说明画的是同一笔（index 没生效）",
            inkEach.toSet().size > 1
        )
    }
}
