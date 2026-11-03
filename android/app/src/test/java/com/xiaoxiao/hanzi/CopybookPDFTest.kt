package com.xiaoxiao.hanzi

import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.data.StrokeCodec
import com.xiaoxiao.hanzi.logic.CopybookPDF
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 字帖导出 PDF。
 *
 * 版式算错会让格子重叠或掉出页面，打印出来才发现；PDF 生成失败更糟——
 * 用户点了导出，什么也没发生。所以这里既验版式（纯函数，好断言），
 * 也验真的吐出了合法的 PDF 字节。
 *
 * 与小程序 `tests/copybook-pdf.test.mjs`、iOS `Checks/CopybookPDFTests.swift` 对应。
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CopybookPDFTest {

    companion object {
        @BeforeClass
        @JvmStatic
        fun load() {
            val assets = java.io.File("src/main/assets/data")
            Repo.loadFromStrings(
                java.io.File(assets, "catalog.json").readText(),
                java.io.File(assets, "meta.json").readText(),
                java.io.File(assets, "strokes.json").readText(),
                java.io.File(assets, "similar.json").readText()
            )
        }
    }

    @Test
    fun `一页六个字，格子四列`() {
        assertEquals(6, CopybookPDF.ROWS_PER_PAGE)
        assertEquals(4, CopybookPDF.COLS)
        val pages = CopybookPDF.layout(listOf("天", "地", "人", "你", "我", "他", "一"))
        assertEquals(2, pages.size)
        assertEquals(6, pages[0].rows.size)
        assertEquals(1, pages[1].rows.size)
    }

    @Test
    fun `第一格是范字，后三格是描红格`() {
        val cells = CopybookPDF.layout(listOf("天"))[0].rows[0].cells
        assertEquals(4, cells.size)
        assertTrue(cells[0].solid)
        assertEquals(listOf(false, false, false), cells.drop(1).map { it.solid })
    }

    @Test
    fun `格子横向居中，不贴左边`() {
        val cells = CopybookPDF.layout(listOf("天"))[0].rows[0].cells
        val left = cells[0].x
        val right = cells[cells.size - 1].x + cells[0].size
        val leftGap = left - CopybookPDF.MARGIN
        val rightGap = CopybookPDF.PAGE_W - CopybookPDF.MARGIN - right
        assertTrue("左右边距应该相等：$leftGap / $rightGap", kotlin.math.abs(leftGap - rightGap) < 0.01f)
        assertTrue(leftGap > 0)
    }

    @Test
    fun `格子之间不重叠，行与行之间留了间隙`() {
        val rows = CopybookPDF.layout(listOf("天", "地"))[0].rows
        val cells = rows[0].cells
        for (i in 1 until cells.size) {
            val prevRight = cells[i - 1].x + cells[i - 1].size
            assertTrue("第 $i 格和前一格重叠了", cells[i].x >= prevRight)
        }
        val r0 = rows[0].cells[0]
        val r1 = rows[1].cells[0]
        assertTrue("第二行压到第一行了", r1.y + r1.size <= r0.y)
    }

    @Test
    fun `所有格子都在页面以内`() {
        val chars = listOf("天", "地", "人", "你", "我", "他", "一", "二", "三", "四", "五", "六")
        for (page in CopybookPDF.layout(chars)) {
            for (row in page.rows) {
                for (c in row.cells) {
                    assertTrue("格子掉出下边距", c.y > CopybookPDF.MARGIN)
                    assertTrue("格子超出上边距", c.y + c.size < CopybookPDF.PAGE_H - CopybookPDF.MARGIN)
                    assertTrue("格子超出左边距", c.x > CopybookPDF.MARGIN)
                    assertTrue("格子超出右边距", c.x + c.size < CopybookPDF.PAGE_W - CopybookPDF.MARGIN)
                }
            }
        }
    }

    @Test
    fun `真的生成了合法 PDF 字节`() {
        val chars = listOf("天", "地", "人")
        val r = CopybookPDF.build(chars, dateLabel = "2026-11-03")
        assertEquals(1, r.pages)
        assertEquals(chars, r.drawn)
        assertTrue("PDF 太小，大概没画出东西：${r.bytes.size}", r.bytes.size > 1000)
        // %PDF 魔数
        assertEquals("%PDF", String(r.bytes, 0, 4, Charsets.US_ASCII))
        // 结尾必须是 %%EOF
        val tail = String(r.bytes, r.bytes.size - 8, 8, Charsets.US_ASCII)
        assertTrue("结尾不是 %%EOF：$tail", tail.contains("%%EOF"))
    }

    @Test
    fun `没有笔画数据的字被跳过并报回来`() {
        // 传一个一定没有笔画数据的字（生僻字）
        val r = CopybookPDF.build(listOf("天", "龘", "地"), dateLabel = "")
        assertEquals(listOf("天", "地"), r.drawn)
        assertEquals(listOf("龘"), r.skipped)
    }

    @Test
    fun `一个字都画不出来时不崩`() {
        val r = CopybookPDF.build(listOf("龘"), strokeFor = { null }, dateLabel = "")
        assertEquals(0, r.drawn.size)
        assertEquals(1, r.pages)
        assertTrue(r.bytes.size > 100)
    }

    @Test
    fun `空列表也能生成`() {
        val r = CopybookPDF.build(emptyList(), dateLabel = "")
        assertEquals(0, r.pages)
        assertEquals("%PDF", String(r.bytes, 0, 4, Charsets.US_ASCII))
    }

    @Test
    fun `文件名带日期且是 pdf`() {
        val name = CopybookPDF.fileName(java.util.Date(2026 - 1900, 0, 5))
        assertEquals("字帖-20260105.pdf", name)
    }

    @Test
    fun `日期补零`() {
        assertEquals("2026-01-05", CopybookPDF.dateLabel(java.util.Date(2026 - 1900, 0, 5)))
        assertEquals("2026-12-31", CopybookPDF.dateLabel(java.util.Date(2026 - 1900, 11, 31)))
    }

    @Test
    fun `字帖里的字真的有笔画数据`() {
        // 这条是给「导出的 PDF 一片空白」兜底的：如果 Repo 没加载，
        // strokeFor 全返回 null，上面那些测试还是会过（drawn 为空也算「跳过」）
        val s = Repo.strokes("天")
        assertNotNull("天 应该有笔画数据", s)
        assertTrue("天的笔画数应该大于 1", s!!.strokes.size > 1)
    }
}
