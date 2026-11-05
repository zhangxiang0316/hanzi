package com.xiaoxiao.hanzi.ui.pages

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Words
import com.xiaoxiao.hanzi.logic.WordRow
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.EmptyState
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.Screen

/**
 * 词语表浏览。
 *
 * 词语此前只在「看拼音选词语」的题目里出现——答对答错，但家长想帮孩子
 * 把这一学期的词过一遍时，没有地方能从头翻。
 *
 * ## 复用 `logic/Words.kt`，不另写一套遍历
 *
 * 那个模块已经处理了一件容易漏的事：**一年级课本没有词语表**，它用每课
 * 生字的第一组词补上（`fromTextbook = false`）。自己另写一份遍历必然把这个
 * 兜底漏掉，结果就是一年级点进词语表看到一片空白——而一年级正是这个 App
 * 最大的用户群。
 *
 * ## 两种去重口径
 *
 * 分组浏览按**册**去重（复用 `bookWords`）：「旅行」在 1b 和 3a 各出现一次
 * 是教材事实，两册都该显示。但搜索和总数统计的是「有多少个词」，
 * 必须**全局**去重，否则搜「行」会列出两条「旅行」。
 *
 * ## 一册里的词可能混合
 *
 * 2a 有 320 个词，其中 92 个是派生词——有的课文有词语表、有的没有。
 * 所以提示语要报出数量，不能笼统说「这一册没有词语表」。
 */
