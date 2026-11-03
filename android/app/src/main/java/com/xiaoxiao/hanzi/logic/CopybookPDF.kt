package com.xiaoxiao.hanzi.logic

import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.data.StrokeCodec

/**
 * 字帖导出 PDF。
 *
 * 屏幕上「我的字帖」是一堆小方块，只能看；打印出来才是真的字帖——
 * 孩子拿铅笔在上面描，比对着屏幕用手指划有用得多。
 *
 * ## 版式
 *
 * 每个字一行，四格：[范字（浓墨）][浅灰][浅灰][浅灰]
 *
 * 第一格是照着写的范字，后三格是描红格。为什么不是四格全浅：
 * 孩子在第三格就写走形了，第五格会更差，留一个对比基准很有用。
 *
 * ## 一页六个字
 *
 * A4 高 842pt，去掉页边距和页眉页脚剩 706pt，每行 110pt（格子 96 + 行距 14），
 * 正好 6 行。格子再小幼儿就写不开了；再大就一页五行，纸太浪费。
 *
 * ## 坐标
 *
 * PDF 用 72dpi 的 point 作单位（595x842 = A4）。原点在左下角、y 向上，
 * 而笔画数据是 y 向下，翻转在 [PdfWriter.glyphPath] 里做。
 *
 * 与小程序 `utils/copybook-pdf.js`、iOS `Logic/CopybookPDF.swift` 版式一致。
 */
object CopybookPDF {

    const val PAGE_W = 595
    const val PAGE_H = 842
    const val MARGIN = 42
    const val HEADER_H = 30
    const val CELL = 96
    const val COL_GAP = 10
    const val ROW_GAP = 14
    const val COLS = 4
    const val ROWS_PER_PAGE = 6

    private const val COLOR_GUIDE = "#C9BDA6"
    private const val COLOR_GRID = "#DED3BD"
    private const val COLOR_INK = "#25332D"

    /**
     * 描红格里的字。
     *
     * 必须比格线明显深一点。第一版用的 #CFC7B6 和格线 #C9BDA6 只差 5 个色阶，
     * 打印出来孩子分不清哪条是格线、哪条是该描的字。
     */
    private const val COLOR_GHOST = "#B3AA96"

    class Page(val rows: List<Row>)

    class Row(val ch: String, val cells: List<Cell>)

    class Cell(val x: Float, val y: Float, val size: Float, val solid: Boolean)

    class Result(
        val bytes: ByteArray,
        val pages: Int,
        val drawn: List<String>,
        val skipped: List<String>
    )

    /** 一行四个格子的总宽 */
    fun rowWidth(): Float = (COLS * CELL + (COLS - 1) * COL_GAP).toFloat()

    /**
     * 排页。纯函数，不碰 PdfDocument —— 版式对不对可以直接断言。
     */
    fun layout(chars: List<String>): List<Page> {
        val pages = ArrayList<Page>()
        var i = 0
        while (i < chars.size) {
            val chunk = chars.subList(i, minOf(i + ROWS_PER_PAGE, chars.size))
            // 横向居中：格子总宽通常小于可用宽度，靠左会显得偏
            val usableW = PAGE_W - 2 * MARGIN
            val x0 = MARGIN + maxOf(0f, (usableW - rowWidth()) / 2)
            val rows = chunk.mapIndexed { r, ch ->
                val top = PAGE_H - MARGIN - HEADER_H - r * (CELL + ROW_GAP)
                val cells = (0 until COLS).map { c ->
                    Cell(
                        x = x0 + c * (CELL + COL_GAP),
                        y = (top - CELL).toFloat(),
                        size = CELL.toFloat(),
                        // 第一格是范字，其余是描红格
                        solid = c == 0
                    )
                }
                Row(ch, cells)
            }
            pages.add(Page(rows))
            i += ROWS_PER_PAGE
        }
        return pages
    }

    /** 给 PdfWriter 用的颜色三元组，避免到处写 spread */
    private fun setStroke(pdf: PdfWriter, hex: String) {
        val h = hex.removePrefix("#")
        pdf.strokeColor(
            h.substring(0, 2).toInt(16) / 255f,
            h.substring(2, 4).toInt(16) / 255f,
            h.substring(4, 6).toInt(16) / 255f
        )
    }

