package com.xiaoxiao.hanzi.ui

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Plan
import com.xiaoxiao.hanzi.logic.Progress
import com.xiaoxiao.hanzi.logic.Store

/**
 * 全局应用状态。
 *
 * 相当于小程序里散落在各页 data 中的那部分共享状态（进度、设置、当前册）。
 * 小程序每次 onShow 都要重新 setData，这里用 mutableStateOf 包一层，
 * 写入即触发重组，页面不用再手动刷新。
 */
class AppState(app: Application) {

    val store = Store(app)
    val progress = Progress(store)
    val nav = Navigator()

    /** 进度版本号：任何写操作后 +1，驱动页面重组 */
    var revision by mutableStateOf(0)
        private set

    // 不能叫 book：Kotlin 会给 var book 生成 setBook(String)，
    // 与下面手写的 setBook(id) 冲突（小程序侧不存在这个概念）
    var currentBook: String by mutableStateOf(progress.settings.book)
        private set

    init {
        Repo.ensureLoaded(app)
        // 设置里存的册次可能已经不存在（比如降级安装），兜底回默认册
        if (Repo.book(currentBook) == null) currentBook = Repo.defaultBook()
    }

    fun touch() {
        revision++
    }

    fun setBook(id: String) {
        currentBook = id
        progress.updateSettings(progress.settings.copy(book = id))
        touch()
    }

    fun setDailyNew(n: Int) {
        progress.updateSettings(progress.settings.copy(dailyNew = n))
        touch()
    }

    fun setShowPinyin(v: Boolean) {
        progress.updateSettings(progress.settings.copy(showPinyin = v))
        touch()
    }

    fun todayTask(): Plan.TodayTask = Plan.buildTodayTask(progress, currentBook)

    fun resetAll() {
        progress.resetAll()
        currentBook = Repo.defaultBook()
        touch()
    }
}
