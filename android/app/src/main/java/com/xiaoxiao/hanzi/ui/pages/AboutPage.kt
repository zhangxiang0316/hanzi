package com.xiaoxiao.hanzi.ui.pages

import com.xiaoxiao.hanzi.BuildConfig
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaoxiao.hanzi.data.Repo
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import com.xiaoxiao.hanzi.ui.HanziGlyph
import com.xiaoxiao.hanzi.ui.Dimens
import com.xiaoxiao.hanzi.ui.FontSizes
import com.xiaoxiao.hanzi.ui.HanziCard
import com.xiaoxiao.hanzi.ui.LocalPalette

/** 关于与数据来源，对应小程序 pages/about/about */
@Composable
fun AboutPage() {
    val p = LocalPalette.current
    val total = Repo.allChars.size
    val books = Repo.books.size
    val lessons = Repo.books.sumOf { it.stat.lessons }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Dimens.pagePad.dp)
    ) {
        Spacer(Modifier.height(8.dp))

        // hero：与 iOS 一致——绿底圆角方块里一个白色的「字」，
        // 下面是名字 / 版本 / 一句话。
        // 原来这里只有两行字，摆在一起时 iOS 像「产品页」、
        // Android 像「设置项」。
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                Modifier
                    .size(88.dp)
                    .testTag("about-hero-icon")
                    .clip(RoundedCornerShape(22.dp))
                    .background(
                        Brush.linearGradient(
                            colors = listOf(p.jade, p.jadeDeep),
                            start = Offset.Zero,
                            end = Offset(200f, 200f)
                        )
                    ),
                contentAlignment = Alignment.Center
            ) {
                HanziGlyph("字", Modifier.size(62.dp), inkColor = Color.White)
            }
            Spacer(Modifier.height(10.dp))
            Text("小小识字家", fontSize = 21.sp, fontWeight = FontWeight.Bold, color = p.ink1)
            Spacer(Modifier.height(4.dp))
            Text(
                "v${BuildConfig.VERSION_NAME}",
                fontSize = FontSizes.caption.sp,
                color = p.ink3
            )
            Spacer(Modifier.height(6.dp))
            Text(
                "陪一二年级的小朋友，一笔一画认汉字",
                fontSize = FontSizes.bodySmall.sp,
                color = p.ink2,
                textAlign = TextAlign.Center
            )
        }

        Spacer(Modifier.height(18.dp))

        InfoCard("内容规模") {
            InfoRow("汉字", "$total 个")
            InfoRow("册次", "$books 册")
            InfoRow("课文", "$lessons 课")
            InfoRow("笔顺数据", "全部生字，逐笔路径")
        }

        Spacer(Modifier.height(12.dp))

        InfoCard("数据来源") {
            Body("生字表、识字表、写字表、组词依据统编版语文教材整理，仅供学习使用，不作商业用途。")
            Spacer(Modifier.height(8.dp))
            Body("汉字笔顺笔画路径来自 Make Me a Hanzi 开源项目（Arphic Public License），在其基础上按屏幕坐标做了翻转与压缩。")
        }

        Spacer(Modifier.height(12.dp))

        InfoCard("关于复习") {
            Body("用过艾宾浩斯间隔复习：一个字答对就推远一次复习，答错就拉回近期。")
            Spacer(Modifier.height(8.dp))
            Body("间隔依次是 0、1、2、4、7、15、30、60 天，连续答对 5 次以上算「已掌握」。")
        }

        Spacer(Modifier.height(12.dp))

        InfoCard("隐私") {
            Body("所有学习记录只保存在这台设备上，没有账号、没有联网上传、没有第三方统计。")
        }

        Spacer(Modifier.height(20.dp))
        Text(
            // 从构建产物读版本，别再写死——写死的那个 "v1.0.0" 在应用
            // 已经走到 1.0.7 之后仍然显示 1.0.0，页面上一直是错的。
            "v${BuildConfig.VERSION_NAME} · 内容仅供学习使用",
            fontSize = 11.sp,
            color = p.ink3,
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(24.dp))
    }
}

/**
 * 一张信息卡。
 *
 * 这里原本是手写的一份 Surface + 圆角 + 描边，等于把 `HanziCard` 又抄了一遍，
 * 而且抄漏了——它还在用 `line` 描边、16 内边距，而 `HanziCard` 已经改成
 * `edge` + 18 了。iOS 的 AboutPage 一直用的就是 `HanziCard`。
 * 直接复用组件，以后改卡片样式只改一处。
 */
@Composable
private fun InfoCard(
    title: String,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit
) {
    val p = LocalPalette.current
    HanziCard {
        Text(
            title,
            fontSize = FontSizes.sectionTitle.sp,
            fontWeight = FontWeight.SemiBold,
            color = p.ink1
        )
        Spacer(Modifier.height(10.dp))
        content()
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    val p = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, fontSize = 13.sp, color = p.ink2, modifier = Modifier.width(96.dp))
        Text(value, fontSize = 13.sp, color = p.ink1, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun Body(text: String) {
    val p = LocalPalette.current
    Text(text, fontSize = 12.sp, color = p.ink2, lineHeight = 20.sp)
}
