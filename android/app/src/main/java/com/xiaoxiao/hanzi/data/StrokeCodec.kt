package com.xiaoxiao.hanzi.data

import org.json.JSONObject

/**
 * 笔顺二进制解码器。
 *
 * 与 scripts/build-data.mjs 的编码格式一一对应，与小程序 utils/stroke-codec.js 等价：
 *
 *   u8  version(3)
 *   u8  strokeCount
 *   strokeCount × { u16 byteLength(小端), pathBytes }
 *   pathBytes: [op, coords...]，op: 0=M 1=L 2=Q 3=C 4=Z，坐标 = 原坐标 / SCALE(6)
 *   u8  medianCount
 *   medianCount × { u8 pointCount, [x,y] × pointCount }
 *
 * 坐标在构建时已翻转为屏幕坐标（y' = 900 - y），解码后直接可用于 Canvas。
 */
object StrokeCodec {
    const val VERSION = 3
    const val SCALE = 6

    const val OP_M = 0
    const val OP_L = 1
    const val OP_Q = 2
    const val OP_C = 3
    const val OP_Z = 4

    /** 一条绘制指令：op 加坐标（坐标个数由 op 决定） */
    class Cmd(val op: Int, val coords: FloatArray)

    /** 一个字的完整笔顺 */
    class CharStrokes(
        val count: Int,
        val strokes: List<List<Cmd>>,
        val medians: List<FloatArray>
    )

    fun decode(base64: String): CharStrokes {
        val buf = Base64.decode(base64)
        var p = 0
        val version = buf[p++].toInt()
        require(version == VERSION) { "笔顺数据版本不支持: $version" }
        val n = buf[p++].toInt()

        val strokes = ArrayList<List<Cmd>>(n)
        repeat(n) {
            val len = (buf[p].toInt() and 0xFF) or ((buf[p + 1].toInt() and 0xFF) shl 8)
            p += 2
            val end = p + len
            val cmds = ArrayList<Cmd>()
            while (p < end) {
                val op = buf[p++].toInt()
                when (op) {
                    OP_M, OP_L -> {
                        cmds.add(Cmd(op, floatArrayOf(c(buf[p++]), c(buf[p++]))))
                    }
                    OP_Q -> {
                        cmds.add(
                            Cmd(
                                op,
                                floatArrayOf(c(buf[p++]), c(buf[p++]), c(buf[p++]), c(buf[p++]))
                            )
                        )
                    }
                    OP_C -> {
                        cmds.add(
                            Cmd(
                                op,
                                floatArrayOf(
                                    c(buf[p++]), c(buf[p++]),
                                    c(buf[p++]), c(buf[p++]),
                                    c(buf[p++]), c(buf[p++])
                                )
                            )
                        )
                    }
                    OP_Z -> cmds.add(Cmd(op, FloatArray(0)))
                    else -> throw IllegalArgumentException("未知路径指令: $op")
                }
            }
            strokes.add(cmds)
        }

        val medianCount = buf[p++].toInt()
        val medians = ArrayList<FloatArray>(medianCount)
        repeat(medianCount) {
            val pc = buf[p++].toInt()
            val pts = FloatArray(pc * 2)
            for (j in 0 until pc) {
                pts[j * 2] = c(buf[p++])
                pts[j * 2 + 1] = c(buf[p++])
            }
            medians.add(pts)
        }

        return CharStrokes(n, strokes, medians)
    }

    private fun c(v: Byte): Float = (v.toInt() and 0xFF) * SCALE.toFloat()
}

/** 极简 base64 解码：避免为一行数据引入 android.util.Base64 的 API 依赖 */
object Base64 {
    private val TABLE = IntArray(128) { -1 }.apply {
        val chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        chars.forEachIndexed { i, ch -> this[ch.code] = i }
    }

    fun decode(s: String): ByteArray {
        val clean = s.filter { it != '\n' && it != '\r' && it != ' ' }
        var pad = 0
        for (i in clean.indices.reversed()) {
            if (clean[i] == '=') pad++ else break
        }
        val outLen = (clean.length / 4) * 3 - pad
        val out = ByteArray(outLen)
        var o = 0
        var i = 0
        while (i + 3 < clean.length) {
            val c0 = TABLE[clean[i].code]
            val c1 = TABLE[clean[i + 1].code]
            val c2 = if (clean[i + 2] == '=') 0 else TABLE[clean[i + 2].code]
            val c3 = if (clean[i + 3] == '=') 0 else TABLE[clean[i + 3].code]
            val triple = (c0 shl 18) or (c1 shl 12) or (c2 shl 6) or c3
            if (o < outLen) out[o++] = ((triple shr 16) and 0xFF).toByte()
            if (o < outLen) out[o++] = ((triple shr 8) and 0xFF).toByte()
            if (o < outLen) out[o++] = (triple and 0xFF).toByte()
            i += 4
        }
        return out
    }
}
