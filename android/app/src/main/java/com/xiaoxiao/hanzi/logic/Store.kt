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

    /**
     * 当前孩子档案的命名空间，空串 = 默认档案。
     *
     * 默认档案用空串，键名和加档案功能之前完全一样（`progress`、`write`…），
     * 老用户升级上来数据原地不动。后建的档案用 `p2`、`p3`，键变成 `p2:progress`。
     * 与小程序 utils/store.js 的 keyOf 一致。
     */
    private var ns: String = ""

    fun setProfile(id: String) {
        ns = id
    }

    fun currentProfile(): String = ns

    /** 拼出真正的存储键（测试用，方便断言兼容性） */
    fun keyOf(name: String): String = if (ns.isEmpty()) name else "$ns:$name"

    fun readJson(name: String): JSONObject? {
        val raw = prefs.getString(keyOf(name), null) ?: return null
        if (raw.isEmpty()) return null
        return try {
            JSONObject(raw)
        } catch (e: Exception) {
            null
        }
    }

    fun writeJson(name: String, value: JSONObject) {
        prefs.edit().putString(keyOf(name), value.toString()).commit()
    }

    fun remove(name: String) {
        prefs.edit().remove(keyOf(name)).commit()
    }

    /**
     * 清空**当前档案**的数据。
     *
     * 不能连别的档案一起清——「清空学习记录」是清这个孩子的记录，
     * 一键把弟弟的进度也清掉是不可接受的。档案表本身（`profiles`）也保留。
     *
     * 早先这里图省事写成了「全清，再把 profiles 放回去」，
     * 结果默认档案一点「清空」，`p2:progress` 这些键一起没了——
     * 弟弟的进度被哥哥的「清空」连坐。测试抓到之后改成按命名空间删。
     */
    fun clearAll() {
        val prefix = if (ns.isEmpty()) "" else "$ns:"
        val edit = prefs.edit()
        for (k in prefs.all.keys) {
            if (k == "profiles") continue
            if (prefix.isEmpty()) {
                // 默认档案只清**不带前缀**的键，`p2:xxx` 属于别的孩子
                if (!k.contains(":")) edit.remove(k)
            } else if (k.startsWith(prefix)) {
                edit.remove(k)
            }
        }
        edit.commit()
    }

    /** 删掉某个档案的全部数据（该档案被删除时调用） */
    /*
     * 档案表本身是**全局**的，不能带命名空间——
     * 它是「有哪些档案」的元数据，属于整个 app 而不是某个孩子。
     * 带前缀的话切一次档案档案表就找不到了。
     */

    fun readJsonUnscoped(name: String): JSONObject? {
        val raw = prefs.getString(name, null) ?: return null
        if (raw.isEmpty()) return null
        return try {
            JSONObject(raw)
        } catch (e: Exception) {
            null
        }
    }

    fun writeJsonUnscoped(name: String, value: JSONObject) {
        prefs.edit().putString(name, value.toString()).commit()
    }

    fun clearProfile(id: String) {
        val prefix = if (id.isEmpty()) "" else "$id:"
        val edit = prefs.edit()
        for (k in prefs.all.keys) {
            if (k == "profiles") continue
            if (prefix.isEmpty()) {
                if (!k.contains(":")) edit.remove(k)
            } else if (k.startsWith(prefix)) {
                edit.remove(k)
            }
        }
        edit.commit()
    }
}
