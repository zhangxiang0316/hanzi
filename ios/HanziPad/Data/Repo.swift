import Foundation

/// 数据仓库，与 Android `data/Repo.kt` 的 API 一一对应。
///
/// 数据是只读的静态 JSON，全部打进 bundle：无网络、无后端。
/// 三个文件加起来 2.9 MB，直接从 bundle 同步加载——比异步加载简单，
/// 也不会出现「界面先渲染出空列表再补数据」的闪动。
/// 标记 `@MainActor` 而不是用锁保护：这份数据是只读的，唯一的可变状态是
/// 几处解码缓存，而所有访问都来自 SwiftUI 视图（本来就在主线程）。
/// 用 actor 隔离能从构造上杜绝数据竞争，比手写 NSLock 更难出错。
@MainActor
final class Repo {
    private static var _shared: Repo?

    /// 全局实例。
    ///
    /// 逻辑层（Quiz / Plan）需要读数据，但硬编码单例会让它们无法在测试里跑——
    /// 测试进程的 Bundle.main 里没有那三个 JSON。所以留一个后可覆盖的口子：
    /// 生产用默认的 bundle 源，测试先 `overrideShared` 再调用。
    static var shared: Repo {
        if let s = _shared { return s }
        let r = Repo()
        _shared = r
        return r
    }

    /// 仅测试使用：替换全局实例
    static func overrideShared(_ repo: Repo) { _shared = repo }

    /// 仅测试使用：清掉全局实例
    static func resetShared() { _shared = nil }

    /// 数据来源。生产用 bundle，测试用目录路径。
    ///
    /// 抽这一层是为了能在命令行工具和单测里加载同一份数据——
    /// `Bundle.main` 在非 App 进程里拿不到 resource，直接依赖它就没法离线验证。
    enum Source {
        case bundle
        case directory(URL)
    }

    private(set) var books: [Book] = []
    private(set) var edition: String = ""

    private var bookMap: [String: Book] = [:]
    private var lessonMap: [String: Lesson] = [:]
    private var metaMap: [String: CharMeta] = [:]
    /// 保持 meta.json 的原始顺序（按教材出现顺序），用于「全部字」列表
    private(set) var charOrder: [String] = []
    private var rawStrokes: [String: String] = [:]
    /// 形近字表（自动生成，见 scripts/build-similar.mjs）
    private var similarMap: [String: [String]] = [:]

    private var bookCharsCache: [String: [String]] = [:]
    /// 课文词语表缓存（见 Logic/Words.swift）
    var lessonWordCache: [String: [LessonWord]] = [:]
    /// 单册词语表缓存（见 Logic/Words.swift 的 `bookWordEntries`）。
    ///
    /// 这一层缓存不是「顺手加的」：词语表页一进来就要把八册都列出来，
    /// 每册还要算总数，而 `WordEntry` 的每个词都要过一遍 `wordPinyin`
    /// （逐字查 meta、再扫该字的组词找带声调的拼音）。第一次进页面时
    /// 不做缓存要重复算十几遍同样八册的东西，主线程卡好几秒——
    /// 表现为点进词语表后白屏一会儿才出内容。
    var bookWordsCache: [String: [WordEntry]] = [:]
    /// 全库词语表缓存（按册拼接，见 Logic/Words.swift 的 `allWordEntries`）
    var allWordsCache: [WordEntry]?
    /// 全库去重词语缓存（见 Logic/Words.swift 的 `uniqueWords`）
    var uniqueWordsCache: [WordEntry]?
    private var strokeCache: [String: StrokeCodec.CharStrokes] = [:]

    init(source: Source = .bundle) {
        load(source: source)
    }

    // MARK: - 加载

    private func url(_ name: String, from source: Source) -> URL? {
        switch source {
        case .bundle:
            return Bundle.main.url(forResource: name, withExtension: "json")
        case .directory(let dir):
            return dir.appendingPathComponent(name + ".json")
        }
    }

