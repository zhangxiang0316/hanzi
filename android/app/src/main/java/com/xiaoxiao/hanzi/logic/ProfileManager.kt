package com.xiaoxiao.hanzi.logic

import org.json.JSONObject

/**
 * 多孩子档案。
 *
 * 一间屋里两个孩子共用一个平板学字是常态。之前所有数据挤在一套键里，
 * 弟弟写几个字就把哥哥的进度、错题本、描红星级全搅在一起，
 * 连「今天新学几个字」都算不对。
 *
 * ## 默认档案的 id 是空串
 *
 * 这一点很关键。老用户的数据存在 `progress`、`write` 这些键里，如果给默认
 * 档案编个 `main` 之类的 id，键就变成 `main:progress`，升级上来进度全丢。
 * 空串让默认档案的键**和以前完全一样**，后建的档案才加前缀（`p2`、`p3`）。
 *
 * ## 上限 4 个
 *
 * 再多就不是家庭共用而是班级共用了——那时该做的是账号体系，不是本地档案。
 *
 * 与小程序 utils/profile.js 行为一致。
 */
class ProfileManager(private val store: Store) {

    data class Profile(val id: String, val name: String)

    private var list: MutableList<Profile> = ArrayList()
    private var active: String = ""
    private var seq: Int = 2

    init {
        load()
        // 启动时把命名空间对上，之后 Progress 读的就是当前档案的数据
        store.setProfile(active)
    }

    /** 全部档案（按创建顺序，默认档案永远第一个） */
    fun profiles(): List<Profile> = list.map { Profile(it.id, it.name) }

    fun activeId(): String = active

    fun active(): Profile = list.firstOrNull { it.id == active } ?: list[0]

    fun count(): Int = list.size

    fun canAdd(): Boolean = list.size < MAX

    /**
     * 切换档案。返回 true 表示真的切了。
     *
     * 调用方必须紧接着重建/重载 Progress —— 存储的命名空间变了，
     * 但内存里那份还是上一个孩子的。
     */
    fun setActive(id: String): Boolean {
        if (id == active) return false
        if (list.none { it.id == id }) return false
        active = id
        persist()
        return true
    }

    /** 新建档案。名字去首尾空格、截断到 8 字，空名字给默认名。 */
    fun add(name: String?): Profile? {
        if (!canAdd()) return null
        val trimmed = (name ?: "").trim().take(8)
        val id = "p$seq"
        seq += 1
        val p = Profile(id, if (trimmed.isEmpty()) "孩子${list.size + 1}" else trimmed)
        list.add(p)
        persist()
        return p
    }

    /** 改名。默认档案也能改——「我」只是占位。 */
    fun rename(id: String, name: String?): Boolean {
        val p = list.firstOrNull { it.id == id } ?: return false
        val trimmed = (name ?: "").trim().take(8)
        if (trimmed.isEmpty()) return false
        val i = list.indexOfFirst { it.id == id }
        list[i] = Profile(p.id, trimmed)
        persist()
        return true
    }

    /**
     * 删除档案（连同它的全部数据）。
     *
     * 不允许删掉最后一个。删的如果是当前档案，自动切到剩下的第一个，
     * 并返回新的 active id（调用方据此决定要不要重载）；返回 null 表示没删成、
     * 或者删的不是当前档案、无需重载。
     */
    fun remove(id: String): String? {
        if (list.size <= 1) return null
        val i = list.indexOfFirst { it.id == id }
        if (i < 0) return null
        val wasActive = active == id
        list.removeAt(i)
        store.clearProfile(id)
        if (wasActive) active = list[0].id
        persist()
        return if (wasActive) active else null
    }

    // ---------- 序列化 ----------

    private fun load() {
        val obj = store.readJsonUnscoped(KEY)
        val l = ArrayList<Profile>()
        if (obj != null) {
            val arr = obj.optJSONArray("list")
            if (arr != null) {
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val id = o.optString("id")
                    val name = o.optString("name")
                    if (name.isEmpty()) continue
                    l.add(Profile(id, name))
                }
            }
            active = obj.optString("active")
            seq = obj.optInt("seq", 2).let { if (it >= 2) it else 2 }
        }
        // 至少留一个档案，否则界面无处可去
        if (l.isEmpty()) l.add(Profile("", DEFAULT_NAME))
        // 默认档案（id 空串）永远存在，否则老用户的数据成了孤儿
        if (l.none { it.id.isEmpty() }) l.add(0, Profile("", DEFAULT_NAME))
        list = l
        if (list.none { it.id == active }) active = list[0].id
    }

    private fun persist() {
        val arr = org.json.JSONArray()
        for (p in list) {
            arr.put(JSONObject().put("id", p.id).put("name", p.name))
        }
        store.writeJsonUnscoped(
            KEY,
            JSONObject().put("list", arr).put("active", active).put("seq", seq)
        )
        // 档案表一变就同步命名空间，避免「切了档案但还在写旧键」
        store.setProfile(active)
    }

    companion object {
        const val MAX = 4
        const val DEFAULT_NAME = "我"
        private const val KEY = "profiles"
    }
}
