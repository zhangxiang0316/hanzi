import Foundation

/// 一个课文词语（带拼音）。
struct LessonWord: Equatable, Hashable {
    let word: String
    let pinyin: String
    /// 这个词是课文词语表里的，还是从生字组词兜底来的
    let fromTextbook: Bool
}

/// 词语表里的一条，带「它属于哪一课、又出现在哪几册」的完整上下文。
///
/// 为什么不是只给一个课时 id：词语表页按册分组、每行标「第 N 课」、
/// 搜索结果要显示「一年级上册 / 三年级下册」，再回头去 catalog 里反查
/// 既慢又容易和课时数据脱节。
struct WordEntry: Equatable, Hashable, Identifiable {
    let word: String
    let pinyin: String
    let lesson: String
    let book: String
    let unit: Int
    let lessonNo: Int
    /// 拆成单字：页面上每个字都要能单独点进详情
    let chars: [String]
    /// 这个词里不在字库中的字数。派生词里有少数会撞上字库外的常用字
    /// （「弓弩」的弩、「镜匣」的匣），那些字点不进详情页，页面要置灰。
    let missing: Int
    /// 派生词：课本这一课没有词语表，用生字的第一组词补的。
    /// 必须标出来，否则家长会以为课本上就写着这些词。
    let derived: Bool
    /// 这个词出现在哪几册。按册浏览时只有一个元素；
    /// `uniqueWords()` 全局去重后才可能跨册（「旅行」在 1b 和 3a 都有）。
    let books: [String]

    var id: String { word }

    /// 一个词算不算「学过」。
    ///
    /// 只有词里**每个字都学过**才算。有一个字不认识，这个词孩子读不出来，
    /// 算学过是自欺欺人。
    func isLearned(_ hasLearned: (String) -> Bool) -> Bool {
        chars.allSatisfy(hasLearned)
    }
}

/// 课文词语表。
///
/// `Lesson.words` 是教材每课末尾的词语表，2a 起共 1276 条。这份数据
/// 从第一天就在 `catalog.json` 里，但三端**一次都没有读过**——
/// 之前的「词语填空」用的是每个字自己带的组词（`meta.w`），那是通用例子，
/// 不是课本上要求学生掌握的那一份。
///
/// 两个用途：
/// 1. 课文词语表（复习时照着念）
/// 2. 「看拼音选词语」练习（`Quiz.buildWordQuiz`）
///
/// 一年级（1a/1b）的课时没有 words。不是数据缺失——一年级课本本来就没有
/// 单独的词语表，识字量还在积累。对这一档用本课生字的组词兜底，
/// 保证功能在所有八册上都可用。
///
/// **词语表页必须走这层**，不能另写一套遍历：兜底只在这里有，另写一份
/// 必然把它漏掉，结果是一年级点进词语表看到一片空白——而一年级正是
/// 这个 App 最大的用户群。
extension Repo {

    /// 一个词的拼音。
    ///
    /// 优先用 meta 里该字组词自带的拼音（`words[].pinyin`，带声调、按词连写），
    /// 拿不到再逐字拼。前者更准——多音字在具体词里的读音只有它知道。
    func wordPinyin(_ word: String) -> String {
        for ch in word {
            guard let m = meta(String(ch)) else { continue }
            for w in m.words where w.word == word && !w.pinyin.isEmpty {
                return w.pinyin
            }
        }
        // 退路：逐字拼，空格分开
        return word.map { meta(String($0))?.py ?? "" }.joined(separator: " ")
    }

    /// 某一课的词语。
    ///
    /// 有课本词语表就用它（带拼音），没有就退到本课生字的组词。
    /// 结果按课本顺序，不排序——家长对照课本念的时候顺序要对得上。
    func lessonWords(_ lessonId: String) -> [LessonWord] {
        if let c = lessonWordCache[lessonId] { return c }
        guard let lesson = lesson(lessonId) else { return [] }

        var out: [LessonWord] = []
        if !lesson.words.isEmpty {
            out = lesson.words.map {
                LessonWord(word: $0, pinyin: wordPinyin($0), fromTextbook: true)
            }
        } else {
            // 一年级兜底：用本课生字各自的第一组词
            var seen = Set<String>()
            for ch in lesson.chars {
                guard let m = meta(ch), let w = m.words.first else { continue }
                guard !w.word.isEmpty, seen.insert(w.word).inserted else { continue }
                let py = w.pinyin.isEmpty ? wordPinyin(w.word) : w.pinyin
                out.append(LessonWord(word: w.word, pinyin: py, fromTextbook: false))
            }
        }
        lessonWordCache[lessonId] = out
        return out
    }

