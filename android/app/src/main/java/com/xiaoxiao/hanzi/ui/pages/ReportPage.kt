package com.xiaoxiao.hanzi.ui.pages

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.logic.DayUtil
import com.xiaoxiao.hanzi.logic.Report
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.HanziCard
import com.xiaoxiao.hanzi.ui.LocalPalette
import com.xiaoxiao.hanzi.ui.Palette

/**
 * 学习周报（家长报告）。
 *
 * 首页告诉你「今天学了几个字」，这一页告诉你「这一周怎么样」——
 * 后者才是家长真正关心的粒度。
 *
 * 口径（哪些天算活跃、没答题时正确率怎么显示）全在 [Report] 里，
 * 那部分是纯函数、有测试；这里只负责排版。这一点刻意和小程序一致：
 * 三端最容易跑偏的不是布局，是「缺数据的那天算不算 0 分」这类口径。
 */
@Composable
fun ReportPage(app: AppState) {
    val p = LocalPalette.current
    app.revision

    val built = Report.build(app.progress.daysStats())

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        Spacer(Modifier.height(8.dp))

        // 顶部结论：家长先扫这一句，数字是佐证
        Text(
            DayUtil.dateLabel() + " · " + DayUtil.weekdayCN(),
            fontSize = 12.sp,
            color = p.ink3
        )
        Spacer(Modifier.height(4.dp))
        // 24 与 iOS 一致（那边是 Fonts.s(24, .bold, .title2)）。
        // 这是页内的大区块标题，不是页面标题，所以不用 pageTitle。
        Text("最近 7 天", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = p.ink1)
        Spacer(Modifier.height(6.dp))
        Text(
            Report.verdict(built.sum),
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            color = toneColor(Report.verdictTone(built.sum), p)
        )
        Spacer(Modifier.height(4.dp))
        Text(built.headline, fontSize = 13.sp, color = p.ink2)

        Spacer(Modifier.height(16.dp))

        ChartCard(built.week)

        Spacer(Modifier.height(12.dp))

        StatsCard(built.sum)

        SectionTitle("每天")
        // 逐日明细：柱状图看趋势，这张表看具体哪天
        Surface(
            Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(Dimens.radiusCard.dp),
            color = p.card
        ) {
            Column {
                built.week.forEachIndexed { i, d ->
                    if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(p.lineSoft))
                    DayRow(d)
                }
            }
        }

        SectionTitle("给家长")
        Surface(
            Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(Dimens.radiusCard.dp),
            color = p.card
        ) {
            Column(Modifier.padding(vertical = 4.dp)) {
                built.advice.forEach { a ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.Top
                    ) {
                        // 圆点用来源的口气上色：good=玉青、tip=朱砂、plain=灰
                        Box(
                            Modifier
                                .padding(top = 7.dp)
                                .size(6.dp)
                                .clip(CircleShape)
                                .background(toneColor(a.tone, p))
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            a.text,
                            fontSize = 13.sp,
                            lineHeight = 22.sp,
                            color = p.ink2
                        )
                    }
                }
            }
        }

        Spacer(Modifier.height(16.dp))
        Text(
            "周报统计最近 7 个自然日（含今天），不是周一到周日——" +
                "滚动 7 天任何时候打开都有内容，不会周一早上看到一片空白。",
            fontSize = 11.sp,
            lineHeight = 18.sp,
            color = p.ink3
        )

        Spacer(Modifier.height(24.dp))
    }
}

private fun toneColor(tone: String, p: Palette): Color = when (tone) {
    "good" -> p.jade
    "tip" -> p.clay
    else -> p.ink2
}

@Composable
private fun SectionTitle(text: String) {
    val p = LocalPalette.current
    Text(
        text,
        modifier = Modifier.padding(top = 20.dp, bottom = 8.dp, start = 4.dp),
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
        color = p.ink2
    )
}

/**
 * 柱状图：每根柱子是一天的活跃度。
 *
 * 高度比例在 [Report.withRatios] 里算好（0~1）。没学的那天没有柱子，
 * 只剩底边那条细线，表示「这一天存在，但是空的」——画成 0 高度会让人
 * 以为是页面缺了一块。
 */
