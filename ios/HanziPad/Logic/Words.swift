import Foundation

/// 一个课文词语（带拼音）。
struct LessonWord: Equatable, Hashable {
    let word: String
    let pinyin: String
    /// 这个词是课文词语表里的，还是从生字组词兜底来的
    let fromTextbook: Bool
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
}
