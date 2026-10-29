package com.xiaoxiao.hanzi.logic

import java.util.Calendar
import java.util.Date

/** 日期工具：以「本地自然日」为单位的编号，与小程序 utils/day.js 一致 */
object DayUtil {
    const val DAY_MS = 86_400_000L

    fun dayNumber(date: Date = Date()): Int {
        val cal = Calendar.getInstance()
        cal.time = date
        val offsetMs = cal.get(Calendar.ZONE_OFFSET) + cal.get(Calendar.DST_OFFSET)
        return ((date.time + offsetMs) / DAY_MS).toInt()
    }

    private fun pad(n: Int): String = if (n < 10) "0$n" else "$n"

    fun todayKey(date: Date = Date()): String {
        val cal = Calendar.getInstance()
        cal.time = date
        // Calendar 的月份从 0 开始
        return "${cal.get(Calendar.YEAR)}-${pad(cal.get(Calendar.MONTH) + 1)}-${pad(cal.get(Calendar.DAY_OF_MONTH))}"
    }

    fun yesterdayKey(date: Date = Date()): String =
        todayKey(Date(date.time - DAY_MS))

    fun weekdayCN(date: Date = Date()): String {
        // Calendar.DAY_OF_WEEK: 1=周日 … 7=周六；与 JS getDay() 的 0-6 对应
        val names = listOf("日", "一", "二", "三", "四", "五", "六")
        val cal = Calendar.getInstance()
        cal.time = date
        return "周" + names[cal.get(Calendar.DAY_OF_WEEK) - 1]
    }

    fun dateLabel(date: Date = Date()): String {
        val cal = Calendar.getInstance()
        cal.time = date
        return "${cal.get(Calendar.MONTH) + 1}月${cal.get(Calendar.DAY_OF_MONTH)}日"
    }

    fun greeting(date: Date = Date()): String {
        val cal = Calendar.getInstance()
        cal.time = date
        return when (cal.get(Calendar.HOUR_OF_DAY)) {
            in 0..5 -> "夜深了"
            in 6..10 -> "早上好"
            in 11..13 -> "中午好"
            in 14..17 -> "下午好"
            else -> "晚上好"
        }
    }

    fun dayKeyOf(offsetDays: Int): String {
        val cal = Calendar.getInstance()
        cal.add(Calendar.DAY_OF_MONTH, offsetDays)
        return todayKey(cal.time)
    }

    fun dateOfOffset(offsetDays: Int): Date {
        val cal = Calendar.getInstance()
        cal.add(Calendar.DAY_OF_MONTH, offsetDays)
        return cal.time
    }
}
