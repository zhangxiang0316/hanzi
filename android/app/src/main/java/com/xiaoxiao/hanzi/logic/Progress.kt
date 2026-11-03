package com.xiaoxiao.hanzi.logic

import com.xiaoxiao.hanzi.data.Repo
import org.json.JSONObject

/**
 * 学习进度：SRS 条目、每日统计、连续天数、错题本、描红成绩、设置。
 * 与小程序 utils/progress.js 行为一致，只是存储换成 SharedPreferences。
 *
 * 内存里保留一份可变状态，写入时整体序列化 —— 数据量小，简单可靠。
 */
class Progress(private val store: Store) {

    data class Settings(
        val dailyNew: Int = 5,
        val book: String = "1a",
        val showPinyin: Boolean = true
    )

    data class DayStat(val learned: Int = 0, val answers: Int = 0, val correct: Int = 0)

    data class WrongItem(val ch: String, val n: Int, val first: Int, val last: Int, val lesson: String?)

    data class WriteRecord(val best: Int, val stars: Int, val tries: Int, val last: Int)

    /** 某一笔的失败 / 尝试次数 / 连胜次数 */
    data class WeakStroke(val fails: Int, val tries: Int, val ok: Int = 0)

    /** 一条薄弱点（用于列表展示） */
    data class WeakPoint(val ch: String, val index: Int, val fails: Int, val tries: Int)

    data class Badge(val id: String, val emoji: String, val name: String, val desc: String, val got: Boolean)

    // 内存状态
    private val entries = HashMap<String, Srs.Entry>()
    private val days = HashMap<String, DayStat>()
    private val wrong = HashMap<String, WrongItemInternal>()
    private val writes = HashMap<String, WriteRecord>()

    /**
     * 笔画薄弱点：字 → (笔画序号 → 记录)。
     *
     * 描红判分本来每笔都会算出「为什么不过」（起笔错 / 偏离 / 写短了），
     * 但之前只拿它拼一句即时提示就丢掉了。留下来才看得出
     * 「这个字的第 2 笔你反复写不好」——比整字分数具体。
     */
    private val weak = HashMap<String, HashMap<Int, WeakStroke>>()

    // 不能叫 streak：Kotlin 会为同名属性生成 getStreak()，与下面手写的 getStreak() 冲突
    private var streakCount: Int = 0
    private var lastDay: Int = 0
    private var quizzes: Int = 0
    private var perfect: Int = 0

    var settings: Settings = Settings()
        private set

    private var lastLesson: String? = null
    private var lastBook: String? = null

    private class WrongItemInternal(
        var n: Int,
        var first: Int,
        var last: Int,
        var lesson: String?
    )

    init {
        load()
    }

    /**
     * 从当前命名空间重读全部状态。
     *
     * 切换孩子档案时必须调用：存储的键换了前缀，但这份内存状态还是上一个
     * 孩子的。不重读的话界面会显示「名字换了、数据没变」——比不换还糟。
     */
    fun reload() {
        entries.clear()
        days.clear()
        wrong.clear()
        writes.clear()
        weak.clear()
        streakCount = 0
        lastDay = 0
        quizzes = 0
        perfect = 0
        lastLesson = null
        lastBook = null
        settings = Settings()
        load()
    }

    // ---------- 序列化 ----------

    private fun load() {
        store.readJson("progress")?.let { obj ->
            val keys = obj.keys()
            while (keys.hasNext()) {
                val ch = keys.next()
                val e = obj.getJSONObject(ch)
                entries[ch] = Srs.Entry(
                    box = e.optInt("box"),
                    seen = e.optInt("seen"),
                    ok = e.optInt("ok"),
                    miss = e.optInt("miss"),
                    due = e.optInt("due"),
                    last = e.optInt("last"),
                    known = e.optBoolean("known")
                )
            }
        }

        store.readJson("settings")?.let { obj ->
            settings = Settings(
                dailyNew = obj.optInt("dailyNew", 5),
                book = obj.optString("book", "1a"),
                showPinyin = obj.optBoolean("showPinyin", true)
            )
        }

        store.readJson("stats")?.let { obj ->
            streakCount = obj.optInt("streak")
            lastDay = obj.optInt("lastDay")
            quizzes = obj.optInt("quizzes")
            perfect = obj.optInt("perfect")
            val d = obj.optJSONObject("days")
            if (d != null) {
                val keys = d.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    val o = d.getJSONObject(k)
                    days[k] = DayStat(
                        o.optInt("learned"),
                        o.optInt("answers"),
                        o.optInt("correct")
                    )
                }
            }
        }