    private func load(source: Source) {
        guard let catalogURL = url("catalog", from: source),
              let metaURL = url("meta", from: source),
              let strokesURL = url("strokes", from: source)
        else {
            // 不用 assertionFailure：测试进程里 Bundle.main 没有这些资源，
            // 断言会把整个测试进程打挂，反而掩盖真正要测的东西
            print("[Repo] 数据文件缺失：catalog/meta/strokes 必须存在")
            return
        }

        let decoder = JSONDecoder()

        if let data = try? Data(contentsOf: catalogURL),
           let cat = try? decoder.decode(Catalog.self, from: data) {
            books = cat.books
            edition = cat.edition
            for b in cat.books { bookMap[b.id] = b }
            lessonMap = cat.lessons
        }

        if let data = try? Data(contentsOf: metaURL),
           let map = try? decoder.decode([String: CharMeta].self, from: data) {
            metaMap = map
            // Dictionary 无序，但 meta.json 里字的顺序是有意义的（教材顺序）。
            // 重新按 raw JSON 的键序读一遍：JSONSerialization 的字典同样无序，
            // 所以这里用 .sorted() 兜底，真正的教材顺序由 bookChars 提供。
            charOrder = map.keys.sorted()
        }

        if let data = try? Data(contentsOf: strokesURL),
           let map = try? decoder.decode([String: String].self, from: data) {
            rawStrokes = map
        }

        // 形近字表是可选资源：缺了只是没有这个练习入口，
        // 其余功能不受影响，所以不进上面的 guard
        if let similarURL = url("similar", from: source),
           let data = try? Data(contentsOf: similarURL),
           let map = try? decoder.decode([String: [String]].self, from: data) {
            similarMap = map
        }
    }

    // MARK: - 基础查询

    func book(_ id: String) -> Book? { bookMap[id] }
    func defaultBook() -> String { books.first?.id ?? "1a" }
    func lesson(_ id: String?) -> Lesson? {
        guard let id else { return nil }
        return lessonMap[id]
    }
    func meta(_ ch: String) -> CharMeta? { metaMap[ch] }
    func hasChar(_ ch: String) -> Bool { metaMap[ch] != nil }
    var charCount: Int { metaMap.count }

    func lessonTitle(_ id: String?) -> String {
        guard let id else { return "" }
        return lessonMap[id]?.title ?? ""
    }

    func lessonLabel(_ id: String?) -> String {
        guard let id, let l = lessonMap[id] else { return "" }
        let prefix = bookMap[l.book].map { $0.short + " · " } ?? ""
        return prefix + "第" + String(l.no) + "课 " + l.title
    }

    // MARK: - 教材顺序

    /// 按「册 → 单元 → 课 → 生字」的教材顺序返回某册全部生字（去重）
    func bookChars(_ bookId: String) -> [String] {
        if let c = bookCharsCache[bookId] { return c }
        guard let book = bookMap[bookId] else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        for lid in book.lessons {
            guard let l = lessonMap[lid] else { continue }
            for ch in l.chars where seen.insert(ch).inserted {
                out.append(ch)
            }
        }
        bookCharsCache[bookId] = out
        return out
    }

    func lessonChars(_ lessonId: String?) -> [String] {
        guard let lessonId else { return [] }
        return lessonMap[lessonId]?.chars ?? []
    }

    // MARK: - 读音

    /// 取本课语境下的读音；多音字按教材标注
    func readingFor(_ ch: String, lessonId: String?) -> String {
        guard let m = metaMap[ch] else { return "" }
        if let rd = m.rd, let lessonId {
            for r in rd where r.l == lessonId { return r.p }
        }
        return m.py
    }

    /// 一个字所有可能读音（用于排除同音干扰项）
    func readingsOf(_ ch: String) -> [String] {
        guard let m = metaMap[ch] else { return [] }
        guard let rd = m.rd else { return [m.py] }
        var seen = Set<String>()
        var out: [String] = []
        for r in rd where seen.insert(r.p).inserted { out.append(r.p) }
        return out
    }

    func readingDetails(_ ch: String) -> [Reading] {
        guard let m = metaMap[ch] else { return [] }
        return m.rd ?? [Reading(p: m.py, l: "")]
    }

    /// 这个字在本项目范围内是否要求会写。
    ///
    /// 不能只看 `meta.x` 非空：有 457 个字的写字课在五、六年级（如「棋」的
    /// x 是 6a-k6），而本项目只做一到四年级。这些字在本项目里是「只认不写」，
    /// 之前三端都误判成会写，导致听写会要求孩子默写「鸦」「氏」「孙」这类字。
    ///
    /// 修正后与本项目课时的 `write` 数组并集严格一致（都是 1798 个），
    /// 这个交叉验证写进了测试。
    func isWriteChar(_ ch: String) -> Bool {
        guard let m = metaMap[ch], !m.x.isEmpty else { return false }
        let bookOfX = m.x.split(separator: "-").first.map(String.init) ?? ""
        return bookMap[bookOfX] != nil
    }

