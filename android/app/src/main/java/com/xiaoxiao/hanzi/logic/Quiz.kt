package com.xiaoxiao.hanzi.logic

import com.xiaoxiao.hanzi.data.Reading
import com.xiaoxiao.hanzi.data.Repo

/**
 * 出题器，与小程序 utils/quiz.js 对应。
 * 题型：看拼音选字 / 看字选拼音 / 词语填空 / 数笔画 / 找词语 / 多音字。
 * 用固定 seed 可复现，方便单测。
 */
object Quiz {

    /**
     * 与 JS 的 mulberry32 完全一致，保证同 seed 三端出同一套题。
     *
     * 对应 JS：
     *   a = (a + 0x6D2B79F5) | 0
     *   let t = Math.imul(a ^ (a >>> 15), 1 | a)
     *   t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
     *   return ((t ^ (t >>> 14)) >>> 0) / 4294967296
     *
     * 第一步乘法的第二个因子是 `1 | a`——**原始的 a**，不是异或之后的中间值。
     * 早先这里写成 `t *= (1 or t)`（t 已经被改写过），于是 Android 的随机序列
     * 与小程序/iOS 完全不同：同一个 seed 出的题不一样。
     *
     * 这个 bug 长期没被发现，是因为当时的测试只断言了「值在 0..1」和
     * 「同 seed 可复现」——两条都成立，却完全没测到「与 JS 相等」。
     * 现在改用黄金值断言（见 `LogicTest.随机数生成器与小程序逐位一致`）。
     */
    fun mulberry32(seed: Int): () -> Double {
        var a = seed
        return {
            a += 0x6d2b79f5
            var t = a xor (a ushr 15)
            t *= (1 or a)
            t = t xor (t + (t xor (t ushr 7)) * (61 or t))
            ((t xor (t ushr 14)).toLong() and 0xFFFFFFFFL) / 4294967296.0
        }
    }

    fun <T> shuffle(list: List<T>, rand: () -> Double): List<T> {
        val arr = list.toMutableList()
        for (i in arr.size - 1 downTo 1) {
            val j = (rand() * (i + 1)).toInt()
            val t = arr[i]
            arr[i] = arr[j]
            arr[j] = t
        }
        return arr
    }

    class Option(val value: String, val label: String)

    class Question(
        val type: String,
        val ch: String,
        val lesson: String?,
        val title: String,
        val prompt: String,
        /** pinyin | char | word —— 决定 prompt 用什么字体渲染 */
        val promptKind: String,
        val sub: String,
        val options: List<Option>,
        val answer: String,
        val explain: String,
        val index: Int,
        val total: Int
    )

    class Result(val questions: List<Question>, val targets: List<String>)

    private fun explainOf(ch: String, lessonId: String?): String {
        val m = Repo.meta(ch) ?: return ""
        val reading = Repo.readingFor(ch, lessonId)
        val word = m.words.firstOrNull()?.word ?: ""
        var text = "「$ch」读 $reading，部首是「${m.radical}」，共 ${m.strokes} 笔。"
        if (word.isNotEmpty()) text += "可以组词「$word」。"
        return text
    }

    private fun distractorChars(
        ch: String,
        count: Int,
        pool: List<String>,
        rand: () -> Double,
        exclude: Set<String>
    ): List<String> {
        val seen = HashSet<String>()
        val candidates = ArrayList<String>()
        for (c in pool) {
            if (c == ch || c in exclude || !seen.add(c)) continue
            candidates.add(c)
        }
        val picked = shuffle(candidates, rand).take(count).toMutableList()
        if (picked.size >= count) return picked
        for (c in Repo.allChars) {
            if (picked.size >= count) break
            if (c != ch && c !in exclude && c !in picked) picked.add(c)
        }
        return picked
    }

    private fun uniqueOptions(opts: List<Option>): List<Option> {
        val seen = HashSet<String>()
        val out = ArrayList<Option>()
        for (o in opts) if (seen.add(o.value)) out.add(o)
        return out
    }

    private fun pinyinToChar(ch: String, lessonId: String?, pool: List<String>, rand: () -> Double): Question? {
        val reading = Repo.readingFor(ch, lessonId)
        if (reading.isEmpty()) return null
        val banned = HashSet<String>()
        for (p in pool) if (reading in Repo.readingsOf(p)) banned.add(p)
        val ds = distractorChars(ch, 3, pool, rand, banned)
        if (ds.size < 3) return null
        val options = uniqueOptions(
            shuffle(listOf(Option(ch, ch)) + ds.map { Option(it, it) }, rand)
        )
        if (options.size < 4) return null
        return Question(
            type = "pinyin2char", ch = ch, lesson = lessonId,
            title = "看拼音，选汉字", prompt = reading, promptKind = "pinyin",
            sub = "哪个字的读音是 $reading？",
            options = options, answer = ch,
            explain = explainOf(ch, lessonId), index = 0, total = 0
        )
    }

