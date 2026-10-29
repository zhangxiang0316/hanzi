package com.xiaoxiao.hanzi.ui.pages

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.HanziCard
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.ProgressBar
import com.xiaoxiao.hanzi.ui.Screen
import com.xiaoxiao.hanzi.ui.SectionHead

/**
 * 我的：概览 / 总进度 / 徽章 / 设置 / 入口列表。
 * 对应小程序 pages/profile/profile。
 */
@Composable
fun ProfilePage(app: AppState) {
    val p = LocalPalette.current
    val scroll = rememberScrollState()
    app.revision

    var showReset by remember { mutableStateOf(false) }

    val learned = app.progress.totalLearned()
    val mastered = app.progress.totalMastered()
    val stars = app.progress.writeStarsTotal()
    val activeDays = app.progress.activeDays()
    val streak = app.progress.getStreak()
    val total = Repo.allChars.size
    val pct = if (total > 0) Math.round(learned * 100f / total) else 0
    val badges = app.progress.badges()
    val gotCount = badges.count { it.got }
    val dailyNew = app.progress.settings.dailyNew
    val rest = (total - learned).coerceAtLeast(0)
    val daysNeeded = if (dailyNew > 0) Math.ceil(rest.toDouble() / dailyNew).toInt() else 0

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(scroll)
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        Spacer(Modifier.height(12.dp))

        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(56.dp)
                    .clip(CircleShape)
                    .background(p.amberSoft),
                contentAlignment = Alignment.Center
            ) { Text("🐣", fontSize = 28.sp) }
            Spacer(Modifier.width(12.dp))
            Column {
                Text("小小识字家", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = p.ink1)
                Spacer(Modifier.height(3.dp))
                Text(
                    "已学习 $activeDays 天 · 连续 $streak 天",
                    fontSize = 12.sp,
                    color = p.ink3
                )
            }
        }

        Spacer(Modifier.height(16.dp))

        HanziCard(padding = 14) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                OvCell("$learned", "学过的字", Modifier.weight(1f))
                Box(Modifier.width(1.dp).height(30.dp).background(p.line))
                OvCell("$mastered", "已掌握", Modifier.weight(1f))
                Box(Modifier.width(1.dp).height(30.dp).background(p.line))
                OvCell("$stars", "描红星", Modifier.weight(1f))
            }
        }

        Spacer(Modifier.height(12.dp))

        HanziCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                // 年级范围按实际册次算，加年级后文案自动跟着变
                Text(
                    gradeSpan() + " $total 字",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = p.ink1,
                    modifier = Modifier.weight(1f)
                )
                Text("$pct%", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = p.jade)
            }
            Spacer(Modifier.height(9.dp))
            ProgressBar(pct)
            Spacer(Modifier.height(8.dp))
            Text(
                "每天 $dailyNew 个字，坚持 $daysNeeded 天就能全部学完",
                fontSize = 11.sp,
                color = p.ink3
            )
        }

        SectionHead("我的徽章", "$gotCount/${badges.size}")
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            badges.chunked(2).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { b ->
                        Surface(
                            Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(Dimens.radiusInner.dp)),
                            shape = RoundedCornerShape(Dimens.radiusInner.dp),
                            color = if (b.got) p.jadeSoft else p.card,
                            border = BorderStroke(
                                1.dp,
                                if (b.got) p.jade.copy(alpha = 0.4f) else p.line
                            )
                        ) {
                            Column(
                                Modifier.padding(11.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Text(if (b.got) b.emoji else "🔒", fontSize = 22.sp)
                                Spacer(Modifier.height(5.dp))
                                Text(
                                    b.name,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = if (b.got) p.ink1 else p.ink3,
                                    textAlign = TextAlign.Center
                                )
                                Spacer(Modifier.height(2.dp))
                                Text(
                                    b.desc,
                                    fontSize = 10.sp,
                                    color = p.ink3,
                                    textAlign = TextAlign.Center
                                )
                            }
                        }
                    }
                    if (row.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }

        SectionHead("学习设置")
        Surface(
            Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(Dimens.radiusCard.dp),
            color = p.card,
            border = BorderStroke(1.dp, p.line)
        ) {
            Column(Modifier.padding(14.dp)) {
                // 每天新学
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("每天新学", fontSize = 14.sp, color = p.ink1, modifier = Modifier.width(88.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf(3, 5, 8, 10).forEach { n ->
                            SegItem("$n 字", n == dailyNew, Modifier.weight(1f), "profile-daily-$n") {
                                app.setDailyNew(n)
                            }
                        }
                    }
                }

                Spacer(Modifier.height(14.dp))

                // 当前册次：标签单独一行，8 个芯片 4 列 2 行。
                // 小程序里这块原来只有一个 setting 行内布局，换行后芯片被压成
                // 「文字居左上」的怪样子，且圆角 999rpx 在 2 行时半径超过高度。
                Text("当前册次", fontSize = 14.sp, color = p.ink1)
                Spacer(Modifier.height(8.dp))
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(p.lineSoft)
                        .padding(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Repo.books.chunked(4).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            row.forEach { book ->
                                SegItem(
                                    book.short,
                                    book.id == app.currentBook,
                                    Modifier.weight(1f),
                                    "profile-book-${book.id}"
                                ) {
                                    app.setBook(book.id)
                                }
                            }
                            repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }

                Spacer(Modifier.height(14.dp))

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("显示组词拼音", fontSize = 14.sp, color = p.ink1, modifier = Modifier.weight(1f))
                    Switch(
                        checked = app.progress.settings.showPinyin,
                        onCheckedChange = { app.setShowPinyin(it) },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Color.White,
                            checkedTrackColor = p.jade
                        )
                    )
                }
            }
        }

        SectionHead("更多")
        Surface(
            Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(Dimens.radiusCard.dp),
            color = p.card,
            border = BorderStroke(1.dp, p.line)
        ) {
            Column {
                LinkRow("错题本", "${app.progress.wrongCount()} 个字 ›") {
                    app.nav.push(Screen.Wrong)
                }
                Box(Modifier.fillMaxWidth().height(1.dp).background(p.lineSoft))
                LinkRow("关于与数据来源", "›") { app.nav.push(Screen.About) }
                Box(Modifier.fillMaxWidth().height(1.dp).background(p.lineSoft))
                LinkRow("清空学习记录", "›", danger = true) { showReset = true }
            }
        }

        Spacer(Modifier.height(22.dp))
        Text(
            "小小识字家 v1.0.0 · 内容仅供学习使用",
            fontSize = 11.sp,
            color = p.ink3,
            modifier = Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(24.dp))
    }

    if (showReset) {
        AlertDialog(
            onDismissRequest = { showReset = false },
            title = { Text("清空学习记录？") },
            text = { Text("所有识字进度、错题、描红成绩都会被删除，且无法恢复。") },
            confirmButton = {
                TextButton(onClick = {
                    app.resetAll()
                    showReset = false
                }) { Text("确认清空", color = p.clay) }
            },
            dismissButton = {
                TextButton(onClick = { showReset = false }) { Text("取消") }
            }
        )
    }
}

@Composable
private fun OvCell(num: String, label: String, modifier: Modifier = Modifier) {
    val p = LocalPalette.current
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(num, fontSize = 21.sp, fontWeight = FontWeight.Bold, color = p.ink1)
        Spacer(Modifier.height(2.dp))
        Text(label, fontSize = 11.sp, color = p.ink3)
    }
}

/**
 * 分段选择项。
 *
 * 小程序侧这块踩过两个坑：文字居左上（.empty 类名冲突）、多行时圆角过大。
 * 这里用 Box + contentAlignment=Center 保证文字永远居中，圆角固定 10dp。
 */
@Composable
private fun SegItem(
    text: String,
    on: Boolean,
    modifier: Modifier = Modifier,
    tag: String? = null,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    Box(
        modifier
            .then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .clip(RoundedCornerShape(10.dp))
            .background(if (on) p.jade else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text,
            fontSize = 12.sp,
            fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal,
            color = if (on) Color.White else p.ink2,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun LinkRow(
    name: String,
    value: String,
    danger: Boolean = false,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            name,
            fontSize = 14.sp,
            color = if (danger) p.clay else p.ink1,
            modifier = Modifier.weight(1f)
        )
        Text(value, fontSize = 13.sp, color = p.ink3)
    }
}
