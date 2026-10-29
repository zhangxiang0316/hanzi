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

    /** 全部汉字（按构建时的顺序，用于组词 / 干扰项取样） */
    var allChars: List<String> = emptyList()
        private set

    val books: List<Book> get() = bookList

    fun ensureLoaded(context: Context) {
        if (loaded) return
        synchronized(this) {
            if (loaded) return
            parse(
                readAsset(context, "data/catalog.json"),
                readAsset(context, "data/meta.json"),
                readAsset(context, "data/strokes.json")
            )
        }
    }

    /** 供测试直接注入 JSON 文本，不依赖 Android Context */
    fun loadFromStrings(catalogJson: String, metaJson: String, strokesJson: String) {
        synchronized(this) {
            if (loaded) return
            parse(catalogJson, metaJson, strokesJson)
        }
    }

    private fun parse(catalogJson: String, metaJson: String, strokesJson: String) {
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

    fun isWriteChar(ch: String): Boolean = !metaMap[ch]?.writeLesson.isNullOrEmpty()

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
