import Foundation

/// 识字量测试。
///
/// 家长最想知道的一个数字是「我家孩子认识多少字」。原来的 app 只能回答
/// 「学过多少字」——那是**点过多少个字**，不是认识多少。孩子点开一百个字
/// 一个没记住，界面上照样显示 100。
///
/// ## 为什么用分层抽测，不是全测
///
/// 2596 个字全问一遍要半小时，一二年级孩子坐不住。所以每册抽 5 个，
/// 按册次从低到高问；某一册正确率低于 40% 就停——再往后的册次问下去
/// 也只是让孩子反复受挫。
///
/// 抽的时候按**等距取样**（`stride`），不是取前 5 个。取前 5 个等于只考
/// 「日月水火」这种最基础的字，估出来的数会虚高一大截。等距取样才能覆盖
/// 整册，包括靠后的难字。
///
/// ## 估算方法
///
/// 每册的得分率 × 该册字数，累加。停下的那一册之后的册次一律记 0——
/// 那是还没学到的部分，不该按更低的比例折算。
///
/// 抽 5 个字的比例误差不小，所以结果只报「约」到百位，并且明说是估算。
/// 报一个精确到个位的数字是在骗家长。
///
/// 与小程序 `utils/vocab.js`、Android `logic/Vocab.kt` 逐位一致。
@MainActor
enum Vocab {

    /// 每册抽几个字。5 × 8 册 = 最多 40 题，中间还会提前停。
    static let perBook = 5

    /// 低于这个正确率就停在这一册
    static let stopRate = 0.4

    struct Group {
        let book: String
        let name: String
        let bookTotal: Int
        let start: Int
        let questions: [Quiz.Question]
    }

    struct Test {
        let groups: [Group]
        let total: Int
        var questions: [Quiz.Question] { groups.flatMap(\.questions) }
    }

    struct GroupScore {
        let book: String
        let name: String
        let asked: Int
        let correct: Int
        let rate: Double
        let counted: Bool
        let contribution: Int
    }

    struct Estimate {
        let size: Int
        let groups: [GroupScore]
        let level: String
        let stopBook: String
        let answered: Int
        let done: Bool
    }

    /// 一册里等距抽 n 个字。
    ///
    /// 起点用 seed 随机，步长固定为 `len / n`——既覆盖全册，不同次测试又不会
    /// 永远考同一批字。只取有拼音的字（没拼音的问不出读音题）。
    static func sampleBook(_ bookId: String, count n: Int, rand: () -> Double) -> [String] {
        let pool = Repo.shared.bookChars(bookId).filter { ch in
            guard let m = Repo.shared.meta(ch) else { return false }
            return m.py.count > 1
        }
        if pool.isEmpty { return [] }
        let count = min(n, pool.count)
        let stride = Double(pool.count) / Double(count)
        let start = Int(rand() * stride)
        var out: [String] = []
        var used = Set<String>()
        for i in 0..<count {
            var idx = (start + Int(Double(i) * stride)) % pool.count
            // 步长取整后可能撞到同一个下标，顺延到下一个没用过的字
            var guardCount = 0
            while used.contains(pool[idx]) && guardCount < pool.count {
                idx = (idx + 1) % pool.count
                guardCount += 1
            }
            used.insert(pool[idx])
            out.append(pool[idx])
        }
        return out
    }

    /// 这个词的读音干扰项：同一册里别的字的拼音
    private static func pinyinOptions(_ ch: String, bookId: String, rand: () -> Double) -> [Quiz.Option]? {
        let reading = Repo.shared.readingFor(ch, lessonId: nil)
        if reading.isEmpty { return nil }
        let banned = Set(Repo.shared.readingsOf(ch))
        var seen: Set<String> = [reading]
        var opts: [Quiz.Option] = [Quiz.Option(value: reading, label: reading)]
        // 干扰项从本册取：同册的字孩子都可能见过，才谈得上「分不清」
        let pool = Quiz.shuffle(Repo.shared.bookChars(bookId).filter { $0 != ch }, rand)
        for c in pool {
            if opts.count >= 4 { break }
            guard let p = Repo.shared.meta(c)?.py, !p.isEmpty else { continue }
            if seen.contains(p) || banned.contains(p) { continue }
            seen.insert(p)
            opts.append(Quiz.Option(value: p, label: p))
        }
        if opts.count < 4 { return nil }
        return Quiz.shuffle(opts, rand)
    }