    private fun charToPinyin(ch: String, lessonId: String?, pool: List<String>, rand: () -> Double): Question? {
        val reading = Repo.readingFor(ch, lessonId)
        val m = Repo.meta(ch)
        if (reading.isEmpty() || m == null) return null
        val banned = Repo.readingsOf(ch).toSet()
        val ds = distractorChars(ch, 8, pool, rand, emptySet())
        val seen = HashSet<String>()
        seen.add(reading)
        val opts = ArrayList<Option>()
        opts.add(Option(reading, reading))
        for (d in ds) {
            if (opts.size >= 4) break
            val p = Repo.meta(d)?.py ?: continue
            if (p.isNotEmpty() && p !in seen && p !in banned) {
                seen.add(p)
                opts.add(Option(p, p))
            }
        }
        if (opts.size < 4) return null
        return Question(
            type = "char2pinyin", ch = ch, lesson = lessonId,
            title = "这个字读什么？", prompt = ch, promptKind = "char",
            sub = "选出正确的读音",
            options = shuffle(opts, rand), answer = reading,
            explain = explainOf(ch, lessonId), index = 0, total = 0
        )
    }

    private fun fillWord(ch: String, lessonId: String?, pool: List<String>, rand: () -> Double): Question? {
        val m = Repo.meta(ch)
        if (m == null || m.words.isEmpty()) return null
        val word = m.words[(rand() * m.words.size).toInt().coerceIn(0, m.words.size - 1)]
        if (!word.word.contains(ch)) return null
        val masked = word.word.replace(ch, "＿")
        val ds = distractorChars(ch, 3, pool, rand, emptySet())
        if (ds.size < 3) return null
        val options = uniqueOptions(
            shuffle(listOf(Option(ch, ch)) + ds.map { Option(it, it) }, rand)
        )
        if (options.size < 4) return null
        return Question(
            type = "fillWord", ch = ch, lesson = lessonId,
            title = "词语填空", prompt = masked, promptKind = "word",
            sub = if (masked.startsWith("＿")) "补上第一个字" else "补上缺少的字",
            options = options, answer = ch,
            explain = "「${word.word}」的「$ch」读 ${Repo.readingFor(ch, lessonId)}。",
            index = 0, total = 0
        )
    }

    private fun strokeCountQ(ch: String, lessonId: String?, pool: List<String>, rand: () -> Double): Question? {
        val m = Repo.meta(ch) ?: return null
        val correct = m.strokes
        if (correct <= 0) return null
        val nums = mutableListOf(correct)
        val offsets = shuffle(listOf(1, -1, 2, -2, 3), rand)
        for (o in offsets) {
            if (nums.size >= 4) break
            val v = correct + o
            if (v > 0 && v !in nums) nums.add(v)
        }
        if (nums.size < 4) return null
        return Question(
            type = "strokeCount", ch = ch, lesson = lessonId,
            title = "数一数笔画", prompt = ch, promptKind = "char",
            sub = "一共几笔？",
            options = shuffle(nums.map { Option(it.toString(), "$it 笔") }, rand),
            answer = correct.toString(),
            explain = "「$ch」共 $correct 笔，部首是「${m.radical}」。",
            index = 0, total = 0
        )
    }

    private fun charToWord(ch: String, lessonId: String?, pool: List<String>, rand: () -> Double): Question? {
        val m = Repo.meta(ch)
        if (m == null || m.words.isEmpty()) return null
        val correct = m.words[(rand() * m.words.size).toInt().coerceIn(0, m.words.size - 1)]
        val ds = distractorChars(ch, 12, pool, rand, emptySet())
        val seen = HashSet<String>()
        seen.add(correct.word)
        val options = ArrayList<Option>()
        options.add(Option(correct.word, correct.word))
        for (d in ds) {
            if (options.size >= 4) break
            for (w in Repo.meta(d)?.words ?: emptyList()) {
                if (w.word.contains(ch) || !seen.add(w.word)) continue
                options.add(Option(w.word, w.word))
                break
            }
        }
        if (options.size < 4) return null
        return Question(
            type = "char2word", ch = ch, lesson = lessonId,
            title = "词语找朋友", prompt = ch, promptKind = "char",
            sub = "哪个词语里有这个字？",
            options = shuffle(options, rand), answer = correct.word,
            explain = "「${correct.word}」里有「$ch」字，读作 ${Repo.readingFor(ch, lessonId)}。",
            index = 0, total = 0
        )
    }

    /** 一轮出题内已用过的「类型|字|题面」，避免同一个字同一个词问两遍。 */
    private val usedPrompts = HashSet<String>()