@Composable
private fun ChartCard(week: List<Report.Day>) {
    val p = LocalPalette.current
    HanziCard(padding = 12) {
        Row(
            Modifier
                .fillMaxWidth()
                .height(120.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.Bottom
        ) {
            week.forEach { d ->
                Column(
                    Modifier
                        .weight(1f)
                        .fillMaxHeight(),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    // 柱子上面的数字是当天认识的字；空的就留白，不写 0
                    Text(
                        if (d.learned > 0) "${d.learned}" else "",
                        fontSize = 10.sp,
                        color = p.ink3,
                        modifier = Modifier.height(14.dp)
                    )
                    Box(
                        Modifier
                            .weight(1f)
                            .fillMaxWidth(),
                        contentAlignment = Alignment.BottomCenter
                    ) {
                        if (d.active) {
                            Box(
                                Modifier
                                    .testTag("report-bar-${d.daysAgo}")
                                    // 比例最小 0.08（见 Report.withRatios），
                                    // 在这个高度里约 8dp，柱子不会细得看不见
                                    .fillMaxHeight(d.ratio.coerceIn(0.0, 1.0).toFloat())
                                    // 撑满列宽（与 iOS 一致）：固定 18dp 时
                                    // 七根细柱孤零零地立在宽屏上，像没画完的草图
                                    .fillMaxWidth(0.62f)
                                    .clip(RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp))
                                    .background(if (d.daysAgo == 0) p.jade else p.jadeSoft)
                            )
                        } else {
                            Box(
                                Modifier
                                    .fillMaxWidth()
                                    .height(1.dp)
                                    .background(p.line)
                            )
                        }
                    }
                    Spacer(Modifier.height(5.dp))
                    Text(
                        d.weekday,
                        fontSize = 11.sp,
                        fontWeight = if (d.daysAgo == 0) FontWeight.Bold else FontWeight.Normal,
                        color = if (d.daysAgo == 0) p.jade else p.ink3
                    )
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            "柱子上面的数字是当天认识的字",
            modifier = Modifier.fillMaxWidth(),
            fontSize = 11.sp,
            color = p.ink3,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun StatsCard(sum: Report.Summary) {
    val p = LocalPalette.current
    HanziCard(padding = 14) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            StatCell("${sum.learned}", "认识的字", Modifier.weight(1f))
            StatCell("${sum.answers}", "答题数", Modifier.weight(1f))
            // 没答题就显示「—」，不是 0%：0% 会让家长以为孩子全答错了
            StatCell(
                sum.accuracy?.let { "$it" } ?: "—",
                sum.accuracy?.let { "正确率 %" } ?: "没答题",
                Modifier.weight(1f)
            )
            StatCell("${sum.activeDays}", "学了几天", Modifier.weight(1f))
        }
    }
}

@Composable
private fun StatCell(num: String, label: String, modifier: Modifier = Modifier) {
    val p = LocalPalette.current
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(num, fontSize = 21.sp, fontWeight = FontWeight.Bold, color = p.ink1)
        Spacer(Modifier.height(2.dp))
        Text(label, fontSize = 10.sp, color = p.ink3, textAlign = TextAlign.Center)
    }
}

@Composable
private fun DayRow(d: Report.Day) {
    val p = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            when (d.daysAgo) {
                0 -> "今天"
                1 -> "昨天"
                else -> d.weekday
            },
            modifier = Modifier.width(48.dp),
            fontSize = 13.sp,
            fontWeight = if (d.daysAgo == 0) FontWeight.Bold else FontWeight.Normal,
            color = if (d.daysAgo == 0) p.jade else p.ink2
        )
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "${d.learned} 字",
                fontSize = 14.sp,
                color = if (d.learned > 0) p.ink1 else p.ink3
            )
            Spacer(Modifier.width(8.dp))
            Text(
                if (d.answers > 0) "${d.answers} 题" else "没答题",
                fontSize = 11.sp,
                color = p.ink3
            )
        }
        Text(
            d.accuracy?.let { "$it%" } ?: "—",
            fontSize = 13.sp,
            color = if (d.active) p.ink2 else p.ink3
        )
    }
}
