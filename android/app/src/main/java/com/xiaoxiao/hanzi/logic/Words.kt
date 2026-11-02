package com.xiaoxiao.hanzi.logic

import com.xiaoxiao.hanzi.data.Repo

/**
 * 一个课文词语（带拼音）。
 *
 * [fromTextbook] 表示这个词来自课本词语表，还是从生字组词兜底来的。
 */
data class LessonWord(val word: String, val pinyin: String, val fromTextbook: Boolean)

/**
 * 课文词语表。
 *
 * `Lesson.words` 是教材每课末尾的词语表，2a 起共 1276 条。这份数据
 * 从第一天就在 catalog.json 里，但三端**一次都没有读过**——
 * 之前的「词语填空」用的是每个字自己带的组词（`meta.w`），那是通用例子，
 * 不是课本上要求学生掌握的那一份。
 *
 * 一年级（1a/1b）的课时没有 words。不是数据缺失——一年级课本本来就没有
 * 单独的词语表，识字量还在积累。对这一档用本课生字的组词兜底，
 * 保证功能在所有八册上都可用。
 *
 * 与 iOS `Repo.lessonWords` / `bookWords`、小程序 `utils/words.js` 对应。
 */
object Words {

    private val lessonCache = HashMap<String, List<LessonWord>>()

    /**
     * 一个词的拼音。
     *
     * 优先用 meta 里该字组词自带的拼音（`words[].p`，带声调、按词连写），
     * 拿不到再逐字拼。前者更准——多音字在具体词里的读音只有它知道。
     */
    fun wordPinyin(word: String): String {
        for (ch in word) {
            val m = Repo.meta(ch.toString()) ?: continue
            for (w in m.words) {
                if (w.word == word && w.pinyin.isNotEmpty()) return w.pinyin
            }
        }
        // 退路：逐字拼，空格分开
        return word.map { Repo.meta(it.toString())?.py ?: "" }.joinToString(" ")
    }

    /**
     * 某一课的词语。
     *
     * 有课本词语表就用它（带拼音），没有就退到本课生字的组词。
     * 结果按课本顺序，不排序——家长对照课本念的时候顺序要对得上。
     */
    fun lessonWords(lessonId: String): List<LessonWord> {
        lessonCache[lessonId]?.let { return it }
        val lesson = Repo.lesson(lessonId) ?: return emptyList()

        val out = ArrayList<LessonWord>()
        if (lesson.words.isNotEmpty()) {
            lesson.words.forEach { w ->
                out.add(LessonWord(w, wordPinyin(w), true))
            }
        } else {
            // 一年级兜底：用本课生字各自的第一组词
            val seen = HashSet<String>()
            lesson.chars.forEach { ch ->
                val m = Repo.meta(ch)
                val w = m?.words?.firstOrNull()
                if (w != null && w.word.isNotEmpty() && seen.add(w.word)) {
                    val py = if (w.pinyin.isEmpty()) wordPinyin(w.word) else w.pinyin
                    out.add(LessonWord(w.word, py, false))
                }
            }
        }
        lessonCache[lessonId] = out
        return out
    }

    /** 某一册的全部词语（按课本顺序，去重） */
    fun bookWords(bookId: String): List<LessonWord> {
        val book = Repo.book(bookId) ?: return emptyList()
        val seen = HashSet<String>()
        val out = ArrayList<LessonWord>()
        book.lessons.forEach { lid ->
            lessonWords(lid).forEach { w ->
                if (seen.add(w.word)) out.add(w)
            }
        }
        return out
    }

    fun bookWordCount(bookId: String): Int = bookWords(bookId).size
}
