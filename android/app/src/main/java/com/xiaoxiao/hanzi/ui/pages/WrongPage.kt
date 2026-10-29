package com.xiaoxiao.hanzi.ui.pages

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.BtnStyle
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.EmptyState
import com.xiaoxiao.hanzi.ui.HanziButton
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.Screen

/** 错题本，对应小程序 pages/wrong/wrong */
@Composable
fun WrongPage(app: AppState) {
    val p = LocalPalette.current
    val scroll = rememberScrollState()
    app.revision

    val items = app.progress.wrongList()

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(scroll)
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        Spacer(Modifier.height(8.dp))
        Text("错题本", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = p.ink1)
        Spacer(Modifier.height(4.dp))
        Text(
            if (items.isEmpty()) "答错过的字会出现在这里" else "共 ${items.size} 个字，错得越多的排在前面",
            fontSize = 12.sp,
            color = p.ink3
        )
        Spacer(Modifier.height(16.dp))

        if (items.isEmpty()) {
            EmptyState("🎈", "错题本是空的", "去练一练，答错的字会自动收进来")
            Spacer(Modifier.height(12.dp))
            HanziButton("去练习", style = BtnStyle.Primary) {
                app.nav.switchTab(Screen.Practice)
            }
        } else {
            HanziButton("重练这些字", style = BtnStyle.Primary) {
                app.nav.push(Screen.Quiz("wrong", app.currentBook, null))
            }
            Spacer(Modifier.height(14.dp))

            items.forEach { w ->
                val m = Repo.meta(w.ch) ?: return@forEach
                Surface(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(Dimens.radiusInner.dp))
                        .clickable { app.nav.push(Screen.Detail(w.ch, w.lesson ?: m.lesson)) },
                    shape = RoundedCornerShape(Dimens.radiusInner.dp),
                    color = p.card,
                    border = BorderStroke(1.dp, p.line)
                ) {
                    Row(
                        Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            Modifier
                                .size(46.dp)
                                .clip(RoundedCornerShape(12.dp))
                                .background(p.cardWarm),
                            contentAlignment = Alignment.Center
                        ) { Text(w.ch, fontSize = 26.sp, color = p.ink1) }
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                m.py,
                                fontSize = 13.sp,
                                color = p.jade,
                                fontWeight = FontWeight.Medium
                            )
                            Spacer(Modifier.height(2.dp))
                            Text(
                                "${m.radical} · ${m.strokes} 画 · " +
                                    (m.words.firstOrNull()?.word ?: ""),
                                fontSize = 11.sp,
                                color = p.ink3
                            )
                        }
                        Box(
                            Modifier
                                .clip(CircleShape)
                                .background(p.claySoft)
                                .padding(horizontal = 8.dp, vertical = 3.dp)
                        ) {
                            Text("错 ${w.n} 次", fontSize = 10.sp, color = p.clay)
                        }
                        Spacer(Modifier.width(6.dp))
                        Text(
                            "✕",
                            fontSize = 12.sp,
                            color = p.ink3,
                            modifier = Modifier.clickable {
                                app.progress.clearWrong(w.ch)
                                app.touch()
                            }
                        )
                    }
                }
                Spacer(Modifier.height(9.dp))
            }

            Spacer(Modifier.height(10.dp))
            HanziButton("清空错题本", style = BtnStyle.Ghost) {
                app.progress.clearWrong(null)
                app.touch()
            }
        }

        Spacer(Modifier.height(24.dp))
    }
}
