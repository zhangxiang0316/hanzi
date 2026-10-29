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
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.DayUtil
import com.xiaoxiao.hanzi.logic.Plan
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.HanziCard
import com.xiaoxiao.hanzi.ui.HanziColors
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.ProgressBar
import com.xiaoxiao.hanzi.ui.Screen
import com.xiaoxiao.hanzi.ui.SectionHead

/**
 * 首页：问候 / 连续天数 / 今日任务 / 八册入口 / 今日一字。
 *
 * 对应小程序 pages/index/index。原页面是 navigationStyle: custom，
 * 要自己躲微信胶囊；Android 没有胶囊，改用系统状态栏 insets，
 * 那套 nav-metrics 计算整体不再需要。
 */
@Composable
fun IndexPage(app: AppState) {
    val p = LocalPalette.current
    val scroll = rememberScrollState()

    // 读一次 revision，让页面在进度变化后重组
    app.revision
    val learned = app.progress.totalLearned()
    val total = Repo.allChars.size
    val pct = if (total > 0) Math.round(learned * 100f / total) else 0
    val streak = app.progress.getStreak()
    val task = app.todayTask()
    val dailyChar = Plan.pickDailyChar(app.currentBook, DayUtil.todayKey())
    val dailyMeta = Repo.meta(dailyChar)

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(scroll)
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        Spacer(Modifier.height(10.dp))

        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    DayUtil.greeting() + "，小朋友",
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    color = p.ink1
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    DayUtil.dateLabel() + " " + DayUtil.weekdayCN(),
                    fontSize = 13.sp,
                    color = p.ink3
                )
            }
            StreakBadge(streak)
        }

        Spacer(Modifier.height(18.dp))

        // 今日任务卡
        Box(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Dimens.radiusCard.dp))
                .background(Brush.linearGradient(listOf(p.jade, p.jadeDeep)))
                .padding(18.dp)
        ) {
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        task.title,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        modifier = Modifier.weight(1f)
                    )
                    if (task.count > 0) {
                        Box(
                            Modifier
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.22f))
                                .padding(horizontal = 10.dp, vertical = 4.dp)
                        ) {
                            Text("${task.count} 个", fontSize = 12.sp, color = Color.White)
                        }
                    }
                }
                Spacer(Modifier.height(6.dp))
                Text(task.desc, fontSize = 13.sp, color = Color.White.copy(alpha = 0.85f))
                Spacer(Modifier.height(14.dp))
                Box(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color.White)
                        .clickable {
                            when (task.type) {
                                "review" -> app.nav.push(Screen.Quiz("review", app.currentBook, null))
                                "done" -> app.nav.push(Screen.Quiz("free", app.currentBook, null))
                                else -> {
                                    val next = Plan.findContinue(app.progress, app.currentBook)
                                    if (next != null) app.nav.push(Screen.Lesson(next.lesson))
                                    else app.nav.push(Screen.Quiz("free", app.currentBook, null))
                                }
                            }
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        task.action,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = p.jadeDeep,
                        modifier = Modifier.padding(vertical = 11.dp)
                    )
                }
            }
        }

        Spacer(Modifier.height(14.dp))
        HanziCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("已认识 $learned 个字", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = p.ink1)
                    Spacer(Modifier.height(2.dp))
                    Text("全库 $total 字", fontSize = 12.sp, color = p.ink3)
                }
                Text("$pct%", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = p.jade)
            }
            Spacer(Modifier.height(10.dp))
            ProgressBar(pct)
        }

        SectionHead("跟课本学", gradeSpan())
        // 两列网格：8 册排成 4 行。整宽卡片一册一行时，八册要占掉一屏多，
        // 首页得滚很久才能看到「今日一字」。
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Repo.books.chunked(2).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { book ->
                        BookTile(
                            bookId = book.id,
                            name = book.name,
                            gradeText = gradeName(book.grade),
                            learned = app.progress.counts(Repo.bookChars(book.id)).learned,
                            total = book.stat.chars,
                            active = book.id == app.currentBook,
                            modifier = Modifier.weight(1f)
                        ) {
                            app.setBook(book.id)
                            app.nav.push(Screen.Unit(book.id))
                        }
                    }
                    // 补齐末行，避免最后一张被拉伸
                    repeat(2 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }

        if (dailyMeta != null) {
            SectionHead("今日一字", "每天换一个")
            HanziCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .size(76.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .background(p.cardWarm)
                            .clickable {
                                app.nav.push(Screen.Detail(dailyChar, dailyMeta.lesson))
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Text(dailyChar, fontSize = 42.sp, color = p.ink1)
                    }
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(dailyMeta.py, fontSize = 15.sp, color = p.jade, fontWeight = FontWeight.Medium)
                        Spacer(Modifier.height(4.dp))
                        Text(
                            "部首「${dailyMeta.radical}」· ${dailyMeta.strokes} 画",
                            fontSize = 13.sp,
                            color = p.ink2
                        )
                        Spacer(Modifier.height(4.dp))
                        Text(
                            dailyMeta.words.take(2).joinToString(" ") { it.word },
                            fontSize = 12.sp,
                            color = p.ink3
                        )
                    }
                    Text("›", fontSize = 24.sp, color = p.ink3)
                }
            }
        }

        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun StreakBadge(streak: Int) {
    val p = LocalPalette.current
    Row(
        Modifier
            .clip(CircleShape)
            .background(p.amberSoft)
            .padding(horizontal = 12.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("🔥", fontSize = 13.sp)
        Spacer(Modifier.width(4.dp))
        Text(
            if (streak > 0) "学了 $streak 天" else "今天开始",
            fontSize = 12.sp,
            color = p.amber,
            fontWeight = FontWeight.Medium
        )
    }
}

/**
 * 册次卡片（两列网格里的一格）。
 *
 * 只保留「册名 + 进度」两件事：整宽卡片还有年级色块、课数和箭头，
 * 放大到八册后高度压过了页面其他所有内容。
 */
@Composable
private fun BookTile(
    bookId: String,
    name: String,
    gradeText: String,
    learned: Int,
    total: Int,
    active: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    val color = HanziColors.bookColor(bookId)
    val pct = if (total > 0) Math.round(learned * 100f / total) else 0
    // 册名首字就是年级（一年级上册 → 一），网格里用单字标色，省掉独立色块
    val short = gradeText.take(1)

    Surface(
        modifier
            .clip(RoundedCornerShape(Dimens.radiusInner.dp))
            .testTag("index-book-$bookId")
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(Dimens.radiusInner.dp),
        color = p.card,
        border = BorderStroke(
            if (active) 2.dp else 1.dp,
            if (active) color.copy(alpha = 0.55f) else p.line.copy(alpha = 0.8f)
        )
    ) {
        Column(Modifier.padding(horizontal = 11.dp, vertical = 10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(17.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(color.copy(alpha = 0.16f)),
                    contentAlignment = Alignment.Center
                ) {
                    Text(short, fontSize = 10.sp, color = color, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.width(6.dp))
                Text(
                    name,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = p.ink1,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Text("$pct%", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = color)
            }
            Spacer(Modifier.height(7.dp))
            ProgressBar(pct, color = color, height = 5)
            Spacer(Modifier.height(5.dp))
            Text(
                "$learned / $total 字",
                fontSize = 10.sp,
                color = p.ink3,
                maxLines = 1
            )
        }
    }
}

fun gradeName(grade: Int): String = when (grade) {
    1 -> "一年级"
    2 -> "二年级"
    3 -> "三年级"
    4 -> "四年级"
    5 -> "五年级"
    6 -> "六年级"
    else -> "${grade}年级"
}

/** 年级范围按实际册次算，加年级后文案自动跟着变（与小程序一致） */
fun gradeSpan(): String {
    val grades = Repo.books.map { it.grade }
    if (grades.isEmpty()) return ""
    return gradeName(grades.min()) + "到" + gradeName(grades.max())
}
