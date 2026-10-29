package com.xiaoxiao.hanzi.logic

import android.content.Context
import android.speech.tts.TextToSpeech
import java.util.Locale

/**
 * 朗读引擎的最小抽象。
 *
 * 抽出来是为了能在 JVM 测试里换成假实现：Robolectric 的 ShadowTextToSpeech
 * 永远返回「不支持」且从不回调初始化，直接测真实引擎只能覆盖失败分支。
 */
interface TtsEngine {
    fun speak(text: String)
    fun stop()
    fun shutdown()
}

/** 造引擎；初始化完成后回调 READY / NO_CHINESE / FAILED（不会回 IDLE） */
fun interface TtsEngineFactory {
    fun create(onReady: (Tts.State) -> Unit): TtsEngine
}

/**
 * 朗读：把生字或词语念出来。
 *
 * 用系统自带的 TTS，和小程序侧必须外挂「微信同声传译」插件不同：不打包音频、
 * 不要权限、不要后端，APK 体积增长为 0。代价是发音质量取决于设备自带的语音包。
 *
 * 三个必须处理的现实问题：
 *   1. 设备不一定装了中文语音包（纯净 AOSP、部分模拟器、海外机型）。这时要明确
 *      进入 NO_CHINESE 让界面提示，绝不静默失败。
 *   2. 引擎初始化是异步的（真实设备上几十到几百毫秒）。用户可能在就绪前就点了
 *      朗读，所以用 pending 把文本存下来，就绪后补播。
 *   3. 必须 shutdown()。引擎绑定的是系统服务，不释放会一直占内存和占用音频焦点。
 *
 * 多音字的已知限制：TTS 只吃文本，喂拼音没用。给一个孤立的「长」字它只能自己猜，
 * 可能猜成课文里不该读的音。所以多字词的准确率明显高于单字，界面据此引导用户
 * 多点组词。
 */
