package com.xiaoxiao.hanzi.ui.pages

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.EmptyState
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.Screen

/**
 * 部首归类浏览。
 *
 * 部首此前只作为「这个字的部首是什么」这道题的答案存在——孩子答对答错，
 * 但从没机会「按部首看一遍字」。归类的价值在横向对比：认识「氵」之后，
 * 看到江、河、湖、海都带三点水，才明白部首是什么意思。
 *
 * ## 数据
 *
 * 字库里 237 个部首，分布极不均：口 144 字、扌 138、氵 132，
 * 但有 54 个部首只带 1 个字。所以默认**按字数从多到少**排，
 * 冷门部首排在后面，不至于一进来就被一堆只有 1 个字的部首淹没。
 *
 * 顺序来自 `Repo.bookRadicals` / `allRadicals`（频次降序、码点升序），
 * 三端一致，不在页面里再排一次。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RadicalPage(app: AppState) {
    val p = LocalPalette.current
    app.revision

    val bookId = app.currentBook
    val book = Repo.book(bookId)
    var scopeAll by remember { mutableStateOf(false) }
    var sel by remember { mutableStateOf("") }

    val radicals = remember(bookId, scopeAll, app.revision) {
        if (scopeAll) Repo.allRadicals() else Repo.bookRadicals(bookId)
    }
    // 进来先选字数最多的那个部首，省得页面一片空白等着点
    val active = if (sel.isNotEmpty() && radicals.any { it.first == sel }) {
        sel
    } else {
        radicals.firstOrNull()?.first ?: ""
    }

    val chars = if (active.isEmpty()) {
        emptyList()
    } else if (scopeAll) {
        Repo.allCharsWithRadical(active)
    } else {
        Repo.charsWithRadical(bookId, active)
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        // 标题交给顶栏，页面里只在首行交代一句「这页是干什么的」
        Spacer(Modifier.height(8.dp))
        Text("按部首看字，明白「三点水」「提手旁」是什么意思", fontSize = 12.sp, color = p.ink3)

        Spacer(Modifier.height(14.dp))

        // 本册 / 全部：本册是「这学期要学哪些部首」，全部是「字库里一共有哪些」
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ScopeButton(
                "本册（${book?.short ?: ""}）",
                !scopeAll,
                Modifier.weight(1f),
                "radical-scope-book"
            ) { scopeAll = false }
            ScopeButton("全部字库", scopeAll, Modifier.weight(1f), "radical-scope-all") {
                scopeAll = true
            }
        }

        Spacer(Modifier.height(14.dp))

        if (radicals.isEmpty()) {
            EmptyState("🧩", "本册还没有学过的部首")
        } else {
            // 部首格子：96dp 一格装得下「部首 + 字数」两行
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                radicals.forEach { r ->
                    RadicalCell(
                        radical = r.first,
                        count = r.second,
                        on = r.first == active
                    ) { sel = r.first }
                }
            }

            Spacer(Modifier.height(18.dp))

            // 选中部首下的字
            Surface(
                Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Dimens.radiusCard.dp),
                color = p.card,
                border = BorderStroke(1.dp, p.line)
            ) {
                Column(Modifier.padding(14.dp)) {
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text("$active 部", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = p.ink1)
                        Spacer(Modifier.width(8.dp))
                        val learned = chars.count { app.progress.hasLearned(it) }
                        Text(
                            "${chars.size} 个字" + if (learned > 0) "，认识 $learned 个" else "",
                            fontSize = 12.sp,
                            color = p.ink3
                        )
                    }
                    Spacer(Modifier.height(12.dp))
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        chars.forEach { ch ->
                            CharCell(ch, learned = app.progress.hasLearned(ch)) {
                                // 部首字里有 93 个是偏旁变形（氵 艹 扌），不是独立汉字、
                                // 没有详情页；理论上不会出现在这里，兜一下底
                                if (Repo.hasChar(ch)) {
                                    app.nav.push(Screen.Detail(ch, Repo.meta(ch)?.lesson))
                                }
                            }
                        }
                    }
                    Spacer(Modifier.height(14.dp))
                    Text(
                        "带绿点的字已经学过；点一个字看笔顺和组词",
                        fontSize = 11.sp,
                        color = p.ink3
                    )
                }
            }
        }

        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun ScopeButton(
    text: String,
    on: Boolean,
    modifier: Modifier = Modifier,
    tag: String,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    Surface(
        shape = RoundedCornerShape(999.dp),
        color = if (on) p.jade else p.card,
        border = BorderStroke(1.dp, if (on) p.jade else p.line),
        modifier = modifier
            .testTag(tag)
            .clip(RoundedCornerShape(999.dp))
            .clickable(onClick = onClick)
            // 88rpx ≈ 44dp：低于这个高度手指点不准（微信版踩过同一个坑）
            .defaultMinSize(minHeight = 44.dp)
    ) {
        Box(Modifier.padding(horizontal = 10.dp), contentAlignment = Alignment.Center) {
            Text(
                text,
                fontSize = 13.sp,
                fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal,
                color = if (on) Color.White else p.ink2,
                maxLines = 1,
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun RadicalCell(radical: String, count: Int, on: Boolean, onClick: () -> Unit) {
    val p = LocalPalette.current
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = if (on) p.jadeSoft else p.card,
        border = BorderStroke(if (on) 2.dp else 1.dp, if (on) p.jade else p.line),
        modifier = Modifier
            .testTag("radical-cell-$radical")
            .size(48.dp)
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
    ) {
        Column(
            Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                radical,
                fontSize = 17.sp,
                lineHeight = 18.sp,
                fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                color = if (on) p.jadeDeep else p.ink1
            )
            Text(count.toString(), fontSize = 9.sp, lineHeight = 10.sp, color = p.ink3)
        }
    }
}

/** 一个字的格子：字号大、拼音小，学过的加绿底与右上角绿点 */
@Composable
private fun CharCell(ch: String, learned: Boolean, onClick: () -> Unit) {
    val p = LocalPalette.current
    Surface(
        shape = RoundedCornerShape(10.dp),
        color = if (learned) p.jadeSoft else p.track,
        modifier = Modifier
            .testTag("radical-char-$ch")
            .size(width = 52.dp, height = 60.dp)
            .clip(RoundedCornerShape(10.dp))
            .clickable(onClick = onClick)
    ) {
        Box(Modifier.fillMaxSize()) {
            Column(
                Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(ch, fontSize = 23.sp, color = p.ink1)
                Text(
                    Repo.meta(ch)?.py ?: "",
                    fontSize = 9.sp,
                    lineHeight = 10.sp,
                    color = p.ink3,
                    maxLines = 1
                )
            }
            if (learned) {
                Box(
                    Modifier
                        .align(Alignment.TopEnd)
                        .padding(5.dp)
                        .size(6.dp)
                        .clip(CircleShape)
                        .background(p.jade)
                )
            }
        }
    }
}