    // MARK: - 多音字

    /// 是否多音字
    func isPolyphone(_ ch: String) -> Bool {
        (metaMap[ch]?.rd?.count ?? 0) > 1
    }

    /// 某册里的多音字（保持教材顺序）
    func polyphones(book: String) -> [String] {
        bookChars(book).filter { isPolyphone($0) }
    }

    /// 全部多音字
    var allPolyphones: [String] {
        charOrder.filter { isPolyphone($0) }
    }

    // MARK: - 同音字

    /// 同音字：读音完全相同（含声调）的一组字。
    ///
    /// 这份关系不用新数据——`CharMeta.py` 里就有完整拼音，按它分组即可。
    /// 全库 588 组、2163 个字；一到四年级就有 383 组。
    ///
    /// 为什么值得单独做：同音字是听写最主要的错因。「地弟第递」「坐作做座」
    /// 读音一样、字形不同，孩子记住音不等于会写。多音字练「一个字读哪个音」，
    /// 同音字练「这个音写哪个字」——是同一个问题的两个方向。
    func homophones(_ ch: String) -> [String] {
        guard let m = metaMap[ch], !m.py.isEmpty else { return [] }
        // 按 Unicode 码点排序，不依赖 charOrder 的顺序：
        // 三端的数据来源顺序不同，不显式排序的话笔画数相同时干扰项的
        // 并列顺序会不一致——同一个 seed 会出不同的题。
        // 这条是跨端黄金值测试抓出来的。
        return charOrder
            .filter { $0 != ch && metaMap[$0]?.py == m.py }
            .sorted { a, b in
                (a.unicodeScalars.first?.value ?? 0) < (b.unicodeScalars.first?.value ?? 0)
            }
    }

    /// 这个字有没有同音字（没有的话同音字题型无从出题）
    func hasHomophones(_ ch: String) -> Bool {
        !homophones(ch).isEmpty
    }

    /// 某一册里的同音字组合（每组 ≥2 个字，组内按教材顺序）。
    ///
    /// 只用本册的字组队：跨册组队会让二年级孩子遇到三年级的字，
    /// 那就不是在练同音字，是在考认字量。
    func homophoneGroups(_ bookId: String) -> [(py: String, chars: [String])] {
        var order: [String] = []
        var byPy: [String: [String]] = [:]
        for ch in bookChars(bookId) {
            guard let m = metaMap[ch], !m.py.isEmpty else { continue }
            if byPy[m.py] == nil {
                byPy[m.py] = []
                order.append(m.py)
            }
            byPy[m.py]?.append(ch)
        }
        var out: [(py: String, chars: [String])] = []
        for py in order {
            guard let list = byPy[py], list.count >= 2 else { continue }
            out.append((py, list))
        }
        // 组大的排前面：错得更多的先练；同规模按拼音稳定排序
        out.sort {
            if $0.chars.count != $1.chars.count { return $0.chars.count > $1.chars.count }
            return $0.py < $1.py
        }
        return out
    }

    /// 某册里所有参与同音字组的字（按教材顺序去重）
    func homophoneChars(_ bookId: String) -> [String] {
        var set = Set<String>()
        for g in homophoneGroups(bookId) {
            for c in g.chars { set.insert(c) }
        }
        return bookChars(bookId).filter { set.contains($0) }
    }

    /// 同音字组里「最适合当干扰项」的字。
    ///
    /// 优先同册、笔画数接近的——「地」和「递」都是 `dì`，但一个 6 画一个 10 画，
    /// 一眼就能排除，当干扰项没意义。笔画差 3 以内才有迷惑性。
    func homophoneDistractors(_ ch: String, book: String?, count: Int) -> [String] {
        guard let m = metaMap[ch] else { return [] }
        let bookId = book ?? m.b
        var inBook = Set<String>()
        for c in bookChars(bookId) { inBook.insert(c) }
        let pool = homophones(ch).map { (ch: $0, s: metaMap[$0]?.s ?? 0) }
        // 三级排序：同册优先 → 笔画接近 → 码点。
        // 第三级不能省：笔画差相同的字会有并列，而 Swift 的 sort **不保证稳定**，
        // 没有确定的 tiebreak 三端就会各排各的，同一个 seed 出不同的题。
        let sorted = pool.sorted { a, b in
            let ba = inBook.contains(a.ch) ? 0 : 1
            let bb = inBook.contains(b.ch) ? 0 : 1
            if ba != bb { return ba < bb }
            let da = abs(a.s - m.s)
            let db = abs(b.s - m.s)
            if da != db { return da < db }
            return (a.ch.unicodeScalars.first?.value ?? 0) < (b.ch.unicodeScalars.first?.value ?? 0)
        }
        return sorted.prefix(count).map(\.ch)
    }

