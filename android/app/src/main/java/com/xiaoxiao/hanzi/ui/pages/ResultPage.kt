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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.BtnStyle
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.HanziButton
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.Screen
import com.xiaoxiao.hanzi.ui.Stars

/** 答题结果，对应小程序 pages/result/result */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ResultPage(
    app: AppState,
    correct: Int,
    total: Int,
    wrongChars: List<String>,
    mode: String,
    bookId: String
) {
    val p = LocalPalette.current
    val scroll = rememberScrollState()
    app.revision

    val rate = if (total > 0) Math.round(correct * 100f / total) else 0
    val stars = when {
        rate >= 100 -> 3
        rate >= 85 -> 2
        rate >= 60 -> 1
        else -> 0
    }
    val mood = when {
        rate >= 100 -> "🏆"
        rate >= 85 -> "🎉"
        rate >= 60 -> "👍"
        else -> "💪"
    }
    val title = when {
        rate >= 100 -> "全对！太厉害了"
        rate >= 85 -> "很棒！"
        rate >= 60 -> "还不错"
        else -> "再练练就好"
    }
    val message = when {
        rate >= 100 -> "这些字你已经记得很牢了"
        rate >= 85 -> "只差一点点就全对了"
        rate >= 60 -> "错过的字已经放进错题本"
        else -> "别灰心，多写几遍就记住了"
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(scroll)
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        Spacer(Modifier.height(24.dp))

        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(mood, fontSize = 46.sp)
            Spacer(Modifier.height(10.dp))
            Text(title, fontSize = 21.sp, fontWeight = FontWeight.Bold, color = p.ink1)
            Spacer(Modifier.height(5.dp))
            Text("$correct / $total 题", fontSize = 13.sp, color = p.ink3)
            Spacer(Modifier.height(10.dp))
            Stars(stars, size = 22)
            Spacer(Modifier.height(6.dp))
            Text(message, fontSize = 12.sp, color = p.ink3)

            Spacer(Modifier.height(20.dp))

            // 正确率圆环：Compose 用两个同心圆 + 进度弧模拟
            Box(
                Modifier
                    .size(120.dp)
                    .clip(CircleShape)
                    .background(p.jadeSoft),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    Modifier
                        .size(98.dp)
                        .clip(CircleShape)
                        .background(p.card),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Row(verticalAlignment = Alignment.Bottom) {
                            Text(
                                "$rate",
                                fontSize = 30.sp,
                                fontWeight = FontWeight.Bold,
                                color = p.jade
                            )
                            Text("%", fontSize = 13.sp, color = p.jade)
                        }
                        Text("正确率", fontSize = 10.sp, color = p.ink3)
                    }
                }
            }
        }

        Spacer(Modifier.height(24.dp))

        if (wrongChars.isNotEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "这几个字还需要多看看",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    color = p.ink1,
                    modifier = Modifier.weight(1f)
                )
                Text("已放进错题本", fontSize = 11.sp, color = p.ink3)
            }
            Spacer(Modifier.height(10.dp))
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                wrongChars.forEach { ch ->
                    val m = Repo.meta(ch)
                    Surface(
                        shape = RoundedCornerShape(14.dp),
                        color = p.card,
                        border = BorderStroke(1.dp, p.line),
                        modifier = Modifier.clickable {
                            app.nav.push(Screen.Detail(ch, m?.lesson))
                        }
                    ) {
                        Column(
                            Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(ch, fontSize = 26.sp, color = p.ink1)
                            Text(m?.py ?: "", fontSize = 10.sp, color = p.jade)
                            Text(
                                m?.words?.firstOrNull()?.word ?: "",
                                fontSize = 9.sp,
                                color = p.ink3
                            )
                        }
                    }
                }
            }
        } else {
            Surface(
                Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Dimens.radiusCard.dp),
                color = p.amberSoft
            ) {
                Row(
                    Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("🏅", fontSize = 22.sp)
                    Spacer(Modifier.width(10.dp))
                    Text(
                        "全部答对，太厉害了！",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = p.ink1
                    )
                }
            }
        }

        Spacer(Modifier.height(24.dp))

        HanziButton(
            if (wrongChars.isNotEmpty()) "再练这几个字" else "再来一组",
            style = BtnStyle.Primary
        ) {
            val next = Screen.Quiz(if (wrongChars.isNotEmpty()) "wrong" else mode, bookId, null)
            app.nav.replace(next)
        }
        Spacer(Modifier.height(9.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            Box(Modifier.weight(1f)) {
                HanziButton("去练习页", style = BtnStyle.Ghost) {
                    app.nav.switchTab(Screen.Practice)
                }
            }
            Box(Modifier.weight(1f)) {
                HanziButton("回首页", style = BtnStyle.Soft) {
                    app.nav.switchTab(Screen.Index)
                }
            }
        }

        Spacer(Modifier.height(24.dp))
    }
}
