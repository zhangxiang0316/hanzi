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

    /**
     * 同音字填空：给一个词，挖掉其中一个字，选项**全部同音**。
     *
     * 与「词语填空」的区别就在选项：那个用的是同册随机字，一眼就能排除；
     * 这里的选项读音完全一样，只能靠「这个字该怎么写」来选。
     * `dì dì` 到底是「弟弟」还是「第第」——这正是听写里最常见的错。
     *
     * 与多音字正好互补：多音字练「一个字有几个音」，同音字练「一个音有几个字」。
     */
    private fun homophoneQ(
        ch: String,
        lessonId: String?,
        pool: List<String>,
        rand: () -> Double
    ): Question? {
        val m = Repo.meta(ch) ?: return null
        if (m.words.isEmpty()) return null
        // 干扰项必须真的同音，凑不够 3 个就不出这道题——
        // 混进非同音的字等于把答案送给孩子，练不到东西
        val ds = Repo.homophoneDistractors(ch, m.book, 3)
        if (ds.size < 3) return null

        val cands = m.words.filter { it.word.contains(ch) }
        if (cands.isEmpty()) return null
        val word = cands[(rand() * cands.size).toInt().coerceIn(0, cands.size - 1)]
        val masked = word.word.replace(ch, "＿")

        val raw = ArrayList<Option>()
        raw.add(Option(ch, ch))
        ds.forEach { raw.add(Option(it, it)) }
        val options = uniqueOptions(shuffle(raw, rand))
        if (options.size != 4) return null

        return Question(
            type = "homophone",
            ch = ch,
            lesson = lessonId,
            title = "同音字填空",
            prompt = masked,
            promptKind = "word",
            sub = "都不是一个音，选对的那个字",
            options = options,
            answer = ch,
            explain = "「${word.word}」写「$ch」；${ds.joinToString("、")} 和它同音（${m.py}），但意思不同。",
            index = 0,
            total = 0
        )
    }

    /**
     * 形近字填空：给一个词，挖掉其中一个字，选项**全部是形近字**。
     *
     * 与同音字是一对：同音字考「音一样，写哪个」；形近字考「长得像，别混」。
     * 这两个是低年级错字的两个主因——「袋/带」是音，「未/末」是形。
     *
     * 干扰项必须真的形近（来自算出来的形近字表），凑不够 3 个就不出这道题：
     * 混进形状无关的字，孩子扫一眼就能排除，练不到辨析。
     */
    private fun similarQ(
        ch: String,
        lessonId: String?,
        pool: List<String>,
        rand: () -> Double
    ): Question? {
        val m = Repo.meta(ch) ?: return null
        if (m.words.isEmpty()) return null
        // 传册次不是课次，和同音字同理：课次会让「同册优先」静默失效
        val ds = Repo.similarDistractors(ch, m.book, 3)
        if (ds.size < 3) return null

        val cands = m.words.filter { it.word.contains(ch) }
        if (cands.isEmpty()) return null
        val word = cands[(rand() * cands.size).toInt().coerceIn(0, cands.size - 1)]
        val masked = word.word.replace(ch, "＿")

        val raw = ArrayList<Option>()
        raw.add(Option(ch, ch))
        ds.forEach { raw.add(Option(it, it)) }
        val options = uniqueOptions(shuffle(raw, rand))
        if (options.size != 4) return null

        return Question(
            type = "similar",
            ch = ch,
            lesson = lessonId,
            title = "形近字填空",
            prompt = masked,
            promptKind = "word",
            sub = "这几个字长得像，别写混了",
            options = options,
            answer = ch,
            explain = "「${word.word}」写「$ch」；${ds.joinToString("、")} 和它长得像，但笔画不一样。",
            index = 0,
            total = 0
        )
    }

    /**
     * 部首：给一个字，选出它的部首。
     *
     * 部首查字法是二年级语文园地的正式内容。与「数笔画」是一对——
     * 查字典要同时知道部首和笔画。
     *
     * 独体字的部首就是它自己（龟→龟、鼓→鼓），答案直接印在题干上，
     * 孩子只要挑那个看得见的字就行，考不到任何东西，所以直接不出题。
     */
    private fun radicalQ(
        ch: String,
        lessonId: String?,
        pool: List<String>,
        rand: () -> Double
    ): Question? {
        val m = Repo.meta(ch) ?: return null
        if (m.radical.isEmpty()) return null
        if (m.radical == ch) return null
        // 干扰项排除字形包含关系（木/林），那种是有争议的
        val ds = Repo.radicalDistractors(m.radical, m.book, 3)
        if (ds.size < 3) return null

        val raw = ArrayList<Option>()
        raw.add(Option(m.radical, m.radical))
        ds.forEach { raw.add(Option(it, it)) }
        val options = uniqueOptions(shuffle(raw, rand))
        if (options.size != 4) return null

        return Question(
            type = "radical",
            ch = ch,
            lesson = lessonId,
            title = "部首",
            prompt = ch,
            promptKind = "char",
            sub = "这个字的部首是哪个？",
            options = options,
            answer = m.radical,
            explain = "「$ch」的部首是「${m.radical}」，共 ${m.strokes} 笔。",
            index = 0,
            total = 0
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
            "homophone" -> homophoneQ(ch, lessonId, pool, rand)
            "radical" -> radicalQ(ch, lessonId, pool, rand)
            "similar" -> similarQ(ch, lessonId, pool, rand)
            "char2word" -> charToWord(ch, lessonId, pool, rand)
            "polyphone" -> polyphone(ch, lessonId, pool, rand)
            else -> null
        }

    /**
     * 「看拼音选词语」：给一个词语的拼音，选出正确的那个词。
     *
     * 直接用课本的词语表（[Words]），不是每个字自带的组词——后者是通用例子，
     * 前者才是要求掌握的那一份。
     *
     * 与字音题的区别：孩子要读的是**整个词**，而不只是其中一个字。
     * 「天空」和「填空」的字音完全不同，光看字形分不出来，必须真的会读。
     *
     * 与 iOS `Quiz.buildWordQuiz`、小程序 `quiz.buildWordQuiz` 对应。
     */
    fun buildWordQuiz(
        book: String?,
        lesson: String? = null,
        count: Int = 10,
        seed: Long = System.currentTimeMillis()
    ): Result {
        val src = if (lesson != null) Words.lessonWords(lesson) else Words.bookWords(book ?: "")
        if (src.size < 4) return Result(emptyList(), emptyList())

        val rand = mulberry32(seed.toInt())
        // 至少两个字、且有拼音的词才能出题
        val pool = src.filter { it.pinyin.isNotEmpty() && it.word.length >= 2 }
        if (pool.size < 4) return Result(emptyList(), emptyList())

        val want = minOf(count, pool.size)
        val picked = ArrayList<LessonWord>()
        val usedWord = HashSet<String>()
        val usedPinyin = HashSet<String>()
        var guard = 0
        while (picked.size < want && guard < want * 8) {
            guard++
            val cand = pool[(rand() * pool.size).toInt().coerceIn(0, pool.size - 1)]
            if (!usedWord.add(cand.word)) continue
            // 题面（拼音）也不能重复：同一轮的题会一块儿显示在结果页
            if (!usedPinyin.add(cand.pinyin)) {
                usedWord.remove(cand.word)
                continue
            }
            picked.add(cand)
        }

        val questions = ArrayList<Question>()
        for (correct in picked) {
            // 干扰项：同册其他词，且拼音不能和正确答案一样（同音词会让这题无解）
            val ds = ArrayList<LessonWord>()
            var tries = 0
            while (ds.size < 3 && tries < 60) {
                tries++
                val cand = pool[(rand() * pool.size).toInt().coerceIn(0, pool.size - 1)]
                if (cand.word == correct.word || cand.pinyin == correct.pinyin) continue
                if (ds.any { it.word == cand.word }) continue
                ds.add(cand)
            }
            if (ds.size != 3) continue

            val raw = ArrayList<Option>()
            raw.add(Option(correct.word, correct.word))
            ds.forEach { raw.add(Option(it.word, it.word)) }
            val options = uniqueOptions(shuffle(raw, rand))
            if (options.size != 4) continue

            questions.add(
                Question(
                    type = "wordPinyin",
                    ch = correct.word,
                    lesson = lesson,
                    title = "看拼音选词语",
                    prompt = correct.pinyin,
                    promptKind = "pinyin",
                    sub = "这个音是哪个词？",
                    options = options,
                    answer = correct.word,
                    explain = "「${correct.word}」读 ${correct.pinyin}。",
                    index = questions.size,
                    total = want
                )
            )
        }

        // 重排 index/total：中途被跳过的题会让前面算的 total 偏大
        val fixed = questions.mapIndexed { i, q ->
            Question(q.type, q.ch, q.lesson, q.title, q.prompt, q.promptKind, q.sub,
                q.options, q.answer, q.explain, i, questions.size)
        }
        return Result(fixed, fixed.map { it.ch })
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
            // 用**尝试次数**推进取字，不能用 questions.size。
            // 某个字出不了题时 questions.size 不增长，就会一直重试同一个字
            // 直到 guard 耗尽——整套题变成 0 道。
            val ch = targets[guard % targets.size]
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
