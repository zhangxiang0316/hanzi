package com.xiaoxiao.hanzi.ui.pages

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.data.StrokeCodec
import com.xiaoxiao.hanzi.logic.Tts
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.BtnStyle
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.HanziButton
import com.xiaoxiao.hanzi.ui.HanziColors
import com.xiaoxiao.hanzi.ui.HanziPainter
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.Screen
import com.xiaoxiao.hanzi.ui.Stars
import com.xiaoxiao.hanzi.ui.TinyPill
import kotlinx.coroutines.delay

/**
 * 认识这个字：笔顺动画 / 笔画定格 / 组词 / 多音字 / 上下字翻页。
 * 对应小程序 packageStrokes/pages/detail/detail。
 *
 * 小程序侧这一页踩过的两个坑，在 Compose 里从根上不会重现：
 *   1. 「点击笔顺后文字变大显示不全」—— 预览画布复用时把 canvas 的
 *      width/height 属性抹掉了，导致内部坐标系放大。这里 Canvas 的尺寸
 *      由 Compose 布局系统给定，绘制时按 size 现算，不存在残留属性。
 *   2. 「点某一笔却把整个字显示出来」—— 定格用的是 data.n（已写笔数），
 *      而不是被点的那一笔。这里用 frozenStroke 单独存，且定格后停掉动画。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DetailPage(app: AppState, ch: String, lessonId: String?) {
    val p = LocalPalette.current
    val scroll = rememberScrollState()
    app.revision

    val meta = Repo.meta(ch) ?: return
    val strokes = remember(ch) { Repo.strokes(ch) }
    val chars = Repo.lessonChars(lessonId).ifEmpty { Repo.bookChars(meta.book) }
    val idx = chars.indexOf(ch)
    val hasPrev = idx > 0
    val hasNext = idx >= 0 && idx < chars.size - 1
    val learned = app.progress.hasLearned(ch)
    val showPinyin = app.progress.settings.showPinyin

    var showNumbers by remember(ch) { mutableStateOf(false) }
    /** -1 表示正在自动按笔顺书写；>=0 表示定格在第 n 笔 */
    var frozenStroke by remember(ch) { mutableIntStateOf(-1) }
    /** 已写好的笔画数（自动播放时递增） */
    var written by remember(ch) { mutableIntStateOf(0) }
    /** 动画开关：每次点「再写一遍」自增，重新触发 LaunchedEffect */
    var playToken by remember(ch) { mutableIntStateOf(0) }

    val count = strokes?.count ?: 0

    // 进页面就预热 TTS 引擎（异步初始化几十到几百毫秒），
    // 免得第一次点朗读要等，也顺便尽早发现「没有中文语音包」
    LaunchedEffect(Unit) { app.tts.warmUp() }

    // 订阅朗读状态：初始化是异步的，必须真的订阅，否则「读完才变成不可用」
    // 这种情况界面不会更新，用户点了没声音还看不到任何说明
    var ttsState by remember(app.tts) { mutableStateOf(app.tts.state) }
    DisposableEffect(app.tts) {
        ttsState = app.tts.state
        val remove = app.tts.addListener { ttsState = it }
        onDispose { remove() }
    }

    // 自动书写动画：一笔一笔写。定格时立即停。
    LaunchedEffect(ch, playToken, frozenStroke) {
        if (frozenStroke >= 0) return@LaunchedEffect
        written = 0
        if (count == 0) return@LaunchedEffect
        delay(220)
        for (i in 1..count) {
            written = i
            delay(HanziPainter.PER_STROKE_MS + HanziPainter.STROKE_GAP_MS)
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(scroll)
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        Spacer(Modifier.height(6.dp))

        // 顶栏：返回本课 + 计数
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                Repo.lessonLabel(lessonId ?: meta.lesson),
                fontSize = 13.sp,
                color = p.jade,
                fontWeight = FontWeight.Medium,
                modifier = Modifier
                    .weight(1f)
                    .clickable {
                        val target = lessonId ?: meta.lesson
                        if (target.isNotEmpty()) {
                            app.nav.back()
                            app.nav.push(Screen.Lesson(target))
                        }
                    }
            )
            Text("${idx + 1} / ${chars.size}", fontSize = 12.sp, color = p.ink3)
        }

        Spacer(Modifier.height(12.dp))

        // 主画布
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .testTag("detail-canvas")
                .clip(RoundedCornerShape(20.dp))
                .background(p.card),
            contentAlignment = Alignment.Center
        ) {
            if (strokes != null) {
                Canvas(Modifier.fillMaxSize().padding(6.dp)) {
                    val box = minOf(size.width, size.height)
                    val ox = (size.width - box) / 2f
                    val oy = (size.height - box) / 2f
                    drawIntoCanvas { c ->
                        HanziPainter.drawGrid(c.nativeCanvas, box, ox, oy)
                        if (frozenStroke >= 0) {
                            // 定格：前面的笔正常画，被点的这一笔用主题色高亮
                            HanziPainter.drawStrokes(
                                c.nativeCanvas, strokes, box, ox, oy,
                                completed = frozenStroke, showGhost = true
                            )
                            HanziPainter.drawStrokeHighlight(
                                c.nativeCanvas, strokes, frozenStroke, box, ox, oy
                            )
                            HanziPainter.drawStrokeNumbers(
                                c.nativeCanvas, strokes, box, ox, oy, onlyIndex = frozenStroke
                            )
                        } else {
                            HanziPainter.drawStrokes(
                                c.nativeCanvas, strokes, box, ox, oy, completed = written
                            )
                            if (showNumbers) {
                                HanziPainter.drawStrokeNumbers(c.nativeCanvas, strokes, box, ox, oy)
                            }
                        }
                    }
                }
            } else {
                Text("暂无笔顺数据", fontSize = 14.sp, color = p.ink3)
            }
        }

        Spacer(Modifier.height(12.dp))

        // 工具条
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ToolChip(
                icon = "🔊",
                label = "朗读",
                on = false,
                modifier = Modifier.weight(1f).testTag("btn-speak")
            ) {
                app.tts.speak(ch)
            }
            ToolChip(
                icon = "①",
                label = "笔顺",
                on = showNumbers,
                modifier = Modifier.weight(1f)
            ) {
                showNumbers = !showNumbers
                frozenStroke = -1
            }
            ToolChip(
                icon = "↻",
                label = "再写一遍",
                on = false,
                modifier = Modifier.weight(1f)
            ) {
                frozenStroke = -1
                playToken++
            }
        }

        // 设备没有中文语音包时常驻提示：不能让「点了没声音」还查不出原因
        Tts.unavailableHint(ttsState)?.let { hint ->
            Spacer(Modifier.height(8.dp))
            Text(hint, fontSize = 11.sp, color = p.clay, modifier = Modifier.testTag("tts-hint"))
        }

        Spacer(Modifier.height(16.dp))

        // 拼音 / 标签
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                Repo.readingFor(ch, lessonId ?: meta.lesson),
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                color = p.jade
            )
            Spacer(Modifier.width(8.dp))
            if ((meta.readings?.size ?: 0) > 1) {
                TinyPill("多音字", HanziColors.amber)
            }
            if (learned) {
                Spacer(Modifier.width(6.dp))
                TinyPill("已学", p.jade)
            }
        }

        Spacer(Modifier.height(12.dp))

        // 部首 / 笔画 / 读音
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            AttrBox("部首", meta.radical, Modifier.weight(1f))
            AttrBox("笔画", "${meta.strokes}", Modifier.weight(1f))
            AttrBox(
                "读音",
                Repo.readingsOf(ch).joinToString(" "),
                Modifier.weight(1f),
                small = true
            )
        }

        // 笔画条：多的字换行，不做横向滚动
        if (count > 1) {
            Spacer(Modifier.height(16.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("按笔顺写", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = p.ink1)
                Spacer(Modifier.weight(1f))
                Text("点数字看这一笔", fontSize = 11.sp, color = p.ink3)
            }
            Spacer(Modifier.height(8.dp))
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(7.dp),
                verticalArrangement = Arrangement.spacedBy(7.dp)
            ) {
                repeat(count) { i ->
                    val on = frozenStroke == i
                    Box(
                        Modifier
                            .size(32.dp)
                            .clip(CircleShape)
                            .background(if (on) p.jade else p.card)
                            .clickable {
                                // 再点一次同一笔 -> 取消定格，回到自动播放
                                if (frozenStroke == i) {
                                    frozenStroke = -1
                                    playToken++
                                } else {
                                    frozenStroke = i
                                }
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            "${i + 1}",
                            fontSize = 12.sp,
                            fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                            color = if (on) Color.White else p.ink2
                        )
                    }
                }
            }
        }

        // 组词
        if (meta.words.isNotEmpty()) {
            Spacer(Modifier.height(18.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("组词", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = p.ink1)
                Spacer(Modifier.weight(1f))
                Text("点一下听读音", fontSize = 11.sp, color = p.ink3)
            }
            Spacer(Modifier.height(8.dp))
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                meta.words.take(8).forEach { w ->
                    Surface(
                        modifier = Modifier
                            .clip(RoundedCornerShape(12.dp))
                            .clickable { app.tts.speak(w.word) }
                            .testTag("word-${w.word}"),
                        shape = RoundedCornerShape(12.dp),
                        color = p.card,
                        border = BorderStroke(1.dp, p.line)
                    ) {
                        Column(
                            Modifier.padding(horizontal = 14.dp, vertical = 9.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(w.word, fontSize = 16.sp, color = p.ink1)
                            if (showPinyin && w.pinyin.isNotEmpty()) {
                                Text(w.pinyin, fontSize = 10.sp, color = p.ink3)
                            }
                        }
                    }
                }
            }
        }

        // 其他读音
        val readings = meta.readings
        if (readings != null && readings.size > 1) {
            Spacer(Modifier.height(18.dp))
            Text("这个字的其他读音", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = p.ink1)
            Spacer(Modifier.height(8.dp))
            readings.forEach { r ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(r.pinyin, fontSize = 15.sp, color = p.jade, fontWeight = FontWeight.Medium)
                    Spacer(Modifier.width(12.dp))
                    Text(
                        Repo.lessonLabel(r.lesson),
                        fontSize = 12.sp,
                        color = p.ink3,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }

        // 描红成绩
        val record = app.progress.writeRecord(ch)
        if (record != null) {
            Spacer(Modifier.height(14.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("描红最好成绩", fontSize = 12.sp, color = p.ink3)
                Spacer(Modifier.width(8.dp))
                Stars(record.stars)
                Spacer(Modifier.width(6.dp))
                Text("${record.best} 分", fontSize = 12.sp, color = p.ink2)
            }
        }

        Spacer(Modifier.height(18.dp))

        // 操作区
        HanziButton("描红跟写", style = BtnStyle.Primary, tag = "btn-write") {
            app.nav.push(Screen.Write(ch))
        }
        Spacer(Modifier.height(9.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            Box(Modifier.weight(1f)) {
                HanziButton("练这个字", style = BtnStyle.Ghost) {
                    app.nav.push(Screen.Quiz("single", meta.book, lessonId ?: meta.lesson))
                }
            }
            Box(Modifier.weight(1f)) {
                HanziButton(
                    if (learned) "已学会 ✓" else "我认识它了",
                    style = BtnStyle.Soft
                ) {
                    if (!learned) {
                        app.progress.markKnown(ch)
                        app.touch()
                    }
                }
            }
        }

        Spacer(Modifier.height(16.dp))

        // 上下字翻页
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PagerButton("‹ 上一个", hasPrev, Modifier.weight(1f)) {
                if (hasPrev) app.nav.replace(Screen.Detail(chars[idx - 1], lessonId))
            }
            PagerButton("下一个 ›", hasNext, Modifier.weight(1f)) {
                if (hasNext) app.nav.replace(Screen.Detail(chars[idx + 1], lessonId))
            }
        }

        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun ToolChip(
    icon: String,
    label: String,
    on: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    Surface(
        modifier
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(12.dp),
        color = if (on) p.jadeSoft else p.card,
        border = BorderStroke(1.dp, if (on) p.jade.copy(alpha = 0.5f) else p.line)
    ) {
        Row(
            Modifier.padding(vertical = 10.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(icon, fontSize = 14.sp, color = if (on) p.jadeDeep else p.ink2)
            Spacer(Modifier.width(6.dp))
            Text(
                label,
                fontSize = 13.sp,
                color = if (on) p.jadeDeep else p.ink2,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

@Composable
private fun AttrBox(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    small: Boolean = false
) {
    val p = LocalPalette.current
    Column(
        modifier
            .clip(RoundedCornerShape(12.dp))
            .background(p.card)
            .padding(vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(label, fontSize = 10.sp, color = p.ink3)
        Spacer(Modifier.height(3.dp))
        Text(
            value,
            fontSize = if (small) 11.sp else 17.sp,
            fontWeight = FontWeight.SemiBold,
            color = p.ink1,
            maxLines = 1,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun PagerButton(
    text: String,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    Box(
        modifier
            .clip(RoundedCornerShape(12.dp))
            .background(p.card)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 12.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text,
            fontSize = 14.sp,
            color = if (enabled) p.ink1 else p.ink3.copy(alpha = 0.45f),
            fontWeight = FontWeight.Medium
        )
    }
}
