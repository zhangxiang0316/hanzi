package com.xiaoxiao.hanzi

import com.xiaoxiao.hanzi.logic.CopybookPick
import com.xiaoxiao.hanzi.logic.Progress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 字帖选字。
 *
 * 这块的价值全在「挑出来的字是不是家长想练的那批」上：错题最该练，
 * 所以来源顺序和标签顺序都要钉死。
 *
 * 与小程序 `tests/copybook-pick.test.mjs` 对应。小程序里还有两条
 * 「没笔顺数据 → 不能导」的用例，Android 不适用：笔顺数据全量打在
 * assets 里，每个字都画得出来，那套 gating 整个没搬。
 */
class CopybookPickTest {

    private fun candidate(ch: String, from: String) = CopybookPick.Candidate(ch, from)

    private fun record(stars: Int) = Progress.WriteRecord(best = 80, stars = stars, tries = 1, last = 1)

    @Test
    fun `合并去重，保持首次出现的顺序`() {
        val merged = CopybookPick.merge(
            listOf(candidate("天", "lesson"), candidate("地", "wrong"), candidate("天", "stars"))
        )
        assertEquals(listOf("天", "地"), merged.map { it.ch })
        assertEquals(listOf("lesson", "stars"), merged[0].froms)
    }

    @Test
    fun `来源标签按「错题 > 弱笔 > 课时 > 低分」排`() {
        val d = CopybookPick.decorate(
            CopybookPick.merge(
                listOf(candidate("天", "stars"), candidate("天", "lesson"), candidate("天", "wrong"))
            )
        )
        assertEquals(listOf("wrong", "lesson", "stars"), d[0].froms)
        assertEquals("错题 · 课时 · 低分", d[0].fromText)
    }

    @Test
    fun `空输入不炸`() {
        assertTrue(CopybookPick.merge(null).isEmpty())
        assertTrue(CopybookPick.build(CopybookPick.Source()).isEmpty())
        assertTrue(CopybookPick.decorate(null).isEmpty())
    }

    @Test
    fun `按星档选出的字只含那一档`() {
        val records = listOf(
            "天" to record(1),
            "地" to record(3),
            "人" to record(1)
        )
        val out = CopybookPick.fromStars(records, 1)
        assertEquals(listOf("天", "人"), out.map { it.ch })
    }

    @Test
    fun `错题优先于课时，同时出现时错题标签在前`() {
        val out = CopybookPick.build(
            CopybookPick.Source(
                lessonChars = listOf("天", "地", "人"),
                wrongChars = listOf("人")
            )
        )
        // 「人」是错题，排在前面
        assertEquals("人", out[0].ch)
        assertTrue(out[0].fromText.contains("错题"))
    }

    @Test
    fun `四条来源可以同时生效`() {
        val out = CopybookPick.build(
            CopybookPick.Source(
                lessonChars = listOf("天", "地"),
                wrongChars = listOf("你"),
                weakChars = listOf("我"),
                records = listOf("他" to record(0)),
                stars = 0
            )
        )
        assertEquals(listOf("他", "你", "天", "地", "我").sorted(), out.map { it.ch }.sorted())
        // 顺序也要对：错题 → 弱笔 → 低星 → 课时
        assertEquals(listOf("你", "我", "他", "天", "地"), out.map { it.ch })
    }

    @Test
    fun `不给星档时不按星级选`() {
        val out = CopybookPick.build(
            CopybookPick.Source(
                lessonChars = listOf("天"),
                records = listOf("地" to record(0)),
                stars = null
            )
        )
        assertEquals(listOf("天"), out.map { it.ch })
    }

    @Test
    fun `重复来源不会产生重复的字，但标签都留着`() {
        val out = CopybookPick.build(
            CopybookPick.Source(
                lessonChars = listOf("天"),
                wrongChars = listOf("天"),
                weakChars = listOf("天")
            )
        )
        assertEquals(1, out.size)
        assertEquals(listOf("wrong", "weak", "lesson"), out[0].froms)
        assertEquals("错题 · 笔画弱 · 课时", out[0].fromText)
    }

    @Test
    fun `Android 笔顺全量，选中的字都能导出`() {
        // 小程序版这里会分成 ready / missing 两组；Android 不做这个区分
        val out = CopybookPick.build(
            CopybookPick.Source(lessonChars = listOf("天", "地"), wrongChars = listOf("龘"))
        )
        assertEquals(3, out.size)
        assertTrue("字库里没有的字也不该被丢掉，导出时再跳过", out.any { it.ch == "龘" })
    }
}
