package com.xiaoxiao.hanzi.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * 教材目录 + 字库 + 笔顺的查询入口。
 *
 * 数据来自 scripts/export-android.mjs 导出的 assets JSON，与小程序同源。
 * catalog / meta 约 540KB，首次访问时解析常驻；笔顺 2.4MB 合并成单文件，
 * 一次性解析成「字 -> base64」，单字解码成路径是懒加载 + 缓存的。
 */
object Repo {

    @Volatile
    private var loaded = false

    private var bookList: List<Book> = emptyList()
    private var lessonMap: Map<String, Lesson> = emptyMap()
    private var metaMap: Map<String, CharMeta> = emptyMap()
    private var rawStrokes: Map<String, String> = emptyMap()

    private val bookMap = HashMap<String, Book>()
    private val decodeCache = HashMap<String, StrokeCodec.CharStrokes>()
    private val bookCharsCache = HashMap<String, List<String>>()

    /** 形近字表（自动生成，见 scripts/build-similar.mjs） */
    private var similarMap: HashMap<String, List<String>> = HashMap()

    /** 全部汉字（按构建时的顺序，用于组词 / 干扰项取样） */
    var allChars: List<String> = emptyList()
        private set

    val books: List<Book> get() = bookList

    fun ensureLoaded(context: Context) {
        if (loaded) return
        synchronized(this) {
            if (loaded) return
            // 形近字表是可选资源：缺了只是没有这个练习入口，
            // 其余功能不受影响
            val similar = runCatching { readAsset(context, "data/similar.json") }.getOrNull()
            parse(
                readAsset(context, "data/catalog.json"),
                readAsset(context, "data/meta.json"),
                readAsset(context, "data/strokes.json"),
                similar
            )
        }
    }

    /** 供测试直接注入 JSON 文本，不依赖 Android Context */
    fun loadFromStrings(
        catalogJson: String,
        metaJson: String,
        strokesJson: String,
        similarJson: String? = null
    ) {
        synchronized(this) {
            if (loaded) {
                // 形近字表是后来才加的可选资源。Repo 是单例，如果第一个测试
                // 用三参数版本加载过，后面的调用会被 `loaded` 守卫挡住，
                // similarMap 永远是空的——单独跑这个测试类时通过，
                // 整套跑就全挂。这里补一次，且只在还没加载时补。
                if (similarJson != null && similarMap.isEmpty()) {
                    similarMap = parseSimilar(similarJson)
                }
                return
            }
            parse(catalogJson, metaJson, strokesJson, similarJson)
        }
    }

    private fun parseSimilar(json: String): HashMap<String, List<String>> {
        val obj = JSONObject(json)
        val mm = HashMap<String, List<String>>(obj.length())
        val keys = obj.keys()
        while (keys.hasNext()) {
            val ch = keys.next()
            mm[ch] = obj.getJSONArray(ch).toStringList()
        }
        return mm
    }

