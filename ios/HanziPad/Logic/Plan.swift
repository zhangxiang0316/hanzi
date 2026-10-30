import Foundation

/// 今日学习计划，与 Android `logic/Plan.kt` / 小程序 `utils/plan.js` 对应。
@MainActor
enum Plan {

    struct LessonCount {
        let total: Int
        let learned: Int
        let rest: Int
    }

    struct BookProgress {
        let total: Int
        let learned: Int
        let mastered: Int
        let due: Int
        let pct: Int
    }

    struct ContinueInfo {
        let book: String
        let lesson: String
        let title: String
        let bookName: String
        let start: String
        let learned: Int
        let total: Int
    }

    struct TodayTask {
        let type: String
        let title: String
        let desc: String
        let action: String
        let count: Int
    }

    struct Session {
        let mode: String
        let title: String
        let book: String
        let chars: [String]
        let count: Int
    }

    static func countLesson(_ prog: Progress, _ lessonId: String?) -> LessonCount {
        let chars = Repo.shared.lessonChars(lessonId)
        let learned = chars.filter { prog.hasLearned($0) }.count
        return LessonCount(total: chars.count, learned: learned, rest: chars.count - learned)
    }

    static func firstUnlearned(_ chars: [String], _ prog: Progress) -> String {
        chars.first { !prog.hasLearned($0) } ?? ""
    }

    static func bookProgress(_ prog: Progress, _ bookId: String) -> BookProgress {
        let chars = Repo.shared.bookChars(bookId)
        let c = prog.counts(chars)
        return BookProgress(
            total: chars.count,
            learned: c.learned,
            mastered: c.mastered,
            due: c.due,
            pct: chars.isEmpty ? 0 : Int((Float(c.learned) / Float(chars.count) * 100).rounded())
        )
    }

    /// 找到应该继续学的那一课：
    /// 1) 上次学到的那一课还没学完 → 继续它
    /// 2) 否则按目录顺序找下一课还有没学的字
    /// 3) 全书学完 → nil
    static func findContinue(_ prog: Progress, _ bookId: String) -> ContinueInfo? {
        guard let book = Repo.shared.book(bookId) else { return nil }
        let last = prog.lastLessonInfo.lesson
        var startIndex = 0

        if let lastLesson = last {
            if let idx = book.lessons.firstIndex(of: lastLesson) {
                let c = countLesson(prog, lastLesson)
                if c.rest > 0 {
                    return ContinueInfo(
                        book: bookId,
                        lesson: lastLesson,
                        title: Repo.shared.lessonTitle(lastLesson),
                        bookName: book.short,
                        start: firstUnlearned(Repo.shared.lessonChars(lastLesson), prog),
                        learned: c.learned,
                        total: c.total
                    )
                }
                startIndex = idx + 1
            }
        }

        if !book.lessons.isEmpty {
            for i in book.lessons.indices {
                let id = book.lessons[(startIndex + i) % book.lessons.count]
                let c = countLesson(prog, id)
                if c.rest > 0 {
                    return ContinueInfo(
                        book: bookId,
                        lesson: id,
                        title: Repo.shared.lessonTitle(id),
                        bookName: book.short,
                        start: firstUnlearned(Repo.shared.lessonChars(id), prog),
                        learned: c.learned,
                        total: c.total
                    )
                }
            }
        }
        return nil
    }

    /// 生成首页「今日任务」
    static func buildTodayTask(_ prog: Progress, _ bookId: String) -> TodayTask {
        let due = prog.allDue()
        let settings = prog.settings
        let today = prog.todayStats
        let dailyNew = settings.dailyNew > 0 ? settings.dailyNew : 5

        if !due.isEmpty {
            return TodayTask(
                type: "review",
                title: "先复习 \(due.count) 个字",
                desc: "温故而知新，几分钟就好",
                action: "开始复习",
                count: due.count
            )
        }
        if today.learned >= dailyNew {
            return TodayTask(
                type: "done",
                title: "今天的任务完成啦",
                desc: "新学了 \(today.learned) 个字，明天见！",
                action: "再练一组",
                count: 0
            )
        }
        if let next = findContinue(prog, bookId) {
            let lessonNo = Repo.shared.lesson(next.lesson)?.no ?? 0
            return TodayTask(
                type: "learn",
                title: "继续学第 \(lessonNo) 课",
                desc: "\(next.title) · 已学 \(next.learned)/\(next.total)",
                action: "去学新字",
                count: dailyNew - today.learned
            )
        }
        return TodayTask(
            type: "done",
            title: "这本已经学完啦",
            desc: "换一册，或者去复习巩固",
            action: "去复习",
            count: 0
        )
    }

    /// 今日推荐一个字（按日期轮换，保证每天不同）
    static func pickDailyChar(_ bookId: String, _ dateKey: String) -> String {
        let chars = Repo.shared.bookChars(bookId)
        if chars.isEmpty { return "" }
        var h: Int32 = 0
        for c in dateKey.utf8 {
            h = (h &* 31 &+ Int32(c)) & 0x7FFF_FFFF
        }
        return chars[Int(h) % chars.count]
    }

    /// 练习会话：决定练哪些字，与 Android / 小程序 utils/session.js 对应
    static func buildSession(
        mode: String,
        prog: Progress,
        book: String? = nil,
        lesson: String? = nil,
        chars: [String]? = nil,
        title: String? = nil
    ) -> Session {
        let bookId = book ?? Repo.shared.defaultBook()
        switch mode {
        case "review":
            let due = chars ?? prog.allDue()
            return Session(
                mode: "review", title: "今日复习", book: bookId,
                chars: Array(due.prefix(15)),
                count: min(15, max(4, due.count * 2))
            )
        case "lesson":
            let list = chars ?? Repo.shared.lessonChars(lesson)
            return Session(
                mode: "lesson", title: title ?? "本课练习", book: bookId,
                chars: list, count: max(list.count, 8)
            )
        case "wrong":
            let list = chars ?? prog.wrongList.map(\.ch)
            return Session(
                mode: "wrong", title: "错题重练", book: bookId,
                chars: Array(list.prefix(12)),
                count: min(15, list.count * 2)
            )
        default:
            let learned = Repo.shared.bookChars(bookId).filter { prog.hasLearned($0) }
            let pool = learned.count >= 8 ? learned : Repo.shared.bookChars(bookId)
            let rand = Quiz.mulberry32(UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000)))
            let picked = Array(Quiz.shuffle(pool, rand).prefix(min(12, pool.count)))
            let bookName = Repo.shared.book(bookId)?.name ?? ""
            return Session(
                mode: "free", title: title ?? (bookName + " · 随机练习"),
                book: bookId, chars: picked, count: 10
            )
        }
    }
}
