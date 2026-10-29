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

    data class Badge(val id: String, val emoji: String, val name: String, val desc: String, val got: Boolean)

    // 内存状态
    private val entries = HashMap<String, Srs.Entry>()
    private val days = HashMap<String, DayStat>()
    private val wrong = HashMap<String, WrongItemInternal>()
    private val writes = HashMap<String, WriteRecord>()

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

    fun writeStarsTotal(): Int = writes.values.sumOf { it.stars }

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