    private fun parse(
        catalogJson: String,
        metaJson: String,
        strokesJson: String,
        similarJson: String? = null
    ) {
        val catalog = JSONObject(catalogJson)

        val bookArr = catalog.getJSONArray("books")
        val bl = ArrayList<Book>(bookArr.length())
        for (i in 0 until bookArr.length()) {
            val b = bookArr.getJSONObject(i)
            val unitArr = b.getJSONArray("units")
            val units = ArrayList<Unit>(unitArr.length())
            for (j in 0 until unitArr.length()) {
                val u = unitArr.getJSONObject(j)
                units.add(
                    Unit(
                        no = u.getInt("no"),
                        title = u.getString("title"),
                        theme = u.optString("theme"),
                        lessons = u.getJSONArray("lessons").toStringList()
                    )
                )
            }
            val st = b.getJSONObject("stat")
            val book = Book(
                id = b.getString("id"),
                name = b.getString("name"),
                short = b.getString("short"),
                grade = b.getInt("grade"),
                term = b.getInt("term"),
                units = units,
                lessons = b.getJSONArray("lessons").toStringList(),
                stat = BookStat(
                    chars = st.optInt("chars"),
                    write = st.optInt("write"),
                    lessons = st.optInt("lessons"),
                    units = st.optInt("units")
                )
            )
            bl.add(book)
            bookMap[book.id] = book
        }
        bookList = bl

        val lessonObj = catalog.getJSONObject("lessons")
        val lm = HashMap<String, Lesson>(lessonObj.length())
        val keys = lessonObj.keys()
        while (keys.hasNext()) {
            val id = keys.next()
            val l = lessonObj.getJSONObject(id)
            lm[id] = Lesson(
                id = id,
                book = l.optString("book"),
                unit = l.optInt("unit"),
                no = l.optInt("no"),
                title = l.optString("title"),
                kind = l.optString("kind"),
                page = l.optInt("page"),
                chars = l.getJSONArray("chars").toStringList(),
                write = l.optJSONArray("write")?.toStringList() ?: emptyList(),
                words = l.optJSONArray("words")?.toStringList() ?: emptyList()
            )
        }
        lessonMap = lm

        val metaObj = JSONObject(metaJson)
        val mm = HashMap<String, CharMeta>(metaObj.length())
        val charOrder = ArrayList<String>(metaObj.length())
        val mkeys = metaObj.keys()
        while (mkeys.hasNext()) {
            val ch = mkeys.next()
            val m = metaObj.getJSONObject(ch)
            val wordArr = m.optJSONArray("w")
            val words = ArrayList<Word>(wordArr?.length() ?: 0)
            if (wordArr != null) {
                for (i in 0 until wordArr.length()) {
                    val w = wordArr.getJSONObject(i)
                    words.add(Word(w.getString("w"), w.optString("p")))
                }
            }
            val rdArr = m.optJSONArray("rd")
            val readings = if (rdArr == null) null else {
                val list = ArrayList<Reading>(rdArr.length())
                for (i in 0 until rdArr.length()) {
                    val r = rdArr.getJSONObject(i)
                    list.add(Reading(r.getString("p"), r.optString("l")))
                }
                list
            }
            mm[ch] = CharMeta(
                ch = ch,
                py = m.getString("py"),
                words = words,
                radical = m.optString("r"),
                strokes = m.optInt("s"),
                book = m.optString("b"),
                lesson = m.optString("l"),
                writeLesson = m.optString("x"),
                readings = readings
            )
            charOrder.add(ch)
        }
        metaMap = mm
        allChars = charOrder

        val strokesObj = JSONObject(strokesJson)
        val sm = HashMap<String, String>(strokesObj.length())
        val sk = strokesObj.keys()
        while (sk.hasNext()) {
            val ch = sk.next()
            sm[ch] = strokesObj.getString(ch)
        }
        rawStrokes = sm

        if (similarJson != null) similarMap = parseSimilar(similarJson)
        loaded = true
    }

    private fun readAsset(context: Context, path: String): String =
        context.assets.open(path).bufferedReader(Charsets.UTF_8).use { it.readText() }

    // ---------- 查询 ----------

    fun book(id: String): Book? = bookMap[id]

    fun defaultBook(): String = bookList.firstOrNull()?.id ?: "1a"

    fun lesson(id: String?): Lesson? = if (id == null) null else lessonMap[id]

    fun meta(ch: String): CharMeta? = metaMap[ch]

    fun hasChar(ch: String): Boolean = metaMap.containsKey(ch)

    fun lessonTitle(id: String): String = lessonMap[id]?.title ?: ""

    fun lessonLabel(id: String): String {
        val l = lessonMap[id] ?: return ""
        val b = bookMap[l.book]
        return (b?.let { it.short + " · " } ?: "") + "第" + l.no + "课 " + l.title
    }

    /** 按「册 -> 单元 -> 课 -> 生字」的教材顺序返回某册全部生字（去重） */
    fun bookChars(bookId: String): List<String> {
        bookCharsCache[bookId]?.let { return it }
        val book = bookMap[bookId] ?: return emptyList()
        val seen = HashSet<String>()
        val out = ArrayList<String>()
        for (lid in book.lessons) {
            val l = lessonMap[lid] ?: continue
            for (ch in l.chars) if (seen.add(ch)) out.add(ch)
        }
        bookCharsCache[bookId] = out
        return out
    }

