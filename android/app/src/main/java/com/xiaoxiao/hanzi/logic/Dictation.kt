package com.xiaoxiao.hanzi.logic

import com.xiaoxiao.hanzi.data.Repo

/**
 * 听写难度。
 *
 * 与 iOS `DictationLevel`、小程序 `utils/dictation.js` 三端语义必须一致。
 *
 * 分级：
 * - [EASY]   念词 + 显示底字（等于描红，只是入口不同，给最没把握的孩子）
 * - [NORMAL] 念词，不显示底字（默认）
 * - [HARD]   只念字，不显示底字，也不念组词
 *
 * 之所以保留 EASY 档：听写最难的是「根本想不起来这个字长什么样」。
 * 一上来就完全不给提示，一部分孩子会直接卡死在第一题，一题都写不出，
 * 从此不愿意再点这个入口。给一个可以从描红过渡的档位，
 * 比逼他们直接跳到听写更可能坚持下去。
 */
enum class DictationLevel(val key: String, val title: String, val desc: String) {
    EASY("easy", "看着写", "念出词语，田字格里还有淡色的字"),
    NORMAL("normal", "听词写", "念出词语，不显示淡色的字"),
    HARD("hard", "只听字", "只念这一个字，不提示词语");

    /** 是否显示底字 */
    val showsGhost: Boolean get() = this == EASY

    /** 朗读什么 */
    fun promptText(ch: String, word: String?): String = when (this) {
        // 有词念词，没词就念字——「天空」比单念「天」更容易想起是哪个字
        EASY, NORMAL -> word ?: ch
        HARD -> ch
    }

    companion object {
        fun fromKey(key: String): DictationLevel =
            entries.firstOrNull { it.key == key } ?: NORMAL
    }
}

/** 一个听写项：写哪个字、念什么词 */
data class DictationItem(val ch: String, val word: String?)

/**
 * 选听写的字。
 *
 * 优先级：本册「会写」的字 → 本册全部字 → 所有有笔顺数据的字。
 * 「会写」这个区分（`isWriteChar`）是教材自带的，之前三端都定义了却没用；
 * 听写场景下它正好合适——只认不写的字（髓、嚼、蟹）要求孩子默写出来没有道理。
 *
 * 顺序固定按教材顺序，而不是随机：听写是「今天学完这几课，默一遍」的场景，
 * 顺序对得上课文才有意义，随机打乱会让家长没法对照课本。
 */
object DictationSource {

    fun pick(book: String, level: DictationLevel, limit: Int): List<DictationItem> {
        var pool = Repo.bookChars(book).filter { Repo.isWriteChar(it) }
        if (pool.size < 4) {
            // 本册会写的字太少，退回本册全部字
            pool = Repo.bookChars(book)
        }
        if (pool.isEmpty()) pool = Repo.allCharsWithStrokes()

        return pool.take(maxOf(1, limit)).map { ch ->
            val meta = Repo.meta(ch)
            // EASY/NORMAL 用第一个组词；HARD 不念词
            val word: String? = if (level == DictationLevel.HARD) null else meta?.words?.firstOrNull()?.word
            DictationItem(ch, word)
        }
    }
}
