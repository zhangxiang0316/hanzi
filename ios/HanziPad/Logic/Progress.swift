import Foundation

/// 学习进度：SRS 条目、每日统计、连续天数、错题本、描红成绩、设置。
/// 与 Android `logic/Progress.kt` / 小程序 `utils/progress.js` 行为一致。
///
/// 内存里保留一份可变状态，写入时整体序列化——数据量小，简单可靠。
///
/// 标 `@MainActor` 的理由和 Repo 一样：所有读写都发生在界面上，
/// 用 actor 隔离比在每个方法里加锁清楚得多。
@MainActor
final class Progress {

    struct Settings: Equatable {
        var dailyNew: Int = 5
        var book: String = "1a"
        var showPinyin: Bool = true
        /// 朗读语速，1.0 为正常。iOS 侧新增（Android 固定 0.85）
        var speechRate: Float = 0.85
        /// 是否开启朗读
        var speakEnabled: Bool = true
    }

    struct DayStat: Equatable {
        var learned: Int = 0
        var answers: Int = 0
        var correct: Int = 0
    }

    struct WrongItem {
        let ch: String
        let n: Int
        let first: Int
        let last: Int
        let lesson: String?
    }

    struct WriteRecord: Equatable {
        var best: Int
        var stars: Int
        var tries: Int
        var last: Int
    }

    struct Badge {
        let id: String
        let emoji: String
        let name: String
        let desc: String
        let got: Bool
    }

    private final class WrongInternal {
        var n: Int
        var first: Int
        var last: Int
        var lesson: String?
        init(n: Int, first: Int, last: Int, lesson: String?) {
            self.n = n
            self.first = first
            self.last = last
            self.lesson = lesson
        }
    }

    private let store: Store

    private var entries: [String: Srs.Entry] = [:]
    private var days: [String: DayStat] = [:]
    private var wrong: [String: WrongInternal] = [:]
    private var writes: [String: WriteRecord] = [:]

    private var streakCount = 0
    private var lastDay = 0
    private var quizzes = 0
    private var perfect = 0

    private(set) var settings = Settings()

    private var lastLesson: String?
    private var lastBook: String?
    /// 上次学习日期（用于计算连续天数）
    private var lastStudyDay = 0

    init(store: Store) {
        self.store = store
        load()
    }

    // MARK: - 序列化

    private func load() {
        if let obj = store.readObject("progress"), let raw = obj["entries"] as? [String: [String: Any]] {
            for (ch, o) in raw {
                entries[ch] = Srs.Entry(
                    box: o["box"] as? Int ?? 0,
                    seen: o["seen"] as? Int ?? 0,
                    ok: o["ok"] as? Int ?? 0,
                    miss: o["miss"] as? Int ?? 0,
                    due: o["due"] as? Int ?? 0,
                    last: o["last"] as? Int ?? 0,
                    known: o["known"] as? Bool ?? false
                )
            }
        }

        if let obj = store.readObject("stats") {
            streakCount = obj["streak"] as? Int ?? 0
            lastDay = obj["lastDay"] as? Int ?? 0
            quizzes = obj["quizzes"] as? Int ?? 0
            perfect = obj["perfect"] as? Int ?? 0
            lastStudyDay = obj["lastStudyDay"] as? Int ?? 0
            if let d = obj["days"] as? [String: [String: Any]] {
                for (k, o) in d {
                    days[k] = DayStat(
                        learned: o["learned"] as? Int ?? 0,
                        answers: o["answers"] as? Int ?? 0,
                        correct: o["correct"] as? Int ?? 0
                    )
                }
            }
        }

        if let obj = store.readObject("wrong"), let raw = obj["items"] as? [String: [String: Any]] {
            for (ch, o) in raw {
                wrong[ch] = WrongInternal(
                    n: o["n"] as? Int ?? 1,
                    first: o["first"] as? Int ?? 0,
                    last: o["last"] as? Int ?? 0,
                    lesson: o["lesson"] as? String
                )
            }
        }

        if let obj = store.readObject("writes"), let raw = obj["items"] as? [String: [String: Any]] {
            for (ch, o) in raw {
                writes[ch] = WriteRecord(
                    best: o["best"] as? Int ?? 0,
                    stars: o["stars"] as? Int ?? 0,
                    tries: o["tries"] as? Int ?? 0,
                    last: o["last"] as? Int ?? 0
                )
            }
        }

        if let obj = store.readObject("settings") {
            var s = Settings()
            s.dailyNew = obj["dailyNew"] as? Int ?? 5
            s.book = obj["book"] as? String ?? "1a"
            s.showPinyin = obj["showPinyin"] as? Bool ?? true
            s.speechRate = (obj["speechRate"] as? Double).map(Float.init) ?? 0.85
            s.speakEnabled = obj["speakEnabled"] as? Bool ?? true
            settings = s
        }

        if let obj = store.readObject("last") {
            lastLesson = obj["lesson"] as? String
            lastBook = obj["book"] as? String
        }
    }