    /**
     * 只出现在写字表、没被任何课时识字表收录的字（共 5 个：匀/剩/训/忧/毒）。
     *
     * 它们不属于任何一册的识字表（`bookChars` 里没有），但要能认、能描红，
     * 所以要进全字表。按（课时、字）稳定排序，与 iOS `writeOnlyChars` 一致。
     */
    val writeOnlyChars: List<String> by lazy {
        metaMap.entries
            .mapNotNull { (ch, m) ->
                val l = m.lesson
                val lesson = if (l.isEmpty()) null else lessonMap[l]
                if (lesson != null && ch !in lesson.chars) l to ch else null
            }
            .sortedWith(compareBy({ it.first }, { it.second }))
            .map { it.second }
    }

    fun lessonChars(lessonId: String?): List<String> =
        if (lessonId == null) emptyList() else (lessonMap[lessonId]?.chars ?: emptyList())

    /** 取本课语境下的读音；多音字按教材标注 */
    fun readingFor(ch: String, lessonId: String?): String {
        val m = metaMap[ch] ?: return ""
        val rd = m.readings
        if (rd != null && lessonId != null) {
            for (r in rd) if (r.lesson == lessonId) return r.pinyin
        }
        return m.py
    }

    /** 一个字所有可能读音（用于排除同音干扰项） */
    fun readingsOf(ch: String): List<String> {
        val m = metaMap[ch] ?: return emptyList()
        val rd = m.readings ?: return listOf(m.py)
        val out = LinkedHashSet<String>()
        rd.forEach { out.add(it.pinyin) }
        return out.toList()
    }

    fun readingDetails(ch: String): List<Reading> {
        val m = metaMap[ch] ?: return emptyList()
        return m.readings ?: listOf(Reading(m.py, ""))
    }

    /**
     * 这个字在本项目范围内是否要求会写。
     *
     * 不能只看 `writeLesson` 非空：有 457 个字的写字课在五、六年级（如「棋」的
     * x 是 6a-k6），而本项目只做一到四年级。这些字在本项目里是「只认不写」，
     * 之前三端都误判成会写，导致听写会要求孩子默写「鸦」「氏」「孙」这类字。
     *
     * 修正后与本项目课时的 `write` 数组并集严格一致（都是 1798 个），
     * 这个交叉验证写进了测试。
     */
    fun isWriteChar(ch: String): Boolean {
        val x = metaMap[ch]?.writeLesson
        if (x.isNullOrEmpty()) return false
        return bookMap[x.substringBefore('-')] != null
    }

    // MARK: - 多音字

    /** 是否多音字 */
    fun isPolyphone(ch: String): Boolean = (metaMap[ch]?.readings?.size ?: 0) > 1

    /** 某册里的多音字（保持教材顺序） */
    fun polyphones(book: String): List<String> = bookChars(book).filter { isPolyphone(it) }

    /** 全部多音字 */
    fun allPolyphones(): List<String> = allChars.filter { isPolyphone(it) }

    // MARK: - 同音字

    /**
     * 同音字：读音完全相同（含声调）的一组字。
     *
     * 这份关系不用新数据——`CharMeta.py` 里就有完整拼音，按它分组即可。
     * 全库 588 组、2163 个字；一到四年级就有 383 组。
     *
     * 为什么值得单独做：同音字是听写最主要的错因。「地弟第递」「坐作做座」
     * 读音一样、字形不同，孩子记住音不等于会写。多音字练「一个字读哪个音」，
     * 同音字练「这个音写哪个字」——是同一个问题的两个方向。
     */
    fun homophones(ch: String): List<String> {
        val m = metaMap[ch] ?: return emptyList()
        if (m.py.isEmpty()) return emptyList()
        // 按 Unicode 码点排序，不依赖 allChars 的顺序：
        // 三端的数据来源顺序不同，不显式排序的话笔画数相同时干扰项的
        // 并列顺序会不一致——同一个 seed 会出不同的题。
        // 这条是跨端黄金值测试抓出来的。
        return allChars.filter { it != ch && metaMap[it]?.py == m.py }
            .sortedBy { it.codePointAt(0) }
    }