    // MARK: - 形近字

    /// 形近字是低年级另一个主要混淆来源（未/末、天/夫、日/目、人/入），
    /// 和同音字正好互补：一个是「音一样写哪个」，一个是「长得像别混」。
    ///
    /// 表不是抄的，是用笔顺数据算出来的——见 `scripts/build-similar.mjs`。
    /// 算法要两条指标同时满足才算形近：笔画几何距离（中线重采样后贪心匹配）
    /// 和像素相关系数。单独用任何一条都不行：只用笔画会放进「人→久九儿」，
    /// 只用像素则分不开「天/夫」和随机字对。

    /// 这个字的形近字（生成时按距离升序，已按码点做最终 tiebreak）
    func similarChars(_ ch: String) -> [String] {
        similarMap[ch] ?? []
    }

    /// 这个字有没有形近字
    func hasSimilar(_ ch: String) -> Bool {
        !similarChars(ch).isEmpty
    }

    /// 形近字题的干扰项。
    ///
    /// 优先取**本册**的形近字：跨册会把三年级的字塞给一年级孩子，
    /// 那就不是在练辨析，是在考认字量。排序三级——同册优先 → 原表顺序
    /// （距离近的在前）→ 码点。第三级不能省：Swift 的 sort 不保证稳定，
    /// 三端并列顺序不一致就会让同一个 seed 出不同的题。
    func similarDistractors(_ ch: String, book: String?, count: Int) -> [String] {
        let bookId = book ?? (metaMap[ch]?.b ?? defaultBook())
        var inBook = Set<String>()
        for c in bookChars(bookId) { inBook.insert(c) }
        let list = similarChars(ch)
        var order: [String: Int] = [:]
        for (i, c) in list.enumerated() { order[c] = i }
        let sorted = list.sorted { a, b in
            let ba = inBook.contains(a) ? 0 : 1
            let bb = inBook.contains(b) ? 0 : 1
            if ba != bb { return ba < bb }
            let oa = order[a] ?? 0
            let ob = order[b] ?? 0
            if oa != ob { return oa < ob }
            return (a.unicodeScalars.first?.value ?? 0) < (b.unicodeScalars.first?.value ?? 0)
        }
        return Array(sorted.prefix(count))
    }

    /// 某一册里所有有形近字的字（按教材顺序）
    func bookSimilarChars(_ bookId: String) -> [String] {
        bookChars(bookId).filter { hasSimilar($0) }
    }

    /// 全部册次里所有有形近字的字
    func allSimilarChars() -> [String] {
        charOrder.filter { hasSimilar($0) }
    }

    // MARK: - 部首

    /// 部首查字法是二年级语文园地的正式内容，但 `CharMeta.r` 一直只在
    /// 解析文案里出现过，从没当成学习维度用过。237 个部首、全部 2596 个字都有。
    ///
    /// 注意：237 个部首里只有 144 个是字库里的生字（能画笔顺），
    /// 另外 93 个是偏旁变形（亻 艹 扌 讠 纟 宀 攵）——它们不是独立汉字，
    /// 没有笔顺数据。所以部首只以**文字**形式出现（当选项、当分组标签），
    /// 不参与描红判分。

    /// 这个字的部首
    func radicalOf(_ ch: String) -> String {
        metaMap[ch]?.r ?? ""
    }

    /// 字库里所有部首（按使用频次从高到低）
    func allRadicals() -> [(radical: String, count: Int, inLib: Bool)] {
        var count: [String: Int] = [:]
        for ch in charOrder {
            guard let r = metaMap[ch]?.r, !r.isEmpty else { continue }
            count[r, default: 0] += 1
        }
        return count.keys
            .map { (radical: $0, count: count[$0] ?? 0, inLib: metaMap[$0] != nil) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                // 频次相同按码点，保证三端顺序一致
                return ($0.radical.unicodeScalars.first?.value ?? 0)
                    < ($1.radical.unicodeScalars.first?.value ?? 0)
            }
    }

