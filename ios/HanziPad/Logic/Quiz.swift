import Foundation

/// 出题器，与 Android `Quiz.kt` / 小程序 `utils/quiz.js` 对应。
///
/// 题型：看拼音选字 / 看字选拼音 / 词语填空 / 数笔画 / 找词语。
/// 用固定 seed 可复现，方便单测。
///
/// 三端必须出同一套题（同 seed），所以随机数生成器要和 JS 的 mulberry32 逐位一致。
@MainActor
enum Quiz {

    /// 与 JS 的 mulberry32 完全一致，保证同 seed 三端出同一套题
    static func mulberry32(_ seed: UInt32) -> () -> Double {
        var a = seed
        return {
            a = a &+ 0x6d2b79f5
            var t = a
            t = (t ^ (t >> 15)) &* (1 | t)
            t = t ^ (t &+ ((t ^ (t >> 7)) &* (61 | t)))
            let v = (t ^ (t >> 14)) & 0xFFFF_FFFF
            return Double(v) / 4_294_967_296.0
        }
    }

    static func shuffle<T>(_ list: [T], _ rand: () -> Double) -> [T] {
        var arr = list
        var i = arr.count - 1
        while i >= 1 {
            let j = Int(rand() * Double(i + 1))
            arr.swapAt(i, j)
            i -= 1
        }
        return arr
    }

    struct Option: Equatable {
        let value: String
        let label: String
    }

    struct Question {
        let type: String
        let ch: String
        let lesson: String?
        let title: String
        let prompt: String
        /// pinyin | char | word —— 决定 prompt 用什么样式渲染
        let promptKind: String
        let sub: String
        let options: [Option]
        let answer: String
        let explain: String
        let index: Int
        let total: Int
    }

    struct Result {
        let questions: [Question]
        let targets: [String]
    }

    // MARK: - 辅助

    private static func explainOf(_ ch: String, _ lessonId: String?) -> String {
        guard let m = Repo.shared.meta(ch) else { return "" }
        let reading = Repo.shared.readingFor(ch, lessonId: lessonId)
        let word = m.words.first?.word ?? ""
        var text = "「\(ch)」读 \(reading)，部首是「\(m.radical)」，共 \(m.strokes) 笔。"
        if !word.isEmpty { text += "可以组词「\(word)」。" }
        return text
    }

    private static func distractorChars(
        _ ch: String,
        _ count: Int,
        _ pool: [String],
        _ rand: () -> Double,
        exclude: Set<String>
    ) -> [String] {
        var seen = Set<String>()
        var candidates: [String] = []
        for c in pool {
            if c == ch || exclude.contains(c) || !seen.insert(c).inserted { continue }
            candidates.append(c)
        }
        var picked = Array(shuffle(candidates, rand).prefix(count))
        if picked.count >= count { return picked }
        for c in Repo.shared.allChars {
            if picked.count >= count { break }
            if c != ch && !exclude.contains(c) && !picked.contains(c) { picked.append(c) }
        }
        return picked
    }

    private static func uniqueOptions(_ opts: [Option]) -> [Option] {
        var seen = Set<String>()
        var out: [Option] = []
        for o in opts where seen.insert(o.value).inserted { out.append(o) }
        return out
    }

    // MARK: - 五种题型

    private static func pinyinToChar(
        _ ch: String, _ lessonId: String?, _ pool: [String], _ rand: () -> Double
    ) -> Question? {
        let reading = Repo.shared.readingFor(ch, lessonId: lessonId)
        if reading.isEmpty { return nil }
        var banned = Set<String>()
        for p in pool where Repo.shared.readingsOf(p).contains(reading) { banned.insert(p) }
        let ds = distractorChars(ch, 3, pool, rand, exclude: banned)
        if ds.count < 3 { return nil }
        let options = uniqueOptions(shuffle([Option(value: ch, label: ch)] + ds.map { Option(value: $0, label: $0) }, rand))
        if options.count < 4 { return nil }
        return Question(
            type: "pinyin2char", ch: ch, lesson: lessonId,
            title: "看拼音，选汉字", prompt: reading, promptKind: "pinyin",
            sub: "哪个字的读音是 \(reading)？",
            options: options, answer: ch,
            explain: explainOf(ch, lessonId), index: 0, total: 0
        )
    }

    private static func charToPinyin(
        _ ch: String, _ lessonId: String?, _ pool: [String], _ rand: () -> Double
    ) -> Question? {
        let reading = Repo.shared.readingFor(ch, lessonId: lessonId)
        guard let m = Repo.shared.meta(ch), !reading.isEmpty else { return nil }
        let banned = Set(Repo.shared.readingsOf(ch))
        let ds = distractorChars(ch, 8, pool, rand, exclude: [])
        var seen = Set<String>([reading])
        var opts = [Option(value: reading, label: reading)]
        for d in ds {
            if opts.count >= 4 { break }
            guard let meta = Repo.shared.meta(d) else { continue }
            let p = meta.py
            if !p.isEmpty && !seen.contains(p) && !banned.contains(p) {
                seen.insert(p)
                opts.append(Option(value: p, label: p))
            }
        }
        if opts.count < 4 { return nil }
        _ = m
        return Question(
            type: "char2pinyin", ch: ch, lesson: lessonId,
            title: "这个字读什么？", prompt: ch, promptKind: "char",
            sub: "选出正确的读音",
            options: shuffle(opts, rand), answer: reading,
            explain: explainOf(ch, lessonId), index: 0, total: 0
        )
    }

