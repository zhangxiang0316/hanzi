package com.xiaoxiao.hanzi.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.xiaoxiao.hanzi.data.Repo
import kotlin.math.max
import kotlin.math.min
import androidx.compose.ui.unit.sp

/**
 * 通用组件。
 *
 * 小程序里这些是 WXSS 的类（.card / .btn-primary / .chip），
 * 搬到 Compose 就变成 @Composable 函数，命名保持一致方便对照。
 */

/**
 * 卡片。
 *
 * 描边色和留白都与 iOS `HanziCard` 对齐：
 * - 边框用 `edge` 而不是 `line`。`line` 和纸底的对比度只有 1.23:1，
 *   做分隔线可以，但作为一张卡的边界等于没画（iOS 端早已改用 edge，
 *   Android 一直用 line@80%，两端卡片在屏幕上的「实感」不一样）。
 * - 内边距 16 → 18，与 iOS 一致。
 */
@Composable
fun HanziCard(
    modifier: Modifier = Modifier,
    padding: Int = 18,
    /**
     * 描边色。默认 `edge`。
     *
     * 有些卡需要自己的强调色（练习页每个模式一张卡，用模式色 35% 区分
     * 错题本/多音字/形近字）。但**形状、圆角、内边距、底色仍然必须
     * 由 HanziCard 统一**——只放开颜色这一个自由度，卡片样式就不会分叉。
     */
    borderColor: Color? = null,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit
) {
    val p = LocalPalette.current
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Dimens.radiusCard.dp),
        color = p.card,
        border = BorderStroke(1.dp, borderColor ?: p.edge)
    ) {
        Column(Modifier.padding(padding.dp), content = content)
    }
}

/**
 * 按钮三档，与 iOS `HanziButton.Kind` 一一对应：
 *
 * | 这里 | iOS | 外观 |
 * | --- | --- | --- |
 * | `Primary` | `.primary` | jade 底、白字 |
 * | `Secondary` | `.secondary` | 白底 + `edge` 描边 + ink1 字 |
 * | `Ghost` | `.ghost` | 透明、jade 字、无描边 |
 *
 * 早先 Android 这三档的含义和 iOS 对不上：`Soft` 是 jadeSoft 水底色、
 * 无描边（iOS 的 secondary 是白底 + 描边），`Ghost` 反而带 `line` 描边、
 * ink2 字（iOS 的 ghost 是无描边 jade 字）。同一个「次要按钮」在两端
 * 长得完全不一样。
 */
enum class BtnStyle { Primary, Secondary, Ghost }

/**
 * 按钮。
 *
 * 小程序踩过的坑：`button.btn { background: transparent }` 的优先级压过了
 * `.btn-primary`，导致一堆按钮变成白底白字、完全看不见。
 * 这里用单一函数 + 显式配色，从根本上不可能出现「底色和文字同色」。
 */
@Composable
fun HanziButton(
    text: String,
    modifier: Modifier = Modifier,
    style: BtnStyle = BtnStyle.Primary,
    enabled: Boolean = true,
    fillWidth: Boolean = true,
    /** 测试用标记，方便按几何位置断言按钮本身而不是里面的文字 */
    tag: String? = null,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    // 禁用态：iOS 是整颗按钮 opacity 0.45，这里用同义做法（底色和字色一起变淡），
    // 而不是把底色换成灰——换灰会让人以为这是另一种按钮。
    val dim = if (enabled) 1f else 0.45f
    val bg = when (style) {
        BtnStyle.Primary -> p.jade.copy(alpha = dim)
        BtnStyle.Secondary -> p.card
        BtnStyle.Ghost -> Color.Transparent
    }
    val fg = when (style) {
        BtnStyle.Primary -> Color.White.copy(alpha = dim)
        BtnStyle.Secondary -> p.ink1.copy(alpha = dim)
        BtnStyle.Ghost -> p.jade.copy(alpha = dim)
    }
    Surface(
        modifier = modifier
            .then(if (fillWidth) Modifier.fillMaxWidth() else Modifier)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .clip(RoundedCornerShape(Dimens.radiusInner.dp))
            .clickable(enabled = enabled, onClick = onClick),
        shape = RoundedCornerShape(Dimens.radiusInner.dp),
        color = bg,
        // 只有 secondary 描边，且用 edge（line 太浅，做按钮边界等于没画）
        border = if (style == BtnStyle.Secondary) BorderStroke(1.dp, p.edge) else null
    ) {
        Box(
            Modifier
                // 44 而不是 48：iOS 是上下 padding 13 + 15pt 字 = 44，
                // 两端按钮高度差 4dp，并排出现时一眼能看出来
                .height(44.dp)
                .then(if (fillWidth) Modifier.fillMaxWidth() else Modifier)
                .padding(horizontal = 20.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text,
                fontSize = FontSizes.body.sp,
                fontWeight = FontWeight.SemiBold,
                color = fg,
                textAlign = TextAlign.Center,
                maxLines = 1
            )
        }
    }
}

