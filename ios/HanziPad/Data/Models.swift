import Foundation

/// 一个字的学习元数据，对应 meta.json 的一项。
///
/// 字段缩写与 JSON 一致（py/r/s/b/l/x），因为这两千多条数据是构建脚本生成的，
/// 改成全拼会让 JSON 大一圈，而映射逻辑集中在这里，可读性不受影响。
struct CharMeta: Decodable {
    /// 拼音
    let py: String
    /// 组词
    let w: [Word]
    /// 部首
    let r: String
    /// 笔画数
    let s: Int
    /// 首次出现的册次
    let b: String
    /// 首次出现的课文
    let l: String
    /// 会写的课次；空串表示只认不写
    let x: String
    /// 多音字读音表；单音字为 nil
    let rd: [Reading]?

    var words: [Word] { w }
    var radical: String { r }
    var strokes: Int { s }
    var book: String { b }
    var lesson: String { l }
    var writeLesson: String { x }
    var readings: [Reading]? { rd }
}

struct Word: Decodable, Hashable {
    let w: String
    let p: String

    var word: String { w }
    var pinyin: String { p }
}

struct Reading: Decodable, Hashable {
    let p: String
    let l: String

    var pinyin: String { p }
    var lesson: String { l }
}

struct Lesson: Decodable, Identifiable {
    let id: String
    let book: String
    let unit: Int
    let no: Int
    let title: String
    let kind: String
    let page: Int
    let chars: [String]
    let write: [String]
    let words: [String]
}

struct Unit: Decodable, Hashable {
    let no: Int
    let title: String
    let theme: String
    let lessons: [String]
}

struct BookStat: Decodable, Hashable {
    let chars: Int
    let write: Int
    let lessons: Int
    let units: Int
}

struct Book: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let short: String
    let grade: Int
    let term: Int
    let units: [Unit]
    let lessons: [String]
    let stat: BookStat
}

/// catalog.json 的结构。lessons 是 { "1a-s1": {...} } 这样的字典而非数组。
struct Catalog: Decodable {
    let version: Int
    let edition: String
    let generatedAt: String
    let books: [Book]
    let lessons: [String: Lesson]
}
