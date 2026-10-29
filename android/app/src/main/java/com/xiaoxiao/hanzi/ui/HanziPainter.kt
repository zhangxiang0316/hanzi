package com.xiaoxiao.hanzi.ui

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.data.StrokeCodec

/**
 * 汉字画布渲染引擎，与小程序 utils/hanzi-canvas.js 一一对应。
 *
 * 小程序的 CanvasRenderingContext2D 与 Android Canvas 概念相同，但有几个必须处理的差异：
 *   1. JS 的 `ctx.fill()` 填充的是 path 内部，Android 的 drawPath(paint.FILL) 等价
 *   2. JS 的虚线 `setLineDash` 对应 DashPathEffect，但需要重建 Path
 *   3. 小程序的「裁剪 + 粗线沿中线推进」画 partial 笔，靠 clip + dash，
 *      这里同样用 clipPath + DashPathEffect，保证逐笔动画的观感一致
 *
 * 坐标：Make Me a Hanzi 用 1024×1024 方格，构建时已把 y 翻转为屏幕坐标，
 * 这里只需把 0-1020 线性映射到画布边长。
 */
object HanziPainter {

    const val SIZE = 1024f

    /** 每一笔的书写时长（毫秒），与小程序 hanzi-canvas.js 保持一致 */
    const val PER_STROKE_MS = 620L
    /** 笔与笔之间的停顿，留出「看清这一笔」的时间 */
    const val STROKE_GAP_MS = 140L
    /** 字形在格子里留一点边距，避免笔画贴死边框 */
    private const val PAD_RATIO = 0.035f

    val INK = Color.parseColor("#25332D")
    val GHOST = Color.parseColor("#CFC7B6")
    val GUIDE = Color.parseColor("#C9BDA6")
    val HINT = Color.parseColor("#8FC4B8")
    /** 定格某一笔时用主题色标出来 */
    val ACCENT = Color.parseColor("#3E8E7E")

    private val BORDER = Color.parseColor("#E0D5C0")
    private val DASH_LINE = Color.parseColor("#EEE3D0")
    private const val NUMBER_BG = 0xEB3E8E7E.toInt()

    private fun padOf(box: Float) = box * PAD_RATIO

    private fun px(v: Float, box: Float): Float {
        val pad = padOf(box)
        return pad + (v / SIZE) * (box - 2 * pad)
    }

    private fun buildPath(cmds: List<StrokeCodec.Cmd>, box: Float, ox: Float, oy: Float): Path {
        val path = Path()
        for (c in cmds) {
            when (c.op) {
                StrokeCodec.OP_M -> path.moveTo(ox + px(c.coords[0], box), oy + px(c.coords[1], box))
                StrokeCodec.OP_L -> path.lineTo(ox + px(c.coords[0], box), oy + px(c.coords[1], box))
                StrokeCodec.OP_Q -> path.quadTo(
                    ox + px(c.coords[0], box), oy + px(c.coords[1], box),
                    ox + px(c.coords[2], box), oy + px(c.coords[3], box)
                )
                StrokeCodec.OP_C -> path.cubicTo(
                    ox + px(c.coords[0], box), oy + px(c.coords[1], box),
                    ox + px(c.coords[2], box), oy + px(c.coords[3], box),
                    ox + px(c.coords[4], box), oy + px(c.coords[5], box)
                )
                StrokeCodec.OP_Z -> path.close()
            }
        }
        return path
    }

    /** 中线折线（已缩放到画布坐标），扁平化 [x0,y0,x1,y1,...] */
    fun medianPoints(median: FloatArray, box: Float, ox: Float, oy: Float): FloatArray {
        val out = FloatArray(median.size)
        for (i in median.indices step 2) {
            out[i] = ox + px(median[i], box)
            out[i + 1] = oy + px(median[i + 1], box)
        }
        return out
    }

    fun polylineLength(pts: FloatArray): Float {
        var len = 0f
        var i = 2
        while (i < pts.size) {
            val dx = pts[i] - pts[i - 2]
            val dy = pts[i + 1] - pts[i - 1]
            len += Math.sqrt((dx * dx + dy * dy).toDouble()).toFloat()
            i += 2
        }
        return len
    }

    private fun tracePath(pts: FloatArray): Path {
        val path = Path()
        if (pts.size < 2) return path
        path.moveTo(pts[0], pts[1])
        var i = 2
        while (i < pts.size) {
            path.lineTo(pts[i], pts[i + 1])
            i += 2
        }
        return path
    }

    /** 田字格：外框 + 虚线十字 */
    fun drawGrid(canvas: Canvas, box: Float, ox: Float, oy: Float) {
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 2f
            color = BORDER
        }
        canvas.drawRect(ox + 0.5f, oy + 0.5f, ox + box - 0.5f, oy + box - 0.5f, border)

