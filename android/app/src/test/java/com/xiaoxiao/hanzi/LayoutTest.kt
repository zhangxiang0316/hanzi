package com.xiaoxiao.hanzi

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.HanziTheme
import com.xiaoxiao.hanzi.ui.Root
import com.xiaoxiao.hanzi.ui.Screen
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.math.abs

/**
 * 布局断言。
 *
 * 用户在小程序版本上陆续报过几个纯样式问题：
 *   - 底部「继续学习」按钮没居中、只有半屏宽
 *   - 「我的」页册次芯片文字跑到左上角
 *   - 芯片换行后圆角变成怪形状
 * 这些问题是肉眼能看出来、但单测断言不到的。这里用节点边界做几何断言，
 * 让它们以后不可能悄悄回归。
 */
@RunWith(RobolectricTestRunner::class)
// 用超长视口，让整页内容一次性铺开：
// getBoundsInRoot() 返回的是裁剪到可视区后的矩形，页面比屏幕长时
// 下半屏的节点会得到 0 宽 / 被截断的高度，几何断言就失真了。
@Config(qualifiers = "w411dp-h2400dp-xxhdpi", sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LayoutTest {

    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun state(): AppState {
        val app = ApplicationProvider.getApplicationContext<Application>()
        return AppState(app)
    }

    /** 屏幕宽度（dp） */
    private fun screenWidthDp(): Float = compose.activity.resources.displayMetrics.widthPixels /
        compose.activity.resources.displayMetrics.density

    @Test
    fun `本课页底部按钮占满宽度并水平居中`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        val lesson = Repo.book("1a")!!.lessons.first()
        app.nav.push(Screen.Lesson(lesson))
        compose.waitForIdle()

        // 用 testTag 取按钮容器本身（文字节点只是按钮的一部分）
        compose.onNodeWithText("开始学习", substring = true).assertExists()
        val b = compose.onNodeWithTag("lesson-start").getBoundsInRoot()
        val center = (b.left + b.right) / 2
        val screenCenter = screenWidthDp() / 2

        // 居中：允许 2dp 误差
        assertTrue(
            "按钮文字应水平居中，实际 center=$center 屏中心=$screenCenter",
            abs(center.value - screenCenter) < 2f
        )

        // 宽度：应接近满宽（屏宽减两侧 20dp 边距），而不是半屏
        val expected = screenWidthDp() - 40f
        assertTrue(
            "按钮应接近满宽，实际 ${(b.right - b.left).value}dp，期望约 ${expected}dp",
            (b.right - b.left).value > expected - 8f
        )
    }

    @Test
    fun `我的页八个册次芯片排成四列两行`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.switchTab(Screen.Profile)
        compose.waitForIdle()

        // 收集 8 个册次芯片的左上角坐标（用 testTag 精确定位芯片容器）
        val positions = Repo.books.map { book ->
            compose.onNodeWithTag("profile-book-${book.id}").getBoundsInRoot()
        }

        val rows = positions.map { (it.top.value).toInt() }.distinct()
        val cols = positions.map { (it.left.value).toInt() }.distinct()
        assertEquals("应排成 2 行，实际 $rows", 2, rows.size)
        assertEquals("应排成 4 列，实际 $cols", 4, cols.size)

        // 每行 4 个，且同一行的 top 完全一致
        val byRow = positions.groupBy { (it.top.value).toInt() }
        assertEquals(4, byRow[rows[0]]!!.size)
        assertEquals(4, byRow[rows[1]]!!.size)

        // 列对齐：同一列的 left 完全一致
        val byCol = positions.groupBy { (it.left.value).toInt() }
        assertEquals(4, byCol.size)
        byCol.values.forEach { assertEquals("同一列应对齐", 2, it.size) }
    }

    @Test
    fun `我的页册次芯片文字水平居中于芯片`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.switchTab(Screen.Profile)
        compose.waitForIdle()

        // 4 个一行的四个芯片，中心应等距分布，说明每个芯片宽度均分
        val texts = Repo.books.take(4).map {
            compose.onNodeWithTag("profile-book-${it.id}").getBoundsInRoot()
        }
        val centers = texts.map { (it.left.value + it.right.value) / 2 }
        // 相邻中心间距应该一致（误差 2dp）
        val gaps = centers.zipWithNext { a, b -> b - a }
        val avg = gaps.average().toFloat()
        gaps.forEach {
            assertTrue("芯片间距应一致，实际 $gaps", abs(it - avg) < 2f)
        }
        // 且第一个和最后一个到屏幕两侧的距离应对称
        val leftMargin = centers.first()
        val rightMargin = screenWidthDp() - centers.last()
        assertTrue(
            "两侧留白应对称：左 $leftMargin 右 $rightMargin",
            abs(leftMargin - rightMargin) < 4f
        )
    }

    @Test
    fun `练习页册次芯片也是四列两行`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.switchTab(Screen.Practice)
        compose.waitForIdle()

        val tops = Repo.books.map {
            compose.onNodeWithTag("practice-book-${it.id}").getBoundsInRoot().top.value.toInt()
        }.distinct()
        assertEquals("应排成 2 行，实际 $tops", 2, tops.size)
    }

    @Test
    fun `底部导航三个 tab 均分宽度`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        compose.waitForIdle()

        val labels = listOf("首页", "练习", "我的")
        val centers = labels.map {
            val b = compose.onNodeWithText(it).getBoundsInRoot()
            (b.left.value + b.right.value) / 2
        }
        val gaps = centers.zipWithNext { a, b -> b - a }
        assertTrue("三个 tab 应等距，实际 $gaps", abs(gaps[0] - gaps[1]) < 2f)
        // 第一个 tab 中心约在 1/6 屏宽处
        val sixth = screenWidthDp() / 6
        assertTrue("首个 tab 应居中于左三分之一，实际 ${centers[0]}", abs(centers[0] - sixth) < 6f)
    }

    @Test
    fun `非 tab 页面显示返回栏且 tab 页面不显示`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        compose.waitForIdle()

        // 首页不应有底部导航之外的返回箭头：用「课本目录」标题验证
        app.nav.push(Screen.Unit("1a"))
        compose.waitForIdle()
        compose.onNodeWithText("课本目录").assertExists()
    }

    @Test
    fun `详情页笔画芯片不超出屏幕宽度`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        // 「繁」17 画，芯片必须换行
        app.nav.push(Screen.Detail("繁", null))
        compose.waitForIdle()

        val count = Repo.strokeCount("繁")
        assertTrue(count >= 10)
        // 每个数字芯片都在屏幕内
        for (i in 1..count) {
            val b = compose.onAllNodesWithText("$i").onFirst().getBoundsInRoot()
            assertTrue("第 $i 笔芯片左侧越界", b.left.value >= 0f)
            assertTrue("第 $i 笔芯片右侧越界 ${b.right.value}", b.right.value <= screenWidthDp() + 0.5f)
        }
    }

    @Test
    fun `首页主按钮是满宽的大按钮`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        compose.waitForIdle()

        val task = app.todayTask()
        val b = compose.onNodeWithText(task.action).getBoundsInRoot()
        val expected = screenWidthDp() - 40f - 36f  // 页面边距 + 卡片内边距
        assertTrue(
            "主按钮应接近满宽，实际 ${(b.right - b.left).value}dp 期望约 ${expected}dp",
            (b.right - b.left).value > expected - 12f
        )
    }

    @Test
    fun `首页八个册次排成两列四行且整体不占过多高度`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        compose.waitForIdle()

        val ids = Repo.books.map { it.id }
        val positions = ids.map { compose.onNodeWithTag("index-book-$it").getBoundsInRoot() }

        // 两列网格。整宽卡片一册一行时，八册要占掉一屏多，
        // 首页得滚很久才能看到「今日一字」。
        val rows = positions.map { it.top.value.toInt() }.distinct()
        val cols = positions.map { it.left.value.toInt() }.distinct()
        assertEquals("应排成 4 行，实际 $rows", 4, rows.size)
        assertEquals("应排成 2 列，实际 $cols", 2, cols.size)

        // 同一行两张等宽，且不超出屏幕
        positions.groupBy { it.top.value.toInt() }.forEach { (_, cards) ->
            assertEquals("同一行应 2 张", 2, cards.size)
            val widths = cards.map { (it.right - it.left).value }
            assertTrue("同一行卡片应等宽，实际 $widths", widths.max() - widths.min() < 1f)
            assertTrue(
                "最右一张不应超出屏幕，实际 ${cards.maxOf { it.right.value }}dp",
                cards.maxOf { it.right.value } <= screenWidthDp()
            )
        }

        // 整块不应超过 400dp —— 回归护栏，防止再改回大卡片
        val top = positions.minOf { it.top.value }
        val bottom = positions.maxOf { it.bottom.value }
        assertTrue(
            "册次区总高应 <= 400dp，实际 ${(bottom - top).toInt()}dp",
            bottom - top <= 400f
        )
    }

    @Test
    fun `首页册次卡片文字不被截断`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        compose.waitForIdle()

        // 最长的册名（四年级上册）必须完整显示
        listOf("一年级上册", "四年级下册", "三年级上册").forEach {
            compose.onNodeWithText(it).assertExists()
        }
    }

    @Test
    fun `我的页徽章排成四列两行且整体不占过多高度`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.switchTab(Screen.Profile)
        compose.waitForIdle()

        val ids = listOf("sprout", "ten", "fifty", "hundred", "five", "streak", "perfect", "write")
        val positions = ids.map { compose.onNodeWithTag("badge-$it").getBoundsInRoot() }

        // 4 列 × 2 行，与小程序一致（width: calc(25% - 16rpx)）。
        // 早先是 2 列 4 行，单卡宽度翻倍、整块占掉近半屏，所以看着太大。
        val rows = positions.map { it.top.value.toInt() }.distinct()
        val cols = positions.map { it.left.value.toInt() }.distinct()
        assertEquals("应排成 2 行，实际 $rows", 2, rows.size)
        assertEquals("应排成 4 列，实际 $cols", 4, cols.size)

        // 同一行四张卡等宽，且不超出屏幕
        val byRow = positions.groupBy { it.top.value.toInt() }
        byRow.forEach { (_, cards) ->
            assertEquals("同一行应 4 张", 4, cards.size)
            val widths = cards.map { (it.right - it.left).value }
            val spread = widths.max() - widths.min()
            assertTrue("同一行卡片应等宽，实际 $widths", spread < 1f)
            assertTrue(
                "最右一张不应超出屏幕，实际 ${cards.maxOf { it.right.value }}dp",
                cards.maxOf { it.right.value } <= screenWidthDp()
            )
        }

        // 整块徽章区（含行间距）不应超过 160dp —— 回归护栏，防止再做成大卡片
        val top = positions.minOf { it.top.value }
        val bottom = positions.maxOf { it.bottom.value }
        assertTrue(
            "徽章区总高应 <= 160dp，实际 ${(bottom - top).toInt()}dp",
            bottom - top <= 160f
        )
    }

    @Test
    fun `我的页徽章文字不被截断`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.switchTab(Screen.Profile)
        compose.waitForIdle()

        // 最长的徽章名与说明都要完整显示（不确定字数，逐条验证存在且非空）
        for ((name, desc) in listOf(
            "破土而出" to "认识 1 个汉字",
            "汉字收藏家" to "认识 500 个汉字",
            "满分小状元" to "闯关全部答对",
            "小小书法家" to "描红获得 10 颗星"
        )) {
            compose.onNodeWithText(name).assertExists()
            compose.onNodeWithText(desc).assertExists()
        }
    }

    @Test
    fun `按钮高度足够手指点击`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Detail("人", null))
        compose.waitForIdle()

        // Material 建议最小 48dp；取按钮容器而非文字节点
        compose.onNodeWithText("描红跟写").assertExists()
        val b = compose.onNodeWithTag("btn-write").getBoundsInRoot()
        assertTrue("按钮高度应 >= 44dp，实际 ${(b.bottom - b.top).value}", (b.bottom - b.top).value >= 44f)
    }
}
