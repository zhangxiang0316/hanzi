package com.xiaoxiao.hanzi.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * 设计 token，与小程序 app.wxss 里的 CSS 变量一一对应。
 *
 * 小程序用 var(--jade) 这类变量贯穿全部 WXSS；搬到 Compose 时
 * 最省事也最不容易跑偏的做法就是把这些变量原样搬成 Palette，
 * 页面里只引用语义名，不再出现字面色值。
 */
object HanziColors {
    val paper = Color(0xFFFBF6EC)
    val card = Color(0xFFFFFFFF)
    val cardWarm = Color(0xFFFDF9F0)

    val ink1 = Color(0xFF25332D)
    val ink2 = Color(0xFF5C6B62)
    val ink3 = Color(0xFF8C9A90)

    val jade = Color(0xFF3E8E7E)
    val jadeDeep = Color(0xFF2F7062)
    val jadeSoft = Color(0xFFE8F2EE)

    val amber = Color(0xFFE9A93C)
    val amberSoft = Color(0xFFFDF1DC)
    val clay = Color(0xFFDF6248)
    val claySoft = Color(0xFFFBE8E3)

    /** 第五种强调色（多音字入口），与 iOS Palette.sky 一致 */
    val sky = Color(0xFF5B8DB8)
    val skySoft = Color(0xFFE8F0F7)

    val line = Color(0xFFE9DFCD)

    /**
     * 可点击元素的边框。与 iOS 的 `Palette.edge` 同一个值。
     *
     * `line`（#E9DFCD）和纸色背景的对比度只有 1.23:1，画分隔线没问题，
     * 但拿来画按钮/字格的边框时孩子几乎看不见边界——iOS 端早就发现并修过
     * 这件事（见 AppTheme.swift 里 `edge` 的注释），Android 一直没跟，
     * 于是同样的「答题选项」在 iOS 上是有清楚描边的白底卡、在 Android 上
     * 是一团模糊的浅色。这个色对比度 2.23:1，配卡片底色就能看出边界。
     *
     * **可点的元素用 edge，纯装饰的分隔线才用 line。**
     */
    val edge = Color(0xFFB8A583)

    val lineSoft = Color(0xFFFAF5EB)
    val track = Color(0xFFF4EFE4)

    /** 册次颜色，与小程序 pages/index/index.js 的 BOOK_COLORS 一致 */
    fun bookColor(id: String): Color = when (id) {
        "1a" -> Color(0xFFE9A93C)
        "1b" -> Color(0xFFDF8A4A)
        "2a" -> Color(0xFF4F9E8D)
        "2b" -> Color(0xFF5A8FBF)
        "3a" -> Color(0xFF9B7FB8)
        "3b" -> Color(0xFFB8763F)
        "4a" -> Color(0xFF6F8FB8)
        "4b" -> Color(0xFF3F7D6A)
        else -> jade
    }
}

/** 圆角 token，对应 WXSS 里的 rpx 值（750rpx = 屏宽，1rpx 约 0.5dp） */
object Dimens {
    const val radiusCard = 20
    const val radiusInner = 14
    const val pagePad = 20
    const val gap = 12
}

/**
 * 字号 token。与 iOS 的 `Fonts` 一一对应。
 *
 * ## 为什么要有这一层
 *
 * iOS 端早就有 `Fonts.pageTitle / sectionTitle / body / bodySmall / caption`
 * 五级，页面里只引用语义名。Android 这边一直没有，各页面直接写
 * `fontSize = 13.sp`、`12.sp`、`11.sp`……同一个 App 里出现了 9～26 之间
 * 十几个互不相干的字号，而且**同一个视觉角色在不同页面用了不同的值**
 * （例如「页面说明文字」有的地方 12、有的地方 13）。
 *
 * 结果就是两端同一个元素字号对不上，改一处也没法全局生效。
 *
 * 下面这五级是按 iOS `Fonts` 的实际取值对齐的，新增页面请只用这些，
 * 别再写字面量。
 */
object FontSizes {
    /** 页面主标题。iOS `Fonts.pageTitle` = 26 */
    const val pageTitle = 26

    /** 区块标题。iOS `Fonts.sectionTitle` = 17 */
    const val sectionTitle = 17

    /** 正文。iOS `Fonts.body` = 15 */
    const val body = 15

    /** 次要正文。iOS `Fonts.bodySmall` = 13 */
    const val bodySmall = 13

    /** 说明/注解。iOS `Fonts.caption` = 12 */
    const val caption = 12
}

class Palette(
    val paper: Color = HanziColors.paper,
    val card: Color = HanziColors.card,
    val cardWarm: Color = HanziColors.cardWarm,
    val ink1: Color = HanziColors.ink1,
    val ink2: Color = HanziColors.ink2,
    val ink3: Color = HanziColors.ink3,
    val jade: Color = HanziColors.jade,
    val jadeDeep: Color = HanziColors.jadeDeep,
    val jadeSoft: Color = HanziColors.jadeSoft,
    val amber: Color = HanziColors.amber,
    val amberSoft: Color = HanziColors.amberSoft,
    val clay: Color = HanziColors.clay,
    val claySoft: Color = HanziColors.claySoft,
    val line: Color = HanziColors.line,
    /** 可点击元素的边框色，见 HanziColors.edge 的注释 */
    val edge: Color = HanziColors.edge,
    val lineSoft: Color = HanziColors.lineSoft,
    val track: Color = HanziColors.track,
    /** 第五种强调色（多音字、只认不写提示），与 iOS Palette.sky 一致 */
    val sky: Color = HanziColors.sky,
    val skySoft: Color = HanziColors.skySoft
)

val LocalPalette = staticCompositionLocalOf { Palette() }

private val scheme = lightColorScheme(
    primary = HanziColors.jade,
    onPrimary = Color.White,
    secondary = HanziColors.amber,
    onSecondary = Color.White,
    background = HanziColors.paper,
    onBackground = HanziColors.ink1,
    surface = HanziColors.card,
    onSurface = HanziColors.ink1,
    error = HanziColors.clay,
    outline = HanziColors.line
)

private val typography = Typography(
    // 中文正文行高给足，避免上下贴太紧
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 24.sp, color = HanziColors.ink1),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 21.sp, color = HanziColors.ink2),
    bodySmall = TextStyle(fontSize = 12.sp, lineHeight = 18.sp, color = HanziColors.ink3),
    titleLarge = TextStyle(fontSize = 20.sp, lineHeight = 28.sp, fontWeight = FontWeight.Bold, color = HanziColors.ink1),
    titleMedium = TextStyle(fontSize = 16.sp, lineHeight = 24.sp, fontWeight = FontWeight.SemiBold, color = HanziColors.ink1)
)

@Composable
fun HanziTheme(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalPalette provides Palette()) {
        MaterialTheme(
            colorScheme = scheme,
            typography = typography,
            content = content
        )
    }
}