    /**
     * 多音字：给一个用例词，问这个字在这里读什么。
     *
     * 单独一个题型、单独一个模式，不混进普通闯关：
     * 多音字只占 2596 个字里的 156 个，混进去出现的概率太低，
     * 孩子每次遇到都像突然换了个游戏。而「读准」本身是个独立的技能，
     * 值得有自己的入口。
     *
     * 选项就是这个字自己的读音（2~3 个），不掺别的字的读音——
     * 掺了会变成「猜哪个不像」，而不是「判断语境」。
     */
    private fun polyphone(ch: String, lessonId: String?, pool: List<String>, rand: () -> Double): Question? {
        val cases = Repo.polyphoneCases(ch)
        if (cases.size <= 1) return null

        // 优先挑「有实际用例词」的读音，这样题目里有语境可依
        val withWord = cases.filter { it.second.isNotEmpty() }
        if (withWord.isEmpty()) return null

        // 同一个字、同一个用例词问两遍不算两道题。随机挑，但跳过这一轮里已经用过的词；
        // 全都用过就退回随机（宁可重复也不能出不来题）。
        val fresh = ArrayList<Pair<Reading, String>>()
        for (c in withWord) {
            for (w in c.second) {
                if (!usedPrompts.contains("polyphone|$ch|$w")) fresh.add(c.first to w)
            }
        }
        val word: String
        val answer: String
        if (fresh.isNotEmpty()) {
            val f = fresh[(rand() * fresh.size).toInt().coerceIn(0, fresh.size - 1)]
            word = f.second
            answer = f.first.pinyin
        } else {
            val picked = withWord[(rand() * withWord.size).toInt().coerceIn(0, withWord.size - 1)]
            val words = picked.second
            word = words[(rand() * words.size).toInt().coerceIn(0, words.size - 1)]
            answer = picked.first.pinyin
        }
        usedPrompts.add("polyphone|$ch|$word")

        val seen = HashSet<String>()
        val opts = ArrayList<Option>()
        for (c in cases) {
            if (seen.add(c.first.pinyin)) opts.add(Option(c.first.pinyin, c.first.pinyin))
        }
        if (opts.size < 2) return null

        // 解释里把每个读音的用例都列出来，这样答完能顺手记住另一个读音
        val detail = cases.joinToString("；") { c ->
            if (c.second.isEmpty()) c.first.pinyin
            else c.first.pinyin + "（" + c.second.take(2).joinToString("、") + "）"
        }

        return Question(
            type = "polyphone", ch = ch, lesson = lessonId,
            title = "多音字读什么", prompt = word, promptKind = "word",
            sub = "「$ch」在「$word」里读什么？",
            options = shuffle(opts, rand), answer = answer,
            explain = "「$ch」是多音字：$detail。",
            index = 0, total = 0
        )
    }

    private val TYPE_ORDER = listOf("pinyin2char", "char2pinyin", "fillWord", "strokeCount", "char2word")

    private fun make(type: String, ch: String, lessonId: String?, pool: List<String>, rand: () -> Double): Question? =
        when (type) {
            "pinyin2char" -> pinyinToChar(ch, lessonId, pool, rand)
            "char2pinyin" -> charToPinyin(ch, lessonId, pool, rand)
            "fillWord" -> fillWord(ch, lessonId, pool, rand)
            "strokeCount" -> strokeCountQ(ch, lessonId, pool, rand)
            "char2word" -> charToWord(ch, lessonId, pool, rand)
            "polyphone" -> polyphone(ch, lessonId, pool, rand)
            else -> null
        }

    fun build(
        chars: List<String>,
        book: String? = null,
        lesson: String? = null,
        count: Int = 10,
        seed: Long = System.currentTimeMillis(),
        types: List<String>? = null
    ): Result {
        // 普通闯关传 null，用固定的 TYPE_ORDER——这样已有的 seed 仍然出同一套题。
        // 多音字模式传 listOf("polyphone")，只出这一种。
        val order = types ?: TYPE_ORDER
        usedPrompts.clear()
        val targets = chars.filter { Repo.hasChar(it) }
        if (targets.isEmpty()) return Result(emptyList(), emptyList())

        val rand = mulberry32(seed.toInt())
        val bookId = book ?: Repo.meta(targets[0])?.book ?: Repo.defaultBook()
        var pool = Repo.bookChars(bookId)
        if (pool.size < 12) pool = Repo.allChars

        val questions = ArrayList<Question>()
        var guard = 0
        while (questions.size < count && guard < count * 6) {
            val ch = targets[questions.size % targets.size]
            val lessonId = lesson ?: Repo.meta(ch)?.lesson
            val start = (rand() * order.size).toInt().coerceIn(0, order.size - 1)
            for (k in order.indices) {
                val type = order[(start + k) % order.size]
                val q = make(type, ch, lessonId, pool, rand)
                if (q != null) {
                    questions.add(q)
                    break
                }
            }
            guard++
        }
        return Result(
            questions = questions.mapIndexed { i, q ->
                Question(q.type, q.ch, q.lesson, q.title, q.prompt, q.promptKind, q.sub,
                    q.options, q.answer, q.explain, i, questions.size)
            },
            targets = targets
        )
    }
}
