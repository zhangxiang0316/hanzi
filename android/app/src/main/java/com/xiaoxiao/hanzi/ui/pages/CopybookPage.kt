package com.xiaoxiao.hanzi.ui.pages

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.HanziButton
import com.xiaoxiao.hanzi.ui.HanziGlyph
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.Screen

/**
 * 我的字帖：把写过的字排成一张字帖。
 *
 * 为什么值得单独做一页：现在的徽章体系几乎全是「认识 N 个字」这一个维度，
 * 而 `WriteRecord` 存了 `best / stars / tries / last` 四个字段却只在单字页
 * 显示三颗星。「我写了一百个字」和「我认识一百个字」对孩子来说是两回事，
 * 后者是看得懂，前者是写得出来——后者更难，也更值得被看见。
 *
 * 与 iOS `CopybookPageView` 对应。
 */
@Composable
fun CopybookPage(app: AppState) {
    val p = LocalPalette.current
    app.revision

    val all = remember(app.revision) { app.progress.allWriteRecords() }
    var starFilter by remember { mutableStateOf<Int?>(null) }
    val shown = if (starFilter == null) all else all.filter { it.second.stars == starFilter }

    Column(
        Modifier
            .fillMaxSize()
            .background(p.paper)
            .verticalScroll(rememberScrollState())
            .padding(Dimens.pagePad.dp)
    ) {
        if (all.isEmpty()) {
            EmptyCopybook(app)
            return@Column
        }

        SummaryCard(
            total = app.progress.writeCount(),
            stars = app.progress.writeStarsTotal(),
            hist = app.progress.writeStarsHistogram()
        )

        Spacer(Modifier.height(14.dp))

        // 筛选：只显示有内容的档位，避免一排「0」占地方
        val hist = app.progress.writeStarsHistogram()
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            FilterChip("全部", all.size, starFilter == null) { starFilter = null }
            listOf(3, 2, 1, 0).forEach { s ->
                val n = hist[s] ?: 0
                if (n > 0) {
                    FilterChip(if (s == 0) "待练" else "$s 星", n, starFilter == s) {
                        starFilter = s
                    }
                }
            }
        }

        Spacer(Modifier.height(14.dp))

        // 用固定列宽的网格：手机上 3 列、平板上更多，和首页生字卡密度一致
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 84.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            // 外层已经在滚动，这里不能自己再滚：高度不设限会崩（无限约束）
            modifier = Modifier.height(tileGridHeight(shown.size))
        ) {
            items(shown, key = { it.first }) { item ->
                CopybookTile(item.first, item.second.best, item.second.stars) {
                    app.nav.push(Screen.Write(item.first))
                }
            }
        }

        Spacer(Modifier.height(24.dp))
    }
}

/**
 * 网格高度。
 *
 * LazyVerticalGrid 被放进 verticalScroll 的 Column 里时拿到的是无限高度约束，
 * 直接摆放会抛异常。这里按「每行约 108dp + 间距」估一个确定高度，
 * 既能让外层正常滚动，也不会把内容裁掉（尾行留足余量）。
 */
private fun tileGridHeight(count: Int): androidx.compose.ui.unit.Dp {
    if (count <= 0) return 0.dp
    // 自适应列宽最小 84dp，窄屏至少 3 列；按 3 列保守估算行数
    val perRow = 4
    val rows = (count + perRow - 1) / perRow
    return (rows * 108 + (rows - 1) * 10).dp
}

@Composable
private fun SummaryCard(total: Int, stars: Int, hist: Map<Int, Int>) {
    val p = LocalPalette.current
    Surface(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Dimens.radiusCard.dp),
        color = p.card,
        border = androidx.compose.foundation.BorderStroke(1.dp, p.line)
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text("$total", fontSize = 32.sp, fontWeight = FontWeight.Bold, color = p.ink1)
                Spacer(Modifier.size(5.dp))
                Text("个字写过", fontSize = 13.sp, color = p.ink3)
                Spacer(Modifier.weight(1f))
                Text("共 $stars 颗星", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = p.amber)
            }

            Spacer(Modifier.height(12.dp))

            // 星级分布：一眼看出「写得好的有多少、还需要练的有多少」
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                listOf(3, 2, 1, 0).forEach { s ->
                    val n = hist[s] ?: 0
                    Column(
                        Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(Dimens.radiusInner.dp))
                            .background(p.track)
                            .padding(vertical = 8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            "$n",
                            fontSize = 16.sp, fontWeight = FontWeight.Bold,
                            color = if (n > 0) starColor(s) else p.ink3.copy(alpha = 0.4f)
                        )
                        Text(
                            if (s == 0) "待练" else "$s 星",
                            fontSize = 10.sp, color = p.ink3
                        )
                    }
                }
            }
        }
    }
}

private fun starColorOf(s: Int, p: com.xiaoxiao.hanzi.ui.Palette): androidx.compose.ui.graphics.Color =
    when {
        s >= 3 -> p.amber
        s == 2 -> p.jade
        s == 1 -> p.ink2
        else -> p.clay
    }

@Composable
private fun starColor(s: Int): androidx.compose.ui.graphics.Color =
    starColorOf(s, LocalPalette.current)

@Composable
private fun FilterChip(title: String, count: Int, on: Boolean, onClick: () -> Unit) {
    val p = LocalPalette.current
    Surface(
        shape = CircleShape,
        color = if (on) p.jade else p.card,
        border = if (on) null else androidx.compose.foundation.BorderStroke(1.dp, p.line),
        modifier = Modifier
            .clip(CircleShape)
            .clickable(onClick = onClick)
    ) {
        Row(
            Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                title,
                fontSize = 13.sp,
                fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal,
                color = if (on) androidx.compose.ui.graphics.Color.White else p.ink2
            )
            Spacer(Modifier.size(5.dp))
            Text(
                "$count",
                fontSize = 11.sp,
                color = (if (on) androidx.compose.ui.graphics.Color.White else p.ink2).copy(alpha = 0.7f)
            )
        }
    }
}

@Composable
private fun CopybookTile(ch: String, best: Int, stars: Int, onClick: () -> Unit) {
    val p = LocalPalette.current
    Column(
        Modifier
            .clip(RoundedCornerShape(Dimens.radiusInner.dp))
            .background(p.card)
            .clickable(onClick = onClick)
            .padding(vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        HanziGlyph(ch, Modifier.size(46.dp))
        Spacer(Modifier.height(5.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            repeat(3) { i ->
                Text(
                    "★",
                    fontSize = 9.sp,
                    color = if (i < stars) p.amber else p.track
                )
            }
        }
        Text(
            "$best 分",
            fontSize = 10.sp, fontWeight = FontWeight.SemiBold,
            color = when {
                best >= 85 -> p.jade
                best >= 65 -> p.amber
                else -> p.clay
            }
        )
    }
}

@Composable
private fun EmptyCopybook(app: AppState) {
    val p = LocalPalette.current
    Column(
        Modifier.fillMaxWidth().padding(vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("🖌️", fontSize = 40.sp)
        Spacer(Modifier.height(10.dp))
        Text("还没有写过字", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = p.ink1)
        Spacer(Modifier.height(6.dp))
        Text(
            "去描红或听写几个字，这里就会有一张你自己的字帖",
            fontSize = 12.sp,
            color = p.ink3,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(14.dp))
        val first = Repo.bookChars(app.currentBook).firstOrNull()
        HanziButton(text = "去描红", fillWidth = false) {
            if (first != null) app.nav.push(Screen.Write(first))
        }
    }
}
