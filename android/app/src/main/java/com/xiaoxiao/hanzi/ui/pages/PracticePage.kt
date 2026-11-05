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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.DictationLevel
import com.xiaoxiao.hanzi.logic.Words
import com.xiaoxiao.hanzi.logic.Plan
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.FontSizes
import com.xiaoxiao.hanzi.ui.HanziCard
import com.xiaoxiao.hanzi.ui.HanziColors
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.Screen
import com.xiaoxiao.hanzi.ui.SectionHead

/**
 * 练一练：待复习统计 / 每日复习 / 错题本 / 随机练习 / 按册练 / 描红 / 最近 7 天。
 * 对应小程序 pages/practice/practice。
 */
@Composable
fun PracticePage(app: AppState) {
    val p = LocalPalette.current
    val scroll = rememberScrollState()
    app.revision

    val due = app.progress.allDue()
    val today = app.progress.todayStats()
    val rate = app.progress.accuracyToday()
    val wrong = app.progress.wrongCount()
    val heroChar = if (due.isNotEmpty()) due.first() else Plan.pickDailyChar(app.currentBook, "hero")

    // 描红候选：学过且笔画数据齐全的字
    val learnedChars = Repo.allChars.filter { app.progress.hasLearned(it) && Repo.strokeCount(it) > 0 }
    val writeChar = learnedChars.firstOrNull() ?: Repo.bookChars(app.currentBook).firstOrNull() ?: ""
    val recentChars = learnedChars.take(7).map { ch ->
        ch to (app.progress.writeRecord(ch)?.stars ?: 0)
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(scroll)
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        Spacer(Modifier.height(10.dp))
        Text(
            "练一练",
            fontSize = FontSizes.pageTitle.sp,
            fontWeight = FontWeight.Bold,
            color = p.ink1
        )
        Spacer(Modifier.height(4.dp))
        Text("今天的复习，都是你学过的字", fontSize = 13.sp, color = p.ink3)
        Spacer(Modifier.height(16.dp))

        // 三格统计
        HanziCard(padding = 14) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                StatCell("${due.size}", "待复习", Modifier.weight(1f))
                Box(Modifier.width(1.dp).height(30.dp).background(p.line))
                StatCell("${today.answers}", "今日答题", Modifier.weight(1f))
                Box(Modifier.width(1.dp).height(30.dp).background(p.line))
                StatCell("$rate%", "正确率", Modifier.weight(1f))
            }
        }

        Spacer(Modifier.height(14.dp))

        // 主卡：每日复习
        Box(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Dimens.radiusCard.dp))
                .background(Brush.linearGradient(listOf(p.jade, p.jadeDeep)))
                .clickable {
                    if (due.isNotEmpty()) app.nav.push(Screen.Quiz("review", app.currentBook, null))
                    else app.nav.push(Screen.Quiz("free", app.currentBook, null))
                }
                .padding(16.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Box(
                        Modifier
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.2f))
                            .padding(horizontal = 9.dp, vertical = 3.dp)
                    ) {
                        Text("每日复习", fontSize = 11.sp, color = Color.White)
                    }
                    Spacer(Modifier.height(9.dp))
                    Text(
                        if (due.isNotEmpty()) "有 ${due.size} 个字等你" else "今天已经复习完啦",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    Spacer(Modifier.height(5.dp))
                    Text(
                        if (due.isNotEmpty()) "复习过的字，记得更牢" else "去学几个新字，或者自由练习",
                        fontSize = 12.sp,
                        color = Color.White.copy(alpha = 0.82f)
                    )
                    Spacer(Modifier.height(11.dp))
                    Text(
                        (if (due.isNotEmpty()) "开始复习" else "学新字") + " →",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White
                    )
                }
                if (heroChar.isNotEmpty()) {
                    Box(
                        Modifier
                            .size(74.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color.White.copy(alpha = 0.16f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(heroChar, fontSize = 40.sp, color = Color.White)
                    }
                }
            }
        }

        Spacer(Modifier.height(14.dp))

        // 错题本 + 随机练习
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ActionCard(
                emoji = "✍️",
                title = "错题本",
                desc = "$wrong 个字",
                badge = wrong,
                modifier = Modifier.weight(1f),
                accent = p.clay,
                enabled = wrong > 0
            ) { app.nav.push(Screen.Wrong) }
            ActionCard(
                emoji = "🎲",
                title = "随机练习",
                desc = Repo.book(app.currentBook)?.short ?: "",
                badge = 0,
                modifier = Modifier.weight(1f),
                accent = p.jade
            ) { app.nav.push(Screen.Quiz("free", app.currentBook, null)) }
        }

        Spacer(Modifier.height(12.dp))

        // 多音字：读准了才算真认识
        val polyCount = Repo.polyphones(app.currentBook).size
        ActionCard(
            emoji = "🎭",
            title = "多音字",
            desc = if (polyCount > 0) "本册 $polyCount 个多音字，练读准" else "换一册就会有多音字",
            badge = 0,
            modifier = Modifier.fillMaxWidth(),
            accent = p.amber,
            enabled = polyCount > 0
        ) {
            app.nav.push(Screen.Quiz("polyphone", app.currentBook, null))
        }

        Spacer(Modifier.height(12.dp))

        // 部首：查字法是低年级语文园地的正式内容
        val radicalCount = Repo.bookRadicals(app.currentBook).size
        ActionCard(
            emoji = "🧩",
            title = "部首",
            desc = "本册 $radicalCount 个部首，练查字法",
            badge = 0,
            modifier = Modifier.fillMaxWidth(),
            accent = p.clay,
            enabled = radicalCount > 0
        ) {
            app.nav.push(Screen.Quiz("radical", app.currentBook, null))
        }

        // 同音字：一个音有好几个字，练「写哪个」。
        // 和多音字互补——那个练读对音，这个练写对字。
        val homoCount = Repo.homophoneChars(app.currentBook).size
        ActionCard(
            emoji = "🔤",
            title = "同音字",
            desc = if (homoCount > 0) "本册 $homoCount 个字有同音伙伴，练写对" else "换一册就会有多组",
            badge = 0,
            modifier = Modifier.fillMaxWidth(),
            accent = p.jade,
            enabled = homoCount > 0
        ) {
            app.nav.push(Screen.Quiz("homophone", app.currentBook, null))
        }

        // 形近字：长得像的字别写混（未/末、天/夫）。
        // 和同音字正好互补——那个考「音一样写哪个」，这个考「长得像别混」
        val simCount = Repo.bookSimilarChars(app.currentBook).size
        ActionCard(
            emoji = "🪞",
            title = "形近字",
            desc = if (simCount > 0) "本册 $simCount 个字长得像，练分清" else "这一册没有形近字",
            badge = 0,
            modifier = Modifier.fillMaxWidth(),
            accent = p.sky,
            enabled = simCount > 0
        ) {
            app.nav.push(Screen.Quiz("similar", app.currentBook, null))
        }

        // 看拼音选词语：题源是课本词语表，不是生字表。
        // 孩子要读的是整个词，光认单字读不出来也白搭。
        val wordCount = Words.bookWordCount(app.currentBook)
        ActionCard(
            emoji = "📚",
            title = "看拼音选词语",
            desc = "本册 $wordCount 个课文词语，练读整个词",
            badge = 0,
            modifier = Modifier.fillMaxWidth(),
            accent = p.clay,
            enabled = wordCount >= 4
        ) {
            app.nav.push(Screen.Quiz("words", app.currentBook, null))
        }

        SectionHead("听写", "念一个词，凭记忆写出来")
        // 三档难度摆出来让家长选，而不是藏在设置里。
        // 适合谁由家长判断——刚学完一课用「看着写」，学过一阵用「听词写」，很熟了用「只听字」。
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            DictationLevel.entries.forEach { level ->
                Surface(
                    Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(Dimens.radiusInner.dp))
                        .clickable {
                            app.nav.push(Screen.Dictation(level.key, app.currentBook))
                        },
                    color = LocalPalette.current.card
                ) {
                    Column(
                        Modifier.padding(vertical = 14.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(level.title, fontSize = 14.sp, fontWeight = FontWeight.Bold,
                            color = LocalPalette.current.ink1)
                        Text(if (level.showsGhost) "有底字" else "无底字",
                            fontSize = 10.sp, color = LocalPalette.current.ink3)
                    }
                }
            }
        }

        SectionHead("按册来练")
        // 8 册芯片：4 列 x 2 行。小程序里这里踩过两个坑：
        // 一是 border-radius 用了 999rpx（两行时圆角半径超过高度，变成胶囊怪形状），
        // 二是 grid 在旧 WebView 上表现不一致；Android 没有这些问题，直接固定 4 列。
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Repo.books.chunked(4).forEach { rowBooks ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    rowBooks.forEach { book ->
                        val c = app.progress.counts(Repo.bookChars(book.id))
                        BookChip(
                            bookId = book.id,
                            short = book.short,
                            learned = c.learned,
                            total = book.stat.chars,
                            active = book.id == app.currentBook,
                            modifier = Modifier.weight(1f)
                        ) {
                            app.setBook(book.id)
                            app.nav.push(Screen.Quiz("free", book.id, null))
                        }
                    }
                    // 不足 4 个时补空位，保证列宽一致
                    repeat(4 - rowBooks.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }

        SectionHead("描红练字", "写一写，记得更牢")
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Surface(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(Dimens.radiusInner.dp))
                    .clickable { if (writeChar.isNotEmpty()) app.nav.push(Screen.Write(writeChar)) },
                shape = RoundedCornerShape(Dimens.radiusInner.dp),
                color = p.card,
                border = BorderStroke(1.dp, p.line)
            ) {
                Column(Modifier.padding(12.dp)) {
                    Text("随机练一个", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = p.ink1)
                    Spacer(Modifier.height(2.dp))
                    Text("从学过的字里挑", fontSize = 11.sp, color = p.ink3)
                    Spacer(Modifier.height(8.dp))
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(64.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(p.cardWarm),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(writeChar, fontSize = 34.sp, color = p.ink1)
                    }
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                recentChars.chunked(4).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { (ch, stars) ->
                            Surface(
                                Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(10.dp))
                                    .clickable { app.nav.push(Screen.Write(ch)) },
                                shape = RoundedCornerShape(10.dp),
                                color = p.card,
                                border = BorderStroke(1.dp, p.line)
                            ) {
                                Column(
                                    Modifier.padding(vertical = 7.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally
                                ) {
                                    Text(ch, fontSize = 22.sp, color = p.ink1)
                                    Text(
                                        if (stars > 0) "$stars★" else " ",
                                        fontSize = 9.sp,
                                        color = p.amber
                                    )
                                }
                            }
                        }
                        repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }

        // 笔画薄弱点：只有真的写错过才出现，平时不占地方
        val weakAll = app.progress.allWeakStrokes()
        if (weakAll.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            Surface(
                Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Dimens.radiusInner.dp),
                color = p.cardWarm,
                border = BorderStroke(1.dp, p.line)
            ) {
                Column(Modifier.padding(12.dp)) {
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("这几笔还不太稳", fontSize = 13.sp,
                             fontWeight = FontWeight.SemiBold, color = p.ink1)
                        Text("点一下再写一遍", fontSize = 11.sp, color = p.ink3)
                    }
                    Spacer(Modifier.height(10.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        // 取失败次数最多的前 4 个：够提示「下次该练哪一笔」，
                        // 又不至于变成一张报表
                        weakAll.take(4).forEach { w ->
                            Surface(
                                Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(10.dp))
                                    .clickable { app.nav.push(Screen.Write(w.ch)) },
                                shape = RoundedCornerShape(10.dp),
                                color = p.card,
                                border = BorderStroke(1.dp, p.line)
                            ) {
                                Column(
                                    Modifier.padding(vertical = 8.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally
                                ) {
                                    Text(w.ch, fontSize = 24.sp, color = p.ink1, maxLines = 1)
                                    // 四枚一排时每枚只有 74dp，`第 12 笔` 在系统大字号下
                                    // 会换行把卡片撑高，限制成一行让它自己缩
                                    Text(
                                        "第 ${w.index + 1} 笔",
                                        fontSize = 9.sp,
                                        color = p.ink3,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                        repeat(4 - minOf(4, weakAll.size)) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }

        SectionHead("最近 7 天")
        val days = app.progress.recentDays(7)
        val maxAnswers = maxOf(1, days.maxOfOrNull { it.answers } ?: 1)
        HanziCard {
            Row(
                Modifier.height(110.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Bottom
            ) {
                days.forEach { d ->
                    Column(
                        Modifier.weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .height(76.dp),
                            contentAlignment = Alignment.BottomCenter
                        ) {
                            Box(
                                Modifier
                                    .fillMaxWidth()
                                    .height((76 * (d.answers.toFloat() / maxAnswers)).dp.coerceAtLeast(3.dp))
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(if (d.answers > 0) p.jade.copy(alpha = 0.75f) else p.track)
                            )
                        }
                        Spacer(Modifier.height(6.dp))
                        Text(d.label, fontSize = 11.sp, color = p.ink3)
                    }
                }
            }
        }

        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun StatCell(num: String, label: String, modifier: Modifier = Modifier) {
    val p = LocalPalette.current
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(num, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = p.ink1)
        Spacer(Modifier.height(2.dp))
        Text(label, fontSize = 11.sp, color = p.ink3)
    }
}

@Composable
private fun ActionCard(
    emoji: String,
    title: String,
    desc: String,
    badge: Int,
    modifier: Modifier = Modifier,
    /** 这一项现在能不能点。不能点时整张卡变淡，而不是「看起来能点、点了没反应」 */
    enabled: Boolean = true,
    /** 模式色，用于描边。与 iOS 的 modeCard(color:) 对应 */
    accent: androidx.compose.ui.graphics.Color? = null,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    // 尺寸与 iOS modeCard 对齐：radiusCard 20、padding 16、emoji 28、标题 16 bold。
    // 原来是 radiusInner 14 / padding 14 / emoji 22 / 标题 14——练习页是入口页，
    // 卡片做得比其他页小一号，点起来也更容易点错。
    val dim = if (enabled) 1f else 0.5f
    Surface(
        modifier
            .clip(RoundedCornerShape(Dimens.radiusCard.dp))
            .clickable(enabled = enabled, onClick = onClick),
        shape = RoundedCornerShape(Dimens.radiusCard.dp),
        color = p.card,
        // 描边用模式色 35%：练习页有八九张卡并排，全都一个灰边时
        // 分不清哪张是哪张；淡彩边让人一眼认出「错题本是红的、多音字是橙的」
        border = BorderStroke(
            1.dp,
            if (enabled) (accent ?: p.line).copy(alpha = 0.35f) else p.line
        )
    ) {
        Box(Modifier.graphicsLayer(alpha = dim)) {
            Column(Modifier.padding(16.dp)) {
                Text(emoji, fontSize = 28.sp)
                Spacer(Modifier.height(9.dp))
                Text(
                    title,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = p.ink1
                )
                Spacer(Modifier.height(2.dp))
                Text(desc, fontSize = FontSizes.caption.sp, color = p.ink3)
            }
            if (badge > 0) {
                Box(
                    Modifier
                        .align(Alignment.TopEnd)
                        .padding(8.dp)
                        .clip(CircleShape)
                        .background(p.clay)
                        .padding(horizontal = 6.dp, vertical = 1.dp)
                ) {
                    Text("$badge", fontSize = 10.sp, color = Color.White)
                }
            }
        }
    }
}

@Composable
private fun BookChip(
    bookId: String,
    short: String,
    learned: Int,
    total: Int,
    active: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    val color = HanziColors.bookColor(bookId)
    Surface(
        modifier
            .testTag("practice-book-$bookId")
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(12.dp),
        color = if (active) p.jadeSoft else p.card,
        border = BorderStroke(1.dp, if (active) p.jade.copy(alpha = 0.5f) else p.line)
    ) {
        Column(
            Modifier.padding(vertical = 9.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                short,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (active) p.jadeDeep else p.ink1
            )
            Spacer(Modifier.height(2.dp))
            Text(
                "$learned/$total",
                fontSize = 10.sp,
                color = if (learned > 0) color.copy(alpha = 0.9f) else p.ink3.copy(alpha = 0.55f)
            )
        }
    }
}
