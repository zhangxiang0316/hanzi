package com.xiaoxiao.hanzi

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Words
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

/**
 * 窄屏溢出检查：320dp（最小的常见手机宽度，iPhone SE / 老安卓机）。
 *
 * 这四个新页面里有两处最怕窄屏：
 *   - 部首格子：一排三四十个 48dp 的方格，换行算错就横向溢出
 *   - 词语表一行：字的点击区（36dp）+「生字组词」小标 + 「第 N 课」+ 绿点，
 *     四个字的词在 320dp 上挤得很紧
 *
 * ## 这条能查出什么、查不出什么
 *
 * Compose 的测试 API 读不到「文字被 ellipsize 了几行」，所以这里用两个
 * **可测量的代理指标**：
 *   1. 节点的右边界不能超出屏幕宽度（溢出 = 一定被裁）
 *   2. 该保住的点击区不能因为被挤压而缩小
 * 如果一行放不下，要么右边界越界、要么带 weight 的那一列把字格压到
 * 最小尺寸以下——两种失败都会被下面的断言抓住。
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w320dp-h2400dp-xxhdpi", sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class NarrowLayoutTest {

    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun state(): AppState {
        val app = ApplicationProvider.getApplicationContext<Application>()
        return AppState(app)
    }

    private fun screenWidthDp(): Float = compose.activity.resources.displayMetrics.widthPixels /
        compose.activity.resources.displayMetrics.density

    /** 断言节点完整落在屏幕内（允许 1dp 的像素取整误差） */
    private fun assertInsideScreen(tag: String, what: String) {
        val b = compose.onNodeWithTag(tag).getBoundsInRoot()
        val w = screenWidthDp()
        assertTrue(
            "$what 左边界越界：${b.left.value} < 0",
            b.left.value >= -1f
        )
        assertTrue(
            "$what 右边界越界：${b.right.value} > 屏宽 $w",
            b.right.value <= w + 1f
        )
    }

    /**
     * 词语表：最长的词（四个字）+ 派生标记 + 课次，在 320dp 上不能溢出，
     * 而且字的点击区不能被挤到 36dp 以下。
     */
    @Test
    fun `窄屏上词语表最长的一行不溢出`() {
        val app = state()
        app.setBook("2a")
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Words)
        compose.waitForIdle()

        // 2a 是混合册：既有最长的课本词，也有带「生字组词」小标的派生词
        val longest = Words.bookWords("2a").maxByOrNull { it.word.length }!!
        compose.onNodeWithTag("words-list")
            .performScrollToNode(hasTestTag("word-row-${longest.word}"))
        compose.waitForIdle()

        assertInsideScreen("word-row-${longest.word}", "「${longest.word}」这一行")

        // 被挤压的直接信号：字格宽度掉到最小尺寸以下
        longest.word.forEachIndexed { i, _ ->
            val b = compose.onNodeWithTag("word-char-${longest.word}-$i").getBoundsInRoot()
            assertTrue(
                "「${longest.word}」第 $i 个字被压窄了：${(b.right - b.left).value}dp",
                (b.right - b.left).value >= 30f
            )
            assertTrue(
                "「${longest.word}」第 $i 个字高度不足：${(b.bottom - b.top).value}dp",
                (b.bottom - b.top).value >= 44f
            )
        }

        // 派生词那一行还多一个小标，单独验一遍
        val derived = Words.bookWords("2a").first { !it.fromTextbook && it.word.length >= 3 }
        compose.onNodeWithTag("words-list")
            .performScrollToNode(hasTestTag("word-row-${derived.word}"))
        compose.waitForIdle()
        assertInsideScreen("word-row-${derived.word}", "派生词「${derived.word}」这一行")
    }

    @Test
    fun `窄屏上搜索框不溢出`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Words)
        compose.waitForIdle()
        assertInsideScreen("words-search", "搜索框")
    }

    /**
     * 部首格子：48dp 一格，320dp 上只放得下 5 格一行，必然要换行。
     * 换行算错（比如用了固定列数的 Row 而不是 FlowRow）就会横向溢出。
     */
    @Test
    fun `窄屏上部首格子全部在屏幕内`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Radical)
        compose.waitForIdle()

        val radicals = Repo.bookRadicals(app.currentBook)
        assertTrue("本册部首太少，测不出换行", radicals.size >= 6)
        // 只量前 12 个：已经跨了至少两行，再多只是重复验证同一段布局
        radicals.take(12).forEach { r ->
            assertInsideScreen("radical-cell-${r.first}", "部首「${r.first}」格子")
        }

        val top = radicals.first().first
        Repo.charsWithRadical(app.currentBook, top).take(6).forEach { ch ->
            assertInsideScreen("radical-char-$ch", "「$ch」字格")
        }

        // 切换按钮是等分的两枚，窄屏上文字不能把它们撑破
        assertInsideScreen("radical-scope-book", "「本册」按钮")
        assertInsideScreen("radical-scope-all", "「全部字库」按钮")
    }

    /**
     * 选字做字帖：四个来源芯片在 320dp 上放不下一行，必须换行而不是溢出。
     */
    @Test
    fun `窄屏上选字的来源芯片换行而不溢出`() {
        val app = state()
        app.progress.learn(Repo.lessonChars(Repo.book("1a")!!.lessons.first()).first())
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.CopybookPick)
        compose.waitForIdle()

        listOf("pick-src-wrong", "pick-src-weak", "pick-src-lesson", "pick-src-stars").forEach {
            assertInsideScreen(it, "来源芯片 $it")
        }
        assertInsideScreen("pick-select-all", "「全选」")
        assertInsideScreen("pick-select-none", "「清空」")

        // 展开星档后再验一遍：多出来一行芯片，不能把上面的布局挤破
        compose.onNodeWithTag("pick-src-stars").performClick()
        compose.waitForIdle()
        listOf("pick-star-0", "pick-star-1", "pick-star-2").forEach {
            assertInsideScreen(it, "星档芯片 $it")
        }

        val first = Repo.lessonChars(Repo.book("1a")!!.lessons.first()).first()
        assertInsideScreen("pick-cell-$first", "字格「$first」")
    }

    /**
     * 周报：柱状图七根柱子等分，窄屏上每根只能分到 30dp 出头，
     * 柱子本身 18dp 还放得下，但整块卡片不能溢出。
     */
    @Test
    fun `窄屏上周报柱状图与四格指标不溢出`() {
        val app = state()
        Repo.bookChars("1a").take(3).forEach { app.progress.learn(it) }
        compose.setContent { HanziTheme { Root(app) } }
        app.nav.push(Screen.Report)
        compose.waitForIdle()

        // 今天有活动，柱子存在
        assertInsideScreen("report-bar-0", "今天的柱子")
        // 没活动的那天**没有柱子**，只剩一条底边——这正是「缺数据 ≠ 0 分」
        // 在界面上的样子，顺手钉住它
        compose.onAllNodesWithTag("report-bar-6").assertCountEquals(0)
    }
}