/**
 * 进度条，对应小程序 .progress / .progress-fill。
 *
 * 宽度从 0 缓动到目标值：孩子刚学几个字时进度只有几个百分点，直接静态画出来
 * 就是一条几乎看不见的细线，动一下才看得出「在涨」。动画只跑一次，不循环。
 */
@Composable
fun ProgressBar(
    pct: Int,
    modifier: Modifier = Modifier,
    color: Color = LocalPalette.current.jade,
    height: Int = 8,
    animated: Boolean = true
) {
    val p = LocalPalette.current
    val target = (pct.coerceIn(0, 100)) / 100f
    // 关掉动画时（截图、纯几何断言）直接给终值，省掉等待
    val fill = remember { Animatable(if (animated) 0f else target) }

    LaunchedEffect(target, animated) {
        if (animated) {
            fill.animateTo(target, tween(Motion.PROGRESS, easing = Motion.EaseOut))
        } else {
            fill.snapTo(target)
        }
    }

    Box(
        modifier
            .fillMaxWidth()
            .height(height.dp)
            .clip(CircleShape)
            .background(p.track)
            .testTag("pb-track")
    ) {
        Box(
            Modifier
                .testTag("pb-fill")
                .fillMaxWidth(fill.value)
                .height(height.dp)
                .clip(CircleShape)
                .background(color)
        )
    }
}

/**
 * 单笔字形：其余笔浅色打底，目标笔用墨色。
 *
 * 对应 iOS 的 `StrokeGlyphView`。详情页的笔画表用这个而不是数字圆点——
 * 「第 3 笔」写成数字，孩子得先在脑子里把它换算成形状；直接画出来，
 * 看到的和要写的是同一个东西。
 */
@Composable
fun SingleStrokeGlyph(
    ch: String,
    index: Int,
    modifier: Modifier = Modifier,
    ghostColor: Color = LocalPalette.current.line
) {
    val p = LocalPalette.current
    val strokes = remember(ch) { Repo.strokes(ch) }
    if (strokes == null || index >= strokes.count) {
        Box(modifier, contentAlignment = Alignment.Center) {
            Text("${index + 1}", fontSize = 12.sp, color = p.ink2)
        }
        return
    }
    Canvas(modifier) {
        // 留 6dp 边，笔画贴边会被圆角切掉
        val box = minOf(size.width, size.height) - 6.dp.toPx()
        val ox = (size.width - box) / 2f
        val oy = (size.height - box) / 2f
        drawIntoCanvas { c ->
            HanziPainter.drawSingleStroke(
                c.nativeCanvas, strokes, index, box, ox, oy,
                inkColor = p.ink1.toArgb(),
                ghostColor = ghostColor.copy(alpha = 0.55f).toArgb()
            )
        }
    }
}

/**
 * 环形进度，对应 iOS 的 `ProgressRing`。
 *
 * 首页「总进度」在 iOS 是一个 84dp 的环、百分比嵌在环心；Android 一直是
 * 一条横向进度条 + 右边一个数字。同一个「学了百分之多少」，两端是两种
 * 完全不同的信息图。
 *
 * 轨道用 track、进度用主色、圆头收尾，参数与 iOS 一一对应。
 */
