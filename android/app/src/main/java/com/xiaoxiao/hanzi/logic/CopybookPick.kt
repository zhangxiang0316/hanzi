package com.xiaoxiao.hanzi.logic

/**
 * 字帖选字：决定「导出哪些字」的纯逻辑。
 *
 * ## 为什么这件事不能只靠界面
 *
 * 候选字来自四条路径（课时 / 错题 / 笔画弱 / 低星），每条都要合并、去重、
 * 标来源，界面只该负责把结果画出来。抽成纯函数放这里，三端照抄同一套口径。
 *
 * ## 优先级
 *
 * 一个字的来源可能同时命中多条（既是错题、星级又低），去重时按
 * 「错题 > 弱笔 > 课时 > 低分」排——错题最该练。
 *
 * ## 与小程序版的差别（有意为之）
 *
 * 小程序端笔画数据在分包里，主包取不到，所以选字时必须先标出「哪些字画不出来」
 * （`available` / `isCached` 那套判断）。Android 的笔顺数据全量打在 assets 里，
 * 每个字都画得出来——那套 gating 在这里只会让界面凭空多出一堆置灰格子，
 * 所以整个去掉：**选中的字一定导得出来**。
 */
object CopybookPick {

    /** 来源标签的展示顺序与文案 */
    val FROM_ORDER = listOf("wrong", "weak", "lesson", "stars")

    val FROM_TEXT = mapOf(
        "wrong" to "错题",
        "weak" to "笔画弱",
        "lesson" to "课时",
        "stars" to "低分"
    )

    /** 一条候选字（尚未去重） */
    data class Candidate(val ch: String, val from: String)

    /** 去重合并后的一个字；[froms] 是排好序的来源 id */
    class Merged(val ch: String, val froms: List<String>)

    /** 给界面用的一个字；[fromText] 是「错题 · 课时」这样的中文标签 */
    class Item(val ch: String, val froms: List<String>, val fromText: String)

    /**
     * 一组候选字去重并合并来源标签，保持首次出现的顺序。
     *
     * 去重会丢掉后来的重复项，但**来源**不丢：同一个字既是错题又是本课生字时，
     * 两个标签都要留着——家长据此判断这个字为什么值得练。
     */
    fun merge(items: List<Candidate>?): List<Merged> {
        val order = ArrayList<String>()
        val map = LinkedHashMap<String, MutableList<String>>()
        for (it in items ?: emptyList()) {
            if (it.ch.isEmpty()) continue
            val froms = map.getOrPut(it.ch) {
                order.add(it.ch)
                ArrayList()
            }
            if (it.from.isNotEmpty() && froms.indexOf(it.from) < 0) froms.add(it.from)
        }
        return order.map { Merged(it, map[it] ?: emptyList()) }
    }

    /** 把来源标签排好序、转成中文，给界面用。 */
    fun decorate(items: List<Merged>?): List<Item> = (items ?: emptyList()).map { it ->
        // 稳定排序：来源顺序与 FROM_ORDER 一致，不在表里的排最前（与小程序一致）
        val froms = it.froms.sortedBy { f -> FROM_ORDER.indexOf(f) }
        Item(it.ch, froms, froms.joinToString(" · ") { f -> FROM_TEXT[f] ?: f })
    }

    /**
     * 按课时取字。
     *
     * 保持教材顺序——家长打印「这课的生字」时，顺序要和课本对得上。
     */
    fun fromLesson(lessonChars: List<String>?): List<Candidate> =
        (lessonChars ?: emptyList()).map { Candidate(it, "lesson") }

    /**
     * 按星档取字。
     *
     * @param records progress.allWriteRecords() 的结果
     * @param stars 要哪一档（0~3）
     */
    fun fromStars(records: List<Pair<String, Progress.WriteRecord>>?, stars: Int): List<Candidate> =
        (records ?: emptyList())
            .filter { it.second.stars == stars }
            .map { Candidate(it.first, "stars") }

    /** 错题本里的字 */
    fun fromWrong(wrongChars: List<String>?): List<Candidate> =
        (wrongChars ?: emptyList()).map { Candidate(it, "wrong") }

    /** 笔画薄弱点里的字（失败过 2 次以上） */
    fun fromWeak(weakChars: List<String>?): List<Candidate> =
        (weakChars ?: emptyList()).map { Candidate(it, "weak") }

    /**
     * 选字的输入。
     *
     * 四条来源各是一份候选清单，页面按勾选状态决定给哪几份；
     * [stars] 为 null 表示不按星级选。
     */
    class Source(
        val lessonChars: List<String> = emptyList(),
        val records: List<Pair<String, Progress.WriteRecord>> = emptyList(),
        val wrongChars: List<String> = emptyList(),
        val weakChars: List<String> = emptyList(),
        val stars: Int? = null
    )

    /**
     * 一次算好整个选字界面要的字，已去重、已按来源优先级排好。
     *
     * 顺序：错题 → 弱笔 → 低星 → 课时。错题优先，因为它最该练；
     * 课时放最后，因为「本课生字」是一整批，排前面会把错题挤到屏幕下面。
     */
    fun build(src: Source): List<Item> {
        val raw = ArrayList<Candidate>()
        raw.addAll(fromWrong(src.wrongChars))
        raw.addAll(fromWeak(src.weakChars))
        val stars = src.stars
        if (stars != null) raw.addAll(fromStars(src.records, stars))
        raw.addAll(fromLesson(src.lessonChars))
        return decorate(merge(raw))
    }
}