    /// 生成整套题。
    ///
    /// 一次全部生成，页面按册边界决定要不要提前停——这样「什么时候停」的
    /// 判断逻辑是纯函数，能在单元测试里测，不用跑界面。
    static func buildTest(seed: Int = Int(Date().timeIntervalSince1970 * 1000) & 0x7FFFFFFF,
                          perBook n: Int = perBook) -> Test {
        let rand = Quiz.mulberry32(UInt32(truncatingIfNeeded: seed))
        var groups: [Group] = []
        var cursor = 0
        for b in Repo.shared.books {
            let picked = sampleBook(b.id, count: n, rand: rand)
            var questions: [Quiz.Question] = []
            for ch in picked {
                let answer = Repo.shared.readingFor(ch, lessonId: nil)
                guard let options = pinyinOptions(ch, bookId: b.id, rand: rand),
                      !answer.isEmpty else { continue }
                questions.append(Quiz.Question(
                    type: "vocab", ch: ch, lesson: nil,
                    title: "这个字读什么？", prompt: ch, promptKind: "char",
                    sub: "会读就选对，不会就随便选",
                    options: options, answer: answer,
                    explain: "「\(ch)」读 \(answer)。",
                    index: cursor + questions.count, total: 0
                ))
            }
            if questions.isEmpty { continue }
            groups.append(Group(book: b.id, name: b.name,
                                bookTotal: Repo.shared.bookChars(b.id).count,
                                start: cursor, questions: questions))
            cursor += questions.count
        }
        // total 要等全部生成完才知道，做一次二次赋值
        let total = cursor
        let fixed = groups.map { g in
            Group(book: g.book, name: g.name, bookTotal: g.bookTotal, start: g.start,
                  questions: g.questions.map { q in
                      Quiz.Question(type: q.type, ch: q.ch, lesson: q.lesson, title: q.title,
                                    prompt: q.prompt, promptKind: q.promptKind, sub: q.sub,
                                    options: q.options, answer: q.answer, explain: q.explain,
                                    index: q.index, total: total)
                  })
        }
        return Test(groups: fixed, total: total)
    }

    /// 根据已答的题算识字量。
    ///
    /// - Parameter answers: 按答题顺序，`true` 表示答对
    static func estimate(_ test: Test, answers: [Bool]) -> Estimate {
        var groups: [GroupScore] = []
        var size = 0
        var stopped = false
        var stopBook = ""
        var level = ""
        for g in test.groups {
            // 已经停过就不再「问」后面的册次。哪怕调用方把全部答案都传进来，
            // 那些题在真实流程里也没被问过，算进去会让 answered 虚高。
            let asked = stopped ? 0 : max(0, min(g.questions.count, answers.count - g.start))
            var correct = 0
            for k in 0..<max(0, asked) where g.start + k < answers.count {
                if answers[g.start + k] { correct += 1 }
            }
            let rate = asked > 0 ? Double(correct) / Double(asked) : 0
            // 一旦停过，后面的册次一律不计——那是还没学到的部分，
            // 按更低的比例折算只会把估算压低成一个没有意义的数
            let counted = asked > 0
            let contribution = counted ? Int((Double(g.bookTotal) * rate).rounded()) : 0
            if counted {
                size += contribution
                if rate >= stopRate { level = g.book }
            }
            groups.append(GroupScore(book: g.book, name: g.name, asked: asked,
                                     correct: correct, rate: rate,
                                     counted: counted, contribution: contribution))
            // 问满一册且没过线就停
            if !stopped && asked >= g.questions.count && rate < stopRate {
                stopped = true
                stopBook = g.book
            }
        }
        // 上界是全库去重后的字数：各册字数相加是 2600，但有些字跨册重复出现，
        // 去重后只有 2596。不封顶的话全对会算出 2600，比字库还大。
        let libraryTotal = Repo.shared.allChars.count
        if size > libraryTotal { size = libraryTotal }
        // 「问过几题」= 各册实际问到的题数之和
        let answered = groups.reduce(0) { $0 + $1.asked }
        return Estimate(size: size, groups: groups, level: level, stopBook: stopBook,
                        answered: answered, done: answered >= test.total || stopped)
    }

    /// 「约 700 字」这种表述比「712 字」诚实：抽 5 个字的误差就在这个量级。
    /// 不足 100 的字数直接报整数，因为那时「约 0 字」很奇怪。
    static func sizeLabel(_ size: Int) -> String {
        let n = max(0, size)
        if n < 100 { return "\(n)" }
        return "约 \(Int((Double(n) / 100).rounded()) * 100)"
    }

    /// 一句评价。分档按《义务教育语文课程标准》的量级：
    /// 一二年级认识 1600 字左右，三四年级 2500 字左右。
    static func verdict(_ size: Int) -> String {
        let n = max(0, size)
        if n < 100 { return "刚开始认字，慢慢来。" }
        if n < 400 { return "一年级上下的水平，继续积累。" }
        if n < 900 { return "一年级末到二年级的水平，很不错。" }
        if n < 1600 { return "接近二年级末的水平，认字量已经不小了。" }
        if n < 2500 { return "到了三四年级的量级，可以多读整本书了。" }
        return "认字量很大，可以试着读章节书了。"
    }
}