@Composable
fun ProgressRing(
    value: Double,
    modifier: Modifier = Modifier,
    size: Int = 84,
    lineWidth: Int = 9,
    color: Color = LocalPalette.current.jade,
    /** 环心内容，通常放百分比文字 */
    content: @Composable () -> Unit = {}
) {
    val p = LocalPalette.current
    val target = max(0.001, min(1.0, value)).toFloat()
    // 与 iOS 的 .animation(.easeOut(duration: 0.5)) 同参数
    val sweep by animateFloatAsState(
        targetValue = target,
        animationSpec = tween(500, easing = LinearOutSlowInEasing),
        label = "ringSweep"
    )
    Box(
        modifier.size(size.dp).testTag("progress-ring"),
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.size(size.dp)) {
            val stroke = lineWidth.dp.toPx()
            val d = this.size.minDimension - stroke
            val topLeft = Offset((this.size.width - d) / 2f, (this.size.height - d) / 2f)
            drawArc(
                color = p.track,
                startAngle = 0f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = topLeft,
                size = Size(d, d),
                style = Stroke(stroke, cap = StrokeCap.Round)
            )
            // -90 起点：与 iOS 的 .rotationEffect(.degrees(-90)) 一致，从 12 点开始
            drawArc(
                color = color,
                startAngle = -90f,
                sweepAngle = 360f * sweep,
                useCenter = false,
                topLeft = topLeft,
                size = Size(d, d),
                style = Stroke(stroke, cap = StrokeCap.Round)
            )
        }
        content()
    }
}

/** 小标签，对应小程序里的 .pill / .chip */
@Composable
fun TinyPill(
    text: String,
    color: Color,
    modifier: Modifier = Modifier,
    bg: Color = color.copy(alpha = 0.13f)
) {
    Box(
        modifier
            .clip(RoundedCornerShape(999.dp))
            .background(bg)
            // 11sp / h9 v3 / α0.13，与 iOS TinyPill 一致
            .padding(horizontal = 9.dp, vertical = 3.dp)
    ) {
        Text(text, fontSize = 11.sp, color = color, fontWeight = FontWeight.SemiBold)
    }
}

/** 区块标题，对应 .section-head / .section-title */
@Composable
fun SectionHead(
    title: String,
    sub: String? = null,
    trailing: @Composable (() -> Unit)? = null
) {
    val p = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = 22.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                title,
                fontSize = FontSizes.sectionTitle.sp,
                fontWeight = FontWeight.SemiBold,
                color = p.ink1
            )
            if (sub != null) {
                Spacer(Modifier.height(2.dp))
                Text(sub, fontSize = 12.sp, color = p.ink3)
            }
        }
        trailing?.invoke()
    }
}

