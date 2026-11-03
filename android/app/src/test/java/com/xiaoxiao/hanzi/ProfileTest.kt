package com.xiaoxiao.hanzi

import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.logic.ProfileManager
import com.xiaoxiao.hanzi.logic.Progress
import com.xiaoxiao.hanzi.logic.Store
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 多孩子档案。
 *
 * 一间屋里两个孩子共用一个平板学字是常态。之前所有数据挤在一套键里，
 * 弟弟写几个字就把哥哥的进度、错题本、描红星级全搅在一起。
 *
 * 最要紧的一条：**老用户升级上来不能丢进度**。默认档案的 id 是空串，
 * 键名和加档案功能之前完全一样。
 *
 * 与 iOS `ProfileTests`、小程序 `tests/profile.test.mjs` 对应。
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ProfileTest {

    private lateinit var store: Store

    private fun fresh(): Pair<ProfileManager, Progress> {
        store = Store(ApplicationProvider.getApplicationContext())
        store.clearAll()
        // 档案表本身也要清掉，否则上一个用例的档案会漏过来
        store.writeJsonUnscoped("profiles", org.json.JSONObject())
        val pm = ProfileManager(store)
        val prog = Progress(store)
        prog.resetAll()
        return pm to prog
    }

    /** 默认档案的键名必须和老版本完全一样，否则升级上来进度全丢 */
    @Test
    fun `默认档案的键名和老版本一致`() {
        val (pm, _) = fresh()
        assertEquals("", pm.activeId())
        assertEquals("progress", store.keyOf("progress"))
        assertEquals("write", store.keyOf("write"))
    }

    @Test
    fun `一开始有一个我`() {
        val (pm, _) = fresh()
        assertEquals(1, pm.count())
        assertEquals("我", pm.active().name)
    }

    @Test
    fun `两个档案的数据互不干扰`() {
        val (pm, prog) = fresh()
        prog.learn("日")
        assertEquals(1, prog.totalLearned())

        val p = pm.add("弟弟")!!
        assertTrue(pm.setActive(p.id))
        prog.reload()
        assertEquals("弟弟不该看到哥哥的进度", 0, prog.totalLearned())

        prog.learn("月")
        prog.saveWrite("月", 90)
        assertEquals(1, prog.totalLearned())

        assertTrue(pm.setActive(""))
        prog.reload()
        assertEquals(1, prog.totalLearned())
        assertFalse("弟弟学的字不该串到哥哥这边", prog.hasLearned("月"))
        assertNull(prog.writeRecord("月"))
    }

    @Test
    fun `错题本和薄弱点各自独立`() {
        val (pm, prog) = fresh()
        prog.grade("日", false, null)
        prog.recordStroke("日", 1, false)
        prog.recordStroke("日", 1, false)

        val p = pm.add("弟弟")!!
        pm.setActive(p.id)
        prog.reload()
        assertEquals("弟弟的错题本应该是空的", 0, prog.wrongCount())
        assertTrue(prog.allWeakStrokes().isEmpty())

        pm.setActive("")
        prog.reload()
        assertEquals(1, prog.wrongCount())
        assertEquals(1, prog.allWeakStrokes().size)
    }

    @Test
    fun `设置也各自独立`() {
        val (pm, prog) = fresh()
        val p = pm.add("妹妹")!!
        pm.setActive(p.id)
        prog.reload()
        prog.updateSettings(prog.settings.copy(book = "2a"))
        assertEquals("2a", prog.settings.book)

        pm.setActive("")
        prog.reload()
        assertEquals("哥哥的册次不该被改", "1a", prog.settings.book)
    }

    @Test
    fun `切换不存在的档案返回 false`() {
        val (pm, _) = fresh()
        assertFalse(pm.setActive("nope"))
        assertEquals("", pm.activeId())
        // 切到当前档案也返回 false，避免无意义的重载
        assertFalse(pm.setActive(""))
    }

    @Test
    fun `最多四个档案`() {
        val (pm, _) = fresh()
        assertEquals(4, ProfileManager.MAX)
        pm.add("老二")
        pm.add("老三")
        pm.add("老四")
        assertEquals(4, pm.count())
        assertFalse(pm.canAdd())
        assertNull(pm.add("老五"))
        assertEquals(4, pm.count())
    }

    @Test
    fun `名字去空格并截断到八字`() {
        val (pm, _) = fresh()
        assertEquals("小明", pm.add("  小明  ")!!.name)
        assertEquals(8, pm.add("一二三四五六七八九十")!!.name.length)
    }

    @Test
    fun `空名字给默认名`() {
        val (pm, _) = fresh()
        assertEquals("孩子2", pm.add("   ")!!.name)
    }

    @Test
    fun `改名`() {
        val (pm, _) = fresh()
        val p = pm.add("老二")!!
        assertTrue(pm.rename(p.id, " 弟弟 "))
        assertEquals("弟弟", pm.profiles().first { it.id == p.id }.name)
        // 空名字拒绝
        assertFalse(pm.rename(p.id, ""))
        assertEquals("弟弟", pm.profiles().first { it.id == p.id }.name)
    }

    @Test
    fun `可以改默认档案的名字`() {
        val (pm, _) = fresh()
        assertTrue(pm.rename("", "哥哥"))
        assertEquals("哥哥", pm.active().name)
    }

    @Test
    fun `删除档案会一起删掉它的数据`() {
        val (pm, prog) = fresh()
        val p = pm.add("弟弟")!!
        pm.setActive(p.id)
        prog.reload()
        prog.learn("月")
        prog.saveWrite("月", 88)

        pm.setActive("")
        prog.reload()
        val before = prog.totalLearned()

        pm.remove(p.id)
        prog.reload()
        assertEquals(before, prog.totalLearned())

        // 弟弟的键应该真的被清掉了
        store.setProfile(p.id)
        assertNull(store.readJson("progress"))
        store.setProfile("")
    }

    @Test
    fun `删掉当前档案会自动切到剩下的第一个`() {
        val (pm, prog) = fresh()
        val p = pm.add("弟弟")!!
        pm.setActive(p.id)
        prog.reload()
        assertEquals(p.id, pm.activeId())

        val next = pm.remove(p.id)
        assertEquals("应该切回默认档案", "", next)
        assertEquals("", pm.activeId())
    }

    @Test
    fun `删掉的不是当前档案时返回 null`() {
        val (pm, _) = fresh()
        val p = pm.add("弟弟")!!
        assertNull(pm.remove(p.id))
    }

    @Test
    fun `不允许删掉最后一个档案`() {
        val (pm, _) = fresh()
        assertEquals(1, pm.count())
        assertNull(pm.remove(""))
        assertEquals(1, pm.count())
    }

    @Test
    fun `清空学习记录只清当前档案`() {
        val (pm, prog) = fresh()
        val p = pm.add("弟弟")!!
        pm.setActive(p.id)
        prog.reload()
        prog.learn("月")

        pm.setActive("")
        prog.reload()
        prog.learn("日")
        prog.resetAll()
        assertEquals("当前档案应该清空", 0, prog.totalLearned())

        pm.setActive(p.id)
        prog.reload()
        assertEquals("弟弟的进度不该被清掉", 1, prog.totalLearned())
    }

    @Test
    fun `档案表能跨重启保留`() {
        val (pm, _) = fresh()
        val p = pm.add("弟弟")!!
        pm.rename(p.id, "小明")
        pm.setActive(p.id)

        // 新建一个 ProfileManager 读同一个 store，模拟重启
        val pm2 = ProfileManager(store)
        assertEquals(p.id, pm2.activeId())
        assertEquals("小明", pm2.active().name)
    }

    @Test
    fun `活跃档案指向已删除的档案时自动修正`() {
        val (pm, _) = fresh()
        val p = pm.add("弟弟")!!
        pm.setActive(p.id)
        // 手工把档案表改坏，模拟异常退出留下的脏数据
        val saved = store.readJsonUnscoped("profiles")!!
        val arr = org.json.JSONArray()
        val list = saved.getJSONArray("list")
        for (i in 0 until list.length()) {
            val o = list.getJSONObject(i)
            if (o.getString("id") != p.id) arr.put(o)
        }
        saved.put("list", arr)
        store.writeJsonUnscoped("profiles", saved)

        val pm2 = ProfileManager(store)
        assertEquals("应该回落到第一个档案", "", pm2.activeId())
    }

    @Test
    fun `档案表丢了也能恢复出默认档案`() {
        fresh()
        store.remove("profiles")
        val pm = ProfileManager(store)
        assertEquals(1, pm.count())
        assertEquals("", pm.activeId())
    }

    @Test
    fun `每个档案的 id 不重复`() {
        val (pm, _) = fresh()
        val a = pm.add("A")!!
        val b = pm.add("B")!!
        assertNotEquals(a.id, b.id)
        assertEquals(3, pm.count())
    }
}