class Tts(
    private val factory: TtsEngineFactory,
    private val onChange: () -> Unit = {}
) {

    private val listeners = mutableListOf<(State) -> Unit>()

    /**
     * 订阅状态变化，返回取消订阅的函数。
     *
     * 光靠 AppState.revision 不够：TTS 初始化是在 LaunchedEffect 里完成的，
     * 那次写入的 revision 有时拿不到，界面就停在「没有提示」的状态。
     * 界面要真正订阅这个状态，才能保证提示一定出现。
     */
    fun addListener(l: (State) -> Unit): () -> Unit {
        listeners += l
        return { listeners -= l }
    }

    enum class State {
        /** 引擎还没初始化 */
        IDLE,

        /** 可以朗读 */
        READY,

        /** 引擎起来了，但设备没有中文语音包 */
        NO_CHINESE,

        /** 引擎没起来 */
        FAILED
    }

    var state: State = State.IDLE
        private set

    /** 界面用：是否该显示「朗读不可用」的提示。IDLE 不算不可用，免得刚进页面闪一下 */
    val unavailable: Boolean
        get() = state == State.NO_CHINESE || state == State.FAILED

    private var engine: TtsEngine? = null

    /** 初始化未完成时用户点了朗读，先存着，就绪后补播 */
    private var pending: String? = null

    /** 正在 create 里：此时回调是同步的，得等 engine 赋值后再处理 */
    private var creating = false
    private var buffered: State? = null

    /** 状态只认第一次，引擎重复回调不重复播 */
    private var handled = false

    private fun setState(s: State) {
        if (state == s) return
        state = s
        // 先通知订阅者再 onChange：订阅者里可能直接读 state
        listeners.toList().forEach { it(s) }
        onChange()
    }

    /** 提前把引擎建好，让第一次点击就有声音。进详情页时调用 */
    fun warmUp() {
        ensureEngine()
    }

    private fun ensureEngine() {
        if (engine != null || handled) return
        creating = true
        val e = factory.create { st ->
            // 回调可能是同步的（假引擎/某些实现），那时 engine 还没赋值
            if (creating) buffered = st else onReady(st)
        }
        engine = e
        creating = false
        buffered?.let {
            buffered = null
            onReady(it)
        }
    }

    private fun onReady(st: State) {
        if (handled) return
        handled = true
        setState(st)
        val queued = pending
        pending = null
        // 只有就绪才补播；不可用时留着文本没意义
        if (st == State.READY && queued != null) engine?.speak(queued)
    }

    /** 朗读一句话。空串直接忽略 */
    fun speak(text: String) {
        val t = text.trim()
        if (t.isEmpty()) return
        when (state) {
            State.READY -> engine?.speak(t)
            // 还没就绪：存起来，等 onReady 补播
            State.IDLE -> {
                pending = t
                ensureEngine()
            }
            // 不可用时由界面常驻提示，这里不重试，免得点一次卡一次
            State.NO_CHINESE, State.FAILED -> Unit
        }
    }

    fun stop() {
        pending = null
        engine?.stop()
    }

    fun shutdown() {
        pending = null
        buffered = null
        handled = false
        engine?.stop()
        engine?.shutdown()
        engine = null
        if (state != State.IDLE) {
            state = State.IDLE
            onChange()
        }
    }

    companion object {

        /** 生产用：系统自带 TTS */
        fun system(context: Context, onChange: () -> Unit = {}): Tts =
            Tts({ onReady -> SystemTtsEngine(context, onReady) }, onChange)

        /**
         * 不可用时给用户看的话。null 表示正常，不显示提示。
         *
         * 放在这里而不是页面里，是为了能直接单测文案分支 —— 静默失败是
         * 朗读功能最难排查的问题，必须保证每种状态都有明确交代。
         */
        fun unavailableHint(state: State): String? = when (state) {
            State.NO_CHINESE ->
                "这台设备没装中文语音包，暂时读不出来。可以在系统设置里装一个中文 TTS"
            State.FAILED -> "朗读引擎没启动起来，暂时读不出来"
            State.IDLE, State.READY -> null
        }
    }
}

/**
 * 真实引擎：包一层系统 TextToSpeech。
 *
 * 语速 0.85 是给一二年级调的，比默认慢一点听得清。
 */
private class SystemTtsEngine(
    context: Context,
    private val onReady: (Tts.State) -> Unit
) : TtsEngine {

    private var tts: TextToSpeech? = null
    private var early: Int? = null
    private var built = false
    private var seq = 0

    init {
        val created = TextToSpeech(context.applicationContext) { status ->
            // TextToSpeech 的 init 在真机上一定是异步的（要绑服务），
            // 这里只是防止某些实现同步回调时 tts 还没赋值
            if (built) report(status) else early = status
        }
        tts = created
        built = true
        early?.let {
            early = null
            report(it)
        }
    }

    private fun report(status: Int) {
        val e = tts ?: return
        if (status != TextToSpeech.SUCCESS) {
            onReady(Tts.State.FAILED)
            return
        }
        if (e.isLanguageAvailable(Locale.SIMPLIFIED_CHINESE) < TextToSpeech.LANG_AVAILABLE) {
            onReady(Tts.State.NO_CHINESE)
            return
        }
        e.language = Locale.SIMPLIFIED_CHINESE
        e.setSpeechRate(RATE)
        onReady(Tts.State.READY)
    }

    override fun speak(text: String) {
        val e = tts ?: return
        seq++
        // QUEUE_FLUSH：连点几个组词时打断上一个，而不是排队念一串
        e.speak(text, TextToSpeech.QUEUE_FLUSH, null, "hanzi-$seq")
    }

    override fun stop() {
        tts?.stop()
    }

    override fun shutdown() {
        tts?.stop()
        tts?.shutdown()
        tts = null
    }

    private companion object {
        const val RATE = 0.85f
    }
}
