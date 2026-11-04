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
        /// 上次识字量测试估出来的字数，0 表示没测过。
        /// 存在 Settings 里而不是单独一个键：它就是一个「上次测出来多少」的
        /// 缓存，跟册次、每天新学一样属于设置区。
        var vocabSize: Int = 0
    }

    /// 上次识字量测试的结果（0 = 没测过）
    var vocabSize: Int { settings.vocabSize }

    /// 记下这次测出的识字量（0 表示没测过，不覆盖已有结果）
    func setVocabSize(_ size: Int) {
        guard size > 0 else { return }
        var s = settings
        s.vocabSize = size
        updateSettings(s)
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

    /// 笔画薄弱点：字 → (笔画序号 → 记录)。
    ///
    /// 描红判分本来每笔都会算出「为什么不过」（起笔错 / 偏离 / 写短了），
    /// 但之前只拿它拼一句即时提示就丢掉了。留下来才看得出
    /// 「这个字的第 2 笔你反复写不好」——比整字分数具体。
    private var weak: [String: [Int: WeakStroke]] = [:]

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

        if let obj = store.readObject("weak"), let raw = obj["items"] as? [String: [String: [String: Any]]] {
            for (ch, strokes) in raw {
                var m: [Int: WeakStroke] = [:]
                for (k, o) in strokes {
                    guard let i = Int(k) else { continue }
                    m[i] = WeakStroke(
                        fails: o["f"] as? Int ?? 0,
                        tries: o["t"] as? Int ?? 0,
                        ok: o["o"] as? Int ?? 0
                    )
                }
                if !m.isEmpty { weak[ch] = m }
            }
        }

        if let obj = store.readObject("settings") {
            var s = Settings()
            s.dailyNew = obj["dailyNew"] as? Int ?? 5
            s.book = obj["book"] as? String ?? "1a"
            s.showPinyin = obj["showPinyin"] as? Bool ?? true
            s.vocabSize = obj["vocabSize"] as? Int ?? 0
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

    private func persistWeak() {
        var map: [String: [String: [String: Any]]] = [:]
        for (ch, m) in weak {
            var strokes: [String: [String: Any]] = [:]
            for (i, r) in m {
                strokes[String(i)] = ["f": r.fails, "t": r.tries, "o": r.ok]
            }
            map[ch] = strokes
        }
        store.writeObject("weak", ["items": map])
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
            "vocabSize": settings.vocabSize,
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

    /// 逐日统计的只读快照，给周报（`Report.build`）用。
    ///
    /// `days` 是私有字典，周报又是纯函数、不该把手伸进 Progress 里，
    /// 所以在这里转成 Report 自己的轻量类型再递出去——顺带把
    /// `@MainActor` 隔离留在这个类里，Report 可以完全脱离 Progress 测试。
    /// 自检用：直接往逐日统计里塞一周数据。
    ///
    /// 周报页光靠 `-seedDemo` 是空的（`learn()` 只记当天），看不到非空态的
    /// 排版。而"空周周报长什么样"和"有数据时长什么样"都得看过才算验过。
    ///
    /// 只在 DEBUG 下存在，参数是 `-seedWeek`。
    #if DEBUG
    func seedWeekForDebug() {
        // 故意留一天（前天）不填，用来验"缺数据 ≠ 0 分"的显示
        let plan: [(Int, Int, Int, Int)] = [
            (0, 5, 12, 10),
            (1, 4, 10, 9),
            (3, 6, 14, 12),
            (4, 3, 6, 6),
            (5, 2, 4, 3),
            (6, 4, 8, 7),
        ]
        for (off, learned, answers, correct) in plan {
            let d = Calendar.current.date(byAdding: .day, value: -off, to: Date()) ?? Date()
            let key = DayUtil.todayKey(d)
            days[key] = DayStat(learned: learned, answers: answers, correct: correct)
        }
        persistStats()
    }
    #endif

    var dayStats: [String: Report.DayStat] {
        days.mapValues {
            Report.DayStat(learned: $0.learned, answers: $0.answers, correct: $0.correct)
        }
    }

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

    // MARK: - 笔画薄弱点

    /// 某一笔的失败 / 尝试 / 连胜次数
    struct WeakStroke {
        var fails: Int
        var tries: Int
        var ok: Int
    }

    /// 一条薄弱点（用于列表展示）
    struct WeakPoint {
        let ch: String
        let index: Int
        let fails: Int
        let tries: Int
    }

    /// 记录一笔的结果。
    ///
    /// `passed` 是这一笔过没过判分线。失败次数才是「薄弱」的依据：
    /// 一次成功不能抵消两次失败——真正写不好的笔画会一直被记着。
    ///
    /// 练好的判定是**连续写对 2 次**（`ok` 记连胜）。
    /// 为什么不「写对一次就清掉」：那样 `tries` 永远等于 `fails`，
    /// 而且手抖蒙对一次就前功尽弃。
    func recordStroke(_ ch: String, index: Int, passed: Bool) {
        guard !ch.isEmpty else { return }
        var m = weak[ch] ?? [:]
        let old = m[index] ?? WeakStroke(fails: 0, tries: 0, ok: 0)
        if passed {
            if old.ok + 1 >= 2 {
                // 连续两次写对：这一笔练稳了，不用再提示
                m.removeValue(forKey: index)
                if m.isEmpty { weak.removeValue(forKey: ch) } else { weak[ch] = m }
                persistWeak()
                return
            }
            m[index] = WeakStroke(fails: old.fails, tries: old.tries + 1, ok: old.ok + 1)
        } else {
            m[index] = WeakStroke(fails: old.fails + 1, tries: old.tries + 1, ok: 0)
        }
        weak[ch] = m
        persistWeak()
    }

    /// 这个字哪些笔画是薄弱点：失败 ≥ 2 次。
    ///
    /// 只错一次是很正常的（手抖、第一次不熟），不算薄弱点。
    /// 不再叠「失败率 ≥40%」——加上「连对两次即移除」之后，任何还在册的
    /// 记录都满足 `tries ≤ 2f+1`，失败率恒 ≥50%，那条判断是死代码。
    func weakStrokesOf(_ ch: String) -> [WeakPoint] {
        guard let m = weak[ch] else { return [] }
        return m.filter { $0.value.fails >= 2 }
            .map { WeakPoint(ch: ch, index: $0.key, fails: $0.value.fails, tries: $0.value.tries) }
            .sorted { $0.index < $1.index }
    }

    /// 有没有需要专门练的笔画
    func hasWeakStrokes(_ ch: String) -> Bool {
        !weakStrokesOf(ch).isEmpty
    }

    /// 全部薄弱点，按「最需要练」排序：失败次数多的在前。
    ///
    /// 同一字的多个笔画各占一条——「日的第2笔」和「日的第4笔」
    /// 是两个不同的动作，合成一条就没法分别练。
    func allWeakStrokes() -> [WeakPoint] {
        weak.keys.flatMap { weakStrokesOf($0) }.sorted { a, b in
            if a.fails != b.fails { return a.fails > b.fails }
            // Swift 的 sort 不保证稳定，必须给确定的 tiebreak，否则三端顺序会不一致
            let ca = a.ch.unicodeScalars.first?.value ?? 0
            let cb = b.ch.unicodeScalars.first?.value ?? 0
            if ca != cb { return ca < cb }
            return a.index < b.index
        }
    }

    /// 有薄弱笔画的字，每个字只出现一次（取最弱的那一笔）。
    ///
    /// 练习入口用这个：一个字的第 2 笔和第 4 笔都在练同一份描红，
    /// 按笔画列出会重复练同一个字。
    func weakChars() -> [WeakPoint] {
        var seen = Set<String>()
        var out: [WeakPoint] = []
        for w in allWeakStrokes() where seen.insert(w.ch).inserted {
            out.append(w)
        }
        return out
    }

    /// 某一笔练好了：把它从薄弱点里去掉
    func clearWeakStroke(_ ch: String, index: Int) {
        guard var m = weak[ch] else { return }
        m.removeValue(forKey: index)
        if m.isEmpty { weak.removeValue(forKey: ch) } else { weak[ch] = m }
        persistWeak()
    }

    /// 整个字从薄弱点里清掉
    func clearWeak(_ ch: String) {
        guard weak.removeValue(forKey: ch) != nil else { return }
        persistWeak()
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

    /// 写过多少个字
    var writeCount: Int { writes.count }

    /// 所有写过字的记录，按「最近写的在前，同一天按最高分降序」排。
    ///
    /// 排序刻意不按字的音序：孩子翻开字帖想看的是「我最近写的」，
    /// 而不是「按拼音排的一堆字」——后者更像词典，不像自己的成果。
    func allWriteRecords() -> [(ch: String, record: WriteRecord)] {
        writes
            .map { (ch: $0.key, record: $0.value) }
            .sorted { a, b in
                if a.record.last != b.record.last { return a.record.last > b.record.last }
                if a.record.best != b.record.best { return a.record.best > b.record.best }
                return a.ch < b.ch   // 兜底：保证顺序稳定，测试可复现
            }
    }

    /// 按星级分档的数量（3 星 / 2 星 / 1 星 / 0 星）
    func writeStarsHistogram() -> [Int: Int] {
        var out: [Int: Int] = [0: 0, 1: 0, 2: 0, 3: 0]
        for (_, r) in writes { out[r.stars, default: 0] += 1 }
        return out
    }

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

    /// 从当前命名空间重读全部状态。
    ///
    /// 切换孩子档案时必须调用：存储的命名空间变了，但这份内存状态还是上一个
    /// 孩子的。不重读的话界面会显示「名字换了、数据没变」——比不换还糟。
    func reload() {
        entries.removeAll()
        days.removeAll()
        wrong.removeAll()
        writes.removeAll()
        weak.removeAll()
        streakCount = 0
        lastDay = 0
        quizzes = 0
        perfect = 0
        lastStudyDay = 0
        settings = Settings(book: Repo.shared.defaultBook())
        lastLesson = nil
        lastBook = nil
        load()
    }

    func resetAll() {
        entries.removeAll()
        days.removeAll()
        wrong.removeAll()
        writes.removeAll()
        weak.removeAll()
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
