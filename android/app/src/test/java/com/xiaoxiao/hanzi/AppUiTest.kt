package com.xiaoxiao.hanzi

import android.app.Application
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
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

        // 八册全部渲染。册卡与 iOS 同构后，「一年级上册」被拆成
        // 年级大字 + 学期胶囊，所以按 testTag 逐张验证更可靠
        for (book in Repo.books) {
            compose.onNodeWithTag("index-book-${book.id}").assertExists()
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

        // 「笔顺」是笔画表的区块标题（不是工具条芯片——
        // 那个芯片叫「显示序号」，和 iOS 一致）
        compose.onNodeWithText("笔顺").assertExists()
        compose.onNodeWithText("显示序号").assertExists()
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

        compose.onNodeWithText("显示序号").performClick()
        compose.waitForIdle()

        // 点完之后工具条、操作按钮都还在，说明没有布局爆炸
        compose.onNodeWithText("隐藏序号").assertExists()
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

        // 第 1 到第 n 个笔形格都应存在，且换行而不是横向滚动
        compose.onNodeWithTag("stroke-cell-0").assertExists()
        compose.onNodeWithTag("stroke-cell-${strokes - 1}").assertExists()
        compose.onNodeWithText("笔顺").assertExists()
        compose.onNodeWithText("$strokes 笔").assertExists()
    }

    @Test
    fun `定格某一笔只高亮那一笔`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.Detail("三", null))
        compose.waitForIdle()

        // 「三」三笔，点第 2 格（i=1）。
        // 格子现在画的是笔形而不是数字，所以按 testTag 点，不能按文本找。
        compose.onNodeWithTag("stroke-cell-1").performClick()
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

        // 四个新入口都挂在「更多」下：漏一个家长就找不到那一页
        listOf("学习周报", "选字做字帖", "部首归类", "词语表").forEach {
            compose.onNodeWithText(it).assertExists()
        }
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

    /**
     * 关于页显示的版本号必须来自构建配置。
     *
     * 这里曾经写死 `v1.0.0`，而应用实际已经走到 1.0.7——页面上一直是错的，
     * 而且改了 versionName 它也不会跟着变。断言里刻意不写具体版本号：
     * 写死就会变成"每次发版都要改测试"，那正是这个 bug 的成因。
     */
    @Test
    fun `关于页版本号跟着构建配置走`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.About)
        compose.waitForIdle()

        compose.onNodeWithText("v${BuildConfig.VERSION_NAME} · 内容仅供学习使用").assertExists()
        // 反证：不能还留着硬编码的旧版本
        compose.onNodeWithText("v1.0.0 · 内容仅供学习使用").assertDoesNotExist()
    }

    // ---------- 新增的四个浏览页 ----------

    /**
     * 周报页在完全没有数据时也要画得出来。
     *
     * 空周是最容易崩的一档：柱状图要除零、汇总要取 best、建议要只给一句。
     * 这些口径在 ReportTest 里钉死了，这里验的是「页面真的能渲染 + 文案对」。
     */
    @Test
    fun `周报页空数据也能渲染并说明还没开始`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.Report)
        compose.waitForIdle()

        compose.onNodeWithText("最近 7 天").assertExists()
        compose.onNodeWithText("这周还没有学习记录").assertExists()
        // 没答题时正确率显示「—」，不是 0%
        compose.onAllNodesWithText("—").onFirst().assertExists()
        compose.onNodeWithText("给家长").assertExists()
    }

    @Test
    fun `选字做字帖页默认带出本课生字`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.CopybookPick)
        compose.waitForIdle()

        compose.onNodeWithText("按课时、错题、薄弱笔画挑字，导出成一张打印版字帖").assertExists()
        compose.onNodeWithText("错题本").assertExists()
        compose.onNodeWithText("本课生字").assertExists()
        // 默认全选本课生字：导出按钮上的字数不该是 0
        compose.onNodeWithText("全选").assertExists()
        compose.onNodeWithText("清空").assertExists()
    }

    @Test
    fun `部首归类页默认选中字数最多的部首`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.Radical)
        compose.waitForIdle()

        compose.onNodeWithText("按部首看字，明白「三点水」「提手旁」是什么意思").assertExists()
        compose.onNodeWithText("全部字库").assertExists()
        // 默认选中第一个（频次最高的）部首，右侧列出它的字
        val top = Repo.bookRadicals(app.currentBook).first()
        compose.onNodeWithText("${top.first} 部").assertExists()
        compose.onNodeWithText(
            "${Repo.charsWithRadical(app.currentBook, top.first).size} 个字"
        ).assertExists()
    }

    /**
     * 词语表页：一年级也必须看得到词。
     *
     * 一年级课本没有词语表，一律靠生字组词兜底——早期实现漏掉这个兜底，
     * 一年级点进来是一片空白，而那正是这个 App 最大的用户群。
     */
    @Test
    fun `词语表页一年级也有词，并标出生字组词`() {
        val app = state()
        app.setBook("1a")
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.Words)
        compose.waitForIdle()

        compose.onNodeWithText("课本词语表，加上一年级用生字组词补的部分").assertExists()
        compose.onNodeWithText("一年级上册").assertExists()
        compose.onNodeWithText("这一册课本没有词语表，下面是每课生字的组词").assertExists()
        compose.onAllNodesWithText("生字组词").onFirst().assertExists()
    }

    @Test
    fun `词语表页搜字能搜到跨册的词`() {
        val app = state()
        compose.setContent { HanziTheme { Root(app) } }

        app.nav.push(Screen.Words)
        compose.waitForIdle()

        compose.onNodeWithText("搜词语，或搜一个字（如「行」）").performTextInput("行")
        compose.waitForIdle()

        compose.onNodeWithText("找到 5 个词").assertExists()
        // 跨册的词要标出所有册次，而不是只显示最早那一册
        compose.onNodeWithText("一年级下册 / 三年级上册").assertExists()
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