/** 空状态，对应 .empty */
@Composable
fun EmptyState(emoji: String, title: String, desc: String? = null, modifier: Modifier = Modifier) {
    val p = LocalPalette.current
    // 与 iOS EmptyState 对齐：emoji 42 / 标题 16 semibold ink1 / 说明 13 / 上下 36
    Column(
        modifier
            .fillMaxWidth()
            .padding(vertical = 36.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(emoji, fontSize = 42.sp)
        Spacer(Modifier.height(10.dp))
        Text(
            title,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = p.ink1,
            textAlign = TextAlign.Center
        )
        if (desc != null) {
            Spacer(Modifier.height(6.dp))
            Text(desc, fontSize = 13.sp, color = p.ink3, textAlign = TextAlign.Center)
        }
    }
}

/**
 * 星级，用于描红成绩与闯关结果。
 *
 * 三颗星错开时间逐个弹出，比「啪一下三颗全在」更有获得的感觉。
 * 用 keyframes 而不是 delay 来做错峰：keyframes 走帧时钟，测试里
 * waitForIdle 能稳定等它结束；delay 依赖协程调度，时序不好把控。
 */
@Composable
fun Stars(count: Int, size: Int = 16, animated: Boolean = true) {
    val p = LocalPalette.current
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        repeat(3) { i ->
            val filled = i < count
            val scale = remember { Animatable(1f) }

            LaunchedEffect(count, animated) {
                if (!animated || !filled) {
                    // 没拿到的星保持原样，不做任何强调
                    scale.snapTo(1f)
                    return@LaunchedEffect
                }
                val start = i * Motion.STAR_STAGGER
                scale.snapTo(0.3f)
                scale.animateTo(
                    1f,
                    keyframes {
                        durationMillis = start + Motion.STAR_POP
                        if (start > 0) {
                            0.3f at 0
                            0.3f at start
                        }
                        // 略微过冲再落回 1，像"弹"出来
                        1.12f at start + Motion.STAR_POP - 90
                    }
                )
            }

            Text(
                if (filled) "★" else "☆",
                fontSize = size.sp,
                color = if (filled) p.amber else p.line,
                modifier = Modifier.graphicsLayer {
                    scaleX = scale.value
                    scaleY = scale.value
                }
            )
        }
    }
}

/** 分隔线 */
@Composable
fun HairLine(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .height(1.dp)
            // 与 iOS HairLine 一致用 line：lineSoft 在白底卡上几乎看不见，
            // 分隔线就失去了意义
            .background(LocalPalette.current.line)
    )
}

/**
 * 「我的」页九行入口的小图标。
 *
 * iOS 用 SF Symbols（单色、跟随 tint），Android 这边没有图标库——
 * 引入 `material-icons-extended` 会给 APK 多塞几百 KB，和这个项目
 * 「零依赖、包体尽量小」的取舍冲突。
 *
 * 所以用 Canvas 画一组极简几何图标：只用直线、矩形、圆，
 * 线条统一 1.6dp、跟文字同色。风格上贴近 SF Symbols 的细线单色，
 * 而不用彩色 emoji——emoji 在两端根本对不上（同一个概念在
 * iOS/Android/各家 ROM 上长得都不一样）。
 */
enum class NavIcon { Chart, Ruler, Bubble, Grid, Pencil, Grid3, Book, Info, Trash }