    /// 某一册里出现过的部首（按频次从高到低）
    func bookRadicals(_ bookId: String) -> [(radical: String, count: Int, inLib: Bool)] {
        var count: [String: Int] = [:]
        for ch in bookChars(bookId) {
            guard let r = metaMap[ch]?.r, !r.isEmpty else { continue }
            count[r, default: 0] += 1
        }
        return count.keys
            .map { (radical: $0, count: count[$0] ?? 0, inLib: metaMap[$0] != nil) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return ($0.radical.unicodeScalars.first?.value ?? 0)
                    < ($1.radical.unicodeScalars.first?.value ?? 0)
            }
    }

    /// 某一册里某个部首下的所有字（按教材顺序）
    func charsWithRadical(_ bookId: String, _ radical: String) -> [String] {
        bookChars(bookId).filter { metaMap[$0]?.r == radical }
    }

    /// 全部册次里某个部首下的所有字
    func allCharsWithRadical(_ radical: String) -> [String] {
        charOrder.filter { metaMap[$0]?.r == radical }
    }

    /// 部首题的干扰项。
    ///
    /// 取本册里最常见的几个部首，但排除跟正确答案有**字形包含关系**的——
    /// 「木」和「林」这种，孩子会争议「林」的部首是不是「木」，
    /// 当干扰项是制造歧义而不是考知识。
    func radicalDistractors(_ radical: String, book: String?, count: Int) -> [String] {
        let bookId = book ?? defaultBook()
        return bookRadicals(bookId)
            .map(\.radical)
            .filter { $0 != radical && !$0.contains(radical) && !radical.contains($0) }
            .prefix(count)
            .map { $0 }
    }

    /// 某个读音的用例词。
    ///
    /// 组词数据里每个词都带拼音，而拼音音节与汉字是一一对应的
    /// （「快乐」→ `lè kuài`… 实际是 `kuài lè`）。所以只要把「本字在词中的位置」
    /// 与「拼音里的音节位置」对上，就能确定这个词用的是哪个读音。
    ///
    /// 早先试过「拼音里任意位置出现该音节就算」——那样会把「地方」的 `dì`
    /// 误配到别的读音上（同一个词里另一个字恰好同音时）。改成按位置对齐后，
    /// 156 个多音字全部都能匹配到用例，且不会串音。
    ///
    /// 音节数与字数不一致的词（儿化、轻声合写等）直接跳过，宁可少几个例子也不出错。
    func wordsUsing(_ ch: String, reading: String) -> [String] {
        guard let m = metaMap[ch] else { return [] }
        var out: [String] = []
        for w in m.words {
            let ws = Array(w.word)
            guard let idx = ws.firstIndex(of: Character(ch)) else { continue }
            let syl = w.pinyin.split(separator: " ").map(String.init)
            guard syl.count == ws.count else { continue }
            if syl[idx] == reading { out.append(w.word) }
        }
        return out
    }

    /// 册次在教材里的先后序号（越小越早）。未知册次排到最后。
    func bookRank(_ id: String) -> Int {
        books.firstIndex(where: { $0.id == id }) ?? books.count
    }

    /// 一个词「最难的字的册次」。用来给多音字例句排序：
    /// 「数落」里「落」是 3 年级的字，一年级的孩子看不懂，
    /// 优先选整词都在本册或更早的词。
    func wordRank(_ word: String) -> Int {
        var worst = 0
        for c in word {
            let r = metaMap[String(c)].map { bookRank($0.book) } ?? books.count
            worst = max(worst, r)
        }
        return worst
    }

    /// 多音字的读音 + 各自的用例词（按「好懂」排序：词里最难的字的册次越早越靠前）
    func polyphoneCases(_ ch: String) -> [(reading: Reading, words: [String])] {
        readingDetails(ch).map { r in
            let ws = wordsUsing(ch, reading: r.p)
                .sorted { a, b in
                    let ra = wordRank(a), rb = wordRank(b)
                    if ra != rb { return ra < rb }
                    return a.count < b.count   // 同难度优先短词
                }
            return (r, ws)
        }
    }

