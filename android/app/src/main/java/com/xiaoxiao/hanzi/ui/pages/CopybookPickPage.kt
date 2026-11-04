package com.xiaoxiao.hanzi.ui.pages

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.CopybookPick
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.HanziButton
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.exportCopybook

/**
 * 选字做字帖。
 *
 * 「我的字帖」只能导**写过的字**。但家长真实的用法是：
 * 「把这课的生字打一张」「把错题打一张」「把三颗星以下的打一张」——
 * 这些都不是「我写过的」，而是「我需要练的」。
 *
 * ## 与小程序版的差别
 *
 * 小程序那边笔画数据在分包里，主包取不到，所以选字时要标出哪些字画不出来。
 * Android 的笔顺数据全量打在 assets 里，每个字都画得出来——那套「置灰 +
 * 先描一遍」的提示在这里不成立，整个没有搬，选中就能导。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CopybookPickPage(app: AppState) {
    val p = LocalPalette.current
    val ctx = LocalContext.current
    app.revision

    val bookId = app.currentBook
    val book = Repo.book(bookId)
    val lessons = book?.lessons ?: emptyList()

    // 默认选本册第一课：家长最常打的就是「这课的生字」
    var lessonId by remember(bookId) { mutableStateOf(lessons.firstOrNull() ?: "") }

    var srcWrong by remember { mutableStateOf(true) }
    var srcWeak by remember { mutableStateOf(false) }
    var srcLesson by remember { mutableStateOf(true) }
    var srcStars by remember { mutableStateOf(false) }
    var starLevel by remember { mutableStateOf(2) }

    // null = 全选。界面上一堆字默认全选，家长不需要先点一百下
    var selected by remember { mutableStateOf<Set<String>?>(null) }
    var busy by remember { mutableStateOf(false) }

    val items = remember(app.revision, bookId, lessonId, srcWrong, srcWeak, srcLesson, srcStars, starLevel) {
        val records = app.progress.allWriteRecords()
        CopybookPick.build(
            CopybookPick.Source(
                lessonChars = if (srcLesson && lessonId.isNotEmpty()) Repo.lessonChars(lessonId) else emptyList(),
                records = records,
                wrongChars = if (srcWrong) app.progress.wrongList().map { it.ch } else emptyList(),
                weakChars = if (srcWeak) app.progress.weakChars().map { it.ch } else emptyList(),
                stars = if (srcStars) starLevel else null
            )
        )
    }

    // 选中集合要跟着候选集走：关掉一个来源后，被它带出来的字不能还占着计数
    val chosen: Set<String> = selected?.let { sel -> items.map { it.ch }.filter { it in sel }.toSet() }
        ?: items.map { it.ch }.toSet()

    fun toggle(ch: String) {
        selected = if (selected == null) {
            // 从「全选」切到「显式选择」：先全选，再去掉这个
            items.map { it.ch }.filter { it != ch }.toSet()
        } else {
            val cur = selected ?: emptySet()
            if (ch in cur) cur - ch else cur + ch
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        // 标题交给顶栏，页面里只在首行交代一句「这页是干什么的」
        Spacer(Modifier.height(8.dp))
        Text("按课时、错题、薄弱笔画挑字，导出成一张打印版字帖", fontSize = 12.sp, color = p.ink3)

        Spacer(Modifier.height(14.dp))

        // 来源：错题 / 笔画弱 / 本课 / 低星。选中顺序由 CopybookPick 统一决定
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PickChip("错题本", srcWrong, "pick-src-wrong") { srcWrong = !srcWrong }
            PickChip("笔画弱", srcWeak, "pick-src-weak") { srcWeak = !srcWeak }
            PickChip("本课生字", srcLesson, "pick-src-lesson") { srcLesson = !srcLesson }
            PickChip("低分字", srcStars, "pick-src-stars") { srcStars = !srcStars }
        }

        if (srcStars) {
            Spacer(Modifier.height(10.dp))
            Text("几颗星以下", fontSize = 11.sp, color = p.ink3)
            Spacer(Modifier.height(6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(0, 1, 2).forEach { n ->
                    StarChip("$n 星及以下", starLevel == n, "pick-star-$n") { starLevel = n }
                }
            }
        }

        if (srcLesson && lessons.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            Text(
                "${book?.name ?: ""} · 选一课",
                fontSize = 11.sp,
                color = p.ink3
            )
            Spacer(Modifier.height(6.dp))
            Row(
                Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                lessons.forEach { lid ->
                    val l = Repo.lesson(lid) ?: return@forEach
                    StarChip("第 ${l.no} 课", lessonId == lid) { lessonId = lid }
                }
            }
        }

        Spacer(Modifier.height(14.dp))

        // 选中条：数字用大字，两个操作放在右边
        Row(
            Modifier
                .fillMaxWidth()
                .padding(vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.Bottom) {
                Text("已选 ", fontSize = 13.sp, color = p.ink2)
                Text(
                    "${chosen.size}",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    color = p.jade
                )
                Text(" 个字", fontSize = 13.sp, color = p.ink2)
            }
            Text(
                "全选",
                fontSize = 12.sp,
                color = p.jadeDeep,
                modifier = Modifier
                    .testTag("pick-select-all")
                    .clickable { selected = null }
                    .defaultMinSize(minWidth = 44.dp, minHeight = 44.dp)
                    .padding(10.dp)
            )
            Spacer(Modifier.width(4.dp))
            Text(
                "清空",
                fontSize = 12.sp,
                color = p.jadeDeep,
                modifier = Modifier
                    .testTag("pick-select-none")
                    .clickable { selected = emptySet() }
                    .defaultMinSize(minWidth = 44.dp, minHeight = 44.dp)
                    .padding(10.dp)
            )
        }

        if (items.isEmpty()) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = 40.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("上面几个来源都没有字", fontSize = 14.sp, color = p.ink2)
                Spacer(Modifier.height(6.dp))
                Text("换一个来源试试", fontSize = 12.sp, color = p.ink3)
            }
        } else {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items.forEach { item ->
                    PickCell(
                        ch = item.ch,
                        fromText = item.fromText,
                        on = item.ch in chosen
                    ) { toggle(item.ch) }
                }
            }
        }

        Spacer(Modifier.height(20.dp))

        HanziButton(
            if (busy) "正在排版…" else "导出字帖（${chosen.size} 个字）",
            enabled = chosen.isNotEmpty() && !busy,
            tag = "选字-导出"
        ) {
            if (chosen.isNotEmpty()) {
                busy = true
                // 按候选列表的顺序导出：错题 / 弱笔在前的顺序是有意义的，
                // 打印出来家长按这个顺序陪练
                val names = items.map { it.ch }.filter { it in chosen }
                exportCopybook(ctx, names) { ok ->
                    busy = false
                    if (!ok) {
                        android.widget.Toast.makeText(
                            ctx, "导出失败了，再试一次", android.widget.Toast.LENGTH_SHORT
                        ).show()
                    }
                }
            }
        }

        Spacer(Modifier.height(10.dp))
        Text(
            "导出的是一张 A4 字帖，一页六个字，可以反复描。",
            modifier = Modifier.fillMaxWidth(),
            fontSize = 11.sp,
            color = p.ink3,
            textAlign = TextAlign.Center
        )

        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun PickChip(text: String, on: Boolean, tag: String, onClick: () -> Unit) {
    val p = LocalPalette.current
    Surface(
        shape = RoundedCornerShape(999.dp),
        color = if (on) p.jade else p.card,
        border = BorderStroke(1.dp, if (on) p.jade else p.line),
        modifier = Modifier
            .testTag(tag)
            .clip(RoundedCornerShape(999.dp))
            .clickable(onClick = onClick)
            .defaultMinSize(minHeight = 44.dp)
    ) {
        Box(Modifier.padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
            Text(
                text,
                fontSize = 13.sp,
                fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal,
                color = if (on) Color.White else p.ink2
            )
        }
    }
}

@Composable
private fun StarChip(text: String, on: Boolean, tag: String? = null, onClick: () -> Unit) {
    val p = LocalPalette.current
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = if (on) p.jadeSoft else p.card,
        border = BorderStroke(1.dp, if (on) p.jade else p.line),
        modifier = Modifier
            .then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .defaultMinSize(minWidth = 44.dp, minHeight = 44.dp)
    ) {
        Box(Modifier.padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
            Text(
                text,
                fontSize = 12.sp,
                color = if (on) p.jadeDeep else p.ink2
            )
        }
    }
}

/**
 * 一个字格。
 *
 * 选中用「加粗边框 + 淡绿底」，不用对勾——对勾会挡在字上面，
 * 而孩子第一眼要看的是字本身。
 */
@Composable
private fun PickCell(ch: String, fromText: String, on: Boolean, onClick: () -> Unit) {
    val p = LocalPalette.current
    Surface(
        shape = RoundedCornerShape(14.dp),
        color = if (on) p.jadeSoft else p.card,
        border = BorderStroke(if (on) 2.dp else 1.dp, if (on) p.jade else p.line),
        modifier = Modifier
            .testTag("pick-cell-$ch")
            .size(width = 68.dp, height = 76.dp)
            .clip(RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
    ) {
        Column(
            Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(ch, fontSize = 26.sp, color = p.ink1)
            Spacer(Modifier.height(2.dp))
            Text(
                fromText,
                fontSize = 8.sp,
                lineHeight = 10.sp,
                color = p.ink3,
                textAlign = TextAlign.Center,
                maxLines = 2
            )
        }
    }
}
