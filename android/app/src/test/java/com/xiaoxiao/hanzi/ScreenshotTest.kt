package com.xiaoxiao.hanzi

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
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
 * 截图测试：把关键页面真实渲染成 PNG，输出到 build/screenshots/。
 *
 * 用途有两个：
 *   1. 视觉回归 —— 布局跑偏、文字被裁、白底白字这类问题，截图一眼就能看出来
 *   2. 没有模拟器时也能验证「界面到底长什么样」
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi", sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ScreenshotTest {

    // 用 createAndroidComposeRule 才能拿到 Activity，把 decorView 直接画进 Bitmap。
    // 官方 captureToImage() 走 PixelCopy，需要真实硬件绘制，Robolectric 下会超时。
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val outDir = File("build/screenshots").apply { mkdirs() }

    private fun state(): AppState {
        val app = ApplicationProvider.getApplicationContext<Application>()
        return AppState(app)
    }

    /** 只截某个节点：用来放大看画布、按钮这类细节 */
    private fun shootNode(tag: String, name: String) {
        compose.waitForIdle()
        val b = compose.onNodeWithTag(tag).getBoundsInRoot()
        val density = compose.activity.resources.displayMetrics.density
        val view = compose.activity.window.decorView
        val full = Bitmap.createBitmap(
            view.width.takeIf { it > 0 } ?: 1080,
            view.height.takeIf { it > 0 } ?: 2400,
            Bitmap.Config.ARGB_8888
        )
        compose.runOnUiThread { view.draw(Canvas(full)) }
        val x = (b.left.value * density).toInt().coerceIn(0, full.width - 1)
        val y = (b.top.value * density).toInt().coerceIn(0, full.height - 1)
        val w = ((b.right - b.left).value * density).toInt().coerceAtLeast(1)
            .coerceAtMost(full.width - x)
        val h = ((b.bottom - b.top).value * density).toInt().coerceAtLeast(1)
            .coerceAtMost(full.height - y)
        val crop = Bitmap.createBitmap(full, x, y, w, h)
        val file = File(outDir, "$name.png")
        file.outputStream().use { crop.compress(Bitmap.CompressFormat.PNG, 100, it) }
        assertTrue("节点截图应有内容：$name", file.length() > 2000)
    }

    private fun shoot(name: String) {
        compose.waitForIdle()
        val view = compose.activity.window.decorView
        val w = view.width.takeIf { it > 0 } ?: 1080
        val h = view.height.takeIf { it > 0 } ?: 2400
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        compose.runOnUiThread {
            view.draw(Canvas(bitmap))
        }
        val file = File(outDir, "$name.png")
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        assertTrue("截图应有内容：$name", file.length() > 2000)
    }

    @Test
    fun `截图 - 首页`() {
        val app = state()
        Repo.bookChars("1a").take(12).forEach { app.progress.learn(it) }
        compose.setContent { HanziTheme { Root(app) } }
        shoot("01-index")
    }

    @Test
    fun `截图 - 单元目录`() {
        val app = state()
        Repo.bookChars("1a").take(8).forEach { app.progress.learn(it) }
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Unit("1a"))
        shoot("02-unit")
    }

    @Test
    fun `截图 - 本课生字`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        val lesson = Repo.book("1a")!!.lessons.first()
        Repo.lessonChars(lesson).take(2).forEach { app.progress.learn(it) }
        app.nav.push(Screen.Lesson(lesson))
        shoot("03-lesson")
    }

    @Test
    fun `截图 - 认识这个字`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        // 手动推进动画时钟，让笔顺真的写出来（Thread.sleep 对 Compose 无效）。
        // 顺序很关键：先进页面、等首帧完成，再拨时钟，
        // 否则 LaunchedEffect 还没启动，拨过去的时间等于白拨。
        app.nav.push(Screen.Detail("人", null))
        compose.waitForIdle()
        compose.mainClock.advanceTimeBy(4000)
        compose.waitForIdle()
        shootNode("detail-canvas", "04a-detail-canvas")
        shoot("04-detail")
    }

    @Test
    fun `截图 - 笔画多的字换行`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        // 「繁」笔画多，用来检查芯片是否换行而不是撑出屏幕
        app.nav.push(Screen.Detail("繁", null))
        compose.waitForIdle()
        compose.mainClock.advanceTimeBy(20000)
        compose.waitForIdle()
        shoot("05-detail-many")
    }

    @Test
    fun `截图 - 描红`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Write("人"))
        shoot("06-write")
    }

    @Test
    fun `截图 - 答题`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Quiz("free", "1a", null))
        shoot("07-quiz")
    }

    @Test
    fun `截图 - 结果`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Result(4, 6, listOf("人", "口"), "review", "1a"))
        shoot("08-result")
    }

    @Test
    fun `截图 - 练习页`() {
        val app = state()
        Repo.bookChars("1a").take(10).forEach { app.progress.learn(it) }
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.switchTab(Screen.Practice)
        shoot("09-practice")
    }

    @Test
    fun `截图 - 我的`() {
        val app = state()
        Repo.bookChars("1a").take(10).forEach { app.progress.learn(it) }
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.switchTab(Screen.Profile)
        shoot("10-profile")
    }

    @Test
    fun `截图 - 我的下半屏`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.switchTab(Screen.Profile)
        compose.waitForIdle()
        // 专门看「当前册次」8 个芯片换行后的样子
        compose.onRoot().assertExists()
        shoot("11-profile-bottom")
    }

    @Test
    fun `截图 - 错题本`() {
        val app = state()
        Repo.bookChars("1a").take(6).forEach { ch ->
            app.progress.learn(ch)
            app.progress.grade(ch, false, null)
        }
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Wrong)
        shoot("12-wrong")
    }

    @Test
    fun `截图 - 关于`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.About)
        shoot("13-about")
    }
}
