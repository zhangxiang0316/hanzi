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

    val line = Color(0xFFE9DFCD)
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
    val lineSoft: Color = HanziColors.lineSoft,
    val track: Color = HanziColors.track
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
