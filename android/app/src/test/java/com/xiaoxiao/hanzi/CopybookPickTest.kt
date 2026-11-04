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
    fun `来源标签按错题、弱笔、课时、低分的先后排`() {
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
        // 顺序也要对：错题 → 弱笔 → 课时 → 低分
        assertEquals(listOf("你", "我", "天", "地", "他"), out.map { it.ch })
    }

    /**
     * 条目顺序与标签顺序必须是同一套。
     *
     * 这两处曾经反着：条目是 错题>弱笔>低分>课时，标签是 错题>弱笔>课时>低分。
     * 结果界面上标着「课时 · 低分」的字排在了纯课时字前面，用户没法解释
     * 这个顺序。顺序只有一套才讲得通。
     */
    @Test
    fun `条目顺序与标签顺序一致`() {
        val out = CopybookPick.build(
            CopybookPick.Source(
                lessonChars = listOf("天", "地"),
                wrongChars = listOf("你"),
                weakChars = listOf("我"),
                records = listOf("他" to record(1)),
                stars = 1
            )
        )
        assertEquals(listOf("你", "我", "天", "地", "他"), out.map { it.ch })

        // 每个字的**首个**来源，按优先级必须单调不增
        val rank = mapOf("wrong" to 0, "weak" to 1, "lesson" to 2, "stars" to 3)
        val ranks = out.map { rank.getValue(it.froms.first()) }
        for (i in 1 until ranks.size) {
            assertTrue(
                "第 $i 个字的来源优先级倒退了：${out[i].ch}",
                ranks[i] >= ranks[i - 1]
            )
        }
    }

    /**
     * 防止有人改了 [CopybookPick.FROM_ORDER] 却忘了改 [CopybookPick.build] 里的 push 顺序。
     *
     * 直接断言声明顺序的字面量，而不是拿 FROM_ORDER 去比自己：那样改一处
     * 两个列表会一起变，测试就永远绿了，等于没测。
     */
    @Test
    fun `来源的声明顺序是错题、弱笔、课时、低分`() {
        assertEquals(
            listOf("wrong", "weak", "lesson", "stars"),
            CopybookPick.FROM_ORDER
        )
        // FROM_TEXT 是 LinkedHashMap（mapOf 保序），声明顺序要和 FROM_ORDER 一致
        assertEquals(
            listOf("wrong", "weak", "lesson", "stars"),
            CopybookPick.FROM_TEXT.keys.toList()
        )
        assertEquals(
            listOf("错题", "笔画弱", "课时", "低分"),
            CopybookPick.FROM_TEXT.values.toList()
        )
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
