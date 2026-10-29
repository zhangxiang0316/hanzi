package com.xiaoxiao.hanzi.logic

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * 描红评分，与小程序 utils/trace.js 逐行对应。
 *
 * 思路：把用户笔迹点与目标笔画中线比对
 *   - 起点距离、终点距离（是否按正确方向起笔收笔）
 *   - 用户点到中线的平均距离（覆盖得好不好）
 *   - 中线上每个点到用户笔迹的距离（防止只点一下就得高分）
 *   - 用户笔迹长度与中线长度比（是否拖泥带水）
 */
object Trace {

    /** 单笔通过分，低于这个分要求重写这一笔 */
    const val ACCEPT = 42

    /** 加权系数，改动会影响手感，与小程序保持一致 */
    private const val W_START = 0.18f
    private const val W_END = 0.12f
    private const val W_COVER = 0.32f
    private const val W_REACH = 0.26f
    private const val W_LENGTH = 0.12f

    class Result(val score: Int, val reason: String)

    fun dist(ax: Float, ay: Float, bx: Float, by: Float): Float {
        val dx = ax - bx
        val dy = ay - by
        return sqrt(dx * dx + dy * dy)
    }

    fun polylineLength(pts: FloatArray): Float {
        var len = 0f
        var i = 2
        while (i < pts.size) {
            len += dist(pts[i - 2], pts[i - 1], pts[i], pts[i + 1])
            i += 2
        }
        return len
    }

    /** 点到折线的最短距离 */
    fun pointToPolyline(px: Float, py: Float, poly: FloatArray): Float {
        var best = Float.MAX_VALUE
        var i = 2
        while (i < poly.size) {
            val ax = poly[i - 2]
            val ay = poly[i - 1]
            val bx = poly[i]
            val by = poly[i + 1]
            val vx = bx - ax
            val vy = by - ay
            val wx = px - ax
            val wy = py - ay
            val len2 = vx * vx + vy * vy
            var t = if (len2 != 0f) (wx * vx + wy * vy) / len2 else 0f
            t = max(0f, min(1f, t))
            val d = dist(px, py, ax + vx * t, ay + vy * t)
            if (d < best) best = d
            i += 2
        }
        return best
    }

    /** 重采样为等距点，减少采样频率差异带来的误差 */
    fun resample(pts: FloatArray, step: Float): FloatArray {
        val n = pts.size / 2
        if (n < 2) return pts.copyOf()
        val out = ArrayList<Float>(pts.size)
        out.add(pts[0]); out.add(pts[1])
        var carry = 0f
        var ax = pts[0]
        var ay = pts[1]
        var idx = 1
        while (idx < n) {
            val bx = pts[idx * 2]
            val by = pts[idx * 2 + 1]
            var seg = dist(ax, ay, bx, by)
            if (seg == 0f) { idx++; continue }
            while (carry + seg >= step) {
                val t = (step - carry) / seg
                val nx = ax + (bx - ax) * t
                val ny = ay + (by - ay) * t
                out.add(nx); out.add(ny)
                ax = nx; ay = ny
                seg = dist(ax, ay, bx, by)
                carry = 0f
            }
            carry += seg
            ax = bx; ay = by
            idx++
        }
        val lastX = pts[(n - 1) * 2]
        val lastY = pts[(n - 1) * 2 + 1]
        val outArr = out.toFloatArray()
        val outN = outArr.size / 2
        if (dist(outArr[(outN - 1) * 2], outArr[(outN - 1) * 2 + 1], lastX, lastY) > step * 0.4f) {
            return outArr + floatArrayOf(lastX, lastY)
        }
        return outArr
    }

    private fun clamp01(v: Float): Float = max(0f, min(1f, v))

    /**
     * @param userPts 用户笔画，扁平化 [x0,y0,x1,y1,...]，画布像素坐标
     * @param targetPts 目标中线，同坐标系
     * @param tolerance 允许偏差像素，默认 26（与小程序一致）
     */
    fun scoreStroke(userPts: FloatArray?, targetPts: FloatArray?, tolerance: Float = 26f): Result {
        if (userPts == null || userPts.size < 4) return Result(0, "empty")
        if (targetPts == null || targetPts.size < 4) return Result(0, "no-target")

        val step = max(3f, tolerance * 0.35f)
        val user = resample(userPts, step)
        val target = resample(targetPts, step)

        val startD = dist(user[0], user[1], target[0], target[1])
        val endD = dist(
            user[user.size - 2], user[user.size - 1],
            target[target.size - 2], target[target.size - 1]
        )
        val startScore = clamp01(1f - startD / (tolerance * 2.2f))
        val endScore = clamp01(1f - endD / (tolerance * 2.2f))

        var sum = 0f
        var i = 0
        while (i < user.size) {
            sum += pointToPolyline(user[i], user[i + 1], target)
            i += 2
        }
        val avg = sum / (user.size / 2)
        val coverScore = clamp01(1f - avg / tolerance)

        var sum2 = 0f
        i = 0
        while (i < target.size) {
            sum2 += pointToPolyline(target[i], target[i + 1], user)
            i += 2
        }
        val reachScore = clamp01(1f - sum2 / (target.size / 2) / tolerance)

        val lu = polylineLength(user)
        val lt = polylineLength(target)
        val ratio = if (lt > 0f) lu / lt else 0f
        val lengthScore = if (ratio >= 0.75f && ratio <= 1.45f) 1f
        else clamp01(1f - abs(1f - ratio) / 0.85f)

        val raw = startScore * W_START + endScore * W_END + coverScore * W_COVER +
            reachScore * W_REACH + lengthScore * W_LENGTH
        val score = Math.round(clamp01(raw) * 100)

        val reason = when {
            startScore < 0.45f -> "start"
            coverScore < 0.45f -> "off"
            reachScore < 0.45f -> "short"
            else -> "ok"
        }
        return Result(score, reason)
    }

    class CharResult(val score: Int, val stars: Int)

    /** 整字评分：各笔平均，但有一笔特别差会扣分，避免「乱画也高分」 */
    fun scoreChar(scores: List<Int>): CharResult {
        if (scores.isEmpty()) return CharResult(0, 0)
        var total = 0
        var minScore = 100
        for (s in scores) {
            total += s
            if (s < minScore) minScore = s
        }
        val avg = total.toFloat() / scores.size
        val score = Math.round(avg * 0.85f + minScore * 0.15f)
        val stars = if (score >= 85) 3 else if (score >= 65) 2 else if (score >= 40) 1 else 0
        return CharResult(score, stars)
    }

    fun starsOf(score: Int): Int = if (score >= 85) 3 else if (score >= 65) 2 else if (score >= 40) 1 else 0
}