        val dash = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1f
            color = DASH_LINE
            pathEffect = DashPathEffect(floatArrayOf(6f, 6f), 0f)
        }
        val mid = Path().apply {
            moveTo(ox + box / 2, oy + box * 0.06f)
            lineTo(ox + box / 2, oy + box * 0.94f)
            moveTo(ox + box * 0.06f, oy + box / 2)
            lineTo(ox + box * 0.94f, oy + box / 2)
        }
        canvas.drawPath(mid, dash)
    }

    private var typefaceCache: Typeface? = null
    private var typefaceKey: String? = null

    /**
     * 楷体优先。Android 设备上楷体不一定存在，逐级回退到 serif，
     * 与小程序那边「Kaiti SC / STKaiti / KaiTi / Songti SC / serif」的意图一致。
     */
    private fun kaiTypeface(): Typeface {
        typefaceCache?.let { return it }
        val candidates = listOf("Kaiti", "STKaiti", "KaiTi", "楷体", "Noto Serif CJK SC", "serif")
        for (name in candidates) {
            val tf = try {
                Typeface.create(name, Typeface.BOLD)
            } catch (e: Exception) {
                null
            }
            if (tf != null && tf != Typeface.DEFAULT_BOLD) {
                typefaceCache = tf
                typefaceKey = name
                return tf
            }
        }
        val fallback = Typeface.SERIF
        typefaceCache = fallback
        typefaceKey = "serif(fallback)"
        return fallback
    }

    fun typefaceName(): String = typefaceKey ?: "?"

    /** 田字格里画淡灰色「字帖底字」（描红参照） */
    fun drawGhostChar(canvas: Canvas, ch: String, box: Float, ox: Float, oy: Float, color: Int = GHOST) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            textSize = box * 0.84f
            textAlign = Paint.Align.CENTER
            typeface = kaiTypeface()
        }
        // 基线居中：Android 没有 textBaseline=middle，用字体度量换算
        val fm = paint.fontMetrics
        val baseline = oy + box * 0.53f - (fm.ascent + fm.descent) / 2f
        canvas.drawText(ch, ox + box / 2, baseline, paint)
    }

    /**
     * 画静态字：已写好的笔画实心，未写的笔画用浅色轮廓。
     *
     * @param completed 已经写完的笔画数
     * @param partial 当前这一笔写到 0-1 之间的进度
     */
    fun drawStrokes(
        canvas: Canvas,
        data: StrokeCodec.CharStrokes,
        box: Float,
        ox: Float,
        oy: Float,
        completed: Int = data.count,
        partial: Float = 0f,
        inkColor: Int = INK,
        showGhost: Boolean = true
    ) {
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            this.color = inkColor
            strokeJoin = Paint.Join.ROUND
            strokeCap = Paint.Cap.ROUND
        }

        for (i in 0 until data.count) {
            val cmds = data.strokes[i]
            val path = buildPath(cmds, box, ox, oy)
            when {
                i < completed -> canvas.drawPath(path, fill)

                i == completed && partial > 0f -> {
                    // 当前笔：裁剪到笔画轮廓内，用粗线沿中线推进
                    canvas.save()
                    canvas.clipPath(path)
                    val pts = medianPoints(data.medians[i], box, ox, oy)
                    val len = polylineLength(pts)
                    val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        style = Paint.Style.STROKE
                        this.color = inkColor
                        strokeWidth = maxOf(box * 0.22f, 18f)
                        strokeJoin = Paint.Join.ROUND
                        strokeCap = Paint.Cap.ROUND
                        pathEffect = DashPathEffect(
                            floatArrayOf(maxOf(len * partial, 0.1f), len + 10f), 0f
                        )
                    }
                    canvas.drawPath(tracePath(pts), stroke)
                    canvas.restore()
                }

                showGhost -> {
                    val ghost = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        style = Paint.Style.STROKE
                        this.color = HINT
                        strokeWidth = maxOf(box * 0.006f, 1f)
                        alpha = (0.55f * 255).toInt()
                    }
                    canvas.drawPath(path, ghost)
                }
            }
        }
    }

    /** 高亮某一笔（详情页点击笔画时用） */
    fun drawStrokeHighlight(
        canvas: Canvas,
        data: StrokeCodec.CharStrokes,
        index: Int,
        box: Float,
        ox: Float,
        oy: Float,
        color: Int = ACCENT
    ) {
        if (index < 0 || index >= data.count) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            this.color = color
            alpha = (0.85f * 255).toInt()
        }
        canvas.drawPath(buildPath(data.strokes[index], box, ox, oy), paint)
    }

    /** 画笔画序号 + 起点圆点（笔顺提示） */
    fun drawStrokeNumbers(
        canvas: Canvas,
        data: StrokeCodec.CharStrokes,
        box: Float,
        ox: Float,
        oy: Float,
        onlyIndex: Int = -1
    ) {
        val circle = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = NUMBER_BG
        }
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        }

        for (i in 0 until data.count) {
            if (onlyIndex >= 0 && i != onlyIndex) continue
            val m = data.medians[i]
            if (m.size < 2) continue
            val x = ox + px(m[0], box)
            val y = oy + px(m[1], box)
            val r = maxOf(box * 0.045f, 7f)
            canvas.drawCircle(x, y, r, circle)
            text.textSize = r * 1.15f
            val fm = text.fontMetrics
            val baseline = y - (fm.ascent + fm.descent) / 2f
            canvas.drawText((i + 1).toString(), x, baseline, text)
        }
    }

    /** 整字填充（结果页大字用） */
    fun drawCharInk(canvas: Canvas, ch: String, box: Float, ox: Float, oy: Float, color: Int = INK) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            textSize = box * 0.9f
            textAlign = Paint.Align.CENTER
            typeface = kaiTypeface()
        }
        val fm = paint.fontMetrics
        val baseline = oy + box * 0.52f - (fm.ascent + fm.descent) / 2f
        canvas.drawText(ch, ox + box / 2, baseline, paint)
    }

    /** 字的笔画数（数据缺失时返回 0） */
    fun strokeCount(ch: String): Int = Repo.strokeCount(ch)
}
