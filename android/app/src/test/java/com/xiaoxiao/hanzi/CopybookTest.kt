package com.xiaoxiao.hanzi

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import com.xiaoxiao.hanzi.logic.Store
import com.xiaoxiao.hanzi.logic.Progress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 我的字帖。
 *
 * 与 iOS `testWriteRecordsSortByRecentThenScore` 等断言对应：
 * 排序规则、星级分档、空状态在三端必须一致，否则同一个账号
 * 在不同设备上看到的字帖顺序会不一样。
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CopybookTest {

    private fun progress(): Progress {
        val app = ApplicationProvider.getApplicationContext<Application>()
        return Progress(Store(app))
    }

    @Test
    fun `同一天写的按分数降序排列`() {
        val prog = progress()
        prog.saveWrite("天", 90)
        prog.saveWrite("地", 50)
        prog.saveWrite("人", 90)

        val all = prog.allWriteRecords()
        assertEquals(3, all.size)
        // 同分时按字稳定排序，保证测试可复现
        assertEquals(listOf("人", "天", "地"), all.map { it.first })
        assertEquals(90, all.first().second.best)
    }

    @Test
    fun `星级分档`() {
        val prog = progress()
        // 85/65/40 是星级门槛：>=85 三星、>=65 两星、>=40 一星
        prog.saveWrite("甲", 90)
        prog.saveWrite("乙", 85)
        prog.saveWrite("丙", 70)
        prog.saveWrite("丁", 39)

        val h = prog.writeStarsHistogram()
        assertEquals(2, h[3])
        assertEquals(1, h[2])
        assertEquals(0, h[1])
        assertEquals(1, h[0])
        assertEquals(4, prog.writeCount())
    }

    @Test
    fun `空状态四个档位都在`() {
        val prog = progress()
        val h = prog.writeStarsHistogram()
        // 页面上直接取四格画，缺键会读到 null 变成空白
        for (k in 0..3) assertEquals(0, h[k])
        assertEquals(0, prog.writeCount())
        assertTrue(prog.allWriteRecords().isEmpty())
    }
}