@Composable
fun NavIconView(icon: NavIcon, tint: Color, size: Int = 20) {
    Canvas(Modifier.size(size.dp)) {
        val w = this.size.width
        val h = this.size.height
        val sw = 1.6.dp.toPx()
        val stroke = Stroke(width = sw, cap = StrokeCap.Round, join = StrokeJoin.Round)
        fun line(x1: Float, y1: Float, x2: Float, y2: Float) =
            drawLine(tint, Offset(x1 * w, y1 * h), Offset(x2 * w, y2 * h),
                strokeWidth = sw, cap = StrokeCap.Round)
        fun rect(x: Float, y: Float, rw: Float, rh: Float) =
            drawRoundRect(
                tint, Offset(x * w, y * h), Size(rw * w, rh * h),
                CornerRadius(sw), style = stroke
            )

        when (icon) {
            // 柱状图
            NavIcon.Chart -> {
                line(0.15f, 0.85f, 0.85f, 0.85f)
                line(0.3f, 0.85f, 0.3f, 0.55f)
                line(0.5f, 0.85f, 0.5f, 0.35f)
                line(0.7f, 0.85f, 0.7f, 0.48f)
            }
            // 尺子
            NavIcon.Ruler -> {
                rect(0.12f, 0.35f, 0.76f, 0.3f)
                line(0.32f, 0.35f, 0.32f, 0.5f)
                line(0.5f, 0.35f, 0.5f, 0.45f)
                line(0.68f, 0.35f, 0.68f, 0.5f)
            }
            // 感叹号气泡
            NavIcon.Bubble -> {
                rect(0.1f, 0.15f, 0.8f, 0.6f)
                line(0.35f, 0.75f, 0.28f, 0.9f)
                line(0.28f, 0.9f, 0.5f, 0.75f)
                line(0.5f, 0.3f, 0.5f, 0.5f)
                drawCircle(tint, radius = sw * 0.7f, center = Offset(0.5f * w, 0.62f * h))
            }
            // 2x2 网格
            NavIcon.Grid -> {
                rect(0.12f, 0.12f, 0.34f, 0.34f)
                rect(0.54f, 0.12f, 0.34f, 0.34f)
                rect(0.12f, 0.54f, 0.34f, 0.34f)
                rect(0.54f, 0.54f, 0.34f, 0.34f)
            }
            // 方框 + 铅笔
            NavIcon.Pencil -> {
                rect(0.1f, 0.25f, 0.62f, 0.65f)
                line(0.45f, 0.8f, 0.92f, 0.33f)
                line(0.45f, 0.8f, 0.6f, 0.88f)
            }
            // 3x3 网格
            NavIcon.Grid3 -> {
                for (i in 0..2) {
                    val x = 0.12f + i * 0.29f
                    line(x, 0.12f, x, 0.88f)
                    line(0.12f, x, 0.88f, x)
                }
            }
            // 打开的书
            NavIcon.Book -> {
                line(0.5f, 0.25f, 0.5f, 0.85f)
                line(0.12f, 0.25f, 0.5f, 0.3f)
                line(0.88f, 0.25f, 0.5f, 0.3f)
                line(0.12f, 0.25f, 0.12f, 0.8f)
                line(0.88f, 0.25f, 0.88f, 0.8f)
                line(0.12f, 0.8f, 0.5f, 0.85f)
                line(0.88f, 0.8f, 0.5f, 0.85f)
            }
            // 圆形信息
            NavIcon.Info -> {
                drawCircle(tint, radius = 0.4f * w,
                    center = Offset(0.5f * w, 0.5f * h), style = stroke)
                line(0.5f, 0.42f, 0.5f, 0.68f)
                drawCircle(tint, radius = sw * 0.7f, center = Offset(0.5f * w, 0.28f * h))
            }
            // 垃圾桶
            NavIcon.Trash -> {
                line(0.15f, 0.28f, 0.85f, 0.28f)
                line(0.4f, 0.28f, 0.4f, 0.18f)
                line(0.6f, 0.28f, 0.6f, 0.18f)
                line(0.4f, 0.18f, 0.6f, 0.18f)
                line(0.25f, 0.28f, 0.3f, 0.88f)
                line(0.75f, 0.28f, 0.7f, 0.88f)
                line(0.3f, 0.88f, 0.7f, 0.88f)
            }
        }
    }
}

/** 圆形图标按钮（返回键用） */
@Composable
fun RoundIconButton(onClick: () -> Unit, content: @Composable () -> Unit) {
    val p = LocalPalette.current
    Box(
        Modifier
            .size(36.dp)
            .clip(CircleShape)
            .background(p.card)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) { content() }
}

/**
 * 静态汉字（不画田字格）。
 *
 * 列表里已经在密集排版，每格再加一遍田字格会糊成一片；
 * 只画笔画，字本身的分量就够了。
 * 与 iOS `HanziView(showGrid: false, showGhost: false)` 对应。
 */
@Composable
fun HanziGlyph(ch: String, modifier: Modifier = Modifier) {
    val p = LocalPalette.current
    val strokes = remember(ch) { Repo.strokes(ch) }
    if (strokes == null) {
        // 没有笔顺数据：退回系统字体，至少不显示空白
        Box(modifier, contentAlignment = Alignment.Center) {
            Text(ch, fontSize = 26.sp, color = p.ink1)
        }
        return
    }
    Canvas(modifier) {
        val box = minOf(size.width, size.height)
        val ox = (size.width - box) / 2f
        val oy = (size.height - box) / 2f
        drawIntoCanvas { c ->
            HanziPainter.drawStrokes(c.nativeCanvas, strokes, box, ox, oy, completed = strokes.count)
        }
    }
}