@Composable
fun WordsPage(app: AppState) {
    val p = LocalPalette.current
    app.revision

    val bookId = app.currentBook
    var query by remember { mutableStateOf("") }

    // 分组：每册一份（册内去重），派生词数量单独数出来
    val groups = remember(app.revision) {
        Repo.books.mapNotNull { b ->
            val list = Words.bookWords(b.id)
            if (list.isEmpty()) return@mapNotNull null
            WordGroup(
                bookId = b.id,
                name = b.name,
                words = list.map { w ->
                    WordLine(
                        word = w.word,
                        lessonNo = Repo.lesson(w.lesson)?.no ?: 0,
                        derived = !w.fromTextbook,
                        learned = Words.learned(w.word) { app.progress.hasLearned(it) }
                    )
                }
            )
        }
    }
    val unique = remember(app.revision) { Words.uniqueWords() }
    val learnedWords = remember(app.revision) {
        unique.count { Words.learned(it.word) { c -> app.progress.hasLearned(c) } }
    }

    val q = query.trim()
    val results = if (q.isEmpty()) emptyList() else Words.wordsWithChar(q)

    LazyColumn(
        Modifier
            .fillMaxSize()
            .testTag("words-list")
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        item {
            // 标题交给顶栏，页面里只在首行交代一句「这页是干什么的」
            Spacer(Modifier.height(8.dp))
            Text(
                "课本词语表，加上一年级用生字组词补的部分",
                fontSize = 12.sp,
                color = p.ink3
            )
            Spacer(Modifier.height(12.dp))
            SearchBox(query) { query = it }
            Spacer(Modifier.height(4.dp))
        }

        if (q.isNotEmpty()) {
            // 搜索结果：全局去重，一条词一行，标注它在哪几册出现过
            item {
                Text(
                    if (results.size > 120) "找到 ${results.size} 个词，先显示前 120 个"
                    else "找到 ${results.size} 个词",
                    modifier = Modifier.padding(top = 14.dp, bottom = 6.dp),
                    fontSize = 11.sp,
                    color = p.ink3
                )
            }
            if (results.isEmpty()) {
                item { EmptyState("🔍", "没找到含「$q」的词语", "换个字试试，比如「行」") }
            } else {
                items(results.take(120), key = { it.word }) { w ->
                    SearchRow(w) { ch ->
                        if (Repo.hasChar(ch)) app.nav.push(Screen.Detail(ch, Repo.meta(ch)?.lesson))
                    }
                }
            }
        } else {
            item {
                // 汇总：分母是全局去重后的词数，不是按册拼接的条目数
                Row(
                    Modifier.padding(top = 16.dp, bottom = 2.dp),
                    verticalAlignment = Alignment.Bottom
                ) {
                    Text(
                        "$learnedWords",
                        fontSize = 26.sp,
                        fontWeight = FontWeight.Bold,
                        color = p.jade
                    )
                    Spacer(Modifier.width(4.dp))
                    Text("/ ${unique.size} 个词", fontSize = 13.sp, color = p.ink3)
                }
                Text(
                    "一个词里的字都学过，这个词才算学会",
                    fontSize = 11.sp,
                    color = p.ink3
                )
                Spacer(Modifier.height(6.dp))
            }

            if (groups.isEmpty()) {
                item { EmptyState("📖", "还没有任何词语") }
            }

            groups.forEach { g ->
                item(key = "head-${g.bookId}") {
                    GroupHead(g, current = g.bookId == bookId)
                }
                item(key = "note-${g.bookId}") {
                    // 派生词要说明白：家长会以为课本上就是有这个词
                    if (g.derivedCount > 0) {
                        Text(
                            if (g.derivedCount == g.words.size) {
                                "这一册课本没有词语表，下面是每课生字的组词"
                            } else {
                                "其中 ${g.derivedCount} 个是生字组词（课本这几课没有词语表）"
                            },
                            modifier = Modifier.padding(bottom = 6.dp),
                            fontSize = 10.sp,
                            lineHeight = 15.sp,
                            color = p.ink3
                        )
                    }
                }
                // 整册的词语包在一张卡里，行间用缩进 16 的细线分隔——
                // 与 iOS 一致。之前这里是完全平铺的行，没有任何容器，
                // 一屏几十个词连成一片，家长看不出「这一册到哪儿结束」。
                item(key = "card-${g.bookId}") {
                    Surface(
                        Modifier
                            .fillMaxWidth()
                            .padding(bottom = 14.dp),
                        shape = RoundedCornerShape(Dimens.radiusCard.dp),
                        color = p.card,
                        border = BorderStroke(1.dp, p.line)
                    ) {
                        Column {
                            g.words.forEachIndexed { i, line ->
                                WordLineRow(line) { ch ->
                                    if (Repo.hasChar(ch)) {
                                        app.nav.push(Screen.Detail(ch, Repo.meta(ch)?.lesson))
                                    }
                                }
                                if (i < g.words.size - 1) {
                                    Box(
                                        Modifier
                                            .fillMaxWidth()
                                            .padding(start = 16.dp)
                                            .height(1.dp)
                                            .background(p.line)
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        item { Spacer(Modifier.height(24.dp)) }
    }
}

private class WordGroup(val bookId: String, val name: String, val words: List<WordLine>) {
    val derivedCount: Int = words.count { it.derived }
}

private class WordLine(
    val word: String,
    val lessonNo: Int,
    val derived: Boolean,
    val learned: Boolean
)

@Composable
private fun SearchBox(value: String, onChange: (String) -> Unit) {
    val p = LocalPalette.current
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        modifier = Modifier
            .fillMaxWidth()
            .testTag("words-search"),
        singleLine = true,
        placeholder = { Text("搜词语，或搜一个字（如「行」）", fontSize = 13.sp, color = p.ink3) },
        textStyle = androidx.compose.ui.text.TextStyle(fontSize = 14.sp, color = p.ink1),
        shape = RoundedCornerShape(999.dp),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = p.card,
            unfocusedContainerColor = p.card,
            focusedBorderColor = p.jade,
            unfocusedBorderColor = p.line
        )
    )
}

@Composable
private fun GroupHead(g: WordGroup, current: Boolean) {
    val p = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = 18.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            g.name,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (current) p.jadeDeep else p.ink2,
            modifier = Modifier.weight(1f)
        )
        Text(
            "${g.words.count { it.learned }}/${g.words.size}",
            fontSize = 11.sp,
            color = p.ink3
        )
    }
}

/**
 * 一行词。
 *
 * 每个字单独可点，但视觉上要像一个词——间距压紧、字号放大。
 * 字库外的字（派生词里 19 个词用到了，比如「弓弩」的「弩」）没有详情页，
 * 所以要置灰且不可点：看起来能点却点不动，比置灰更让人困惑。
 */
@Composable
private fun WordLineRow(line: WordLine, onChar: (String) -> Unit) {
    val p = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .testTag("word-row-${line.word}")
            .padding(horizontal = 16.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
            line.word.forEachIndexed { idx, c ->
                WordChar(
                    ch = c.toString(),
                    tag = "word-char-${line.word}-$idx",
                    onChar = onChar
                )
            }
        }
        if (line.derived) {
            Box(
                Modifier
                    .clip(RoundedCornerShape(4.dp))
                    .background(p.lineSoft)
                    .padding(horizontal = 5.dp, vertical = 2.dp)
            ) {
                Text("生字组词", fontSize = 9.sp, color = p.ink3)
            }
            Spacer(Modifier.width(6.dp))
        }
        Text("第 ${line.lessonNo} 课", fontSize = 10.sp, color = p.ink3)
        if (line.learned) {
            Spacer(Modifier.width(6.dp))
            Box(
                Modifier
                    .size(6.dp)
                    .clip(CircleShape)
                    .background(p.jade)
            )
        }
    }
}

/**
 * 词里的一个字。
 *
 * 点击区高度必须 >= 44dp（和微信版一致：那边是 `min-height: 88rpx`）——
 * 20sp 的字本身只有 24dp 高，直接让 Text 可点的话手指点不准。
 *
 * 宽度刻意**不**拉到 44dp：词里的字必须挨着看才像一个词。
 * 相邻的字连成一片，两个字的词整体仍有 70dp+ 的点击区，
 * 而视觉上仍然是紧凑的一个词。
 */
@Composable
private fun WordChar(ch: String, tag: String, onChar: (String) -> Unit) {
    val p = LocalPalette.current
    val tappable = Repo.hasChar(ch)
    Box(
        Modifier
            .testTag(tag)
            .clip(RoundedCornerShape(4.dp))
            .then(if (tappable) Modifier.clickable { onChar(ch) } else Modifier)
            .defaultMinSize(minWidth = 36.dp, minHeight = 44.dp)
            .padding(horizontal = 2.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            ch,
            fontSize = 20.sp,
            lineHeight = 24.sp,
            color = if (tappable) p.ink1 else p.ink3.copy(alpha = 0.5f)
        )
    }
}

/** 搜索结果的一行：出处是「一年级上册 / 三年级下册」这种跨册写法 */
@Composable
private fun SearchRow(w: WordRow, onChar: (String) -> Unit) {
    val p = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
            w.word.forEachIndexed { idx, c ->
                WordChar(
                    ch = c.toString(),
                    tag = "search-char-${w.word}-$idx",
                    onChar = onChar
                )
            }
        }
        Text(
            w.books.joinToString(" / ") { id -> Repo.book(id)?.name ?: id },
            modifier = Modifier.width(112.dp),
            fontSize = 10.sp,
            color = p.ink3,
            textAlign = TextAlign.End
        )
    }
}