        store.readJson("wrong")?.let { obj ->
            val keys = obj.keys()
            while (keys.hasNext()) {
                val ch = keys.next()
                val o = obj.getJSONObject(ch)
                wrong[ch] = WrongItemInternal(
                    n = o.optInt("n", 1),
                    first = o.optInt("first"),
                    last = o.optInt("last"),
                    lesson = o.optString("lesson").ifEmpty { null }
                )
            }
        }

        store.readJson("write")?.let { obj ->
            val keys = obj.keys()
            while (keys.hasNext()) {
                val ch = keys.next()
                val o = obj.getJSONObject(ch)
                writes[ch] = WriteRecord(
                    best = o.optInt("best"),
                    stars = o.optInt("stars"),
                    tries = o.optInt("tries"),
                    last = o.optInt("last")
                )
            }
        }

        store.readJson("weak")?.let { obj ->
            val chKeys = obj.keys()
            while (chKeys.hasNext()) {
                val ch = chKeys.next()
                val o = obj.getJSONObject(ch)
                val m = HashMap<Int, WeakStroke>()
                val iKeys = o.keys()
                while (iKeys.hasNext()) {
                    val k = iKeys.next()
                    val r = o.getJSONObject(k)
                    m[k.toIntOrNull() ?: continue] = WeakStroke(
                        fails = r.optInt("f"),
                        tries = r.optInt("t"),
                        ok = r.optInt("o")
                    )
                }
                if (m.isNotEmpty()) weak[ch] = m
            }
        }