    /// 某一册的全部词语（按课本顺序，去重）
    func bookWords(_ bookId: String) -> [LessonWord] {
        guard let book = book(bookId) else { return [] }
        var seen = Set<String>()
        var out: [LessonWord] = []
        for lid in book.lessons {
            for w in lessonWords(lid) where seen.insert(w.word).inserted {
                out.append(w)
            }
        }
        return out
    }

    func bookWordCount(_ bookId: String) -> Int { bookWords(bookId).count }

    // MARK: - 词语表浏览
    //
    // 下面这组的**去重粒度是有意分两层的**，别合并：
    //
    // - 按册浏览：一册内去重。同一个词出现在两册是教材事实（「旅行」在
    //   1b 和 3a 都有），分组浏览时该各显示一次，否则二年级家长在 1b 里
    //   找不到「旅行」，会以为数据丢了。
    // - 搜索和总数：全局去重。搜「行」列出两条「旅行」是明显的 bug。
    //
    // 按册条目 2492 条、全局 1967 个词——这对数字和小程序一致，测试里钉死。

    /// 某一册的词语表条目（按教材顺序，册内去重）。
    ///
    /// 走 `lessonWords`，所以一年级也有词（来自生字组词，`derived == true`）。
    func bookWordEntries(_ bookId: String) -> [WordEntry] {
        if let c = bookWordsCache[bookId] { return c }
        guard let book = book(bookId) else { return [] }
        var seen = Set<String>()
        var out: [WordEntry] = []
        for lid in book.lessons {
            guard let lesson = lesson(lid) else { continue }
            for w in lessonWords(lid) {
                guard seen.insert(w.word).inserted else { continue }
                let chars = w.word.map(String.init)
                out.append(WordEntry(
                    word: w.word,
                    pinyin: w.pinyin,
                    lesson: lid,
                    book: lesson.book,
                    unit: lesson.unit,
                    lessonNo: lesson.no,
                    chars: chars,
                    missing: chars.filter { !hasChar($0) }.count,
                    derived: !w.fromTextbook,
                    books: [lesson.book]
                ))
            }
        }
        bookWordsCache[bookId] = out
        return out
    }

    /// 全库词语表条目：按册拼接，只做到册内去重（2492 条）。
    ///
    /// 遍历顺序按「册 → 课」而不是字典键序：Swift 的 Dictionary 无序，
    /// 不按教材顺序走的话列表顺序会不稳定，同一课保留哪个词也会漂。
    func allWordEntries() -> [WordEntry] {
        if let c = allWordsCache { return c }
        var out: [WordEntry] = []
        for b in books {
            out.append(contentsOf: bookWordEntries(b.id))
        }
        allWordsCache = out
        return out
    }

    /// 全库去重后的词语（1967 个），保留最早出现的那一册/课。
    ///
    /// `books` 里会累积还包括哪几册，搜索结果据此显示「一年级上册 / 三年级下册」，
    /// 而不是让同一个词在列表里出现两次。
    func uniqueWords() -> [WordEntry] {
        if let c = uniqueWordsCache { return c }
        var order: [String] = []
        var byWord: [String: WordEntry] = [:]
        var booksOf: [String: [String]] = [:]
        for w in allWordEntries() {
            if byWord[w.word] == nil {
                byWord[w.word] = w
                booksOf[w.word] = [w.book]
                order.append(w.word)
            } else if !(booksOf[w.word]?.contains(w.book) ?? false) {
                booksOf[w.word]?.append(w.book)
            }
        }
        let out: [WordEntry] = order.compactMap { word in
            guard let e = byWord[word] else { return nil }
            return WordEntry(
                word: e.word, pinyin: e.pinyin, lesson: e.lesson, book: e.book,
                unit: e.unit, lessonNo: e.lessonNo, chars: e.chars,
                missing: e.missing, derived: e.derived,
                books: booksOf[word] ?? [e.book]
            )
        }
        uniqueWordsCache = out
        return out
    }

    /// 按字搜词（全局去重）。
    ///
    /// 只看词里是否含这个字，不看读音——搜「行」应该把「行走」「银行」都列出来，
    /// 孩子要的是「哪些词里有这个字」。
    func wordsWithChar(_ ch: String) -> [WordEntry] {
        guard !ch.isEmpty else { return [] }
        return uniqueWords().filter { $0.chars.contains(ch) }
    }
}
