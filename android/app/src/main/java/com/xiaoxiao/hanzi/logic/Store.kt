package com.xiaoxiao.hanzi.logic

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/**
 * 本地存储封装，对应小程序 utils/store.js。
 *
 * 小程序用 wx.setStorageSync 存 JS 对象，Android 侧用 SharedPreferences + JSON 字符串。
 * 数据量很小（进度条目按学过的字增长，2596 字全学完约 200KB），
 * 不值得上 Room/DataStore —— 单纯 KV 就够，还省掉线程切换的复杂度。
 *
 * 注意 SharedPreferences 的 apply() 是异步落盘，进程被杀时可能丢最后几次写。
 * 这里用 commit()：每次写入都是一次答题，丢一条会影响复习间隔，宁可慢一点。
 */
class Store(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("hanzi:v1", Context.MODE_PRIVATE)

    fun readJson(name: String): JSONObject? {
        val raw = prefs.getString(name, null) ?: return null
        if (raw.isEmpty()) return null
        return try {
            JSONObject(raw)
        } catch (e: Exception) {
            null
        }
    }

    fun writeJson(name: String, value: JSONObject) {
        prefs.edit().putString(name, value.toString()).commit()
    }

    fun remove(name: String) {
        prefs.edit().remove(name).commit()
    }

    fun clearAll() {
        prefs.edit().clear().commit()
    }
}