        store.readJson("last")?.let { obj ->
            lastLesson = obj.optString("lesson").ifEmpty { null }
            lastBook = obj.optString("book").ifEmpty { null }
        }
    }

    private fun persistProgress() {
        val obj = JSONObject()
        for ((ch, e) in entries) {
            obj.put(
                ch,
                JSONObject()
                    .put("box", e.box).put("seen", e.seen).put("ok", e.ok)
                    .put("miss", e.miss).put("due", e.due).put("last", e.last)
                    .put("known", e.known)
            )
        }
        store.writeJson("progress", obj)
    }

    private fun persistStats() {
        val d = JSONObject()
        for ((k, v) in days) {
            d.put(k, JSONObject().put("learned", v.learned).put("answers", v.answers).put("correct", v.correct))
        }
        store.writeJson(
            "stats",
            JSONObject().put("days", d).put("streak", streakCount).put("lastDay", lastDay)
                .put("quizzes", quizzes).put("perfect", perfect)
        )
    }

    private fun persistWrong() {
        val obj = JSONObject()
        for ((ch, w) in wrong) {
            obj.put(
                ch,
                JSONObject().put("n", w.n).put("first", w.first).put("last", w.last)
                    .put("lesson", w.lesson ?: "")
            )
        }
        store.writeJson("wrong", obj)
    }

    private fun persistSettings() {
        store.writeJson(
            "settings",
            JSONObject().put("dailyNew", settings.dailyNew).put("book", settings.book)
                .put("showPinyin", settings.showPinyin)
        )
    }

    private fun persistWeak() {
        val obj = JSONObject()
        for ((ch, m) in weak) {
            val o = JSONObject()
            for ((i, r) in m) {
                o.put(i.toString(), JSONObject().put("f", r.fails)
                    .put("t", r.tries).put("o", r.ok))
            }
            obj.put(ch, o)
        }
        store.writeJson("weak", obj)
    }

    private fun persistWrite() {
        val obj = JSONObject()
        for ((ch, w) in writes) {
            obj.put(ch, JSONObject().put("best", w.best).put("stars", w.stars)
                .put("tries", w.tries).put("last", w.last))
        }
        store.writeJson("write", obj)
    }

    // ---------- 日期与连续天数 ----------

    private fun today(): Int = DayUtil.dayNumber()

    private fun ensureDay(): DayStat {
        val n = today()
        val key = DayUtil.todayKey()
        val cur = days.getOrPut(key) { DayStat() }
        if (lastDay != n) {
            streakCount = if (lastDay == n - 1) streakCount + 1 else 1
            lastDay = n
        }
        return cur
    }

    fun getStreak(): Int {
        val n = today()
        return if (lastDay == n || lastDay == n - 1) streakCount else 0
    }

    fun todayStats(): DayStat = days[DayUtil.todayKey()] ?: DayStat()

    fun accuracyToday(): Int {
        val d = todayStats()
        return if (d.answers > 0) Math.round(d.correct.toFloat() / d.answers * 100) else 0
    }

    // ---------- 学习状态 ----------

    fun entry(ch: String): Srs.Entry? = entries[ch]

    fun hasLearned(ch: String): Boolean = Srs.isLearning(entries[ch])

    fun isMastered(ch: String): Boolean = Srs.isMastered(entries[ch])

    fun learn(ch: String) {
        val e = entries[ch]
        if (e != null && e.box >= 1) return
        val daily = ensureDay()
        entries[ch] = Srs.learn(e, today())
        days[DayUtil.todayKey()] = daily.copy(learned = daily.learned + 1)
        persistProgress()
        persistStats()
    }

    fun markKnown(ch: String) {
        val daily = ensureDay()
        val before = entries[ch]
        val addLearned = before == null || before.box < 1
        entries[ch] = Srs.markKnown(before, today())
        if (addLearned) days[DayUtil.todayKey()] = daily.copy(learned = daily.learned + 1)
        persistProgress()
        persistStats()
    }

    fun grade(ch: String, correct: Boolean, lesson: String? = null) {
        val daily = ensureDay()
        entries[ch] = Srs.grade(entries[ch], correct, today())
        days[DayUtil.todayKey()] = daily.copy(
            answers = daily.answers + 1,
            correct = if (correct) daily.correct + 1 else daily.correct
        )

        if (correct) {
            val w = wrong[ch]
            if (w != null) {
                w.n -= 1
                if (w.n <= 0) wrong.remove(ch)
            }
        } else {
            val now = today()
            val w = wrong[ch]
            if (w == null) {
                wrong[ch] = WrongItemInternal(1, now, now, lesson)
            } else {
                w.n += 1
                w.last = now
                if (lesson != null) w.lesson = lesson
            }
        }
        persistProgress()
        persistStats()
        persistWrong()
    }

    fun recordQuiz(total: Int, correct: Int) {
        quizzes += 1
        if (total > 0 && correct == total) perfect += 1
        persistStats()
    }

    fun dueChars(chars: List<String>? = null): List<String> {
        val t = today()
        val list = chars ?: entries.keys.toList()
        return list.filter { Srs.isDue(entries[it], t) }
    }

    fun allDue(): List<String> = dueChars(entries.keys.toList())

    class Counts(val total: Int, val learned: Int, val mastered: Int, val due: Int, val weak: Int)

    fun counts(chars: List<String>): Counts {
        val t = today()
        var learned = 0
        var mastered = 0
        var due = 0
        var weak = 0
        for (ch in chars) {
            val e = entries[ch] ?: continue
            if (e.box < 1) continue
            learned++
            if (e.box >= Srs.MASTERED_BOX) mastered++
            if (e.box < 3) weak++
            if (Srs.isDue(e, t)) due++
        }
        return Counts(chars.size, learned, mastered, due, weak)
    }

    fun totalLearned(): Int = entries.values.count { it.box >= 1 }

    fun totalMastered(): Int = entries.values.count { Srs.isMastered(it) }

    // ---------- 错题 ----------

    fun wrongList(): List<WrongItem> = wrong.map { (ch, w) ->
        WrongItem(ch, w.n, w.first, w.last, w.lesson)
    }.sortedWith(compareByDescending<WrongItem> { it.n }.thenByDescending { it.last })

    fun wrongCount(): Int = wrong.size

    fun clearWrong(ch: String? = null) {
        if (ch != null) wrong.remove(ch) else wrong.clear()
        persistWrong()
    }

    // ---------- 描红成绩 ----------

    fun writeRecord(ch: String): WriteRecord? = writes[ch]

    fun saveWrite(ch: String, score: Int): WriteRecord {
        val old = writes[ch]
        val stars = Trace.starsOf(score)
        val record = WriteRecord(
            best = maxOf(old?.best ?: 0, score),
            stars = maxOf(old?.stars ?: 0, stars),
            tries = (old?.tries ?: 0) + 1,
            last = today()
        )
        writes[ch] = record
        persistWrite()
        return record
    }

    /**
     * 记录一笔的结果。
     *
     * `passed` 是这一笔过没过判分线。失败次数才是「薄弱」的依据：
     * 一次成功不能抵消两次失败——真正写不好的笔画会一直被记着。
     *
     * 练好的判定是**连续写对 2 次**（`ok` 记连胜）。
     * 为什么不「写对一次就清掉」：那样 `tries` 永远等于 `fails`，
     * 而且手抖蒙对一次就前功尽弃。
     */
    fun recordStroke(ch: String, index: Int, passed: Boolean) {
        if (ch.isEmpty()) return
        val m = weak.getOrPut(ch) { HashMap() }
        val old = m[index] ?: WeakStroke(0, 0)
        if (passed) {
            if (old.ok + 1 >= 2) {
                // 连续两次写对：这一笔练稳了，不用再提示
                m.remove(index)
                if (m.isEmpty()) weak.remove(ch)
                persistWeak()
                return
            }
            m[index] = WeakStroke(old.fails, old.tries + 1, old.ok + 1)
        } else {
            m[index] = WeakStroke(old.fails + 1, old.tries + 1, 0)
        }
        persistWeak()
    }

    /**
     * 这个字哪些笔画是薄弱点：失败 ≥ 2 次。
     *
     * 只错一次是很正常的（手抖、第一次不熟），不算薄弱点。
     * 不再叠「失败率 ≥40%」——加上「连对两次即移除」之后，任何还在册的
     * 记录都满足 `tries ≤ 2f+1`，失败率恒 ≥50%，那条判断是死代码。
     */
    fun weakStrokesOf(ch: String): List<WeakPoint> {
        val m = weak[ch] ?: return emptyList()
        return m.entries
            .filter { it.value.fails >= 2 }
            .map { WeakPoint(ch, it.key, it.value.fails, it.value.tries) }
            .sortedBy { it.index }
    }

    /** 有没有需要专门练的笔画 */
    fun hasWeakStrokes(ch: String): Boolean = weakStrokesOf(ch).isNotEmpty()

    /**
     * 全部薄弱点，按「最需要练」排序：失败次数多的在前。
     *
     * 同一字的多个笔画各占一条——「日的第2笔」和「日的第4笔」
     * 是两个不同的动作，合成一条就没法分别练。
     */
    fun allWeakStrokes(): List<WeakPoint> = weak.keys
        .flatMap { weakStrokesOf(it) }
        .sortedWith(compareByDescending<WeakPoint> { it.fails }
            .thenBy { it.ch.codePointAt(0) }
            .thenBy { it.index })

    /**
     * 有薄弱笔画的字，每个字只出现一次（取最弱的那一笔）。
     *
     * 练习入口用这个：一个字的第 2 笔和第 4 笔都在练同一份描红，
     * 按笔画列出会重复练同一个字。
     */
    fun weakChars(): List<WeakPoint> {
        val seen = HashSet<String>()
        val out = ArrayList<WeakPoint>()
        for (w in allWeakStrokes()) {
            if (seen.add(w.ch)) out.add(w)
        }
        return out
    }

    /** 某一笔练好了：把它从薄弱点里去掉 */
    fun clearWeakStroke(ch: String, index: Int) {
        val m = weak[ch] ?: return
        m.remove(index)
        if (m.isEmpty()) weak.remove(ch)
        persistWeak()
    }

    /** 整个字从薄弱点里清掉 */
    fun clearWeak(ch: String) {
        weak.remove(ch) ?: return
        persistWeak()
    }

    fun writeStarsTotal(): Int = writes.values.sumOf { it.stars }

    /** 写过多少个字 */
    fun writeCount(): Int = writes.size

    /**
     * 所有写过字的记录，按「最近写的在前，同一天按最高分降序」排。
     *
     * 排序刻意不按字的音序：孩子翻开字帖想看的是「我最近写的」，
     * 而不是「按拼音排的一堆字」——后者更像词典，不像自己的成果。
     */
    fun allWriteRecords(): List<Pair<String, WriteRecord>> =
        writes.entries
            .map { it.key to it.value }
            .sortedWith(
                compareByDescending<Pair<String, WriteRecord>> { it.second.last }
                    .thenByDescending { it.second.best }
                    .thenBy { it.first }   // 兜底：保证顺序稳定，测试可复现
            )

    /** 按星级分档的数量（3 星 / 2 星 / 1 星 / 0 星），四个键一定存在 */
    fun writeStarsHistogram(): Map<Int, Int> {
        val out = mutableMapOf(0 to 0, 1 to 0, 2 to 0, 3 to 0)
        for (r in writes.values) out[r.stars] = (out[r.stars] ?: 0) + 1
        return out
    }

    // ---------- 设置 ----------

    fun updateSettings(patch: Settings) {
        settings = patch
        persistSettings()
    }

    fun lastLessonInfo(): Pair<String?, String?> = lastLesson to lastBook

    fun setLast(lesson: String, book: String) {
        lastLesson = lesson
        lastBook = book
        store.writeJson("last", JSONObject().put("lesson", lesson).put("book", book).put("at", today()))
    }

    // ---------- 统计 ----------

    class DayRow(
        val key: String, val label: String,
        val learned: Int, val answers: Int, val correct: Int, val rate: Int
    )

    fun recentDays(n: Int): List<DayRow> {
        val out = ArrayList<DayRow>(n)
        for (i in n - 1 downTo 0) {
            val key = DayUtil.dayKeyOf(-i)
            val d = days[key] ?: DayStat()
            val date = DayUtil.dateOfOffset(-i)
            out.add(
                DayRow(
                    key = key,
                    label = DayUtil.weekdayCN(date).replace("周", ""),
                    learned = d.learned,
                    answers = d.answers,
                    correct = d.correct,
                    rate = if (d.answers > 0) Math.round(d.correct.toFloat() / d.answers * 100) else 0
                )
            )
        }
        return out
    }

    fun activeDays(): Int = days.values.count { it.learned > 0 || it.answers > 0 }

    fun badges(): List<Badge> {
        val learned = totalLearned()
        val streak = getStreak()
        val stars = writeStarsTotal()
        return listOf(
            Badge("sprout", "🌱", "破土而出", "认识 1 个汉字", learned >= 1),
            Badge("ten", "📖", "小书童", "认识 10 个汉字", learned >= 10),
            Badge("fifty", "⭐", "识字小达人", "认识 50 个汉字", learned >= 50),
            Badge("hundred", "🏅", "百字斩", "认识 100 个汉字", learned >= 100),
            Badge("five", "👑", "汉字收藏家", "认识 500 个汉字", learned >= 500),
            Badge("streak", "🔥", "坚持之星", "连续学习 3 天", streak >= 3),
            Badge("perfect", "🎯", "满分小状元", "闯关全部答对", perfect >= 1),
            Badge("write", "✍️", "小小书法家", "描红获得 10 颗星", stars >= 10)
        )
    }

    fun resetAll() {
        entries.clear()
        days.clear()
        wrong.clear()
        writes.clear()
        weak.clear()
        streakCount = 0
        lastDay = 0
        quizzes = 0
        perfect = 0
        settings = Settings(book = Repo.defaultBook())
        lastLesson = null
        lastBook = null
        store.clearAll()
        persistSettings()
    }
}