    private fun setFill(pdf: PdfWriter, hex: String) {
        val h = hex.removePrefix("#")
        pdf.fillColor(
            h.substring(0, 2).toInt(16) / 255f,
            h.substring(2, 4).toInt(16) / 255f,
            h.substring(4, 6).toInt(16) / 255f
        )
    }

    /** 画一个田字格：外框实线 + 十字虚线 */
    private fun drawGrid(pdf: PdfWriter, cell: Cell) {
        setStroke(pdf, COLOR_GUIDE)
        pdf.lineWidth(0.6f)
        pdf.dash(null)
        pdf.rect(cell.x, cell.y, cell.size, cell.size)
        pdf.stroke()

        // 十字虚线，留 2pt 内缩，别和外框粘在一起
        setStroke(pdf, COLOR_GRID)
        pdf.lineWidth(0.45f)
        pdf.dash(floatArrayOf(3f, 2.5f))
        val midX = cell.x + cell.size / 2
        val midY = cell.y + cell.size / 2
        pdf.moveTo(midX, cell.y + 2)
        pdf.lineTo(midX, cell.y + cell.size - 2)
        pdf.moveTo(cell.x + 2, midY)
        pdf.lineTo(cell.x + cell.size - 2, midY)
        pdf.stroke()
        pdf.dash(null)
    }

    /**
     * 生成 PDF 字节。
     *
     * @param chars 要排的字
     * @param strokeFor 取笔画数据，拿不到返回 null（会被跳过并报回来）
     */
    fun build(
        chars: List<String>,
        strokeFor: (String) -> StrokeCodec.CharStrokes? = { Repo.strokes(it) },
        dateLabel: String = ""
    ): Result {
        val pages = layout(chars)
        val pdf = PdfWriter(PAGE_W.toFloat(), PAGE_H.toFloat())
        val drawn = ArrayList<String>()
        val skipped = ArrayList<String>()

        pages.forEachIndexed { idx, page ->
            // 页眉：只有日期和页码。中文标题要靠嵌字体，不值得为它塞 3MB
            setFill(pdf, "#8A8073")
            pdf.text(dateLabel, (PAGE_W - MARGIN - 96).toFloat(), (MARGIN + 14).toFloat(), 8.5f)
            pdf.text("${idx + 1} / ${pages.size}", (PAGE_W - MARGIN - 26).toFloat(), (MARGIN + 14).toFloat(), 8.5f)

            for (row in page.rows) {
                val data = strokeFor(row.ch)
                for (cell in row.cells) {
                    drawGrid(pdf, cell)
                    if (data == null) continue
                    // 田字格画完再填字，否则虚线会压在字上面
                    setFill(pdf, if (cell.solid) COLOR_INK else COLOR_GHOST)
                    pdf.glyphPath(data.strokes, cell, 0.05f)
                }
                if (data != null) drawn.add(row.ch) else if (!skipped.contains(row.ch)) skipped.add(row.ch)
            }

            // 页脚：一行极细的分隔线，视觉上收住版面
            setStroke(pdf, COLOR_GRID)
            pdf.lineWidth(0.4f)
            val fy = (MARGIN + 14).toFloat()
            pdf.moveTo(MARGIN.toFloat(), fy)
            pdf.lineTo((PAGE_W - MARGIN).toFloat(), fy)
            pdf.stroke()

            pdf.endPage()
        }

        return Result(pdf.build(), pages.size, drawn, skipped)
    }

    /** 建议的文件名，走 FileProvider 分享时用 */
    fun fileName(date: java.util.Date = java.util.Date()): String {
        val f = java.text.SimpleDateFormat("yyyyMMdd", java.util.Locale.US)
        return "字帖-${f.format(date)}.pdf"
    }

    /** 页眉上的日期，用 ASCII 数字 */
    fun dateLabel(date: java.util.Date = java.util.Date()): String {
        val f = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
        return f.format(date)
    }
}
