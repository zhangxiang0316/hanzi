package com.xiaoxiao.hanzi.ui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing

/**
 * 动效参数。
 *
 * 一条硬约束：**本 App 只做「一次性、会结束」的动画，不做常驻循环动画**
 * （不用 rememberInfiniteTransition 做呼吸、漂浮、持续脉冲）。两个原因：
 *
 *   1. 产品上：面向一二年级，持续动效会分散注意力，也更费电；动画的作用是
 *      「说明发生了什么」，而不是一直晃。
 *   2. 工程上：测试里有 86 处 waitForIdle()，而它会一直等到合成完全静止。
 *      一旦存在无限动画，这些测试会全部挂到超时。
 *
 * 时长统一放这里，避免各页面各写一套、节奏忽快忽慢。
 */
object Motion {

    /** 状态翻转，比如按钮按下、勾选出现 */
    const val QUICK = 150

    /** 颜色过渡，比如答题选项变绿/变红 */
    const val NORMAL = 220

    /** 进度条从 0 长到目标值：稍慢一点才看得出「涨」的过程 */
    const val PROGRESS = 700

    /** 星星逐个弹出的间隔 */
    const val STAR_STAGGER = 110

    /** 单颗星从缩小到回弹到位的时间 */
    const val STAR_POP = 300

    /** 缓出：起步快、收尾稳，符合"东西落到位"的直觉 */
    val EaseOut: Easing = CubicBezierEasing(0.2f, 0f, 0f, 1f)
}
