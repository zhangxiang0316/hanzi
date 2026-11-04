import Foundation

/// 一个课文词语（带拼音）。
struct LessonWord: Equatable, Hashable {
    let word: String
    let pinyin: String
    /// 这个词是课文词语表里的，还是从生字组词兜底来的
    let fromTextbook: Bool
}

/// 词语表里的一条，带「它属于哪一课」的完整上下文。
///
/// 和小程序 `catalog.allWords()` 的返回项一一对应。之所以要带 `book`/`unit`/
/// `lessonNo` 而不是只给一个课时 id：词语表页按册分组、每行标「第 N 课」，
/// 再回头去 catalog 里反查一次既慢又容易和课时数据脱节。
struct WordEntry: Equatable, Hashable, Identifiable {
    let word: String
    let lesson: String
    let book: String
    let unit: Int
    let lessonNo: Int
    /// 拆成单字：页面上每个字都要能单独点进详情
    let chars: [String]
    /// 这个词里不在字库中的字数，页面上要标一下
    let missing: Int

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

    // MARK: - 词语表浏览（对应小程序 catalog.allWords 系列）

    /// 全库词语表，按教材顺序，跨课去重。
    ///
    /// 1276 条词语此前只在「看拼音选词语」的题目和课时页里露过脸，没有任何
    /// 地方能从头翻一遍。家长想帮孩子过一遍这学期的词，只能靠一课一课点进去。
    ///
    /// 同一个词可能在多课重复出现（教材就是这样），这里按词去重，保留**最早
    /// 出现的那一课**——复习时按学习顺序过更顺。
    ///
    /// 只读 `lesson.words`，**不**走上面 `lessonWords` 的一年级兜底：
    /// 一年级课本本身没有词语表，词语表页要老实显示「这一册没有」，
    /// 拿生字组词兜底会让家长误以为课本上有这些词。
    ///
    /// 遍历顺序按「册 → 课」而不是字典键序：Swift 的 Dictionary 无序，
    /// 不按教材顺序走的话，同一个词保留哪一课、整个列表的顺序都会不稳定。
    func allWords() -> [WordEntry] {
        if let c = allWordsCache { return c }
        var seen = Set<String>()
        var out: [WordEntry] = []
        for b in books {
            for lid in b.lessons {
                guard let lesson = lesson(lid) else { continue }
                for word in lesson.words where seen.insert(word).inserted {
                    let chars = word.map(String.init)
                    out.append(WordEntry(
                        word: word,
                        lesson: lid,
                        book: lesson.book,
                        unit: lesson.unit,
                        lessonNo: lesson.no,
                        chars: chars,
                        missing: chars.filter { !hasChar($0) }.count
                    ))
                }
            }
        }
        allWordsCache = out
        return out
    }

    /// 某一册的词语（按教材顺序，跨课去重）。
    func bookWordEntries(_ bookId: String) -> [WordEntry] {
        allWords().filter { $0.book == bookId }
    }

    /// 按字搜词。
    ///
    /// 只看词里是否含这个字，不看读音——搜「行」应该把「行走」「银行」都列出来，
    /// 孩子要的是「哪些词里有这个字」。
    func wordsWithChar(_ ch: String) -> [WordEntry] {
        guard !ch.isEmpty else { return [] }
        return allWords().filter { $0.chars.contains(ch) }
    }
}