    /** 这个字有没有同音字（没有的话同音字题型无从出题） */
    fun hasHomophones(ch: String): Boolean = homophones(ch).isNotEmpty()

    /**
     * 某一册里的同音字组合（每组 ≥2 个字，组内按教材顺序）。
     *
     * 只用本册的字组队：跨册组队会让二年级孩子遇到三年级的字，
     * 那就不是在练同音字，是在考认字量。
     */
    fun homophoneGroups(book: String): List<Pair<String, List<String>>> {
        val order = ArrayList<String>()
        val byPy = HashMap<String, MutableList<String>>()
        for (ch in bookChars(book)) {
            val py = metaMap[ch]?.py ?: continue
            if (py.isEmpty()) continue
            if (byPy[py] == null) {
                byPy[py] = ArrayList()
                order.add(py)
            }
            byPy[py]!!.add(ch)
        }
        val out = ArrayList<Pair<String, List<String>>>()
        for (py in order) {
            val list = byPy[py]!!
            if (list.size >= 2) out.add(py to list)
        }
        // 组大的排前面：错得更多的先练；同规模按拼音稳定排序
        out.sortWith(compareByDescending<Pair<String, List<String>>> { it.second.size }
            .thenBy { it.first })
        return out
    }

    /** 某册里所有参与同音字组的字（按教材顺序去重） */
    fun homophoneChars(book: String): List<String> {
        val set = HashSet<String>()
        homophoneGroups(book).forEach { set.addAll(it.second) }
        return bookChars(book).filter { set.contains(it) }
    }

    /**
     * 同音字组里「最适合当干扰项」的字。
     *
     * 优先同册、笔画数接近的——「地」和「递」都是 `dì`，但一个 6 画一个 10 画，
     * 一眼就能排除，当干扰项没意义。笔画差 3 以内才有迷惑性。
     */
    fun homophoneDistractors(ch: String, book: String?, count: Int): List<String> {
        val m = metaMap[ch] ?: return emptyList()
        val bookId = book ?: m.book
        val inBook = bookChars(bookId).toHashSet()
        val pool = homophones(ch).map { it to (metaMap[it]?.strokes ?: 0) }
        // 三级排序：同册优先 → 笔画接近 → 码点。
        // 第三级不能省：笔画差相同的字会有并列，没有确定的 tiebreak
        // 三端就会各排各的，同一个 seed 出不同的题。
        val sorted = pool.sortedWith(compareBy<Pair<String, Int>> {
            if (inBook.contains(it.first)) 0 else 1
        }.thenBy { Math.abs(it.second - m.strokes) }
            .thenBy { it.first.codePointAt(0) })
        return sorted.take(count).map { it.first }
    }

    // MARK: - 形近字

    /**
     * 形近字是低年级另一个主要混淆来源（未/末、天/夫、日/目、人/入），
     * 和同音字正好互补：一个是「音一样写哪个」，一个是「长得像别混」。
     *
     * 表不是抄的，是用笔顺数据算出来的——见 `scripts/build-similar.mjs`。
     * 算法要两条指标同时满足才算形近：笔画几何距离（中线重采样后贪心匹配）
     * 和像素相关系数。单独用任何一条都不行：只用笔画会放进「人→久九儿」，
     * 只用像素则分不开「天/夫」和随机字对。
     */

    /** 这个字的形近字（生成时按距离升序，已按码点做最终 tiebreak） */
    fun similarChars(ch: String): List<String> = similarMap[ch] ?: emptyList()

    /** 这个字有没有形近字 */
    fun hasSimilar(ch: String): Boolean = similarChars(ch).isNotEmpty()

