package com.xiaoxiao.hanzi.logic

import com.xiaoxiao.hanzi.data.StrokeCodec
import java.util.Locale

/**
 * 极简 PDF 写入器。
 *
 * ## 为什么不用 android.graphics.pdf.PdfDocument
 *
 * 它只能在真机上跑——Robolectric 没有它的实现（`writeTo` 直接抛
 * `document is closed!`）。而我们在这个环境里**没法跑真机**，用 PdfDocument
 * 就意味着「导出 PDF」这条路径永远无法自动验证，只能靠人肉点一遍。
 *
 * PDF 本身只是「对象 + 交叉引用表」的文本格式，自己拼并不难。自己拼的
 * 好处是：字节完全可断言、三端输出一致（小程序 / iOS 也是这么做的）、
 * 而且不依赖 Android 图形栈。
 *
 * ## 为什么没有中文字体
 *
 * 正经做法是嵌一个中文 TTF，但要 3-10MB，还得做子集化。所以这里
 * **一个中文字都不画成文字**：汉字全部用笔顺轮廓画成矢量路径
 * （界面上描红的范字本来也是这么画的）。只有日期和页码用 PDF 内置的
 * Helvetica —— Base-14 标准字体，阅读器自带，不需要嵌入。
 *
 * 顺带的好处：输出是纯矢量，放大到 A3 也不糊。
 *
 * ## 坐标
 *
 * PDF 原点在页面左下角、y 轴向上；笔画数据是 y 向下。翻转在
 * [glyphPath] 里做，调用方只用「格子左上角 + 边长」这种直观坐标。
 *
 * 与小程序 `utils/pdf.js` 逐行对应。
 */
class PdfWriter(val width: Float = 595.28f, val height: Float = 841.89f) {

    private val pages = ArrayList<String>()
    private val ops = ArrayList<String>()
    private var current = floatArrayOf(0f, 0f)

    private fun n(v: Float): String {
        // PDF 不接受科学计数法：1e-7 这种会让阅读器整页不显示
        val x = if (kotlin.math.abs(v) < 1e-6f) 0f else v
        val s = String.format(Locale.US, "%.2f", x)
        // 去掉多余的 0，但保留至少一个整数位
        return s.trimEnd('0').trimEnd('.').ifEmpty { "0" }
    }

    fun strokeColor(r: Float, g: Float, b: Float) {
        ops.add("${n(r)} ${n(g)} ${n(b)} RG")
    }

    fun fillColor(r: Float, g: Float, b: Float) {
        ops.add("${n(r)} ${n(g)} ${n(b)} rg")
    }

    fun lineWidth(w: Float) {
        ops.add("${n(w)} w")
    }

    /** 虚线。[实线长, 间隔]；传 null 恢复实线 */
    fun dash(pattern: FloatArray?) {
        ops.add(if (pattern == null || pattern.isEmpty()) "[] 0 d"
        else "[${pattern.joinToString(" ") { n(it) }}] 0 d")
    }

    fun moveTo(x: Float, y: Float) {
        ops.add("${n(x)} ${n(y)} m")
        current = floatArrayOf(x, y)
    }

    fun lineTo(x: Float, y: Float) {
        ops.add("${n(x)} ${n(y)} l")
        current = floatArrayOf(x, y)
    }

    fun rect(x: Float, y: Float, w: Float, h: Float) {
        ops.add("${n(x)} ${n(y)} ${n(w)} ${n(h)} re")
    }

    fun stroke() = ops.add("S")
    fun fill() = ops.add("f")
    fun close() = ops.add("h")

    /**
     * 二次贝塞尔。
     *
     * PDF 的路径指令里**没有二次曲线**，只有三次（`c`）。所以先把二次
     * 升阶成三次：控制点取 P0 + 2/3(Q-P0) 和 P1 + 2/3(Q-P1)。
     * 这是精确等价的变换，不是近似。
     */
    fun quadTo(cx: Float, cy: Float, x: Float, y: Float) {
        val (x0, y0) = current[0] to current[1]
        val c1x = x0 + (2f / 3f) * (cx - x0)
        val c1y = y0 + (2f / 3f) * (cy - y0)
        val c2x = x + (2f / 3f) * (cx - x)
        val c2y = y + (2f / 3f) * (cy - y)
        ops.add("${n(c1x)} ${n(c1y)} ${n(c2x)} ${n(c2y)} ${n(x)} ${n(y)} c")
        current = floatArrayOf(x, y)
    }

    fun cubicTo(c1x: Float, c1y: Float, c2x: Float, c2y: Float, x: Float, y: Float) {
        ops.add("${n(c1x)} ${n(c1y)} ${n(c2x)} ${n(c2y)} ${n(x)} ${n(y)} c")
        current = floatArrayOf(x, y)
    }

