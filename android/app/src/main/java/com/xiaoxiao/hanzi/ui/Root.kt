package com.xiaoxiao.hanzi.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.ui.pages.AboutPage
import com.xiaoxiao.hanzi.ui.pages.DetailPage
import com.xiaoxiao.hanzi.ui.pages.IndexPage
import com.xiaoxiao.hanzi.ui.pages.LessonPage
import com.xiaoxiao.hanzi.ui.pages.PracticePage
import com.xiaoxiao.hanzi.ui.pages.ProfilePage
import com.xiaoxiao.hanzi.ui.pages.QuizPage
import com.xiaoxiao.hanzi.ui.pages.ResultPage
import com.xiaoxiao.hanzi.ui.pages.UnitPage
import com.xiaoxiao.hanzi.ui.pages.WritePage
import com.xiaoxiao.hanzi.ui.pages.WrongPage

/**
 * 应用外壳：状态栏 / 顶部返回栏 / 底部 tab / 当前页面。
 *
 * 小程序里页面切换、返回栈、tabBar 都是宿主提供的；Android 侧要自己搭。
 * 关键的三个决定：
 *   1. 用 BackHandler 接管系统返回键 —— 小程序侧「返回按钮不好使」的坑，
 *      在 Android 上等价于「按返回键直接退出 App」，必须显式处理。
 *   2. 只有三个 tab 根页面显示底部导航；详情/答题等全屏页不显示。
 *   3. 顶部返回栏只在非 tab 页出现，避免首页也顶一个返回箭头。
 */
@Composable
fun Root(app: AppState) {
    val p = LocalPalette.current
    val nav = app.nav
    val screen = nav.current

    // 系统返回键：能退就退，退不动就让系统处理（退出 App）
    BackHandler(enabled = nav.canGoBack) { nav.back() }

    Column(
        Modifier
            .fillMaxSize()
            .background(p.paper)
    ) {
        // 状态栏留白
        Spacer(
            Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.statusBars)
                .height(1.dp)
        )

        // 顶部返回栏（非 tab 根页面才显示）
        if (!isTabRoot(screen)) {
            TopBar(title = titleOf(screen), onBack = { nav.back() })
        }

        Box(
            Modifier
                .weight(1f)
                .fillMaxWidth()
        ) {
            when (screen) {
                is Screen.Index -> IndexPage(app)
                is Screen.Practice -> PracticePage(app)
                is Screen.Profile -> ProfilePage(app)
                is Screen.Unit -> UnitPage(app, screen.book)
                is Screen.Lesson -> LessonPage(app, screen.id)
                is Screen.Detail -> DetailPage(app, screen.ch, screen.lesson)
                is Screen.Write -> WritePage(app, screen.ch)
                is Screen.Quiz -> QuizPage(app, screen.mode, screen.book, screen.lesson)
                is Screen.Result -> ResultPage(
                    app, screen.correct, screen.total, screen.wrongChars, screen.mode, screen.book
                )
                is Screen.Wrong -> WrongPage(app)
                is Screen.About -> AboutPage()
            }
        }

        if (isTabRoot(screen)) {
            BottomBar(current = screen, onSelect = { nav.switchTab(it) })
        }
    }
}

private fun titleOf(screen: Screen): String = when (screen) {
    is Screen.Unit -> "课本目录"
    is Screen.Lesson -> "本课生字"
    is Screen.Detail -> "认识这个字"
    is Screen.Write -> "描红跟写"
    is Screen.Quiz -> "练一练"
    is Screen.Result -> "练习结果"
    is Screen.Wrong -> "错题本"
    is Screen.About -> "关于"
    else -> ""
}

@Composable
private fun TopBar(title: String, onBack: () -> Unit) {
    val p = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(34.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(p.card)
                .clickable(onClick = onBack),
            contentAlignment = Alignment.Center
        ) {
            Text("‹", fontSize = 22.sp, color = p.ink1, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.width(10.dp))
        Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = p.ink1)
    }
}

@Composable
private fun BottomBar(current: Screen, onSelect: (Screen) -> Unit) {
    val p = LocalPalette.current
    Surface(color = p.card, shadowElevation = 10.dp) {
        Row(
            Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(vertical = 6.dp)
        ) {
            TabItem("🏠", "首页", current is Screen.Index, Modifier.weight(1f)) {
                onSelect(Screen.Index)
            }
            TabItem("✏️", "练习", current is Screen.Practice, Modifier.weight(1f)) {
                onSelect(Screen.Practice)
            }
            TabItem("🐣", "我的", current is Screen.Profile, Modifier.weight(1f)) {
                onSelect(Screen.Profile)
            }
        }
    }
}

@Composable
private fun TabItem(
    emoji: String,
    label: String,
    on: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    Column(
        modifier
            .clickable(onClick = onClick)
            .padding(vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(emoji, fontSize = 19.sp)
        Spacer(Modifier.height(2.dp))
        Text(
            label,
            fontSize = 10.sp,
            color = if (on) p.jade else p.ink3,
            fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal
        )
    }
}
