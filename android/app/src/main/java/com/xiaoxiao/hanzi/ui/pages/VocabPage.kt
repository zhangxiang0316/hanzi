package com.xiaoxiao.hanzi.ui.pages

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Vocab
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.BtnStyle
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.HanziButton
import com.xiaoxiao.hanzi.ui.HanziCard
import com.xiaoxiao.hanzi.ui.LocalPalette

/**
 * 识字量测试，对应小程序 `pages/vocab`。
 *
 * 三步同页切换（`stage`）：开始页 → 逐题作答 → 结果页。
 * 不用三个 Screen：这是个一次性流程，来回跳只会让孩子误触返回键卡在中间态。
 */
private enum class Stage { Intro, Test, Result }

@Composable
fun VocabPage(app: AppState) {
    val p = LocalPalette.current
    var stage by remember { mutableStateOf(Stage.Intro) }
    var test by remember { mutableStateOf<Vocab.Test?>(null) }
    var answers by remember { mutableStateOf<List<Boolean>>(emptyList()) }
    var qIndex by remember { mutableStateOf(0) }
    var picked by remember { mutableStateOf<String?>(null) }
    var result by remember { mutableStateOf<Vocab.Estimate?>(null) }

    fun start() {
        // 每次开测用新 seed：反复测同一套题，孩子会把答案背下来
        test = Vocab.buildTest()
        answers = emptyList()
        qIndex = 0
        picked = null
        result = null
        stage = Stage.Test
    }

    fun finish(t: Vocab.Test, ans: List<Boolean>) {
        val est = Vocab.estimate(t, ans)
        result = est
        // 记一笔：家长在「我的」里也能看到上次测出来多少
        app.progress.setVocabSize(est.size)
        app.touch()
        stage = Stage.Result
    }

    fun answer(t: Vocab.Test, v: String) {
        if (picked != null) return
        val q = t.questions[qIndex]
        val correct = v == q.answer
        picked = v
        val next = answers + correct
        answers = next
        // 答错也立刻往下走：这是测验不是练习，孩子没有第二次机会，
        // 但要让正确答案在屏幕上停久一点（下面的延迟靠重组时的选择色体现）
        val i = qIndex + 1
        // 一册问完就判一次要不要停：正确率过低的册次之后不必再问，
        // 问下去只是让孩子反复受挫
        val g = t.groups.firstOrNull { it.start + it.questions.size == i }
        if (g != null) {
            val est = Vocab.estimate(t, next)
            val gs = est.groups.firstOrNull { it.book == g.book }
            if (gs != null && gs.asked >= g.questions.size && gs.rate < Vocab.STOP_RATE) {
                finish(t, next)
                return
            }
        }
        if (i >= t.total) {
            finish(t, next)
            return
        }
        qIndex = i
        picked = null
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        Spacer(Modifier.height(8.dp))
        when (stage) {
            Stage.Intro -> IntroStage(onStart = { start() })
            Stage.Test -> {
                val t = test
                if (t == null) {
                    IntroStage(onStart = { start() })
                } else {
                    TestStage(
                        t = t,
                        qIndex = qIndex,
                        picked = picked,
                        onPick = { answer(t, it) }
                    )
                }
            }
            Stage.Result -> {
                val est = result
                if (est == null) IntroStage(onStart = { start() })
                else ResultStage(
                    est = est,
                    onRestart = { start() },
                    onDone = { app.nav.back() }
                )
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun IntroStage(onStart: () -> Unit) {
    val p = LocalPalette.current
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(32.dp))
        Text("📏", fontSize = 48.sp)
        Spacer(Modifier.height(10.dp))
        Text("测测认识多少字", fontSize = 23.sp, fontWeight = FontWeight.Bold, color = p.ink1)
        Spacer(Modifier.height(7.dp))
        Text(
            "从八册里各抽几个字，看看认字量大概到哪儿了",
            fontSize = 13.sp,
            color = p.ink3,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(24.dp))
    }

    HanziCard(padding = 14) {
        listOf(
            "最多 40 个字，两三分钟",
            "答不出来很正常，不会的字直接跳过",
            "结果是估算，不是精确值"
        ).forEach { line ->
            Row(Modifier.padding(vertical = 5.dp)) {
                Text("·", fontSize = 13.sp, color = p.jade)
                Text(
                    line,
                    fontSize = 13.sp,
                    color = p.ink2,
                    modifier = Modifier.padding(start = 8.dp)
                )
            }
        }
    }
    Spacer(Modifier.height(20.dp))
    HanziButton("开始测", tag = "识字量-开始") { onStart() }
}

@Composable
private fun TestStage(
    t: Vocab.Test,
    qIndex: Int,
    picked: String?,
    onPick: (String) -> Unit
) {
    val p = LocalPalette.current
    val q = t.questions[qIndex]
    // Quiz.Question 没有册次字段（它给普通练习用），从分组里反查
    val group = t.groups.lastOrNull { it.start <= qIndex }
    val book = group?.let { Repo.book(it.book) }

    LinearProgressIndicator(
        progress = { qIndex.toFloat() / t.total },
        modifier = Modifier
            .fillMaxWidth()
            .height(6.dp),
        color = p.jade,
        trackColor = p.line
    )
    Spacer(Modifier.height(8.dp))
    Text(
        "${qIndex + 1} / ${t.total} · ${book?.name ?: ""}",
        fontSize = 12.sp,
        color = p.ink3
    )
    Spacer(Modifier.height(20.dp))

    HanziCard(padding = 0) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(vertical = 30.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(q.prompt, fontSize = 96.sp, color = p.ink1)
        }
    }
    Spacer(Modifier.height(18.dp))

    // 一行两个，四个选项两行——和微信版一致
    q.options.chunked(2).forEach { row ->
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            row.forEach { o ->
                val state = when {
                    picked == null -> ""
                    o.value == q.answer -> "right"
                    o.value == picked -> "wrong"
                    else -> ""
                }
                val bg = when (state) {
                    "right" -> p.jadeSoft
                    "wrong" -> p.claySoft
                    else -> p.card
                }
                val border = when (state) {
                    "right" -> p.jade
                    "wrong" -> p.clay
                    else -> p.line
                }
                val fg = when (state) {
                    "right" -> p.jadeDeep
                    "wrong" -> p.clay
                    else -> p.ink1
                }
                Surface(
                    modifier = Modifier
                        .weight(1f)
                        .padding(vertical = 5.dp)
                        .clickable(enabled = picked == null) { onPick(o.value) },
                    shape = RoundedCornerShape(14.dp),
                    color = bg,
                    border = BorderStroke(1.dp, border)
                ) {
                    Text(
                        o.label,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 15.dp),
                        fontSize = 17.sp,
                        color = fg,
                        fontWeight = if (state == "right") FontWeight.Bold else FontWeight.Normal,
                        textAlign = TextAlign.Center
                    )
                }
            }
        }
    }

    Spacer(Modifier.height(10.dp))
    Text(
        "会读就选，不会就随便选一个，后面还会继续",
        modifier = Modifier.fillMaxWidth(),
        fontSize = 12.sp,
        color = p.ink3,
        textAlign = TextAlign.Center
    )
}

