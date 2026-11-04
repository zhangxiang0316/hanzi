package com.xiaoxiao.hanzi.logic

import com.xiaoxiao.hanzi.data.Repo

/**
 * 一个课文词语（带拼音）。
 *
 * [fromTextbook] 表示这个词来自课本词语表，还是从生字组词兜底来的。
 * [lesson] 是这个词出现在哪一课——词语表页要显示「第 N 课」，
 * 而 [Words.bookWords] 是跨课拼接的，不带上课次就回查不出来。
 */
data class LessonWord(
    val word: String,
    val pinyin: String,
    val fromTextbook: Boolean,
    val lesson: String = ""
)

/**
 * 词语表里的一条（浏览 / 搜索用）。
 *
 * 与 [LessonWord] 的区别是它带上了出处：[lesson] / [book] 是这个词最早出现的
 * 那一课，[books] 是**全部**出现过的册次——「旅行」在 1b 和 3a 各出现一次，
 * 分组浏览时两册各显示一条，全局搜索时只有一条、但要注明两册都有。
 *
 * [fromTextbook] 为 false 表示这是生字组词兜底来的派生词，不是课本原文。
 */
data class WordRow(
    val word: String,
    val pinyin: String,
    val lesson: String,
    val book: String,
    val lessonNo: Int,
    val fromTextbook: Boolean,
    val books: List<String>
)

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

    /** 全库（按册拼接）结果缓存；数据加载一次就不变，没必要每次重算 */
    private var allCache: List<WordRow>? = null
    private var uniqueCache: List<WordRow>? = null

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
                out.add(LessonWord(w, wordPinyin(w), true, lessonId))
            }
        } else {
            // 一年级兜底：用本课生字各自的第一组词
            val seen = HashSet<String>()
            lesson.chars.forEach { ch ->
                val m = Repo.meta(ch)
                val w = m?.words?.firstOrNull()
                if (w != null && w.word.isNotEmpty() && seen.add(w.word)) {
                    val py = if (w.pinyin.isEmpty()) wordPinyin(w.word) else w.pinyin
                    out.add(LessonWord(w.word, py, false, lessonId))
                }
            }
        }
        lessonCache[lessonId] = out
        return out
    }

    /** 某一册的全部词语（按课本顺序，册内去重） */
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

    // ---------- 词语表浏览 ----------

    /**
     * 全库词语，按册次顺序拼接。
     *
     * 词语表页要「从头翻一遍」，所以需要一份把 8 册串起来的列表。
     * 复用 [bookWords] 而不是另写一遍遍历：那里面已经处理了一年级的兜底
     * （课本没有词语表时用生字的组词补），另写一份必然会把那个兜底漏掉，
     * 结果就是一年级点进词语表看到一片空白——而一年级正是这个 App
     * 最大的用户群。
     */
    fun allWords(): List<WordRow> {
        allCache?.let { return it }
        val out = ArrayList<WordRow>()
        for (b in Repo.books) {
            // 册内去重：同一册里同一个词出现在两课，只留最早那一课
            val seen = HashSet<String>()
            for (lid in b.lessons) {
                val no = Repo.lesson(lid)?.no ?: 0
                for (w in lessonWords(lid)) {
                    if (!seen.add(w.word)) continue
                    out.add(
                        WordRow(
                            word = w.word,
                            pinyin = w.pinyin,
                            lesson = lid,
                            book = b.id,
                            lessonNo = no,
                            fromTextbook = w.fromTextbook,
                            books = listOf(b.id)
                        )
                    )
                }
            }
        }
        allCache = out
        return out
    }

    /**
     * 全库去重后的词语（按册次顺序，保留最早出现的那一册）。
     *
     * [allWords] 是按册拼接的，去重只做到册内——「旅行」在 1b 和 3a 各出一次
     * 是教材事实，分组浏览时应该各显示一次。但搜索和总数统计算的是
     * 「有多少个词」，那就必须全局去重，否则搜「行」会列出两条「旅行」。
     */
    fun uniqueWords(): List<WordRow> {
        uniqueCache?.let { return it }
        val order = LinkedHashMap<String, MutableList<String>>()
        val first = HashMap<String, WordRow>()
        allWords().forEach { w ->
            val books = order.getOrPut(w.word) {
                first[w.word] = w
                ArrayList()
            }
            if (!books.contains(w.book)) books.add(w.book)
        }
        val out = order.map { (word, books) ->
            val w = first[word]!!
            WordRow(w.word, w.pinyin, w.lesson, w.book, w.lessonNo, w.fromTextbook, books)
        }
        uniqueCache = out
        return out
    }

    /**
     * 按字搜词。全局去重。
     *
     * 只看词里是否含这个字，不看读音——搜「行」应该把「行走」「银行」都列出来，
     * 孩子要的是「哪些词里有这个字」。
     */
    fun wordsWithChar(ch: String?): List<WordRow> {
        if (ch.isNullOrEmpty()) return emptyList()
        return uniqueWords().filter { it.word.contains(ch) }
    }

    /**
     * 一个词算不算「学过」：词里**每个字都学过**才算。
     *
     * 有一个字不认识，这个词孩子就读不出来，算「学过」是自欺欺人。
     */
    fun learned(word: String, hasLearned: (String) -> Boolean): Boolean =
        word.isNotEmpty() && word.all { hasLearned(it.toString()) }
}
