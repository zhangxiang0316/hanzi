package com.xiaoxiao.hanzi.logic

import com.xiaoxiao.hanzi.data.Repo

/**
 * 识字量测试。
 *
 * 家长最想知道的一个数字是「我家孩子认识多少字」。原来的 app 只能回答
 * 「学过多少字」——那是**点过多少个字**，不是认识多少。孩子点开一百个字
 * 一个没记住，界面上照样显示 100。
 *
 * ## 为什么用分层抽测，不是全测
 *
 * 2596 个字全问一遍要半小时，一二年级孩子坐不住。所以每册抽 5 个，
 * 按册次从低到高问；某一册正确率低于 40% 就停——再往后的册次问下去
 * 也只是让孩子反复受挫。
 *
 * 抽的时候按**等距取样**（`stride`），不是取前 5 个。取前 5 个等于只考
 * 「日月水火」这种最基础的字，估出来的数会虚高一大截。等距取样才能覆盖
 * 整册，包括靠后的难字。
 *
 * ## 估算方法
 *
 * 每册的得分率 × 该册字数，累加。停下的那一册之后的册次一律记 0——
 * 那是还没学到的部分，不该按更低的比例折算。
 *
 * 抽 5 个字的比例误差不小，所以结果只报「约」到百位，并且明说是估算。
 * 报一个精确到个位的数字是在骗家长。
 *
 * 与小程序 `utils/vocab.js`、iOS `Logic/Vocab.swift` 逐位一致。
 */
object Vocab {

    /** 每册抽几个字。5 × 8 册 = 最多 40 题，中间还会提前停。 */
    const val PER_BOOK = 5

    /** 低于这个正确率就停在这一册 */
    const val STOP_RATE = 0.4

    class Group(
        val book: String,
        val name: String,
        val bookTotal: Int,
        val start: Int,
        val questions: List<Quiz.Question>
    )

    class Test(val groups: List<Group>, val total: Int) {
        val questions: List<Quiz.Question> get() = groups.flatMap { it.questions }
    }

    class GroupScore(
        val book: String,
        val name: String,
        val asked: Int,
        val correct: Int,
        val rate: Double,
        val counted: Boolean,
        val contribution: Int
    )

    class Estimate(
        val size: Int,
        val groups: List<GroupScore>,
        val level: String,
        val stopBook: String,
        val answered: Int,
        val done: Boolean
    )

    /**
     * 一册里等距抽 n 个字。
     *
     * 起点用 seed 随机，步长固定为 `len / n`——既覆盖全册，不同次测试又不会
     * 永远考同一批字。只取有拼音的字（没拼音的问不出读音题）。
     */
    fun sampleBook(bookId: String, n: Int, rand: () -> Double): List<String> {
        val pool = Repo.bookChars(bookId).filter { ch ->
            val m = Repo.meta(ch)
            m != null && m.py.length > 1
        }
        if (pool.isEmpty()) return emptyList()
        val count = minOf(n, pool.size)
        val stride = pool.size.toDouble() / count
        val start = (rand() * stride).toInt()
        val out = ArrayList<String>()
        val used = HashSet<String>()
        for (i in 0 until count) {
            var idx = ((start + i * stride).toInt()) % pool.size
            // 步长取整后可能撞到同一个下标，顺延到下一个没用过的字
            var guard = 0
            while (pool[idx] in used && guard < pool.size) {
                idx = (idx + 1) % pool.size
                guard++
            }
            used.add(pool[idx])
            out.add(pool[idx])
        }
        return out
    }

    /** 这个词的读音干扰项：同一册里别的字的拼音 */
    private fun pinyinOptions(ch: String, bookId: String, rand: () -> Double): List<Quiz.Option>? {
        val reading = Repo.readingFor(ch, "") ?: return null
        val banned = Repo.readingsOf(ch).toHashSet()
        val seen = HashSet<String>()
        seen.add(reading)
        val opts = ArrayList<Quiz.Option>()
        opts.add(Quiz.Option(reading, reading))
        // 干扰项从本册取：同册的字孩子都可能见过，才谈得上「分不清」
        val pool = Quiz.shuffle(Repo.bookChars(bookId).filter { it != ch }, rand)
        for (c in pool) {
            if (opts.size >= 4) break
            val p = Repo.meta(c)?.py ?: continue
            if (p.isEmpty() || p in seen || p in banned) continue
            seen.add(p)
            opts.add(Quiz.Option(p, p))
        }
        if (opts.size < 4) return null
        return Quiz.shuffle(opts, rand)
    }