@Composable
private fun ResultStage(est: Vocab.Estimate, onRestart: () -> Unit, onDone: () -> Unit) {
    val p = LocalPalette.current
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(28.dp))
        Text("估算认识", fontSize = 13.sp, color = p.ink3)
        Spacer(Modifier.height(4.dp))
        Text(
            Vocab.sizeLabel(est.size),
            fontSize = 54.sp,
            fontWeight = FontWeight.Bold,
            color = p.jadeDeep
        )
        Text("个字", fontSize = 13.sp, color = p.ink3)
        Spacer(Modifier.height(12.dp))
        Text(
            Vocab.verdict(est.size),
            fontSize = 14.sp,
            color = p.ink2,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(7.dp))
        val stop = est.groups.firstOrNull { it.book == est.stopBook }
        Text(
            if (stop != null) "到${stop.name}就停下来了，后面的册次还没学到" else "八册都测完了",
            fontSize = 12.sp,
            color = p.ink3,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(20.dp))
    }

    HanziCard(padding = 14) {
        Text("各册情况", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = p.ink1)
        Spacer(Modifier.height(6.dp))
        est.groups.filter { it.asked > 0 }.forEach { g ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(g.name, fontSize = 13.sp, color = p.ink2, modifier = Modifier.weight(1f))
                Text("${g.correct} / ${g.asked}", fontSize = 13.sp, color = p.ink1)
                Text(
                    if (g.contribution > 0) "+${g.contribution}" else "不计",
                    modifier = Modifier.padding(start = 14.dp),
                    fontSize = 12.sp,
                    color = if (g.contribution > 0) p.jadeDeep else p.ink3
                )
            }
        }
    }

    Spacer(Modifier.height(18.dp))
    HanziButton("再测一次", tag = "识字量-再测") { onRestart() }
    Spacer(Modifier.height(10.dp))
    HanziButton("回到我的", style = BtnStyle.Soft) { onDone() }
}