    // MARK: - 前后导航

    func nextInLesson(_ lessonId: String?, _ ch: String) -> String {
        let list = lessonChars(lessonId)
        guard let i = list.firstIndex(of: ch), i < list.count - 1 else { return "" }
        return list[i + 1]
    }

    func prevInLesson(_ lessonId: String?, _ ch: String) -> String {
        let list = lessonChars(lessonId)
        guard let i = list.firstIndex(of: ch), i > 0 else { return "" }
        return list[i - 1]
    }

    func nextInBook(_ bookId: String, _ ch: String) -> String {
        let list = bookChars(bookId)
        guard let i = list.firstIndex(of: ch), i < list.count - 1 else { return "" }
        return list[i + 1]
    }

    func prevInBook(_ bookId: String, _ ch: String) -> String {
        let list = bookChars(bookId)
        guard let i = list.firstIndex(of: ch), i > 0 else { return "" }
        return list[i - 1]
    }

    /// 找到某字在教材中的首次出现课文
    func lessonOfChar(_ ch: String) -> String { metaMap[ch]?.l ?? "" }

    func bookStat(_ bookId: String) -> BookStat {
        bookMap[bookId]?.stat ?? BookStat(chars: 0, write: 0, lessons: 0, units: 0)
    }

    // MARK: - 笔顺

    /// 取某字的笔顺（解码并缓存）；数据缺失返回 nil
    func strokes(_ ch: String) -> StrokeCodec.CharStrokes? {
        if let c = strokeCache[ch] { return c }
        guard let raw = rawStrokes[ch] else { return nil }
        guard let decoded = try? StrokeCodec.decode(base64: raw) else { return nil }
        strokeCache[ch] = decoded
        return decoded
    }

    func strokeCount(_ ch: String) -> Int { strokes(ch)?.count ?? 0 }

    var strokeCharCount: Int { rawStrokes.count }

    /// 所有有笔顺数据的字（按教材顺序，教材外的按字典序补在后面）。
    /// 描红相关的全量校验用得到。
    func allCharsWithStrokes() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for ch in allChars where rawStrokes[ch] != nil {
            if seen.insert(ch).inserted { out.append(ch) }
        }
        for ch in rawStrokes.keys.sorted() where !seen.contains(ch) {
            seen.insert(ch)
            out.append(ch)
        }
        return out
    }

    // MARK: - 全部字（搜索用，M5 的搜索页会用到）

    /// 全部字（教材顺序）。出题时用作最后一档干扰项来源，与 Android 的 Repo.allChars 对应
    private var allCharsCache: [String]?

    var allChars: [String] {
        if let c = allCharsCache { return c }
        let list = allCharsInOrder()
        allCharsCache = list
        return list
    }

    /// 只出现在写字表、没被任何课时识字表收录的字（共 5 个：匀/剩/训/忧/毒）。
    ///
    /// 它们不属于任何一册的识字表（`bookChars` 里没有），但要能认、能描红，
    /// 所以要进全字表。按（课时、字）稳定排序，保证三端顺序一致——
    /// 小程序端的全字表就是 meta 的键序，这五个字正好在末尾。
    var writeOnlyChars: [String] {
        metaMap.compactMap { ch, m -> (String, String)? in
            let l = m.l
            guard !l.isEmpty, let lesson = lessonMap[l] else { return nil }
            guard !lesson.chars.contains(ch) else { return nil }
            return (l, ch)
        }
        .sorted { a, b in
            if a.0 != b.0 { return a.0 < b.0 }
            return a.1 < b.1
        }
        .map { $0.1 }
    }

    /// 按册次分组返回所有字，顺序遵循教材。
    ///
    /// 末尾补上只出现在写字表的那几个字——它们不在任何一册的识字表里，
    /// 但必须能认、能描红。之前这里只并了 bookChars，导致 iOS/Android
    /// 的全字表是 2591 个，而小程序端（meta 键序）是 2596 个，
    /// 三端的干扰项池和听写候选范围因此对不上。
    func allCharsInOrder() -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for b in books {
            for ch in bookChars(b.id) where seen.insert(ch).inserted {
                out.append(ch)
            }
        }
        for ch in writeOnlyChars where seen.insert(ch).inserted {
            out.append(ch)
        }
        return out
    }
}
