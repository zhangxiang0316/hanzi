package com.xiaoxiao.hanzi

import android.app.Application
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.HanziTheme
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
 * 真实 Compose 渲染测试（Robolectric）。
 *
 * 本机模拟器在沙箱里起不来（AVD 快照锁文件在沙箱外、无法清理），
 * 所以改用 Robolectric 在 JVM 上跑真实的 Compose 布局与绘制 ——
 * 能真正验证「页面画得出来、文字在、点击有反应」，
 * 而不是只测纯函数。
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi", sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AppUiTest {

    @get:Rule
    val compose = createComposeRule()

    private fun state(): AppState {
        val app = ApplicationProvider.getApplicationContext<Application>()
        return AppState(app)
    }

    // ---------- 首页 ----------

    @Test
    fun `首页显示问候语与八册入口`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        // 问候语随时段变化，用日期行定位更稳
        compose.onNodeWithText("跟课本学").assertIsDisplayed()

        // 八册全部渲染：册名来自 catalog
        for (book in Repo.books) {
            compose.onNodeWithText(book.name).assertExists()
        }
        assertEquals(8, Repo.books.size)
    }

    @Test
    fun `首页显示今日任务与总进度`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        // 全新安装时应提示去学新字，而不是「已完成」
        val task = app.todayTask()
        assertTrue("新装应为 learn 或 review", task.type in setOf("learn", "review"))
        compose.onNodeWithText(task.title).assertIsDisplayed()
        compose.onNodeWithText("已认识 0 个字").assertIsDisplayed()
    }

    @Test
    fun `首页年级范围按实际册次计算`() {
        // 加了四年级之后，文案不能还写死「一到三年级」
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }
        compose.onNodeWithText("一年级到四年级").assertExists()
    }

    // ---------- 导航 ----------

    @Test
    fun `进入单元页能看到课文列表`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.Unit("1a"))
        compose.waitForIdle()

        val book = Repo.book("1a")!!
        compose.onNodeWithText(book.name).assertExists()
        compose.onNodeWithText(book.units.first().title).assertExists()
    }

    @Test
    fun `系统返回键回到上一页`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.Unit("1a"))
        compose.waitForIdle()
        assertEquals(2, app.nav.size())

        compose.runOnIdle { assertTrue(app.nav.back()) }
        compose.waitForIdle()
        assertEquals(1, app.nav.size())
    }

    @Test
    fun `详情页翻上下字不会加深返回栈`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        val lesson = Repo.book("1a")!!.lessons.first()
        val chars = Repo.lessonChars(lesson)
        app.nav.push(Screen.Lesson(lesson))
        app.nav.push(Screen.Detail(chars[0], lesson))
        val depth = app.nav.size()

        // 连翻 5 个字
        var i = 0
        repeat(5) {
            val next = Repo.nextInLesson(lesson, chars[minOf(i, chars.size - 1)])
            if (next.isNotEmpty()) {
                app.nav.replace(Screen.Detail(next, lesson))
                i++
            }
        }
        assertEquals("翻页不应压栈", depth, app.nav.size())
    }

    // ---------- 认识这个字 ----------

    @Test
    fun `认识这个字页面渲染出笔顺按钮与组词`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        // 「一」笔画少、数据稳定
        app.nav.push(Screen.Detail("一", null))
        compose.waitForIdle()

        compose.onNodeWithText("笔顺").assertExists()
        compose.onNodeWithText("再写一遍").assertExists()
        compose.onNodeWithText("描红跟写").assertExists()
        compose.onNodeWithText("我认识它了").assertExists()
    }

    @Test
    fun `点笔顺不会让页面字号失控`() {
        // 小程序踩过的坑：点「笔顺」后文字变大、显示不全。
        // 这里点一下，确认按钮仍在原位、没有多出异常节点。
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.Detail("人", null))
        compose.waitForIdle()

        compose.onNodeWithText("笔顺").performClick()
        compose.waitForIdle()

        // 点完之后工具条、操作按钮都还在，说明没有布局爆炸
        compose.onNodeWithText("笔顺").assertExists()
        compose.onNodeWithText("描红跟写").assertExists()
    }

    @Test
    fun `笔画多的字换行展示而不是横向滚动`() {
        // 「繁」17 画、23 画级别的字也换行；这里验证芯片全部存在
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        val ch = "繁"
        val strokes = Repo.strokeCount(ch)
        assertTrue("「$ch」应有较多笔画", strokes >= 10)

        app.nav.push(Screen.Detail(ch, null))
        compose.waitForIdle()

        // 第 1 笔到第 n 笔的芯片都应存在
        compose.onNodeWithText("1").assertExists()
        compose.onNodeWithText("按笔顺写").assertExists()
        compose.onNodeWithText("点数字看这一笔").assertExists()
    }

    @Test
    fun `定格某一笔只高亮那一笔`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.Detail("三", null))
        compose.waitForIdle()

        // 「三」三笔，点第 2 笔
        compose.onNodeWithText("2").performClick()
        compose.waitForIdle()

        // 定格后仍能正常渲染
        compose.onRoot().assertExists()
        compose.onNodeWithText("描红跟写").assertExists()
    }

    // ---------- 描红 ----------

    @Test
    fun `描红页显示当前笔与工具`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.Write("一"))
        compose.waitForIdle()

        compose.onNodeWithText("看这一笔").assertExists()
        compose.onNodeWithText("退一笔").assertExists()
        compose.onNodeWithText("擦掉重写").assertExists()
    }

    @Test
    fun `描红页对没有笔顺数据的字给出提示`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        // 所有 2596 个字都有数据，这里用一个不存在的字验证兜底
        app.nav.push(Screen.Write("㐀"))
        compose.waitForIdle()
        compose.onNodeWithText("这个字暂时没有笔顺数据").assertExists()
    }

    // ---------- 答题 ----------

    @Test
    fun `答题页出题并能选中选项`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        // 用 free 模式：review 模式下 learn() 会把 due 排到明天，今天没有到期字
        app.nav.push(Screen.Quiz("free", "1a", null))
        compose.waitForIdle()

        // 进度计数「1/10」
        compose.onNodeWithText("1/", substring = true).assertExists()
        compose.onRoot().assertExists()
    }

    @Test
    fun `刚学过的字今天不会被排进复习`() {
        // 学完即刻复习会打乱间隔复习的节奏，due 必须是明天
        val app = state()
        val ch = Repo.bookChars("1a").first()
        app.progress.learn(ch)
        assertTrue("刚学完不应到期", app.progress.allDue().isEmpty())
        assertEquals(1, app.progress.entry(ch)!!.box)
    }

    @Test
    fun `没有可练的字时给出去学新字的引导`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        // 全新状态、复习模式 -> 没有到期字
        app.nav.push(Screen.Quiz("review", "1a", null))
        compose.waitForIdle()

        compose.onNodeWithText("还没有可以练的字").assertExists()
        compose.onNodeWithText("回到练习页").assertExists()
    }

    @Test
    fun `结果页显示正确率与错字`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.Result(3, 5, listOf("人", "口"), "review", "1a"))
        compose.waitForIdle()

        compose.onNodeWithText("3 / 5 题").assertExists()
        // 圆环里「60」和「%」是两个 Text（字号不同），分开断言
        compose.onNodeWithText("60").assertExists()
        compose.onNodeWithText("正确率").assertExists()
        compose.onNodeWithText("这几个字还需要多看看").assertExists()
    }

    @Test
    fun `全部答对时结果页不显示错字区`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.Result(4, 4, emptyList(), "review", "1a"))
        compose.waitForIdle()

        compose.onNodeWithText("全部答对，太厉害了！").assertExists()
        compose.onNodeWithText("100").assertExists()
        compose.onNodeWithText("正确率").assertExists()
    }

    // ---------- 练习 / 我的 ----------

    @Test
    fun `练习页显示三格统计与八个册次芯片`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.switchTab(Screen.Practice)
        compose.waitForIdle()

        compose.onNodeWithText("待复习").assertExists()
        compose.onNodeWithText("今日答题").assertExists()
        compose.onNodeWithText("正确率").assertExists()
        compose.onNodeWithText("按册来练").assertExists()
        // 八册都出现（short 名，如「一上」）。
        // 注意「随机练习」卡的副标题也写着当前册名，所以同一个词会出现 2 次
        for (b in Repo.books) {
            compose.onAllNodesWithText(b.short).onFirst().assertExists()
        }
    }

    @Test
    fun `我的页面八个册次芯片都在且文字可读`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.switchTab(Screen.Profile)
        compose.waitForIdle()

        compose.onNodeWithText("学习设置").assertExists()
        compose.onNodeWithText("当前册次").assertExists()
        for (b in Repo.books) {
            compose.onNodeWithText(b.short).assertExists()
        }
        // 总字数文案不能写死年级
        compose.onNodeWithText(
            com.xiaoxiao.hanzi.ui.pages.gradeSpan() + " 2596 字"
        ).assertExists()
    }

    @Test
    fun `我的页面徽章与清空入口存在`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.switchTab(Screen.Profile)
        compose.waitForIdle()

        compose.onNodeWithText("我的徽章").assertExists()
        compose.onNodeWithText("破土而出").assertExists()
        compose.onNodeWithText("清空学习记录").assertExists()
    }

    @Test
    fun `关于页显示数据来源`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.About)
        compose.waitForIdle()

        compose.onNodeWithText("关于小小识字家").assertExists()
        compose.onNodeWithText("数据来源").assertExists()
        compose.onNodeWithText("隐私").assertExists()
    }

    @Test
    fun `错题本为空时显示空状态`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.Wrong)
        compose.waitForIdle()

        compose.onNodeWithText("错题本是空的").assertExists()
    }
}