    /**
     * 形近字题的干扰项。
     *
     * 优先取**本册**的形近字：跨册会把三年级的字塞给一年级孩子，
     * 那就不是在练辨析，是在考认字量。排序三级——同册优先 → 原表顺序
     * （距离近的在前）→ 码点。第三级不能省，否则三端并列顺序不一致，
     * 同一个 seed 会出不同的题。
     */
    fun similarDistractors(ch: String, book: String?, count: Int): List<String> {
        val m = metaMap[ch] ?: return emptyList()
        val bookId = book ?: m.book
        val inBook = bookChars(bookId).toHashSet()
        val list = similarChars(ch)
        val order = HashMap<String, Int>(list.size)
        list.forEachIndexed { i, c -> order[c] = i }
        return list.sortedWith(
            compareBy<String> { if (inBook.contains(it)) 0 else 1 }
                .thenBy { order[it] ?: 0 }
                .thenBy { it.codePointAt(0) }
        ).take(count)
    }

    /** 某一册里所有有形近字的字（按教材顺序） */
    fun bookSimilarChars(book: String): List<String> =
        bookChars(book).filter { hasSimilar(it) }

    /** 全部册次里所有有形近字的字 */
    fun allSimilarChars(): List<String> = allChars.filter { hasSimilar(it) }

    // MARK: - 部首

    /**
     * 部首查字法是二年级语文园地的正式内容，但 `CharMeta.radical` 一直只在
     * 解析文案里出现过，从没当成学习维度用过。237 个部首、全部 2596 个字都有。
     *
     * 注意：237 个部首里只有 144 个是字库里的生字（能画笔顺），
     * 另外 93 个是偏旁变形（亻 艹 扌 讠 纟 宀 攵）——它们不是独立汉字，
     * 没有笔顺数据。所以部首只以**文字**形式出现（当选项、当分组标签），
     * 不参与描红判分。
     */

    /** 这个字的部首 */
    fun radicalOf(ch: String): String = metaMap[ch]?.radical ?: ""

    /** 字库里所有部首（按使用频次从高到低） */
    fun allRadicals(): List<Triple<String, Int, Boolean>> {
        val count = HashMap<String, Int>()
        for (ch in allChars) {
            val r = metaMap[ch]?.radical ?: continue
            if (r.isEmpty()) continue
            count[r] = (count[r] ?: 0) + 1
        }
        return count.keys
            .map { Triple(it, count[it] ?: 0, metaMap[it] != null) }
            .sortedWith(compareByDescending<Triple<String, Int, Boolean>> { it.second }
                // 频次相同按码点，保证三端顺序一致
                .thenBy { it.first.codePointAt(0) })
    }

    /** 某一册里出现过的部首（按频次从高到低） */
    fun bookRadicals(book: String): List<Triple<String, Int, Boolean>> {
        val count = HashMap<String, Int>()
        for (ch in bookChars(book)) {
            val r = metaMap[ch]?.radical ?: continue
            if (r.isEmpty()) continue
            count[r] = (count[r] ?: 0) + 1
        }
        return count.keys
            .map { Triple(it, count[it] ?: 0, metaMap[it] != null) }
            .sortedWith(compareByDescending<Triple<String, Int, Boolean>> { it.second }
                .thenBy { it.first.codePointAt(0) })
    }

    /** 某一册里某个部首下的所有字（按教材顺序） */
    fun charsWithRadical(book: String, radical: String): List<String> =
        bookChars(book).filter { metaMap[it]?.radical == radical }

    /** 全部册次里某个部首下的所有字 */
    fun allCharsWithRadical(radical: String): List<String> =
        allChars.filter { metaMap[it]?.radical == radical }

    /**
     * 部首题的干扰项。
     *
     * 取本册里最常见的几个部首，但排除跟正确答案有**字形包含关系**的——
     * 「木」和「林」这种，孩子会争议「林」的部首是不是「木」，
     * 当干扰项是制造歧义而不是考知识。
     */
    fun radicalDistractors(radical: String, book: String?, count: Int): List<String> =
        bookRadicals(book ?: defaultBook())
            .map { it.first }
            .filter { it != radical && !it.contains(radical) && !radical.contains(it) }
            .take(count)

    /** 所有带笔顺数据的字（教材顺序优先，再补额外字） */
    fun allCharsWithStrokes(): List<String> {
        val seen = HashSet<String>()
        val out = ArrayList<String>()
        for (ch in allChars) {
            if (rawStrokes[ch] != null && seen.add(ch)) out.add(ch)
        }
        rawStrokes.keys.sorted().forEach { if (seen.add(it)) out.add(it) }
        return out
    }