    /**
     * 把汉字轮廓画成路径并填充。
     *
     * @param box {x, y, size} —— 格子左上角与边长（PDF 坐标）
     * @param padRatio 格子内边距比例
     */
    fun glyphPath(strokes: List<List<StrokeCodec.Cmd>>, box: CopybookPDF.Cell, padRatio: Float = 0.035f) {
        val pad = box.size * padRatio
        val inner = box.size - 2 * pad
        fun toX(v: Float) = box.x + pad + (v / 1024f) * inner
        // y 要翻转：数据是 y 向下，PDF 是 y 向上
        fun toY(v: Float) = box.y + box.size - pad - (v / 1024f) * inner
        for (cmds in strokes) {
            for (c in cmds) {
                when (c.op) {
                    StrokeCodec.OP_M -> moveTo(toX(c.coords[0]), toY(c.coords[1]))
                    StrokeCodec.OP_L -> lineTo(toX(c.coords[0]), toY(c.coords[1]))
                    StrokeCodec.OP_Q -> quadTo(
                        toX(c.coords[0]), toY(c.coords[1]),
                        toX(c.coords[2]), toY(c.coords[3])
                    )
                    StrokeCodec.OP_C -> cubicTo(
                        toX(c.coords[0]), toY(c.coords[1]),
                        toX(c.coords[2]), toY(c.coords[3]),
                        toX(c.coords[4]), toY(c.coords[5])
                    )
                    StrokeCodec.OP_Z -> close()
                }
            }
            // 每一笔单独填充：笔画之间有重叠，分开填充更稳
            // （有些轮廓方向不一致，合成一条用 evenodd 会挖洞）
            fill()
        }
    }

    /** 画一段文字。只用于数字和 ASCII —— 中文字体不嵌入。 */
    fun text(str: String, x: Float, y: Float, size: Float, font: String = "F1") {
        // 只保留可打印 ASCII，防止误传中文变成乱码方块
        val safe = str.map { if (it in ' '..'~') it else '?' }.joinToString("")
        val esc = safe.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
        ops.add("BT /$font ${n(size)} Tf ${n(x)} ${n(y)} Td ($esc) Tj ET")
    }

    fun endPage() {
        pages.add(ops.joinToString("\n"))
        ops.clear()
    }

    /**
     * 输出 PDF 字节。
     *
     * 对象编号：1 = Catalog，2 = Pages，3 = Font，
     * 之后每页两个对象（Page + Contents）。
     */
    fun build(): ByteArray {
        if (ops.isNotEmpty()) endPage()
        val pageCount = pages.size
        val firstPageObj = 4
        val maxObj = firstPageObj + pageCount * 2

        val objects = arrayOfNulls<String>(maxObj)
        objects[1] = "<< /Type /Catalog /Pages 2 0 R >>"
        val kids = (0 until pageCount).joinToString(" ") { "${firstPageObj + it * 2} 0 R" }
        objects[2] = "<< /Type /Pages /Kids [$kids] /Count $pageCount >>"
        objects[3] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"

        for (i in 0 until pageCount) {
            val pageObj = firstPageObj + i * 2
            val contentObj = pageObj + 1
            val body = pages[i]
            objects[pageObj] =
                "<< /Type /Page /Parent 2 0 R " +
                    "/MediaBox [0 0 ${n(width)} ${n(height)}] " +
                    "/Resources << /Font << /F1 3 0 R >> >> " +
                    "/Contents $contentObj 0 R >>"
            objects[contentObj] = "<< /Length ${body.length} >>\nstream\n$body\nendstream"
        }

        // 拼字节并记录每个对象的偏移量（xref 表要用）
        val sb = StringBuilder()
        sb.append("%PDF-1.4\n%\u00E2\u00E3\u00CF\u00D3\n")
        val offsets = IntArray(maxObj)
        for (i in 1 until maxObj) {
            val o = objects[i] ?: continue
            offsets[i] = sb.length
            sb.append(i).append(" 0 obj\n").append(o).append("\nendobj\n")
        }
        val xrefPos = sb.length
        sb.append("xref\n0 ").append(maxObj).append("\n0000000000 65535 f \n")
        for (i in 1 until maxObj) {
            sb.append(String.format(Locale.US, "%010d", offsets[i])).append(" 00000 n \n")
        }
        sb.append("trailer\n<< /Size ").append(maxObj).append(" /Root 1 0 R >>\n")
        sb.append("startxref\n").append(xrefPos).append("\n%%EOF\n")

        // Latin-1 逐字节写出：内容全是 ASCII，长度和字符数一致
        val out = ByteArray(sb.length)
        for (i in sb.indices) out[i] = (sb[i].code and 0xFF).toByte()
        return out
    }
}
