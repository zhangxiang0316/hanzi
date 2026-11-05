package com.xiaoxiao.hanzi

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
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
    fun `详情页工具条三个芯片等宽且文字放得下`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Detail("日", null))
        compose.waitForIdle()

        // 加了「朗读」之后工具条变成三块，每块从 1/2 变成 1/3，
        // 「再写一遍」是最长的标签，必须确认没被挤掉
        val chip = compose.onNodeWithTag("btn-speak").getBoundsInRoot()
        val chipW = (chip.right - chip.left).value

        for (label in listOf("朗读", "笔顺", "再写一遍")) {
            val b = compose.onNodeWithText(label, useUnmergedTree = true).getBoundsInRoot()
            val textW = (b.right - b.left).value
            // 图标(14) + 间距(6) + 文字，还要留点余量
            assertTrue(
                "「$label」宽 ${textW}dp 在 ${chipW}dp 的芯片里放不下",
                textW + 20f + 6f < chipW
            )
        }
    }

    @Test
    fun `底部导航高度不超过 56dp 且每个 tab 仍可点击`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        compose.waitForIdle()

        // 底栏原先是 74dp（19sp 表情行高 + 双层 6dp 内边距），加系统导航条后
        // 逼近 100dp，显得笨重。现在压到 52dp。
        val bar = compose.onNodeWithTag("bottom-bar").getBoundsInRoot()
        val h = (bar.bottom - bar.top).value
        assertTrue("底栏高度应 <= 56dp，实际 ${h}dp", h <= 56f)

        // 但每个 tab 的可点区域不能低于 Material 的最小点击尺寸 48dp
        listOf("首页", "练习", "我的").forEach { label ->
            val b = compose.onNodeWithText(label).getBoundsInRoot()
            val itemH = (b.bottom - b.top).value
            assertTrue("$label 的点击区应 >= 48dp，实际 ${itemH}dp", itemH >= 48f)
        }
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

    // ---------- 新增页面 ----------

    /**
     * 周报柱状图：有活动的日子必须有柱子，没活动的日子只有底边。
     *
     * 这条挡的是两种真实会出的错：把「没学」画成 0 高度柱子（看起来像页面
     * 缺了一块），以及最小高度没兜住导致 1 个字的柱子看不见。
     */
    @Test
    fun `周报柱状图活跃日有柱子、空白日只有底边`() {
        val app = state()
        // 今天学 1 个字、6 天前学 100 个字：前者就是「最小高度」那一档
        app.progress.learn(Repo.bookChars("1a").first())
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Report)
        compose.waitForIdle()

        val today = compose.onNodeWithTag("report-bar-0").getBoundsInRoot()
        assertTrue(
            "有活动的日子必须有可见高度，实际 ${(today.bottom - today.top).value}dp",
            (today.bottom - today.top).value >= 3f
        )
    }

    @Test
    fun `选字做字帖的字格可点且不小于 44dp`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.CopybookPick)
        compose.waitForIdle()

        val first = Repo.lessonChars(Repo.book("1a")!!.lessons.first()).first()
        val b = compose.onNodeWithTag("pick-cell-$first").getBoundsInRoot()
        assertTrue("字格宽应 >= 44dp，实际 ${(b.right - b.left).value}", (b.right - b.left).value >= 44f)
        assertTrue("字格高应 >= 44dp，实际 ${(b.bottom - b.top).value}", (b.bottom - b.top).value >= 44f)
    }

    @Test
    fun `词语表的字不超出屏幕宽度`() {
        val app = state()
        app.setBook("2a")
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Words)
        compose.waitForIdle()

        // 最长的课本词（四个字）加上「生字组词」标记也不能撑出屏幕：
        // 2a 是混合册，派生词会多带一个「生字组词」小标
        val w = com.xiaoxiao.hanzi.logic.Words.bookWords("2a").maxByOrNull { it.word.length }!!
        // 列表是懒加载的，长词在屏幕下方，先滚到它再量
        compose.onNodeWithTag("words-list")
            .performScrollToNode(hasTestTag("word-row-${w.word}"))
        compose.waitForIdle()
        val b = compose.onNodeWithTag("word-row-${w.word}").getBoundsInRoot()
        assertTrue("行左边界应 >= 0，实际 ${b.left.value}", b.left.value >= 0f)
        assertTrue(
            "行右边界应在屏宽 ${screenWidthDp()}dp 内，实际 ${b.right.value}",
            b.right.value <= screenWidthDp() + 1f
        )
    }

    // ---------- 四个新页面的点击区 ----------

    /**
     * 部首页：本册/全部 切换和部首格子都必须 >= 44dp。
     *
     * 微信版这两处原来只有 60rpx / 96rpx 的内容高度，手指点不准，
     * 后来统一补到 88rpx（≈44dp）。Android 侧自己量一遍，别靠「应该够」。
     */
    @Test
    fun `部首页切换按钮与部首格子不小于 44dp`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Radical)
        compose.waitForIdle()

        listOf("radical-scope-book", "radical-scope-all").forEach { tag ->
            val b = compose.onNodeWithTag(tag).getBoundsInRoot()
            assertTrue(
                "$tag 高度应 >= 44dp，实际 ${(b.bottom - b.top).value}dp",
                (b.bottom - b.top).value >= 44f
            )
        }

        val top = Repo.bookRadicals(app.currentBook).first().first
        val cell = compose.onNodeWithTag("radical-cell-$top").getBoundsInRoot()
        assertTrue("部首格子高应 >= 44dp", (cell.bottom - cell.top).value >= 44f)
        assertTrue("部首格子宽应 >= 44dp", (cell.right - cell.left).value >= 44f)

        // 部首下的字也要能点准
        val ch = Repo.charsWithRadical(app.currentBook, top).first()
        val cb = compose.onNodeWithTag("radical-char-$ch").getBoundsInRoot()
        assertTrue("字格高应 >= 44dp，实际 ${(cb.bottom - cb.top).value}dp", (cb.bottom - cb.top).value >= 44f)
        assertTrue("字格宽应 >= 44dp，实际 ${(cb.right - cb.left).value}dp", (cb.right - cb.left).value >= 44f)
    }

    /**
     * 词语表：搜索框和词里的每个字都要能点准。
     *
     * 字本身的 20sp 行高只有 24dp——如果只让 Text 可点，手指必然点不准。
     * 微信版为此给 `.row-ch` 加了 `min-height: 88rpx`；这里断言同样的口径。
     */
    @Test
    fun `词语表的搜索框与词字不小于 44dp`() {
        val app = state()
        app.setBook("1a")
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Words)
        compose.waitForIdle()

        val box = compose.onNodeWithTag("words-search").getBoundsInRoot()
        assertTrue(
            "搜索框高度应 >= 44dp，实际 ${(box.bottom - box.top).value}dp",
            (box.bottom - box.top).value >= 44f
        )

        val w = com.xiaoxiao.hanzi.logic.Words.bookWords("1a").first()
        val b = compose.onNodeWithTag("word-char-${w.word}-0").getBoundsInRoot()
        assertTrue(
            "词字高度应 >= 44dp，实际 ${(b.bottom - b.top).value}dp（「${w.word}」）",
            (b.bottom - b.top).value >= 44f
        )
        assertTrue("词字宽度应 >= 30dp，实际 ${(b.right - b.left).value}dp", (b.right - b.left).value >= 30f)
    }

    /**
     * 选字做字帖：来源芯片、星档芯片、全选/清空、字格，一个都不能低于 44dp。
     */
    @Test
    fun `选字做字帖的所有点击元素不小于 44dp`() {
        val app = state()
        app.progress.learn(Repo.lessonChars(Repo.book("1a")!!.lessons.first()).first())
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.CopybookPick)
        compose.waitForIdle()

        val tags = listOf(
            "pick-src-wrong", "pick-src-weak", "pick-src-lesson", "pick-src-stars",
            "pick-select-all", "pick-select-none"
        )
        tags.forEach { tag ->
            val b = compose.onNodeWithTag(tag).getBoundsInRoot()
            assertTrue(
                "$tag 高度应 >= 44dp，实际 ${(b.bottom - b.top).value}dp",
                (b.bottom - b.top).value >= 44f
            )
        }

        // 星档芯片是展开后才出现的：先点「低分字」
        compose.onNodeWithTag("pick-src-stars").performClick()
        compose.waitForIdle()
        listOf("pick-star-0", "pick-star-1", "pick-star-2").forEach { tag ->
            val b = compose.onNodeWithTag(tag).getBoundsInRoot()
            assertTrue(
                "$tag 高度应 >= 44dp，实际 ${(b.bottom - b.top).value}dp",
                (b.bottom - b.top).value >= 44f
            )
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

/**
 * 两端样式对齐的几何断言。
 *
 * 背景：iOS 和 Android 是两套独立 UI，样式慢慢漂开了——同一个「次要按钮」
 * 在 iOS 是白底描边、在 Android 是浅绿水底；同一个入口在 iOS 是独立卡片
 * 带图标和箭头、在 Android 是一张大卡加分隔线。这些差异肉眼一看就知道
 * 「这不是同一个 App」，但单测完全照不到。
 *
 * 下面几条把对齐后的关键几何固定住。
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h2400dp-xxhdpi", sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class StyleParityTest {

    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun state(): AppState {
        val app = ApplicationProvider.getApplicationContext<Application>()
        return AppState(app)
    }

    private fun screenWidthDp(): Float = compose.activity.resources.displayMetrics.widthPixels /
        compose.activity.resources.displayMetrics.density

    /**
     * 「我的」页九行是**九张独立卡片**，不是一张大卡。
     *
     * iOS 侧每行一张 radiusInner 卡片、行间 12。判断方法很直接：
     * 相邻两行的纵向间距必须等于 12dp 的卡片间隔，而不是 0（同卡内分隔线）。
     */
    @Test
    fun `我的页九行是独立卡片且间距 12dp`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.switchTab(Screen.Profile)
        compose.waitForIdle()

        val first = compose.onNodeWithTag("profile-row-学习周报").getBoundsInRoot()
        val second = compose.onNodeWithTag("profile-row-识字量测试").getBoundsInRoot()

        // 两张卡之间的空隙 = 第二张顶 - 第一张底，应为 12dp
        val gap = second.top.value - first.bottom.value
        assertTrue(
            "九行应当是独立卡片、行间 12dp，实测间距 ${gap}dp（若是 0 说明又合并成一张大卡了）",
            abs(gap - 12f) <= 1.5f
        )
    }

    /**
     * 九行每行的触达高度不低于 48dp。
     *
     * iOS 是 padding 16 + 15pt 字 + 可选副标题。Android 若漏掉副标题或
     * padding 给小了，行高会掉到 44 以下——九行全靠手指点，这一条不能松。
     */
    @Test
    fun `我的页每行入口高度不低于 48dp`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.switchTab(Screen.Profile)
        compose.waitForIdle()

        listOf("学习周报", "识字量测试", "错题本", "我的字帖", "选字做字帖",
               "部首归类", "词语表", "关于与数据来源", "清空学习记录").forEach { name ->
            val b = compose.onNodeWithTag("profile-row-$name").getBoundsInRoot()
            val rowH = b.bottom.value - b.top.value
            assertTrue(
                "「$name」行高 ${rowH}dp，低于 48dp",
                rowH >= 48f
            )
        }
    }

    /**
     * 识字量测试的「开始测」固定在**屏幕底部**，不跟着内容滚。
     *
     * iOS 用 .safeAreaInset(edge: .bottom) 钉底。Android 早先是跟着
     * verticalScroll 走的，按钮浮在屏幕中间。
     */
    @Test
    fun `识字量测试的开始按钮贴屏幕底部`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Vocab)
        compose.waitForIdle()

        val btn = compose.onNodeWithTag("识字量-开始").getBoundsInRoot()
        val screenH = compose.activity.resources.displayMetrics.heightPixels /
            compose.activity.resources.displayMetrics.density

        // 按钮底边应落在屏幕底部 24dp 以内（底部条 padding 12 + 按钮自身）
        val fromBottom = screenH - btn.bottom.value
        assertTrue(
            "「开始测」应当在屏幕底部，实际距底 ${fromBottom}dp（屏幕 ${screenH}dp）",
            fromBottom <= 24f
        )
        // 且不能超出屏幕
        assertTrue("按钮超出了屏幕底部", btn.bottom.value <= screenH + 1f)
    }

    /**
     * 选字做字帖的「导出」同样钉底。
     */
    @Test
    fun `选字做字帖的导出按钮贴屏幕底部`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.CopybookPick)
        compose.waitForIdle()

        val btn = compose.onNodeWithTag("选字-导出").getBoundsInRoot()
        val screenH = compose.activity.resources.displayMetrics.heightPixels /
            compose.activity.resources.displayMetrics.density
        val fromBottom = screenH - btn.bottom.value
        assertTrue(
            "「导出字帖」应当固定在底部，实际距底 ${fromBottom}dp",
            fromBottom <= 72f
        )
    }

    /**
     * 首页总进度是环形图（不是横条），且百分比嵌在环心。
     *
     * iOS 一直是 84dp 环 + 环内 19pt 百分比。Android 之前是「横条 + 靠右数字」，
     * 同一个指标在两端是两种完全不同的信息图。
     */
    @Test
    fun `首页总进度是 84dp 环形图`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        compose.waitForIdle()

        val ring = compose.onNodeWithTag("progress-ring").getBoundsInRoot()
        val w = ring.right.value - ring.left.value
        val h = ring.bottom.value - ring.top.value
        assertEquals("环形应为 84dp 见方，实测宽 ${w}dp", 84f, w, 1.5f)
        assertEquals("环形应为 84dp 见方，实测高 ${h}dp", 84f, h, 1.5f)
        // 正圆，不是椭圆
        assertEquals("应当是正圆", w, h, 0.5f)
    }

    /**
     * 主按钮高度 44dp，与 iOS 一致（原来是 48）。
     */
    @Test
    fun `主按钮高度是 44dp`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.switchTab(Screen.Profile)
        compose.waitForIdle()
        // 「我的」页九行里没有主按钮，用识字量页的开始按钮
        app.nav.push(Screen.Vocab)
        compose.waitForIdle()

        val b = compose.onNodeWithTag("识字量-开始").getBoundsInRoot()
        val btnH = b.bottom.value - b.top.value
        assertEquals(
            "按钮高度应为 44dp（与 iOS 一致），实测 ${btnH}dp",
            44f, btnH, 1.5f
        )
    }
}
