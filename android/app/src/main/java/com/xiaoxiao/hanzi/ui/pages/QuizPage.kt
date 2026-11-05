package com.xiaoxiao.hanzi.ui.pages

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Plan
import com.xiaoxiao.hanzi.logic.Quiz
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.BtnStyle
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.HanziButton
import com.xiaoxiao.hanzi.ui.HanziGlyph
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.Motion
import com.xiaoxiao.hanzi.ui.ProgressBar
import com.xiaoxiao.hanzi.ui.Screen

/**
 * 答题页，对应小程序 pages/quiz/quiz。
 *
 * 出题在进入页面时一次性生成（同一个 seed），后续所有交互只是索引推进 ——
 * 这样中途「退一笔」或旋转屏幕都不会换题，也不会重复计分。
 */
@Composable
fun QuizPage(app: AppState, mode: String, bookId: String, lessonId: String?) {
    val p = LocalPalette.current
    val scroll = rememberScrollState()
    app.revision

    // 生成题目：只在进页面时算一次
    val session = remember(mode, bookId, lessonId) {
        // 词语模式的题源是课本词语表，和生字表无关，走单独的构建函数
        if (mode == "words") {
            val r = Quiz.buildWordQuiz(bookId, null, 10)
            val name = Repo.book(bookId)?.name
            val title = if (name != null) "$name · 看拼音选词语" else "看拼音选词语"
            val s = Plan.Session("words", title, bookId, emptyList(), r.questions.size)
            return@remember Triple(s, r.questions, r.targets)
        }
        val s = when (mode) {
            "single" -> {
                // 单字练习：就那一个字，出 4 道不同类型的题
                val chars = Repo.lessonChars(lessonId)
                Plan.buildSession("lesson", app.progress, bookId, lessonId, chars, "练这个字")
            }
            else -> Plan.buildSession(mode, app.progress, bookId, lessonId)
        }
        // 多音字模式只出多音字题；其余模式用默认题型轮转
        val types = when (s.mode) {
            "polyphone" -> listOf("polyphone")
            "homophone" -> listOf("homophone")
            "radical" -> listOf("radical")
            "similar" -> listOf("similar")
            else -> null
        }
        val result = Quiz.build(s.chars, bookId, lessonId, s.count, types = types)
        Triple(s, result.questions, result.targets)
    }
    val questions = session.second

    var index by remember { mutableIntStateOf(0) }
    var picked by remember { mutableStateOf<String?>(null) }
    var answered by remember { mutableStateOf(false) }
    var showFeedback by remember { mutableStateOf(false) }
    var correctCount by remember { mutableIntStateOf(0) }
    val wrongChars = remember { mutableStateListOf<String>() }

    if (questions.isEmpty()) {
        Column(Modifier.fillMaxSize().padding(Dimens.pagePad.dp)) {
            Spacer(Modifier.height(60.dp))
            Text(
                "还没有可以练的字",
                fontSize = 16.sp,
                color = p.ink2,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "先去学几个新字吧",
                fontSize = 13.sp,
                color = p.ink3,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(20.dp))
            HanziButton("回到练习页", style = BtnStyle.Ghost) { app.nav.back() }
        }
        return
    }

    val q = questions[index]
    val pct = Math.round((index.toFloat() / questions.size) * 100)
    val isLast = index == questions.size - 1

    Column(
        Modifier
            .fillMaxSize()
            .testTag("quiz-root")
            .verticalScroll(scroll)
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        Spacer(Modifier.height(8.dp))

        // 顶栏：关闭 + 进度 + 计数
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(30.dp)
                    .clip(RoundedCornerShape(9.dp))
                    .background(p.card)
                    .clickable { app.nav.back() },
                contentAlignment = Alignment.Center
            ) { Text("✕", fontSize = 14.sp, color = p.ink2) }
            Spacer(Modifier.width(12.dp))
            Box(Modifier.weight(1f)) { ProgressBar(pct) }
            Spacer(Modifier.width(12.dp))
            Text("${index + 1}/${questions.size}", fontSize = 12.sp, color = p.ink3)
        }

        Spacer(Modifier.height(20.dp))

        // 题型标签 + 副标题
        Text(
            q.title,
            fontSize = 11.sp,
            color = p.jade,
            modifier = Modifier
                .clip(RoundedCornerShape(999.dp))
                .background(p.jadeSoft)
                .padding(horizontal = 10.dp, vertical = 4.dp)
        )
        Spacer(Modifier.height(10.dp))
        Text(q.sub, fontSize = 13.sp, color = p.ink2)

        Spacer(Modifier.height(16.dp))

        // 题干
        Box(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Dimens.radiusCard.dp))
                .background(p.card)
                .padding(vertical = 26.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                q.prompt,
                fontSize = when (q.promptKind) {
                    "pinyin" -> 38.sp
                    "word" -> 40.sp
                    else -> if (q.type == "strokeCount") 52.sp else 62.sp
                },
                fontWeight = if (q.promptKind == "pinyin") FontWeight.Bold else FontWeight.Normal,
                color = p.ink1,
                textAlign = TextAlign.Center
            )
        }

        Spacer(Modifier.height(18.dp))

        // 选项
        val twoCol = q.promptKind == "pinyin"
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            q.options.chunked(if (twoCol) 2 else 1).forEach { rowOpts ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    rowOpts.forEach { opt ->
                        val isCorrect = opt.value == q.answer
                        val isPicked = opt.value == picked
                        // 答对之后：正确项标绿；答错时同时标出自己选错的
                        val bgTarget = when {
                            !answered -> p.card
                            isCorrect -> p.jadeSoft
                            isPicked -> p.claySoft
                            else -> p.card
                        }
                        val borderTarget = when {
                            // 未作答时用 edge：line 和纸底对比度只有 1.23:1，
                            // 作为「可以点」的边界等于没画。iOS 答题选项也用 edge。
                            !answered -> p.edge
                            isCorrect -> p.jade
                            isPicked -> p.clay
                            else -> p.line
                        }
                        // 颜色渐变而不是瞬间翻色：低年级孩子需要"看见变化发生"
                        val bg by animateColorAsState(bgTarget, tween(Motion.NORMAL), label = "optBg")
                        val border by animateColorAsState(
                            borderTarget,
                            tween(Motion.NORMAL),
                            label = "optBorder"
                        )

                        // 被选中的那一项按下时轻微回缩再弹回，给一个"点到了"的确认
                        val press = remember { Animatable(1f) }
                        LaunchedEffect(picked, answered) {
                            if (answered && isPicked) {
                                press.snapTo(0.96f)
                                press.animateTo(
                                    1f,
                                    spring(
                                        dampingRatio = Spring.DampingRatioMediumBouncy,
                                        stiffness = Spring.StiffnessMedium
                                    )
                                )
                            }
                        }

                        Surface(
                            Modifier
                                .weight(1f)
                                .testTag("quiz-opt")
                                .graphicsLayer {
                                    scaleX = press.value
                                    scaleY = press.value
                                }
                                .clip(RoundedCornerShape(14.dp))
                                .clickable(enabled = !answered) {
                                    picked = opt.value
                                    answered = true
                                    val ok = opt.value == q.answer
                                    if (ok) correctCount += 1
                                    // 词语题的 ch 是整词，错题本和 SRS 都按单字组织——
                                    // 拆成字反而更符合学习逻辑：词错了，落点是其中某个字。
                                    val gradeChars =
                                        if (q.ch.length > 1 && Repo.meta(q.ch) == null)
                                            q.ch.map { it.toString() }.filter { Repo.meta(it) != null }
                                        else listOf(q.ch)
                                    if (!ok) {
                                        gradeChars.forEach { if (it !in wrongChars) wrongChars.add(it) }
                                    }
                                    gradeChars.forEach { app.progress.grade(it, ok, q.lesson) }
                                    app.touch()
                                    showFeedback = true
                                },
                            shape = RoundedCornerShape(14.dp),
                            color = bg,
                            border = BorderStroke(1.dp, border)
                        ) {
                            Row(
                                Modifier.padding(vertical = 15.dp, horizontal = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.Center
                            ) {
                                // 汉字选项配一个字形图，与 iOS 一致。
                                //
                                // iOS 的选项文字一律 17 medium，靠一个 42pt 的
                                // HanziView 把汉字放大——而不是把文字本身撑到 28。
                                // Android 之前没有字形图，只能靠字号（28/22/19）
                                // 硬顶，结果同一个选项框在不同题型下字差一倍。
                                // 现在文字统一 17，汉字另外画字形。
                                // 汉字选项：只画字形、不再排一遍文字，
                                // 否则同一个字会出现两次。
                                // 其它选项（拼音、词语、笔画数）照常排文字。
                                if (opt.label.length == 1 && isHanzi(opt.label)) {
                                    HanziGlyph(opt.label, Modifier.size(30.dp))
                                } else {
                                    Text(
                                        opt.label,
                                        fontSize = 17.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = p.ink1
                                    )
                                }
                                // ✓/✕ 淡入并轻微放大，避免"突然多出一个符号"的跳变
                                AnimatedVisibility(
                                    visible = answered && isCorrect,
                                    enter = fadeIn(tween(Motion.QUICK)) +
                                        scaleIn(tween(Motion.QUICK), initialScale = 0.5f)
                                ) {
                                    Row {
                                        Spacer(Modifier.width(6.dp))
                                        Text("✓", fontSize = 14.sp, color = p.jade)
                                    }
                                }
                                AnimatedVisibility(
                                    visible = answered && isPicked && !isCorrect,
                                    enter = fadeIn(tween(Motion.QUICK)) +
                                        scaleIn(tween(Motion.QUICK), initialScale = 0.5f)
                                ) {
                                    Row {
                                        Spacer(Modifier.width(6.dp))
                                        Text("✕", fontSize = 14.sp, color = p.clay)
                                    }
                                }
                            }
                        }
                    }
                    if (rowOpts.size < if (twoCol) 2 else 1) Spacer(Modifier.weight(1f))
                }
            }
        }

        // 反馈区：只淡入，不做高度动画。高度动画会让下方按钮位置抖动，
        // 既影响观感，也会影响按几何位置断言的测试
        AnimatedVisibility(
            visible = showFeedback,
            enter = fadeIn(tween(Motion.NORMAL))
        ) {
            Column {
                Spacer(Modifier.height(18.dp))
                Surface(
                    Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(Dimens.radiusCard.dp),
                    color = if (picked == q.answer) p.jadeSoft else p.claySoft
                ) {
                Column(Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(if (picked == q.answer) "🎉" else "💪", fontSize = 16.sp)
                        Spacer(Modifier.width(7.dp))
                        Text(
                            if (picked == q.answer) "答对啦！" else "再想一想",
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (picked == q.answer) p.jadeDeep else p.clay
                        )
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(q.explain, fontSize = 13.sp, color = p.ink2)
                    Spacer(Modifier.height(14.dp))
                    HanziButton(if (isLast) "看结果" else "继续", style = BtnStyle.Primary) {
                        if (isLast) {
                            app.progress.recordQuiz(questions.size, correctCount)
                            app.touch()
                            app.nav.replace(
                                Screen.Result(
                                    correct = correctCount,
                                    total = questions.size,
                                    wrongChars = wrongChars.toList(),
                                    mode = mode,
                                    book = bookId
                                )
                            )
                        } else {
                            index += 1
                            picked = null
                            answered = false
                            showFeedback = false
                        }
                    }
                }
                }
            }
        }

        Spacer(Modifier.height(24.dp))
    }
}

/** 判断一个字符是不是汉字（用于决定要不要画字形而不是直接排字） */
private fun isHanzi(s: String): Boolean {
    if (s.isEmpty()) return false
    val c = s[0]
    return c.code in 0x4E00..0x9FFF
}
