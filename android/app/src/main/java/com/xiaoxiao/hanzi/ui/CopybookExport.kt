package com.xiaoxiao.hanzi.ui

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.xiaoxiao.hanzi.logic.CopybookPDF
import java.io.File

/**
 * 生成字帖 PDF 并交给系统去打印 / 分享 / 存盘。
 *
 * 「我的字帖」和「选字做字帖」两个页面都要导出，逻辑一模一样，所以抽到这里。
 * 之前这段是抄在页面里的匿名 Thread 里，第二份拷贝几乎必然会漏掉某一步
 * （先写文件、再 FileProvider、最后 chooser），漏掉哪一步用户看到的都是
 * 「点了没反应」。
 *
 * 排版要遍历每个字的笔画轮廓，几百个字能到上百毫秒，放主线程会卡一下，
 * 所以放到后台线程，结果回主线程再弹系统面板。
 *
 * @param onResult 主线程回调：true 表示已经弹出分享面板，false 表示失败
 */
fun exportCopybook(context: Context, names: List<String>, onResult: (Boolean) -> Unit) {
    if (names.isEmpty()) {
        onResult(false)
        return
    }
    Thread {
        val bytes = try {
            CopybookPDF.build(names, dateLabel = CopybookPDF.dateLabel()).bytes
        } catch (e: Exception) {
            null
        }
        val uri = bytes?.let { b ->
            try {
                val dir = File(context.cacheDir, "copybook").apply { mkdirs() }
                val f = File(dir, CopybookPDF.fileName())
                f.writeBytes(b)
                FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", f)
            } catch (e: Exception) {
                null
            }
        }
        (context as? android.app.Activity)?.runOnUiThread {
            if (uri == null) {
                onResult(false)
            } else {
                // 用 chooser 而不是直接 ACTION_VIEW：
                // 家长可能想打印、想发到电脑、想存到网盘，让系统去列应用
                try {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "application/pdf"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    context.startActivity(Intent.createChooser(send, "字帖已生成"))
                    onResult(true)
                } catch (e: Exception) {
                    onResult(false)
                }
            }
        }
    }.start()
}