    /**
     * 某个读音的用例词。
     *
     * 组词数据里每个词都带拼音，而拼音音节与汉字一一对应。所以只要把
     * 「本字在词中的位置」与「拼音里的音节位置」对上，就能确定这个词用的是哪个读音。
     *
     * 早先试过「拼音里任意位置出现该音节就算」——那样会把「地方」的 `dì`
     * 误配到别的读音上（同一个词里另一个字恰好同音时）。改成按位置对齐后，
     * 156 个多音字全部都能匹配到用例，且不会串音。
     *
     * 音节数与字数不一致的词（儿化、轻声合写等）直接跳过，宁可少几个例子也不出错。
     */
    fun wordsUsing(ch: String, reading: String): List<String> {
        val m = metaMap[ch] ?: return emptyList()
        val target = ch[0]
        val out = ArrayList<String>()
        for (w in m.words) {
            val idx = w.word.indexOf(target)
            if (idx < 0) continue
            val syl = w.pinyin.split(Regex("\\s+"))
            if (syl.size != w.word.length) continue
            if (syl[idx] == reading) out.add(w.word)
        }
        return out
    }

    /** 册次在教材里的先后序号（越小越早） */
    fun bookRank(id: String): Int {
        val i = bookList.indexOfFirst { it.id == id }
        return if (i >= 0) i else bookList.size
    }

    /**
     * 一个词「最难的字的册次」。用来给多音字例句排序：
     * 「数落」里「落」是 3 年级的字，一年级的孩子看不懂，
     * 优先选整词都在本册或更早的词。
     */
    fun wordRank(word: String): Int {
        var worst = 0
        for (c in word) {
            val r = metaMap[c.toString()]?.let { bookRank(it.book) } ?: bookList.size
            if (r > worst) worst = r
        }
        return worst
    }

    /** 多音字的读音 + 各自用例词（按「好懂」排序） */
    fun polyphoneCases(ch: String): List<Pair<Reading, List<String>>> =
        readingDetails(ch).map { r ->
            val ws = wordsUsing(ch, r.pinyin).sortedWith(
                compareBy({ wordRank(it) }, { it.length })
            )
            r to ws
        }

    fun nextInLesson(lessonId: String?, ch: String): String {
        val list = lessonChars(lessonId)
        val i = list.indexOf(ch)
        return if (i >= 0 && i < list.size - 1) list[i + 1] else ""
    }

    fun prevInLesson(lessonId: String?, ch: String): String {
        val list = lessonChars(lessonId)
        val i = list.indexOf(ch)
        return if (i > 0) list[i - 1] else ""
    }

    fun nextInBook(bookId: String, ch: String): String {
        val list = bookChars(bookId)
        val i = list.indexOf(ch)
        return if (i >= 0 && i < list.size - 1) list[i + 1] else ""
    }

    fun prevInBook(bookId: String, ch: String): String {
        val list = bookChars(bookId)
        val i = list.indexOf(ch)
        return if (i > 0) list[i - 1] else ""
    }

    /** 找到某字在教材中的首次出现课文 */
    fun lessonOfChar(ch: String): String = metaMap[ch]?.lesson ?: ""

    fun bookStat(bookId: String): BookStat =
        bookMap[bookId]?.stat ?: BookStat(0, 0, 0, 0)

    // ---------- 笔顺 ----------

    /** 取某字的笔顺（解码并缓存）；数据缺失返回 null */
    fun strokes(ch: String): StrokeCodec.CharStrokes? {
        decodeCache[ch]?.let { return it }
        val raw = rawStrokes[ch] ?: return null
        val decoded = StrokeCodec.decode(raw)
        synchronized(decodeCache) { decodeCache[ch] = decoded }
        return decoded
    }

    fun strokeCount(ch: String): Int = strokes(ch)?.count ?: 0
}

private fun JSONArray.toStringList(): List<String> {
    val out = ArrayList<String>(length())
    for (i in 0 until length()) out.add(getString(i))
    return out
}
