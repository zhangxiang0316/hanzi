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
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Vocab
import androidx.compose.foundation.Canvas
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.HanziCard
import com.xiaoxiao.hanzi.ui.FontSizes
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.NavIcon
import com.xiaoxiao.hanzi.ui.NavIconView
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
    var showAddProfile by remember { mutableStateOf(false) }
    var showRenameProfile by remember { mutableStateOf(false) }
    var showRemoveProfile by remember { mutableStateOf(false) }
    var nameDraft by remember { mutableStateOf("") }

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
                Text(
                    app.profiles.active().name,
                    fontSize = 17.sp, fontWeight = FontWeight.Bold, color = p.ink1
                )
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
        // 4 列 × 2 行，与小程序一致（那边是 width: calc(25% - 16rpx)）。
        // Android 版早先做成 2 列 4 行，单行高度翻倍，整块占了半屏，所以显得过大。
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            badges.chunked(4).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    row.forEach { b ->
                        Surface(
                            Modifier
                                .weight(1f)
                                .testTag("badge-${b.id}")
                                .clip(RoundedCornerShape(11.dp)),
                            shape = RoundedCornerShape(11.dp),
                            // 未解锁用暖灰（对应小程序 .badge 的 #f5f0e5）。
                            // 原来用纯白，和米色纸底只差几阶，卡片缩到 1/4 宽后几乎看不见了。
                            color = if (b.got) p.jadeSoft else p.track,
                            border = BorderStroke(
                                1.dp,
                                if (b.got) p.jade.copy(alpha = 0.4f) else p.line
                            )
                        ) {
                            Column(
                                Modifier.padding(vertical = 7.dp, horizontal = 3.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Text(if (b.got) b.emoji else "🔒", fontSize = 18.sp)
                                Spacer(Modifier.height(3.dp))
                                Text(
                                    b.name,
                                    fontSize = 10.sp,
                                    lineHeight = 12.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = if (b.got) p.ink1 else p.ink3,
                                    textAlign = TextAlign.Center,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Spacer(Modifier.height(1.dp))
                                Text(
                                    b.desc,
                                    fontSize = 8.sp,
                                    lineHeight = 10.sp,
                                    color = p.ink3,
                                    textAlign = TextAlign.Center,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                    // 补齐末行，避免最后一行卡片被拉伸
                    repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }

        SectionHead("孩子", if (app.profiles.count() > 1) "各用各的进度" else "")
        HanziCard(padding = 12) {
            // 最多 4 个档案 + 一个「＋」，一行放得下（每个最宽 88dp）
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                app.profiles.profiles().forEach { pf ->
                    val on = pf.id == app.profiles.activeId()
                    Surface(
                        Modifier
                            .weight(1f, fill = false)
                            .clip(RoundedCornerShape(999.dp))
                            .clickable(enabled = !on) { switchProfile(app, pf.id) },
                        shape = RoundedCornerShape(999.dp),
                        color = if (on) p.jade else p.cardWarm,
                        border = BorderStroke(1.dp, if (on) p.jade else p.line)
                    ) {
                        Text(
                            pf.name,
                            fontSize = 13.sp,
                            fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                            color = if (on) Color.White else p.ink2,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 11.dp)
                        )
                    }
                }
                if (app.profiles.canAdd()) {
                    Surface(
                        Modifier
                            .clip(RoundedCornerShape(999.dp))
                            .clickable { showAddProfile = true },
                        shape = RoundedCornerShape(999.dp),
                        color = p.card,
                        border = BorderStroke(1.dp, p.line)
                    ) {
                        Text(
                            "＋",
                            fontSize = 15.sp,
                            color = p.ink3,
                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp)
                        )
                    }
                }
            }
            if (app.profiles.count() > 1) {
                Spacer(Modifier.height(10.dp))
                Row {
                    Text(
                        "改名",
                        fontSize = 12.sp,
                        color = p.ink2,
                        modifier = Modifier
                            .clickable { showRenameProfile = true }
                            .padding(vertical = 8.dp)
                    )
                    Spacer(Modifier.width(20.dp))
                    Text(
                        "删除这个孩子",
                        fontSize = 12.sp,
                        color = p.clay,
                        modifier = Modifier
                            .clickable { showRemoveProfile = true }
                            .padding(vertical = 8.dp)
                    )
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
        // 九行入口，与 iOS 一致：**每行一张独立卡**（不是一张大卡加分隔线），
        // 每行带图标和 chevron。早先这里是一张圆角 20 的大卡、行间用 1px
        // lineSoft 分隔、没有图标也没有箭头——和 iOS 摆在一起时，
        // 一眼就能看出「这不是同一个 App 的两个版本」。
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            // 周报：首页只看得到「今天」，家长关心的是「这一周」
            LinkRow(
                icon = NavIcon.Chart,
                title = "学习周报",
                subtitle = "最近 7 天",
                value = null
            ) { app.nav.push(Screen.Report) }

            // 识字量测试：「学过多少字」是点过多少个字，不是认识多少，
            // 家长真正想知道的是后者，所以按抽测单独给一个入口。
            LinkRow(
                icon = NavIcon.Ruler,
                title = "识字量测试",
                subtitle = "从八册里抽字估算",
                value = if (app.progress.vocabSize() > 0)
                    "上次 ${Vocab.sizeLabel(app.progress.vocabSize())} 字" else "测一测"
            ) { app.nav.push(Screen.Vocab) }

            LinkRow(
                icon = NavIcon.Bubble,
                title = "错题本",
                subtitle = null,
                value = "${app.progress.wrongCount()} 个字"
            ) { app.nav.push(Screen.Wrong) }

            // 字帖：写出来的字和认得的字是两种能力，值得单独有一个入口。
            // 徽章体系几乎全是「认识 N 个字」，写字这个维度此前只有单字页里的三颗星。
            LinkRow(
                icon = NavIcon.Grid,
                title = "我的字帖",
                subtitle = null,
                value = if (app.progress.writeCount() > 0)
                    "${app.progress.writeCount()} 个字" else "还没写过"
            ) { app.nav.push(Screen.Copybook) }

            // 选字做字帖：「我的字帖」只能导写过的字，而家长想打的是
            // 「这课的生字」「错题」——那是「需要练的」，不是「写过的」
            LinkRow(
                icon = NavIcon.Pencil,
                title = "选字做字帖",
                subtitle = "按课时 / 错题挑字导出",
                value = null
            ) { app.nav.push(Screen.CopybookPick) }

            // 部首与词语：两种「换个角度看字」的浏览方式
            LinkRow(
                icon = NavIcon.Grid3,
                title = "部首归类",
                subtitle = "按部首看字",
                value = null
            ) { app.nav.push(Screen.Radical) }

            LinkRow(
                icon = NavIcon.Book,
                title = "词语表",
                subtitle = "按册翻词语",
                value = null
            ) { app.nav.push(Screen.Words) }

            LinkRow(
                icon = NavIcon.Info,
                title = "关于与数据来源",
                subtitle = null,
                value = null
            ) { app.nav.push(Screen.About) }

            LinkRow(
                icon = NavIcon.Trash,
                title = "清空学习记录",
                subtitle = null,
                value = null,
                danger = true
            ) { showReset = true }
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

    if (showAddProfile) {
        NameDialog(
            title = "添加一个孩子",
            initial = "",
            onDismiss = { showAddProfile = false },
            onConfirm = { name ->
                val pf = app.profiles.add(name)
                showAddProfile = false
                // 新建后直接切过去：家长的意图就是「给这个孩子开始用」
                if (pf != null) switchProfile(app, pf.id)
            }
        )
    }

    if (showRenameProfile) {
        NameDialog(
            title = "改名",
            initial = app.profiles.active().name,
            onDismiss = { showRenameProfile = false },
            onConfirm = { name ->
                // 空名字 rename 会返回 false，此时静默保留原名（对话框已经关了）
                app.profiles.rename(app.profiles.activeId(), name)
                showRenameProfile = false
                app.touch()
            }
        )
    }

    if (showRemoveProfile) {
        val cur = app.profiles.active()
        AlertDialog(
            onDismissRequest = { showRemoveProfile = false },
            title = { Text("删除「${cur.name}」？") },
            text = { Text("这个孩子的学习进度、错题本、描红记录都会一起删掉，不能恢复。") },
            confirmButton = {
                TextButton(onClick = {
                    app.profiles.remove(cur.id)
                    app.progress.reload()
                    app.setBook(Repo.defaultBook())
                    showRemoveProfile = false
                    app.touch()
                }) { Text("删除", color = p.clay) }
            },
            dismissButton = {
                TextButton(onClick = { showRemoveProfile = false }) { Text("取消") }
            }
        )
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

/**
 * 切换孩子。
 *
 * 切完必须 `progress.reload()`——存储的键换了前缀，但 Progress 里那份
 * 内存状态还是上一个孩子的，不重读会显示「名字换了、数据没变」。
 */
private fun switchProfile(app: AppState, id: String) {
    if (!app.profiles.setActive(id)) return
    app.progress.reload()
    // 每个孩子可能读不同册次，册次也跟着重读
    app.setBook(app.progress.settings.book)
    app.touch()
}

/** 输入孩子名字的小对话框 */
@Composable
private fun NameDialog(
    title: String,
    initial: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { if (it.length <= 8) text = it },
                singleLine = true,
                label = { Text("名字（8 字以内）") }
            )
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(text) }) { Text("确定") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        }
    )
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
    icon: NavIcon,
    title: String,
    subtitle: String?,
    value: String?,
    danger: Boolean = false,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    val tint = if (danger) p.clay else p.jade
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Dimens.radiusInner.dp))
            .clickable(onClick = onClick)
            .testTag("profile-row-$title"),
        shape = RoundedCornerShape(Dimens.radiusInner.dp),
        color = p.card,
        border = BorderStroke(1.dp, p.line)
    ) {
        Row(
            Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            NavIconView(icon, tint)
            Column(Modifier.weight(1f)) {
                Text(
                    title,
                    fontSize = FontSizes.body.sp,
                    color = if (danger) p.clay else p.ink1
                )
                if (subtitle != null) {
                    Spacer(Modifier.height(2.dp))
                    Text(subtitle, fontSize = FontSizes.caption.sp, color = p.ink3)
                }
            }
            if (value != null) {
                Text(
                    value,
                    fontSize = FontSizes.caption.sp,
                    color = if (danger) p.clay else p.ink3,
                    maxLines = 1
                )
            }
            // chevron：iOS 用 SF Symbol chevron.right 12pt semibold。
            // 这里用两个线段画一个「>」，省一个依赖，视觉上等价。
            Canvas(Modifier.size(12.dp)) {
                val sw = 1.6.dp.toPx()
                val w = size.width
                val h = size.height
                drawLine(p.ink3, Offset(w * 0.35f, h * 0.2f), Offset(w * 0.65f, h * 0.5f),
                    strokeWidth = sw, cap = StrokeCap.Round)
                drawLine(p.ink3, Offset(w * 0.65f, h * 0.5f), Offset(w * 0.35f, h * 0.8f),
                    strokeWidth = sw, cap = StrokeCap.Round)
            }
        }
    }
}
