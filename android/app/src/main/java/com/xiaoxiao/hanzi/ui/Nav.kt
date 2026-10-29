package com.xiaoxiao.hanzi.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * 路由。
 *
 * 小程序侧有 9 个主包页面 + 3 个分包各 2 个页面（详情/描红），
 * 但分包页面是同一份逻辑的薄壳（只是携带不同年级的笔顺数据），
 * 到 Android 侧数据已经合并，所以实际只有 9 个目的地 —— 比小程序少 4 个。
 */
sealed class Screen {
    object Index : Screen()
    object Practice : Screen()
    object Profile : Screen()
    data class Unit(val book: String) : Screen()
    data class Lesson(val id: String) : Screen()
    data class Detail(val ch: String, val lesson: String?) : Screen()
    data class Write(val ch: String) : Screen()
    data class Quiz(val mode: String, val book: String, val lesson: String?) : Screen()
    data class Result(
        val correct: Int,
        val total: Int,
        val wrongChars: List<String>,
        val mode: String,
        val book: String
    ) : Screen()
    object Wrong : Screen()
    object About : Screen()
}

/** 三个 tab 根页面：只有它们显示底部导航 */
private val TAB_ROOTS = setOf(Screen.Index, Screen.Practice, Screen.Profile)

/**
 * 极简返回栈。
 *
 * 没有引 navigation-compose：这个 App 只有 11 个目的地、没有深链接、
 * 没有跨栈共享 ViewModel 的需求，一个 List + 两个方法足够，
 * 也省掉一个版本要和 Compose BOM 对齐的依赖。
 */
class Navigator {
    private val stack = mutableStateListOf<Screen>(Screen.Index)
    var current by mutableStateOf<Screen>(Screen.Index)
        private set

    val canGoBack: Boolean get() = stack.size > 1

    fun push(screen: Screen) {
        stack.add(screen)
        current = screen
    }

    /** 回到某个 tab 根：清空到该根为止（相当于小程序 switchTab） */
    fun switchTab(screen: Screen) {
        if (stack.size == 1 && stack[0] == screen) return
        stack.clear()
        stack.add(screen)
        current = screen
    }

    /**
     * 用新页面替换栈顶，不增加栈深度。
     * 详情页「上一个/下一个」用它：连翻 20 个字不应该需要按 20 次返回。
     */
    fun replace(screen: Screen) {
        if (stack.isEmpty()) {
            stack.add(screen)
        } else {
            stack[stack.size - 1] = screen
        }
        current = screen
    }

    /** 返回上一页；到根了就返回 false 交给系统处理 */
    fun back(): Boolean {
        if (stack.size <= 1) return false
        stack.removeAt(stack.size - 1)
        current = stack.last()
        return true
    }

    fun size(): Int = stack.size
}

fun isTabRoot(screen: Screen): Boolean = TAB_ROOTS.contains(screen)
