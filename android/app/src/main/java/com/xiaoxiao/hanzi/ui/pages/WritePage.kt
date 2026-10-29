package com.xiaoxiao.hanzi.ui.pages

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.toSize
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.data.StrokeCodec
import com.xiaoxiao.hanzi.logic.DayUtil
import com.xiaoxiao.hanzi.logic.Trace
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.BtnStyle
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.HanziButton
import com.xiaoxiao.hanzi.ui.HanziPainter
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.Screen
import com.xiaoxiao.hanzi.ui.Stars

/**
 * 描红跟写：逐笔临摹 + 实时评分。
 * 对应小程序 packageStrokes/pages/write/write。
 *
 * 交互要点（都是小程序阶段调出来的手感，这里原样保留）：
 *   - 一笔写完立刻判分，不合格就提示「再来一次」，不强制
 *   - 起点/终点偏差单独降分，避免「从反方向倒着画」也过关
 *   - ACCEPT=42 低于这个分就退回重写该笔
 */
@Composable
fun WritePage(app: AppState, ch: String) {
    val p = LocalPalette.current
    app.revision

    val strokes = remember(ch) { Repo.strokes(ch) }
    val meta = Repo.meta(ch)
    val count = strokes?.count ?: 0
    val lessonId = meta?.lesson

    /** 当前正在写第几笔 */
    var strokeIndex by remember(ch) { mutableIntStateOf(0) }
    /** 已完成各笔的得分 */
    val scores = remember(ch) { mutableStateListOf<Int>() }
    /** 当前笔的用户笔迹（画布像素坐标） */
    val current = remember(ch) { mutableStateListOf<Offset>() }
    /** 是否正在按下 */
    var drawing by remember(ch) { mutableStateOf(false) }
    /** 提示：显示当前笔的示范 */
    var hintOn by remember(ch) { mutableStateOf(false) }
    /** 上一笔没通过的原因，显示在提示条上；再下笔时清空 */
    var failure by remember(ch) { mutableStateOf("") }
    /** 完成后弹层 */
    var done by remember(ch) { mutableStateOf(false) }
    var finalScore by remember(ch) { mutableIntStateOf(0) }
    var finalStars by remember(ch) { mutableIntStateOf(0) }
    /**
     * 画布几何。绘制时写入、评分时读取，两者共用同一份，
     * 从根上避免小程序里那种「坐标空间不一致导致评分错位」的问题。
     */
    val geom = remember(ch) { Geom() }
    val density = androidx.compose.ui.platform.LocalDensity.current

    val targetMedian = remember(ch, strokeIndex) {
        if (strokes == null || strokeIndex >= count) FloatArray(0)
        else strokes.medians[strokeIndex]
    }

    val hint = when {
        count == 0 -> "这个字暂时没有笔顺数据"
        done -> "写完啦，看看得了几分"
        failure.isNotEmpty() -> failure
        current.isNotEmpty() -> "写完这一笔，会自动打分"
        strokeIndex == 0 -> "从第 1 笔开始，按笔顺写"
        else -> "第 ${strokeIndex + 1} 笔：照着虚线写"
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        Spacer(Modifier.height(8.dp))

        // 头部：字 + 读音 + 当前笔 + 实时分
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(54.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(p.cardWarm),
                contentAlignment = Alignment.Center
            ) { Text(ch, fontSize = 30.sp, color = p.ink1) }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    Repo.readingFor(ch, lessonId),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = p.jade
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    "${meta?.radical ?: ""} · $count 笔 · 第 ${minOf(strokeIndex + 1, count)} 笔",
                    fontSize = 11.sp,
                    color = p.ink3
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    if (scores.isEmpty()) "—" else "${scores.average().toInt()}",
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    color = p.jade
                )
                Text("分", fontSize = 10.sp, color = p.ink3)
            }
        }

        Spacer(Modifier.height(12.dp))

        // 进度点
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            repeat(count) { i ->
                Box(
                    Modifier
                        .weight(1f)
                        .height(4.dp)
                        .clip(CircleShape)
                        .background(
                            when {
                                i < strokeIndex || done -> p.jade
                                i == strokeIndex -> p.jade.copy(alpha = 0.45f)
                                else -> p.track
                            }
                        )
                )
            }
        }

        Spacer(Modifier.height(12.dp))

        // 画布
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .clip(RoundedCornerShape(20.dp))
                .background(p.card)
                .testTag("write-canvas")
                // 画布几何（边长 + 居中偏移）在「布局」阶段就确定下来。
                // 早先写在绘制 lambda 里，依赖「先画后摸」的顺序：
                // 单测/无障碍等场景下没有绘制过程，评分就会因为 box=0 而静默失效。
                .onSizeChanged { sz -> geom.update(sz.width, sz.height, density) }
                .pointerInput(ch, strokeIndex, done) {
                    if (done || count == 0) return@pointerInput
                    // 不用 detectDragGestures：它要等超过触摸滑动阈值才回调 onDragStart，
                    // 笔画开头的几毫米会被丢掉（小程序用 touchstart 记录起点，没有这个损失）。
                    // 这里从按下那一刻就开始采样，并且立即消费事件，
                    // 避免外层 verticalScroll 把「写字」误判成「滚页」。
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        down.consume()
                        drawing = true
                        failure = ""
                        current.clear()
                        current.add(down.position)

                        var pointerId = down.id
                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == pointerId } ?: break
                            if (change.pressed) {
                                change.consume()
                                current.add(change.position)
                            } else {
                                change.consume()
                                break
                            }
                        }

                        drawing = false
                        // 一笔结束：评分。用户坐标与绘制坐标共用 geom，
                        // 不存在小程序里那套 dpr 换算误差
                        val userPts = FloatArray(current.size * 2)
                        current.forEachIndexed { i, o ->
                            userPts[i * 2] = o.x
                            userPts[i * 2 + 1] = o.y
                        }
                        // 只点了一下、或者划得太短：不算数，但一定要说清楚。
                        // 早先这里什么都不做，孩子会以为「写了没反应」——
                        // 而点（点画）恰恰经常是最后一笔，于是就成了「最后一笔写不上」。
                        if (current.size < 2 || Trace.polylineLength(userPts) < geom.box * 0.04f) {
                            current.clear()
                            failure = "这一笔太短了，沿着虚线完整写一遍"
                        } else if (geom.box > 0f) {
                            val target = medianInPixels(strokes, strokeIndex, geom)
                            // 容差按画布边长取比例，和屏幕大小/密度无关
                            val r = Trace.scoreStroke(userPts, target, geom.box * 0.075f)
                            if (r.score >= Trace.ACCEPT) {
                                scores.add(r.score)
                                current.clear()
                                failure = ""
                                if (strokeIndex + 1 >= count) {
                                    finish(strokes, scores, ch, app) { sc, stars ->
                                        finalScore = sc
                                        finalStars = stars
                                        done = true
                                    }
                                } else {
                                    strokeIndex += 1
                                }
                            } else {
                                // 不达标：清空这一笔让用户重写，并说明原因
                                current.clear()
                                failure = reasonText(r.reason)
                            }
                        }
                    }
                }
        ) {
            Canvas(Modifier.fillMaxSize().padding(6.dp)) {
                // 与触摸评分共用同一份几何，绘制与评分不可能错位
                val box = geom.box
                val ox = geom.ox - 6.dp.toPx()
                val oy = geom.oy - 6.dp.toPx()

                drawIntoCanvas { c ->
                    HanziPainter.drawGrid(c.nativeCanvas, box, ox, oy)

                    // 底字：淡灰描红参照
                    HanziPainter.drawGhostChar(c.nativeCanvas, ch, box, ox, oy)

                    if (strokes != null) {
                        // 写完最后一笔时 strokeIndex 不再自增（改为置 done），
                        // 所以这里必须显式处理 done，否则最后一笔会一直停在虚线提示状态，
                        // 看起来就像「最后一笔没写上去」。
                        HanziPainter.drawStrokes(
                            c.nativeCanvas, strokes, box, ox, oy,
                            completed = if (done) strokes.count else minOf(strokeIndex, strokes.count),
                            showGhost = false
                        )
                        // 当前笔的中线虚线（提示）：全部写完就不再画
                        if (!done && strokeIndex < strokes.count) {
                            val pts = HanziPainter.medianPoints(strokes.medians[strokeIndex], box, ox, oy)
                            val path = Path()
                            if (pts.size >= 2) {
                                path.moveTo(pts[0], pts[1])
                                var i = 2
                                while (i < pts.size) {
                                    path.lineTo(pts[i], pts[i + 1])
                                    i += 2
                                }
                            }
                            drawPath(
                                path,
                                color = if (hintOn) Color(HanziPainter.ACCENT) else Color(HanziPainter.HINT),
                                style = Stroke(
                                    width = if (hintOn) 4f else 2f,
                                    cap = StrokeCap.Round,
                                    join = StrokeJoin.Round
                                )
                            )
                            // 起点圆点：告诉孩子从哪起笔
                            if (pts.size >= 2) {
                                drawCircle(
                                    color = Color(HanziPainter.ACCENT),
                                    radius = maxOf(box * 0.022f, 5f),
                                    center = Offset(pts[0], pts[1])
                                )
                            }
                        }
                    }
                }

                // 用户笔迹
                if (current.size >= 2) {
                    val path = Path()
                    path.moveTo(current[0].x, current[0].y)
                    for (i in 1 until current.size) path.lineTo(current[i].x, current[i].y)
                    drawPath(
                        path,
                        color = Color(HanziPainter.INK),
                        style = Stroke(
                            width = maxOf(geom.box * 0.09f, 10f),
                            cap = StrokeCap.Round,
                            join = StrokeJoin.Round
                        )
                    )
                }
            }
        }

        Spacer(Modifier.height(10.dp))

        // 提示条
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(6.dp)
                    .clip(CircleShape)
                    .background(if (failure.isNotEmpty() && !done) p.clay else p.jade)
            )
            Spacer(Modifier.width(7.dp))
            Text(
                hint,
                fontSize = 12.sp,
                color = if (failure.isNotEmpty() && !done) p.ink1 else p.ink2
            )
        }

        Spacer(Modifier.height(12.dp))

        // 工具
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            WritTool("💡", "看这一笔", Modifier.weight(1f)) { hintOn = !hintOn }
            WritTool("↩️", "退一笔", Modifier.weight(1f)) {
                if (done) {
                    // 完成时 strokeIndex 停在最后一笔上（不再自增），
                    // 退回时要保留它，否则会跳过最后一笔。
                    done = false
                    if (scores.isNotEmpty()) scores.removeAt(scores.size - 1)
                    current.clear()
                    failure = ""
                } else if (strokeIndex > 0) {
                    strokeIndex -= 1
                    if (scores.isNotEmpty()) scores.removeAt(scores.size - 1)
                    current.clear()
                    failure = ""
                }
            }
            WritTool("🧽", "擦掉重写", Modifier.weight(1f)) {
                strokeIndex = 0
                scores.clear()
                current.clear()
                done = false
                hintOn = false
                failure = ""
            }
        }

        Spacer(Modifier.height(20.dp))

        // 完成弹层（用内联卡片代替 Dialog，保证能跟着页面滚，小屏不被键盘/导航栏遮挡）
        if (done) {
            Surface(
                Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Dimens.radiusCard.dp),
                color = p.card,
                shadowElevation = 6.dp
            ) {
                Column(
                    Modifier.padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        if (finalStars >= 2) "写得真棒！" else "完成啦！",
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = p.ink1
                    )
                    Spacer(Modifier.height(10.dp))
                    Text(ch, fontSize = 52.sp, color = p.ink1)
                    Spacer(Modifier.height(8.dp))
                    Stars(finalStars, size = 22)
                    Spacer(Modifier.height(6.dp))
                    Text("得分 $finalScore 分", fontSize = 14.sp, color = p.ink2)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        when {
                            finalStars >= 3 -> "每一笔都很到位，继续保持！"
                            finalStars >= 2 -> "写得不错，再练一次会更工整"
                            else -> "别急，慢慢写，一笔一笔来"
                        },
                        fontSize = 12.sp,
                        color = p.ink3,
                        textAlign = TextAlign.Center
                    )
                    Spacer(Modifier.height(16.dp))
                    HanziButton("再写一次", style = BtnStyle.Primary) {
                        strokeIndex = 0
                        scores.clear()
                        current.clear()
                        done = false
                        failure = ""
                    }
                    Spacer(Modifier.height(8.dp))
                    Box(Modifier.fillMaxWidth()) {
                        HanziButton("下一个字", style = BtnStyle.Ghost) {
                            val next = Repo.nextInBook(meta?.book ?: Repo.defaultBook(), ch)
                            if (next.isNotEmpty()) app.nav.replace(Screen.Write(next))
                            else app.nav.back()
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun WritTool(
    emoji: String,
    label: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    Box(
        modifier
            .clip(RoundedCornerShape(12.dp))
            .background(p.card)
            .clickable(onClick = onClick)
            .padding(vertical = 11.dp),
        contentAlignment = Alignment.Center
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(emoji, fontSize = 13.sp)
            Spacer(Modifier.width(5.dp))
            Text(label, fontSize = 13.sp, color = p.ink2)
        }
    }
}

/**
 * 一笔没过关时给孩子的说明。
 * 文案与小程序 utils/write-page.js 的 reasonText 一致，
 * 同一套评分原因，两端的提示不能各说各的。
 */
private fun reasonText(reason: String): String = when (reason) {
    "start" -> "起笔的位置不对，从红色小点开始写"
    "short" -> "这一笔还没有写完整，再拉长一点"
    "off" -> "偏离了笔画，沿着淡淡的那一笔写"
    else -> "再试一次，慢慢写会更准"
}

/**
 * 画布几何：边长 + 居中偏移，绘制与评分共用。
 *
 * 由 onSizeChanged 在布局阶段填充（不依赖绘制顺序），
 * 绘制时直接读取，所以「画在哪」和「按哪判分」永远是同一套坐标。
 */
private class Geom {
    /** 田字格边长（px） */
    var box: Float = 0f
    /** 田字格左上角相对画布节点的偏移（px，已含内边距） */
    var ox: Float = 0f
    var oy: Float = 0f

    fun update(w: Int, h: Int, density: androidx.compose.ui.unit.Density) {
        val pad = with(density) { 6.dp.toPx() }
        val side = minOf(w, h).toFloat()
        box = (side - pad * 2).coerceAtLeast(1f)
        ox = (w - side) / 2f + pad
        oy = (h - side) / 2f + pad
    }
}

/**
 * 把某一笔的中线从 1024 坐标系换算到画布像素坐标。
 * 与 HanziPainter 里的 px() 必须完全一致，否则评分会错位。
 */
private fun medianInPixels(
    strokes: StrokeCodec.CharStrokes?,
    index: Int,
    geom: Geom
): FloatArray {
    if (strokes == null || index >= strokes.count || geom.box <= 0f) return FloatArray(0)
    return HanziPainter.medianPoints(strokes.medians[index], geom.box, geom.ox, geom.oy)
}

/** 整字完成：平均分 + 存成绩 */
private fun finish(
    strokes: StrokeCodec.CharStrokes?,
    scores: List<Int>,
    ch: String,
    app: AppState,
    cb: (Int, Int) -> Unit
) {
    val r = Trace.scoreChar(scores.toList())
    app.progress.saveWrite(ch, r.score)
    app.touch()
    cb(r.score, r.stars)
}
