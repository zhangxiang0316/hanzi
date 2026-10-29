package com.xiaoxiao.hanzi.ui.pages

import androidx.compose.foundation.BorderStroke
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Plan
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.HanziColors
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.ProgressBar
import com.xiaoxiao.hanzi.ui.Screen

/** 单元目录，对应小程序 pages/unit/unit */
@Composable
fun UnitPage(app: AppState, bookId: String) {
    val p = LocalPalette.current
    val scroll = rememberScrollState()
    app.revision

    val book = Repo.book(bookId) ?: return
    val stat = Plan.bookProgress(app.progress, bookId)
    val color = HanziColors.bookColor(bookId)

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(scroll)
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        Spacer(Modifier.height(8.dp))

        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(book.name, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = p.ink1)
                Spacer(Modifier.height(4.dp))
                Text(
                    "${stat.learned} / ${stat.total} 字已学 · 共 ${book.stat.units} 个单元 ${book.stat.lessons} 课",
                    fontSize = 12.sp,
                    color = p.ink3
                )
            }
            Box(
                Modifier
                    .size(52.dp)
                    .clip(CircleShape)
                    .background(color.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center
            ) {
                Text("${stat.pct}%", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = color)
            }
        }

        Spacer(Modifier.height(12.dp))
        ProgressBar(stat.pct, color = color)
        Spacer(Modifier.height(14.dp))

        Row {
            Box(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(color)
                    .clickable {
                        val next = Plan.findContinue(app.progress, bookId)
                        if (next != null) app.nav.push(Screen.Lesson(next.lesson))
                    }
                    .padding(vertical = 11.dp),
                contentAlignment = Alignment.Center
            ) {
                Text("接着上次学", fontSize = 14.sp, color = Color.White, fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.width(10.dp))
            Box(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(p.card)
                    .clickable { app.nav.push(Screen.Quiz("free", bookId, null)) }
                    .padding(vertical = 11.dp),
                contentAlignment = Alignment.Center
            ) {
                Text("练这一册", fontSize = 14.sp, color = p.ink1, fontWeight = FontWeight.SemiBold)
            }
        }

        Spacer(Modifier.height(18.dp))

        book.units.forEachIndexed { idx, unit ->
            // 单元之间用册次色的深浅区分，避免全篇同一个色调
            val unitColor = color.copy(alpha = 1f - idx * 0.08f)
            val unitLessons = unit.lessons.mapNotNull { Repo.lesson(it) }
            val unitCharCount = unitLessons.sumOf { it.chars.size }
            val unitLearned = unitLessons.sumOf { l -> l.chars.count { app.progress.hasLearned(it) } }
            val unitPct = if (unitCharCount > 0) Math.round(unitLearned * 100f / unitCharCount) else 0

            Column(Modifier.padding(bottom = 18.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .size(9.dp)
                            .clip(CircleShape)
                            .background(unitColor)
                    )
                    Spacer(Modifier.width(8.dp))
                    Column(Modifier.weight(1f)) {
                        Text(unit.title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = p.ink1)
                        Spacer(Modifier.height(2.dp))
                        Text(
                            "${unit.theme} · ${unit.lessons.size} 课 · $unitCharCount 字",
                            fontSize = 11.sp,
                            color = p.ink3
                        )
                    }
                    Text("$unitPct%", fontSize = 12.sp, color = p.ink3)
                }

                Spacer(Modifier.height(9.dp))

                Surface(
                    Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(Dimens.radiusInner.dp),
                    color = p.card,
                    border = BorderStroke(1.dp, p.line)
                ) {
                    Column {
                        unitLessons.forEachIndexed { i, lesson ->
                            if (i > 0) {
                                Box(
                                    Modifier
                                        .fillMaxWidth()
                                        .height(1.dp)
                                        .background(p.lineSoft)
                                )
                            }
                            val learnedInLesson = lesson.chars.count { app.progress.hasLearned(it) }
                            val done = learnedInLesson == lesson.chars.size && lesson.chars.isNotEmpty()
                            LessonRow(
                                no = lesson.no,
                                title = lesson.title,
                                kind = lesson.kind,
                                charCount = lesson.chars.size,
                                learned = learnedInLesson,
                                done = done
                            ) { app.nav.push(Screen.Lesson(lesson.id)) }
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun LessonRow(
    no: Int,
    title: String,
    kind: String,
    charCount: Int,
    learned: Int,
    done: Boolean,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(28.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(p.lineSoft),
            contentAlignment = Alignment.Center
        ) {
            Text("$no", fontSize = 12.sp, color = p.ink2, fontWeight = FontWeight.Medium)
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, fontSize = 14.sp, color = p.ink1)
                if (kind != "课文") {
                    Spacer(Modifier.width(5.dp))
                    Text(
                        kind,
                        fontSize = 10.sp,
                        color = p.amber,
                        modifier = Modifier
                            .clip(RoundedCornerShape(4.dp))
                            .background(p.amberSoft)
                            .padding(horizontal = 4.dp, vertical = 1.dp)
                    )
                }
            }
            Spacer(Modifier.height(2.dp))
            Text(
                "$charCount 字" + if (learned > 0) " · 已学 $learned" else "",
                fontSize = 11.sp,
                color = p.ink3
            )
        }
        if (done) {
            Text("✓", fontSize = 14.sp, color = p.jade, fontWeight = FontWeight.Bold)
        } else {
            Text("›", fontSize = 18.sp, color = p.ink3)
        }
    }
}
