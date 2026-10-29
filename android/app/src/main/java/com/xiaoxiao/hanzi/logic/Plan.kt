package com.xiaoxiao.hanzi.logic

import com.xiaoxiao.hanzi.data.Repo

/** 今日学习计划，与小程序 utils/plan.js 对应 */
object Plan {

    class LessonCount(val total: Int, val learned: Int, val rest: Int)

    fun countLesson(prog: Progress, lessonId: String?): LessonCount {
        val chars = Repo.lessonChars(lessonId)
        val learned = chars.count { prog.hasLearned(it) }
        return LessonCount(chars.size, learned, chars.size - learned)
    }

    fun firstUnlearned(chars: List<String>, prog: Progress): String =
        chars.firstOrNull { !prog.hasLearned(it) } ?: ""

    class BookProgress(val total: Int, val learned: Int, val mastered: Int, val due: Int, val pct: Int)

    fun bookProgress(prog: Progress, bookId: String): BookProgress {
        val chars = Repo.bookChars(bookId)
        val c = prog.counts(chars)
        return BookProgress(
            total = chars.size,
            learned = c.learned,
            mastered = c.mastered,
            due = c.due,
            pct = if (chars.isEmpty()) 0 else Math.round(c.learned.toFloat() / chars.size * 100)
        )
    }

    class ContinueInfo(
        val book: String,
        val lesson: String,
        val title: String,
        val bookName: String,
        val start: String,
        val learned: Int,
        val total: Int
    )

    /**
     * 找到应该继续学的那一课：
     * 1) 上次学到的那一课还没学完 -> 继续它
     * 2) 否则按目录顺序找下一课还有没学的字
     * 3) 全书学完 -> null
     */
    fun findContinue(prog: Progress, bookId: String): ContinueInfo? {
        val book = Repo.book(bookId) ?: return null
        val (lastLesson, _) = prog.lastLessonInfo()
        var startIndex = 0

        if (lastLesson != null) {
            val idx = book.lessons.indexOf(lastLesson)
            if (idx >= 0) {
                val c = countLesson(prog, lastLesson)
                if (c.rest > 0) {
                    return ContinueInfo(
                        book = bookId,
                        lesson = lastLesson,
                        title = Repo.lessonTitle(lastLesson),
                        bookName = book.short,
                        start = firstUnlearned(Repo.lessonChars(lastLesson), prog),
                        learned = c.learned,
                        total = c.total
                    )
                }
                startIndex = idx + 1
            }
        }

        for (i in book.lessons.indices) {
            val id = book.lessons[(startIndex + i) % book.lessons.size]
            val c = countLesson(prog, id)
            if (c.rest > 0) {
                return ContinueInfo(
                    book = bookId,
                    lesson = id,
                    title = Repo.lessonTitle(id),
                    bookName = book.short,
                    start = firstUnlearned(Repo.lessonChars(id), prog),
                    learned = c.learned,
                    total = c.total
                )
            }
        }
        return null
    }

    class TodayTask(
        val type: String,
        val title: String,
        val desc: String,
        val action: String,
        val count: Int
    )

    /** 生成首页「今日任务」 */
    fun buildTodayTask(prog: Progress, bookId: String): TodayTask {
        val due = prog.allDue()
        val settings = prog.settings
        val today = prog.todayStats()
        val dailyNew = if (settings.dailyNew > 0) settings.dailyNew else 5

        if (due.isNotEmpty()) {
            return TodayTask(
                type = "review",
                title = "先复习 ${due.size} 个字",
                desc = "温故而知新，几分钟就好",
                action = "开始复习",
                count = due.size
            )
        }
        if (today.learned >= dailyNew) {
            return TodayTask(
                type = "done",
                title = "今天的任务完成啦",
                desc = "新学了 ${today.learned} 个字，明天见！",
                action = "再练一组",
                count = 0
            )
        }
        val next = findContinue(prog, bookId)
        if (next != null) {
            val lessonNo = Repo.lesson(next.lesson)?.no ?: 0
            return TodayTask(
                type = "learn",
                title = "继续学第 $lessonNo 课",
                desc = "${next.title} · 已学 ${next.learned}/${next.total}",
                action = "去学新字",
                count = dailyNew - today.learned
            )
        }
        return TodayTask(
            type = "done",
            title = "这本已经学完啦",
            desc = "换一册，或者去复习巩固",
            action = "去复习",
            count = 0
        )
    }

    /** 今日推荐一个字（按日期轮换，保证每天不同） */
    fun pickDailyChar(bookId: String, dateKey: String): String {
        val chars = Repo.bookChars(bookId)
        if (chars.isEmpty()) return ""
        var h = 0
        for (c in dateKey) h = (h * 31 + c.code) and 0x7FFFFFFF
        return chars[h % chars.size]
    }

    class Session(val mode: String, val title: String, val book: String, val chars: List<String>, val count: Int)

    /** 练习会话：决定练哪些字，与小程序 utils/session.js 对应 */
    fun buildSession(
        mode: String,
        prog: Progress,
        book: String = Repo.defaultBook(),
        lesson: String? = null,
        chars: List<String>? = null,
        title: String? = null
    ): Session {
        return when (mode) {
            "review" -> {
                val due = chars ?: prog.allDue()
                Session("review", "今日复习", book, due.take(15), minOf(15, maxOf(4, due.size * 2)))
            }
            "lesson" -> {
                val list = chars ?: Repo.lessonChars(lesson)
                Session(
                    "lesson",
                    title ?: "本课练习",
                    book,
                    list,
                    maxOf(list.size, 8)
                )
            }
            "wrong" -> {
                val list = chars ?: prog.wrongList().map { it.ch }
                Session("wrong", "错题重练", book, list.take(12), minOf(15, list.size * 2))
            }
            else -> {
                val learned = Repo.bookChars(book).filter { prog.hasLearned(it) }
                val pool = if (learned.size >= 8) learned else Repo.bookChars(book)
                val picked = Quiz.shuffle(pool, Quiz.mulberry32(System.currentTimeMillis().toInt()))
                    .take(minOf(12, pool.size))
                Session(
                    "free",
                    title ?: (Repo.book(book)?.name ?: "") + " · 随机练习",
                    book,
                    picked,
                    10
                )
            }
        }
    }
}