    /**
     * 生成整套题。
     *
     * 一次全部生成，页面按册边界决定要不要提前停——这样「什么时候停」的
     * 判断逻辑是纯函数，能在单元测试里测，不用跑界面。
     */
    fun buildTest(seed: Int = (System.currentTimeMillis() and 0xFFFFFFFFL).toInt(), perBook: Int = PER_BOOK): Test {
        val rand = Quiz.mulberry32(seed)
        val groups = ArrayList<Group>()
        var cursor = 0
        for (b in Repo.books) {
            val picked = sampleBook(b.id, perBook, rand)
            val questions = ArrayList<Quiz.Question>()
            for (ch in picked) {
                val options = pinyinOptions(ch, b.id, rand) ?: continue
                val answer = Repo.readingFor(ch, "") ?: continue
                questions.add(
                    Quiz.Question(
                        type = "vocab",
                        ch = ch,
                        lesson = null,
                        title = "这个字读什么？",
                        prompt = ch,
                        promptKind = "char",
                        sub = "会读就选对，不会就随便选",
                        options = options,
                        answer = answer,
                        explain = "「$ch」读 $answer。",
                        index = cursor + questions.size,
                        total = 0
                    )
                )
            }
            if (questions.isEmpty()) continue
            groups.add(Group(b.id, b.name, Repo.bookChars(b.id).size, cursor, questions))
            cursor += questions.size
        }
        // total 要等全部生成完才知道，Builder 式的二次赋值
        val total = cursor
        val fixed = groups.map { g ->
            Group(g.book, g.name, g.bookTotal, g.start, g.questions.map { q ->
                Quiz.Question(q.type, q.ch, q.lesson, q.title, q.prompt, q.promptKind,
                    q.sub, q.options, q.answer, q.explain, q.index, total)
            })
        }
        return Test(fixed, total)
    }

    /**
     * 根据已答的题算识字量。
     *
     * @param answers 按答题顺序，`true` 表示答对
     */
    fun estimate(test: Test, answers: List<Boolean>): Estimate {
        val groups = ArrayList<GroupScore>()
        var size = 0
        var stopped = false
        var stopBook = ""
        var level = ""
        for (g in test.groups) {
            // 已经停过就不再「问」后面的册次。哪怕调用方把全部答案都传进来，
            // 那些题在真实流程里也没被问过，算进去会让 answered 虚高。
            val asked = if (stopped) 0 else minOf(g.questions.size, answers.size - g.start).coerceAtLeast(0)
            var correct = 0
            for (k in 0 until asked) {
                if (answers[g.start + k]) correct++
            }
            val rate = if (asked > 0) correct.toDouble() / asked else 0.0
            // 一旦停过，后面的册次一律不计——那是还没学到的部分，
            // 按更低的比例折算只会把估算压低成一个没有意义的数
            val counted = asked > 0
            val contribution = if (counted) Math.round(g.bookTotal * rate).toInt() else 0
            if (counted) {
                size += contribution
                if (rate >= STOP_RATE) level = g.book
            }
            groups.add(GroupScore(g.book, g.name, asked, correct, rate, counted, contribution))
            // 问满一册且没过线就停
            if (!stopped && asked >= g.questions.size && rate < STOP_RATE) {
                stopped = true
                stopBook = g.book
            }
        }
        // 上界是全库去重后的字数：各册字数相加是 2600，但有些字跨册重复出现，
        // 去重后只有 2596。不封顶的话全对会算出 2600，比字库还大。
        val libraryTotal = Repo.allChars.size
        if (size > libraryTotal) size = libraryTotal
        // 「问过几题」= 各册实际问到的题数之和
        val answered = groups.sumOf { it.asked }
        return Estimate(
            size = size,
            groups = groups,
            level = level,
            stopBook = stopBook,
            answered = answered,
            done = answered >= test.total || stopped
        )
    }

    /**
     * 「约 700 字」这种表述比「712 字」诚实：抽 5 个字的误差就在这个量级。
     * 不足 100 的字数直接报整数，因为那时「约 0 字」很奇怪。
     */
    fun sizeLabel(size: Int): String {
        val n = maxOf(0, size)
        if (n < 100) return n.toString()
        return "约 ${Math.round(n / 100.0).toInt() * 100}"
    }

    /**
     * 一句评价。分档按《义务教育语文课程标准》的量级：
     * 一二年级认识 1600 字左右，三四年级 2500 字左右。
     */
    fun verdict(size: Int): String {
        val n = maxOf(0, size)
        return when {
            n < 100 -> "刚开始认字，慢慢来。"
            n < 400 -> "一年级上下的水平，继续积累。"
            n < 900 -> "一年级末到二年级的水平，很不错。"
            n < 1600 -> "接近二年级末的水平，认字量已经不小了。"
            n < 2500 -> "到了三四年级的量级，可以多读整本书了。"
            else -> "认字量很大，可以试着读章节书了。"
        }
    }
}