    private func persistProgress() {
        var map: [String: [String: Any]] = [:]
        for (ch, e) in entries {
            map[ch] = [
                "box": e.box, "seen": e.seen, "ok": e.ok,
                "miss": e.miss, "due": e.due, "last": e.last, "known": e.known,
            ]
        }
        store.writeObject("progress", ["entries": map])
    }

    private func persistStats() {
        var d: [String: [String: Any]] = [:]
        for (k, v) in days {
            d[k] = ["learned": v.learned, "answers": v.answers, "correct": v.correct]
        }
        store.writeObject("stats", [
            "days": d, "streak": streakCount, "lastDay": lastDay,
            "quizzes": quizzes, "perfect": perfect, "lastStudyDay": lastStudyDay,
        ])
    }

    private func persistWrong() {
        var map: [String: [String: Any]] = [:]
        for (ch, w) in wrong {
            var o: [String: Any] = ["n": w.n, "first": w.first, "last": w.last]
            if let l = w.lesson { o["lesson"] = l }
            map[ch] = o
        }
        store.writeObject("wrong", ["items": map])
    }

    private func persistWrites() {
        var map: [String: [String: Any]] = [:]
        for (ch, w) in writes {
            map[ch] = ["best": w.best, "stars": w.stars, "tries": w.tries, "last": w.last]
        }
        store.writeObject("writes", ["items": map])
    }

    private func persistSettings() {
        store.writeObject("settings", [
            "dailyNew": settings.dailyNew,
            "book": settings.book,
            "showPinyin": settings.showPinyin,
            "speechRate": Double(settings.speechRate),
            "speakEnabled": settings.speakEnabled,
        ])
    }

    // MARK: - 日期与连续天数

    private func today() -> Int { DayUtil.dayNumber() }

    @discardableResult
    private func ensureDay() -> DayStat {
        let n = today()
        let key = DayUtil.todayKey()
        if days[key] == nil { days[key] = DayStat() }
        if lastDay != n {
            streakCount = (lastDay == n - 1) ? streakCount + 1 : 1
            lastDay = n
        }
        lastStudyDay = n
        return days[key]!
    }

    var streak: Int {
        let n = today()
        return (lastDay == n || lastDay == n - 1) ? streakCount : 0
    }

    var todayStats: DayStat { days[DayUtil.todayKey()] ?? DayStat() }

    var accuracyToday: Int {
        let d = todayStats
        guard d.answers > 0 else { return 0 }
        return Int((Float(d.correct) / Float(d.answers) * 100).rounded())
    }

    // MARK: - 学习状态

    func entry(_ ch: String) -> Srs.Entry? { entries[ch] }
    func hasLearned(_ ch: String) -> Bool { Srs.isLearning(entries[ch]) }
    func isMastered(_ ch: String) -> Bool { Srs.isMastered(entries[ch]) }

    func learn(_ ch: String) {
        if let e = entries[ch], e.box >= 1 { return }
        var daily = ensureDay()
        entries[ch] = Srs.learn(entries[ch], today: today())
        daily.learned += 1
        days[DayUtil.todayKey()] = daily
        persistProgress()
        persistStats()
    }

    func markKnown(_ ch: String) {
        var daily = ensureDay()
        let before = entries[ch]
        let addLearned = before == nil || before!.box < 1
        entries[ch] = Srs.markKnown(before, today: today())
        if addLearned {
            daily.learned += 1
            days[DayUtil.todayKey()] = daily
        }
        persistProgress()
        persistStats()
    }

    func grade(_ ch: String, correct: Bool, lesson: String? = nil) {
        var daily = ensureDay()
        entries[ch] = Srs.grade(entries[ch], correct: correct, today: today())
        daily.answers += 1
        if correct { daily.correct += 1 }
        days[DayUtil.todayKey()] = daily

        if correct {
            if let w = wrong[ch] {
                w.n -= 1
                if w.n <= 0 { wrong.removeValue(forKey: ch) }
            }
        } else {
            let now = today()
            if let w = wrong[ch] {
                w.n += 1
                w.last = now
                if let lesson { w.lesson = lesson }
            } else {
                wrong[ch] = WrongInternal(n: 1, first: now, last: now, lesson: lesson)
            }
        }
        persistProgress()
        persistStats()
        persistWrong()
    }

    func recordQuiz(total: Int, correct: Int) {
        quizzes += 1
        if total > 0 && correct == total { perfect += 1 }
        persistStats()
    }

    func dueChars(_ chars: [String]? = nil) -> [String] {
        let t = today()
        let list = chars ?? Array(entries.keys)
        return list.filter { Srs.isDue(entries[$0], today: t) }
    }

    func allDue() -> [String] { dueChars(Array(entries.keys)) }

    struct Counts {
        let total: Int
        let learned: Int
        let mastered: Int
        let due: Int
        let weak: Int
    }

