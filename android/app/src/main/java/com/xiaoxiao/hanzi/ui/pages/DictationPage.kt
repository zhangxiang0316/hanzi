package com.xiaoxiao.hanzi.ui.pages

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.DictationLevel
import com.xiaoxiao.hanzi.logic.DictationSource
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.BtnStyle
import com.xiaoxiao.hanzi.ui.HanziButton
import com.xiaoxiao.hanzi.ui.Stars
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.ProgressBar
import com.xiaoxiao.hanzi.ui.Screen

/**
 * 听写页：念一个词，孩子凭记忆写。
 *
 * 复用描红的判分与画布（[WritePage] 的 `hideGhost` 参数），
 * 只是把底字藏起来。页面自己管「一道题写完之后进下一题」，
 * 因为听写是按字推进的，而描红是「一个字写完就结束」。
 *
 * 与 iOS `DictationPageView` 对应，三档难度的语义必须一致。
 */
@Composable
fun DictationPage(app: AppState, levelName: String, book: String) {
    val p = LocalPalette.current
    app.revision

    val level = DictationLevel.fromKey(levelName)
    // 只算一次：旋转屏幕、recompose 都不能换一批字
    val items = remember(levelName, book) {
        DictationSource.pick(book, level, 8)
    }

    var index by remember { mutableIntStateOf(0) }
    val scores = remember { mutableMapOf<String, Int>() }
    var finishedRound by remember { mutableStateOf(false) }

    if (finishedRound) {
        DictationResult(app, level, items, scores) {
            app.nav.back()
        }
        return
    }

    val item = items.getOrNull(index)
    if (item == null) {
        // 这一册没有可听写的字（理论上不会发生，全册 2255 个会写字）
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("这一册没有可以听写的字", color = p.ink3)
        }
        return
    }

    // 换字后自动念一遍——否则孩子不知道要写什么
    LaunchedEffect(index) {
        app.tts.speak(level.promptText(item.ch, item.word))
    }

    var score by remember(index) { mutableStateOf<Int?>(null) }

    Column(
        Modifier
            .fillMaxSize()
            .background(p.paper)
            .verticalScroll(rememberScrollState())
            .padding(Dimens.pagePad.dp)
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                "第 ${minOf(index + 1, items.size)} / ${items.size} 个",
                fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = p.ink2
            )
            val avg = if (scores.isEmpty()) null else scores.values.average().toInt()
            if (avg != null) {
                Text("平均 $avg 分", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = p.jade)
            }
        }

        Spacer(Modifier.height(8.dp))
        // 进度条，与 iOS 一致（那边一直有，这边漏了）。
        // 听写是「一批字连着写」，没有进度条时孩子不知道还剩多少，
        // 家长也没法判断快结束了没有。
        ProgressBar(
            pct = if (items.isEmpty()) 0
            else (index * 100) / items.size,
            height = 6
        )

        Spacer(Modifier.height(12.dp))

        // 题面卡片：写之前是「＿」，写完才露字
        Surface(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Dimens.radiusInner.dp)),
            color = p.card
        ) {
            Row(
                Modifier.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(Modifier.weight(1f)) {
                    Text(
                        "听到的是——",
                        fontSize = 11.sp, color = p.ink3
                    )
                    Text(
                        if (score != null) item.ch else "＿",
                        fontSize = 38.sp, color = if (score != null) p.ink1 else p.ink3.copy(alpha = 0.35f)
                    )
                    if (item.word != null && level != DictationLevel.HARD) {
                        Text(item.word, fontSize = 13.sp, color = p.ink3)
                    }
                }
                // 再念一遍
                Surface(
                    Modifier
                        .size(44.dp)
                        .clip(CircleShape)
                        .clickable {
                            app.tts.speak(level.promptText(item.ch, item.word))
                        },
                    color = p.jadeSoft
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text("🔊", fontSize = 17.sp)
                    }
                }
            }
        }

        Spacer(Modifier.height(14.dp))

        // 画布：听写不给底字
        Box(
            Modifier
                .fillMaxWidth()
                .height(320.dp)
                .clip(RoundedCornerShape(Dimens.radiusInner.dp))
                .background(p.card)
        ) {
            WritePage(
                app = app,
                ch = item.ch,
                hideGhost = level != DictationLevel.EASY,
                onFinished = { sc ->
                    score = sc
                    scores[item.ch] = sc
                }
            )
        }

        Spacer(Modifier.height(14.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (score != null) {
                HanziButton(
                    text = if (index + 1 >= items.size) "看结果" else "下一个",
                    modifier = Modifier.weight(1f)
                ) {
                    if (index + 1 >= items.size) finishedRound = true else index += 1
                }
            } else {
                HanziButton(
                    text = "跳过这个字",
                    modifier = Modifier.weight(1f),
                    style = BtnStyle.Ghost
                ) {
                    if (index + 1 >= items.size) finishedRound = true else index += 1
                }
            }
        }

        Spacer(Modifier.height(20.dp))
    }
}

/** 听写结果：写了几个字、平均多少分、得了几个星 */
@Composable
private fun DictationResult(
    app: AppState,
    level: DictationLevel,
    items: List<com.xiaoxiao.hanzi.logic.DictationItem>,
    scores: Map<String, Int>,
    onDone: () -> Unit
) {
    val p = LocalPalette.current
    val avg = if (scores.isEmpty()) 0 else scores.values.average().toInt()
    val stars = com.xiaoxiao.hanzi.logic.Trace.starsOf(avg)

    // 听写的成绩也进描红记录：都是「写」这个能力，没理由分开统计
    LaunchedEffect(Unit) {
        scores.forEach { (ch, sc) -> app.progress.saveWrite(ch, sc) }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(p.paper)
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("听写完成", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = p.ink1)
        Spacer(Modifier.height(16.dp))
        Stars(count = stars, size = 30)
        Spacer(Modifier.height(20.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(26.dp)) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("${scores.size} 个字", fontSize = 19.sp, fontWeight = FontWeight.Bold, color = p.ink1)
                Text("写了", fontSize = 11.sp, color = p.ink3)
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("$avg 分", fontSize = 19.sp, fontWeight = FontWeight.Bold, color = p.ink1)
                Text("平均", fontSize = 11.sp, color = p.ink3)
            }
        }

        Spacer(Modifier.height(20.dp))

        // 逐字列出得分，家长一眼能看出哪几个字没记住
        Surface(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Dimens.radiusInner.dp)),
            color = p.card
        ) {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                items.filter { scores.containsKey(it.ch) }.forEach { it ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(vertical = 9.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(it.ch, fontSize = 20.sp, color = p.ink1)
                        val sc = scores[it.ch] ?: 0
                        Text(
                            "$sc 分",
                            fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                            color = when {
                                sc >= 85 -> p.jade
                                sc >= 65 -> p.amber
                                else -> p.clay
                            }
                        )
                    }
                }
            }
        }

        Spacer(Modifier.height(22.dp))
        HanziButton(text = "完成", modifier = Modifier.fillMaxWidth(), onClick = onDone)
    }
}
