package com.xiaoxiao.hanzi

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import com.xiaoxiao.hanzi.ui.AppState
import com.xiaoxiao.hanzi.ui.HanziTheme
import com.xiaoxiao.hanzi.ui.Root

class MainActivity : ComponentActivity() {

    /**
     * 提成字段是为了在 onDestroy 里释放 TTS 引擎。
     * 引擎绑定的是系统服务，不 shutdown 会一直占着内存和音频焦点。
     */
    private lateinit var state: AppState

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        // 状态栏透明 + 深色图标，配合米色纸背景
        window.statusBarColor = Color.Transparent.toArgb()
        window.navigationBarColor = Color.Transparent.toArgb()

        state = AppState(application)

        setContent {
            HanziTheme {
                val app = remember { state }
                Root(app)
            }
        }
    }

    override fun onDestroy() {
        if (::state.isInitialized) state.tts.shutdown()
        super.onDestroy()
    }
}
