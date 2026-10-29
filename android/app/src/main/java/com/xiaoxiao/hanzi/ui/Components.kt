package com.xiaoxiao.hanzi.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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

/**
 * 通用组件。
 *
 * 小程序里这些是 WXSS 的类（.card / .btn-primary / .chip），
 * 搬到 Compose 就变成 @Composable 函数，命名保持一致方便对照。
 */

@Composable
fun HanziCard(
    modifier: Modifier = Modifier,
    padding: Int = 16,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit
) {
    val p = LocalPalette.current
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Dimens.radiusCard.dp),
        color = p.card,
        border = BorderStroke(1.dp, p.line.copy(alpha = 0.8f))
    ) {
        Column(Modifier.padding(padding.dp), content = content)
    }
}

enum class BtnStyle { Primary, Ghost, Soft }

/**
 * 按钮。
 *
 * 小程序踩过的坑：`button.btn { background: transparent }` 的优先级压过了
 * `.btn-primary`，导致一堆按钮变成白底白字、完全看不见。
 * 这里用单一函数 + 显式配色，从根本上不可能出现「底色和文字同色」。
 */
@Composable
fun HanziButton(
    text: String,
    modifier: Modifier = Modifier,
    style: BtnStyle = BtnStyle.Primary,
    enabled: Boolean = true,
    fillWidth: Boolean = true,
    /** 测试用标记，方便按几何位置断言按钮本身而不是里面的文字 */
    tag: String? = null,
    onClick: () -> Unit
) {
    val p = LocalPalette.current
    val bg = when (style) {
        BtnStyle.Primary -> if (enabled) p.jade else p.ink3.copy(alpha = 0.35f)
        BtnStyle.Ghost -> Color.Transparent
        BtnStyle.Soft -> p.jadeSoft
    }
    val fg = when (style) {
        BtnStyle.Primary -> Color.White
        BtnStyle.Ghost -> p.ink2
        BtnStyle.Soft -> p.jadeDeep
    }
    Surface(
        modifier = modifier
            .then(if (fillWidth) Modifier.fillMaxWidth() else Modifier)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .clip(RoundedCornerShape(14.dp))
            .clickable(enabled = enabled, onClick = onClick),
        shape = RoundedCornerShape(14.dp),
        color = bg,
        border = if (style == BtnStyle.Ghost) BorderStroke(1.dp, p.line) else null
    ) {
        Box(
            Modifier
                .height(48.dp)
                .then(if (fillWidth) Modifier.fillMaxWidth() else Modifier)
                .padding(horizontal = 20.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = fg,
                textAlign = TextAlign.Center
            )
        }
    }
}

/** 进度条，对应小程序 .progress / .progress-fill */
@Composable
fun ProgressBar(
    pct: Int,
    modifier: Modifier = Modifier,
    color: Color = LocalPalette.current.jade,
    height: Int = 8
) {
    val p = LocalPalette.current
    Box(
        modifier
            .fillMaxWidth()
            .height(height.dp)
            .clip(CircleShape)
            .background(p.track)
    ) {
        Box(
            Modifier
                .fillMaxWidth((pct.coerceIn(0, 100)) / 100f)
                .height(height.dp)
                .clip(CircleShape)
                .background(color)
        )
    }
}

/** 小标签，对应小程序里的 .pill / .chip */
@Composable
fun TinyPill(
    text: String,
    color: Color,
    modifier: Modifier = Modifier,
    bg: Color = color.copy(alpha = 0.14f)
) {
    Box(
        modifier
            .clip(RoundedCornerShape(999.dp))
            .background(bg)
            .padding(horizontal = 10.dp, vertical = 4.dp)
    ) {
        Text(text, fontSize = 12.sp, color = color, fontWeight = FontWeight.Medium)
    }
}

/** 区块标题，对应 .section-head / .section-title */
@Composable
fun SectionHead(
    title: String,
    sub: String? = null,
    trailing: @Composable (() -> Unit)? = null
) {
    val p = LocalPalette.current
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = 22.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = p.ink1)
            if (sub != null) {
                Spacer(Modifier.height(2.dp))
                Text(sub, fontSize = 12.sp, color = p.ink3)
            }
        }
        trailing?.invoke()
    }
}

/** 空状态，对应 .empty */
@Composable
fun EmptyState(emoji: String, title: String, desc: String? = null, modifier: Modifier = Modifier) {
    val p = LocalPalette.current
    Column(
        modifier
            .fillMaxWidth()
            .padding(vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(emoji, fontSize = 34.sp)
        Spacer(Modifier.height(10.dp))
        Text(title, fontSize = 15.sp, color = p.ink2, textAlign = TextAlign.Center)
        if (desc != null) {
            Spacer(Modifier.height(6.dp))
            Text(desc, fontSize = 13.sp, color = p.ink3, textAlign = TextAlign.Center)
        }
    }
}

/** 星级，用于描红成绩 */
@Composable
fun Stars(count: Int, size: Int = 16) {
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        repeat(3) { i ->
            Text(
                if (i < count) "★" else "☆",
                fontSize = size.sp,
                color = if (i < count) LocalPalette.current.amber else LocalPalette.current.line
            )
        }
    }
}

/** 分隔线 */
@Composable
fun HairLine(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(LocalPalette.current.lineSoft)
    )
}

/** 圆形图标按钮（返回键用） */
@Composable
fun RoundIconButton(onClick: () -> Unit, content: @Composable () -> Unit) {
    val p = LocalPalette.current
    Box(
        Modifier
            .size(36.dp)
            .clip(CircleShape)
            .background(p.card)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) { content() }
}