    private static func fillWord(
        _ ch: String, _ lessonId: String?, _ pool: [String], _ rand: () -> Double
    ) -> Question? {
        guard let m = Repo.shared.meta(ch), !m.words.isEmpty else { return nil }
        let idx = min(max(Int(rand() * Double(m.words.count)), 0), m.words.count - 1)
        let word = m.words[idx]
        if !word.word.contains(ch) { return nil }
        let masked = word.word.replacingOccurrences(of: ch, with: "＿")
        let ds = distractorChars(ch, 3, pool, rand, exclude: [])
        if ds.count < 3 { return nil }
        let options = uniqueOptions(shuffle([Option(value: ch, label: ch)] + ds.map { Option(value: $0, label: $0) }, rand))
        if options.count < 4 { return nil }
        return Question(
            type: "fillWord", ch: ch, lesson: lessonId,
            title: "词语填空", prompt: masked, promptKind: "word",
            sub: masked.hasPrefix("＿") ? "补上第一个字" : "补上缺少的字",
            options: options, answer: ch,
            explain: "「\(word.word)」的「\(ch)」读 \(Repo.shared.readingFor(ch, lessonId: lessonId))。",
            index: 0, total: 0
        )
    }

    private static func strokeCountQ(
        _ ch: String, _ lessonId: String?, _ pool: [String], _ rand: () -> Double
    ) -> Question? {
        guard let m = Repo.shared.meta(ch) else { return nil }
        let correct = m.strokes
        if correct <= 0 { return nil }
        var nums = [correct]
        let offsets = shuffle([1, -1, 2, -2, 3], rand)
        for o in offsets {
            if nums.count >= 4 { break }
            let v = correct + o
            if v > 0 && !nums.contains(v) { nums.append(v) }
        }
        if nums.count < 4 { return nil }
        return Question(
            type: "strokeCount", ch: ch, lesson: lessonId,
            title: "数一数笔画", prompt: ch, promptKind: "char",
            sub: "一共几笔？",
            options: shuffle(nums.map { Option(value: String($0), label: "\($0) 笔") }, rand),
            answer: String(correct),
            explain: "「\(ch)」共 \(correct) 笔，部首是「\(m.radical)」。",
            index: 0, total: 0
        )
    }

    private static func charToWord(
        _ ch: String, _ lessonId: String?, _ pool: [String], _ rand: () -> Double
    ) -> Question? {
        guard let m = Repo.shared.meta(ch), !m.words.isEmpty else { return nil }
        let idx = min(max(Int(rand() * Double(m.words.count)), 0), m.words.count - 1)
        let correct = m.words[idx]
        let ds = distractorChars(ch, 12, pool, rand, exclude: [])
        var seen = Set<String>([correct.word])
        var options = [Option(value: correct.word, label: correct.word)]
        for d in ds {
            if options.count >= 4 { break }
            for w in Repo.shared.meta(d)?.words ?? [] {
                if w.word.contains(ch) || !seen.insert(w.word).inserted { continue }
                options.append(Option(value: w.word, label: w.word))
                break
            }
        }
        if options.count < 4 { return nil }
        return Question(
            type: "char2word", ch: ch, lesson: lessonId,
            title: "词语找朋友", prompt: ch, promptKind: "char",
            sub: "哪个词语里有这个字？",
            options: shuffle(options, rand), answer: correct.word,
            explain: "「\(correct.word)」里有「\(ch)」字，读作 \(Repo.shared.readingFor(ch, lessonId: lessonId))。",
            index: 0, total: 0
        )
    }

    private static let typeOrder = ["pinyin2char", "char2pinyin", "fillWord", "strokeCount", "char2word"]

    private static func make(
        _ type: String, _ ch: String, _ lessonId: String?, _ pool: [String], _ rand: () -> Double
    ) -> Question? {
        switch type {
        case "pinyin2char": return pinyinToChar(ch, lessonId, pool, rand)
        case "char2pinyin": return charToPinyin(ch, lessonId, pool, rand)
        case "fillWord": return fillWord(ch, lessonId, pool, rand)
        case "strokeCount": return strokeCountQ(ch, lessonId, pool, rand)
        case "char2word": return charToWord(ch, lessonId, pool, rand)
        default: return nil
        }
    }

    // MARK: - 入口

    static func build(
        chars: [String],
        book: String? = nil,
        lesson: String? = nil,
        count: Int = 10,
        seed: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) -> Result {
        let targets = chars.filter { Repo.shared.hasChar($0) }
        if targets.isEmpty { return Result(questions: [], targets: []) }

        let rand = mulberry32(UInt32(truncatingIfNeeded: seed))
        let bookId = book ?? Repo.shared.meta(targets[0])?.book ?? Repo.shared.defaultBook()
        var pool = Repo.shared.bookChars(bookId)
        if pool.count < 12 { pool = Repo.shared.allChars }

        var questions: [Question] = []
        var guardCount = 0
        while questions.count < count && guardCount < count * 6 {
            let ch = targets[questions.count % targets.count]
            let lessonId = lesson ?? Repo.shared.meta(ch)?.lesson
            let start = min(max(Int(rand() * Double(typeOrder.count)), 0), typeOrder.count - 1)
            for k in 0..<typeOrder.count {
                let type = typeOrder[(start + k) % typeOrder.count]
                if let q = make(type, ch, lessonId, pool, rand) {
                    questions.append(q)
                    break
                }
            }
            guardCount += 1
        }

        let total = questions.count
        let indexed = questions.enumerated().map { i, q in
            Question(
                type: q.type, ch: q.ch, lesson: q.lesson, title: q.title,
                prompt: q.prompt, promptKind: q.promptKind, sub: q.sub,
                options: q.options, answer: q.answer, explain: q.explain,
                index: i, total: total
            )
        }
        return Result(questions: indexed, targets: targets)
    }
}
