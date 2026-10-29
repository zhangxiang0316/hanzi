package com.xiaoxiao.hanzi.ui

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.xiaoxiao.hanzi.data.Repo
import com.xiaoxiao.hanzi.logic.Plan
import com.xiaoxiao.hanzi.logic.Progress
import com.xiaoxiao.hanzi.logic.Store
import com.xiaoxiao.hanzi.logic.Tts

/**
 * 全局应用状态。
 *
 * 相当于小程序里散落在各页 data 中的那部分共享状态（进度、设置、当前册）。
 * 小程序每次 onShow 都要重新 setData，这里用 mutableStateOf 包一层，
 * 写入即触发重组，页面不用再手动刷新。
 */
class AppState(app: Application, ttsFactory: ((() -> Unit) -> Tts)? = null) {

    val store = Store(app)
    val progress = Progress(store)
    val nav = Navigator()

    /** 进度版本号：任何写操作后 +1，驱动页面重组 */
    var revision by mutableStateOf(0)
        private set

    /**
     * 朗读。状态变化时 touch()，借现有的 revision 机制驱动页面重组，
     * 不需要为它单独再加一套监听。
     *
     * 必须声明在 revision 之后：注入的引擎可能在构造期就回调 onChange，
     * 那时 revision 的委托还没初始化，会直接 NPE。
     *
     * ttsFactory 只为测试注入假引擎（Robolectric 的 TTS shadow 恒为不可用，
     * 否则「就绪后点击真的会播」这条链路没法验证）。生产路径走系统 TTS。
     */
    val tts: Tts = ttsFactory?.invoke { touch() } ?: Tts.system(app) { touch() }

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