    func counts(_ chars: [String]) -> Counts {
        let t = today()
        var learned = 0, mastered = 0, due = 0, weak = 0
        for ch in chars {
            guard let e = entries[ch], e.box >= 1 else { continue }
            learned += 1
            if e.box >= Srs.masteredBox { mastered += 1 }
            if e.box < 3 { weak += 1 }
            if Srs.isDue(e, today: t) { due += 1 }
        }
        return Counts(total: chars.count, learned: learned, mastered: mastered, due: due, weak: weak)
    }

    var totalLearned: Int { entries.values.filter { $0.box >= 1 }.count }
    var totalMastered: Int { entries.values.filter { Srs.isMastered($0) }.count }

    // MARK: - 错题

    var wrongList: [WrongItem] {
        wrong.map { WrongItem(ch: $0.key, n: $0.value.n, first: $0.value.first,
                              last: $0.value.last, lesson: $0.value.lesson) }
            // 先按错误次数降序，次数相同按最近出错时间降序
            .sorted { a, b in
                a.n != b.n ? a.n > b.n : a.last > b.last
            }
    }

    var wrongCount: Int { wrong.count }

    func clearWrong(_ ch: String? = nil) {
        if let ch { wrong.removeValue(forKey: ch) } else { wrong.removeAll() }
        persistWrong()
    }

    // MARK: - 描红成绩

    func writeRecord(_ ch: String) -> WriteRecord? { writes[ch] }

    @discardableResult
    func saveWrite(_ ch: String, score: Int) -> WriteRecord {
        let old = writes[ch]
        let stars = Trace.starsOf(score)
        let record = WriteRecord(
            best: max(old?.best ?? 0, score),
            stars: max(old?.stars ?? 0, stars),
            tries: (old?.tries ?? 0) + 1,
            last: today()
        )
        writes[ch] = record
        persistWrites()
        return record
    }

    var writeStarsTotal: Int { writes.values.reduce(0) { $0 + $1.stars } }

    // MARK: - 设置

    func updateSettings(_ patch: Settings) {
        settings = patch
        persistSettings()
    }

    var lastLessonInfo: (lesson: String?, book: String?) { (lastLesson, lastBook) }

    func setLast(lesson: String, book: String) {
        lastLesson = lesson
        lastBook = book
        store.writeObject("last", ["lesson": lesson, "book": book, "at": today()])
    }

    // MARK: - 统计

    struct DayRow {
        let key: String
        let label: String
        let learned: Int
        let answers: Int
        let correct: Int
        let rate: Int
    }

    func recentDays(_ n: Int) -> [DayRow] {
        var out: [DayRow] = []
        for i in stride(from: n - 1, through: 0, by: -1) {
            let key = DayUtil.dayKeyOf(-i)
            let d = days[key] ?? DayStat()
            let date = DayUtil.dateOfOffset(-i)
            out.append(DayRow(
                key: key,
                label: DayUtil.weekdayCN(date).replacingOccurrences(of: "周", with: ""),
                learned: d.learned,
                answers: d.answers,
                correct: d.correct,
                rate: d.answers > 0 ? Int((Float(d.correct) / Float(d.answers) * 100).rounded()) : 0
            ))
        }
        return out
    }

    var activeDays: Int {
        days.values.filter { $0.learned > 0 || $0.answers > 0 }.count
    }

    func badges() -> [Badge] {
        let learned = totalLearned
        let streak = self.streak
        let stars = writeStarsTotal
        return [
            Badge(id: "sprout", emoji: "🌱", name: "破土而出", desc: "认识 1 个汉字", got: learned >= 1),
            Badge(id: "ten", emoji: "📖", name: "小书童", desc: "认识 10 个汉字", got: learned >= 10),
            Badge(id: "fifty", emoji: "⭐", name: "识字小达人", desc: "认识 50 个汉字", got: learned >= 50),
            Badge(id: "hundred", emoji: "🏅", name: "百字斩", desc: "认识 100 个汉字", got: learned >= 100),
            Badge(id: "five", emoji: "👑", name: "汉字收藏家", desc: "认识 500 个汉字", got: learned >= 500),
            Badge(id: "streak", emoji: "🔥", name: "坚持之星", desc: "连续学习 3 天", got: streak >= 3),
            Badge(id: "perfect", emoji: "🎯", name: "满分小状元", desc: "闯关全部答对", got: perfect >= 1),
            Badge(id: "write", emoji: "✍️", name: "小小书法家", desc: "描红获得 10 颗星", got: stars >= 10),
        ]
    }

    func resetAll() {
        entries.removeAll()
        days.removeAll()
        wrong.removeAll()
        writes.removeAll()
        streakCount = 0
        lastDay = 0
        quizzes = 0
        perfect = 0
        lastStudyDay = 0
        settings = Settings(book: Repo.shared.defaultBook())
        lastLesson = nil
        lastBook = nil
        store.clearAll()
        persistSettings()
    }
}
