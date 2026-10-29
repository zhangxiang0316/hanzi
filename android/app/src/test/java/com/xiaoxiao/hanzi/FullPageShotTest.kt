package com.xiaoxiao.hanzi

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.ui.AppState
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
import java.io.File

/**
 * 整页截图。
 *
 * 普通手机视口只能截到首屏，「我的」页的册次芯片、描红工具条都在下面。
 * 这里用超高视口把整页一次性铺开，方便逐屏检查。
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h2600dp-xxhdpi", sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class FullPageShotTest {

    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val outDir = File("build/screenshots").apply { mkdirs() }

    private fun state(): AppState =
        AppState(ApplicationProvider.getApplicationContext<Application>())

    private fun shoot(name: String) {
        compose.waitForIdle()
        val view = compose.activity.window.decorView
        val w = view.width.takeIf { it > 0 } ?: 1080
        val h = view.height.takeIf { it > 0 } ?: 7800
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        compose.runOnUiThread { view.draw(Canvas(bmp)) }
        val file = File(outDir, "$name.png")
        file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        assertTrue("应产出截图 $name", file.length() > 2000)
    }

    @Test
    fun `整页 - 我的`() {
        val app = state()
        Repo.bookChars("1a").take(12).forEach { app.progress.learn(it) }
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.switchTab(Screen.Profile)
        shoot("20-profile-full")
    }

    @Test
    fun `整页 - 练习`() {
        val app = state()
        Repo.bookChars("1a").take(10).forEach { app.progress.learn(it) }
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.switchTab(Screen.Practice)
        shoot("21-practice-full")
    }

    @Test
    fun `整页 - 首页`() {
        val app = state()
        Repo.bookChars("1a").take(12).forEach { app.progress.learn(it) }
        compose.setContent { HanziTheme { Root(app) } }
        shoot("22-index-full")
    }

    @Test
    fun `整页 - 认识这个字`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Detail("人", null))
        compose.waitForIdle()
        compose.mainClock.advanceTimeBy(4000)
        shoot("23-detail-full")
    }

    @Test
    fun `整页 - 描红写完`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        val ch = "我"
        app.nav.push(Screen.Write(ch))
        compose.waitForIdle()

        // 沿中线写完全部笔画，拍「完成」状态，用来确认最后一笔是实心而不是虚线
        val d = compose.activity.resources.displayMetrics.density
        val b = compose.onNodeWithTag("write-canvas").getBoundsInRoot()
        val pad = 6f * d
        val box = minOf((b.right - b.left).value * d, (b.bottom - b.top).value * d) - 2 * pad
        val s = com.xiaoxiao.hanzi.data.Repo.strokes(ch)!!
        for (i in 0 until s.count) {
            val pts = com.xiaoxiao.hanzi.ui.HanziPainter.medianPoints(s.medians[i], box, pad, pad)
            compose.onNodeWithTag("write-canvas").performTouchInput {
                down(Offset(pts[0], pts[1]))
                var k = 2
                while (k < pts.size) { moveTo(Offset(pts[k], pts[k + 1])); k += 2 }
                up()
            }
            compose.waitForIdle()
        }
        shoot("25-write-done")
    }

    @Test
    fun `整页 - 描红`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Write("人"))
        shoot("24-write-full")
    }
}
