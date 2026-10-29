package com.xiaoxiao.hanzi.ui.pages

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
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
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable

import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Srs
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.HanziColors
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.Screen

/**
 * 一课的生字网格，对应小程序 pages/lesson/lesson。
 *
 * 小程序底部「继续学习」按钮踩过的坑：原生 <button> 在 display:flex 父容器下
 * 会塌缩成半宽，需要显式 display:block; width:100%。
 * Compose 里用 Box(Modifier.fillMaxWidth()) 天然没有这个问题。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LessonPage(app: AppState, lessonId: String) {
    val p = LocalPalette.current
    val scroll = rememberScrollState()
    app.revision

    val lesson = Repo.lesson(lessonId) ?: return
    val book = Repo.book(lesson.book)
    val color = HanziColors.bookColor(lesson.book)
    val chars = lesson.chars
    val learnedCount = chars.count { app.progress.hasLearned(it) }
    val pct = if (chars.isEmpty()) 0 else Math.round(learnedCount * 100f / chars.size)
    val nextChar = chars.firstOrNull { !app.progress.hasLearned(it) } ?: ""
    val started = learnedCount > 0

    Column(Modifier.fillMaxSize()) {
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(scroll)
                .padding(horizontal = Dimens.pagePad.dp)
        ) {
            Spacer(Modifier.height(8.dp))
            Text(
                "${book?.name ?: ""} · 第 ${lesson.unit} 单元",
                fontSize = 12.sp,
                color = p.ink3
            )
            Spacer(Modifier.height(6.dp))

            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(lesson.title, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = p.ink1)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        lesson.kind + " · 识字 ${chars.size} 个" +
                            if (lesson.write.isNotEmpty()) " · 会写 ${lesson.write.size} 个" else "",
                        fontSize = 12.sp,
                        color = p.ink3
                    )
                }
                Box(
                    Modifier
                        .size(54.dp)
                        .clip(CircleShape)
                        .background(color.copy(alpha = 0.14f)),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("$pct%", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = color)
                        Text("已学", fontSize = 9.sp, color = color.copy(alpha = 0.8f))
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // 生字网格：3 列
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                chars.chunked(3).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        row.forEach { ch ->
                            CharCell(
                                ch = ch,
                                lessonId = lessonId,
                                app = app,
                                modifier = Modifier.weight(1f)
                            ) { app.nav.push(Screen.Detail(ch, lessonId)) }
                        }
                        repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }

            if (lesson.words.isNotEmpty()) {
                Spacer(Modifier.height(20.dp))
                Text("本课词语", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = p.ink1)
                Spacer(Modifier.height(9.dp))
                // 词语标签自动换行：小程序里用 flex-wrap，Compose 用 FlowRow
                androidx.compose.foundation.layout.FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    lesson.words.forEach { w ->
                        Box(
                            Modifier
                                .clip(RoundedCornerShape(999.dp))
                                .background(p.card)
                                .padding(horizontal = 12.dp, vertical = 6.dp)
                        ) {
                            Text(w, fontSize = 13.sp, color = p.ink2)
                        }
                    }
                }
            }

            Spacer(Modifier.height(20.dp))
        }

        // 底部固定按钮
        Surface(color = p.paper, shadowElevation = 8.dp) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = Dimens.pagePad.dp, vertical = 12.dp)
            ) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .testTag("lesson-start")
                        .clip(RoundedCornerShape(14.dp))
                        .background(color)
                        .clickable {
                            val target = if (nextChar.isNotEmpty()) nextChar else chars.firstOrNull()
                            if (target != null) app.nav.push(Screen.Detail(target, lessonId))
                        }
                        .padding(vertical = 14.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        (if (started) "继续学习" else "开始学习") +
                            if (nextChar.isNotEmpty()) " · $nextChar" else "",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White
                    )
                }
            }
        }
    }
}

@Composable
private fun CharCell(
    ch: String,
    lessonId: String,
    app: AppState,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    val meta = Repo.meta(ch)
    val entry = app.progress.entry(ch)
    val learned = Srs.isLearning(entry)
    val mastered = Srs.isMastered(entry)
    val due = entry != null && Srs.isDue(entry, com.xiaoxiao.hanzi.logic.DayUtil.dayNumber())
    val py = Repo.readingFor(ch, lessonId)
    val word = meta?.words?.firstOrNull()?.word ?: ""

    Column(
        modifier
            .clip(RoundedCornerShape(14.dp))
            .clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(84.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(if (learned) p.jadeSoft else p.card)
                .padding(2.dp),
            contentAlignment = Alignment.Center
        ) {
            Surface(
                Modifier.fillMaxSize(),
                shape = RoundedCornerShape(12.dp),
                color = if (learned) p.jadeSoft else p.cardWarm,
                border = BorderStroke(
                    1.dp,
                    if (learned) p.jade.copy(alpha = 0.35f) else p.line
                )
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(ch, fontSize = 36.sp, color = p.ink1)
                    if (learned) {
                        Box(
                            Modifier
                                .align(Alignment.TopEnd)
                                .padding(4.dp)
                                .size(16.dp)
                                .clip(CircleShape)
                                .background(p.jade),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                if (mastered) "★" else if (due) "↻" else "✓",
                                fontSize = 9.sp,
                                color = Color.White
                            )
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(5.dp))
        Text(py, fontSize = 12.sp, color = p.jade, fontWeight = FontWeight.Medium)
        if (word.isNotEmpty()) {
            Spacer(Modifier.height(1.dp))
            Text(word, fontSize = 10.sp, color = p.ink3, maxLines = 1)
        }
    }
}
