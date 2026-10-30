import SwiftUI

/// 静态汉字视图：田字格 + 淡灰底字 + 笔画。
///
/// 把「画什么」和「画到第几笔」分开：调用方传 `completed` / `partial`，
/// 视图只负责渲染。动画版见 `HanziPlayerView`。
struct HanziView: View {
    let ch: String
    var strokes: StrokeCodec.CharStrokes?
    var showGrid: Bool = true
    var showGhost: Bool = true
    var showNumbers: Bool = false
    /// nil 表示全部写完
    var completed: Int? = nil
    /// 当前这一笔的进度 0...1
    var partial: CGFloat = 0
    var inkColor: Color = HanziDraw.ink

    var body: some View {
        Canvas { ctx, size in
            let box = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - box) / 2, y: (size.height - box) / 2)

            if showGrid {
                HanziDraw.drawGrid(&ctx, box: box, origin: origin)
            }

            guard let strokes, strokes.count > 0 else {
                // 没有笔顺数据时退回字体轮廓。用墨色而不是淡灰：
                // 既然描不了红，至少要让人看清这是什么字。
                HanziDraw.drawGlyphChar(&ctx, ch: ch, box: box, origin: origin, color: inkColor)
                return
            }

            if showGhost {
                HanziDraw.drawGhostChar(&ctx, strokes, box: box, origin: origin)
            }

            HanziDraw.drawStrokes(
                &ctx, strokes, box: box, origin: origin,
                completed: completed, partial: partial,
                inkColor: inkColor, showGhost: false
            )

            if showNumbers {
                HanziDraw.drawStrokeNumbers(&ctx, strokes, box: box, origin: origin)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        strokes == nil ? "汉字 \(ch)，暂无笔顺数据" : "汉字 \(ch)，共 \(strokes!.count) 笔"
    }
}

/// 逐笔动画播放。
///
/// 用 `TimelineView(.animation)` 而不是给每笔挂 `withAnimation`：
/// 笔画数量不定、每笔时长要精确可控，时间轴驱动更容易做「播到一半暂停」
/// 和「跳回某一笔」——描红页需要这两种能力。
struct HanziPlayerView: View {
    let ch: String
    var strokes: StrokeCodec.CharStrokes?
    var showGrid: Bool = true
    var showGhost: Bool = true
    var showNumbers: Bool = false
    var inkColor: Color = HanziDraw.ink

    @State private var startedAt = Date()
    @State private var paused = false
    @State private var pausedElapsed: Double = 0
    /// 播完一遍后是否自动重播
    var loop: Bool = false
    /// 非 nil 时只播到第 n 笔就停（详情页「学这一笔」用）
    var stopAfter: Int? = nil
    var onFinish: (() -> Void)? = nil

    var body: some View {
        TimelineView(.animation(paused: paused && !loop)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(startedAt) + pausedElapsed)
            let state = Self.state(at: elapsed, count: strokes?.count ?? 0,
                                   stopAfter: stopAfter, loop: loop)

            Canvas { ctx, size in
                let box = min(size.width, size.height)
                let origin = CGPoint(x: (size.width - box) / 2, y: (size.height - box) / 2)

                if showGrid {
                    HanziDraw.drawGrid(&ctx, box: box, origin: origin)
                }

                guard let strokes, strokes.count > 0 else {
                    HanziDraw.drawGlyphChar(&ctx, ch: ch, box: box, origin: origin,
                                            color: inkColor)
                    return
                }

                if showGhost {
                    HanziDraw.drawGhostChar(&ctx, strokes, box: box, origin: origin)
                }

                HanziDraw.drawStrokes(
                    &ctx, strokes, box: box, origin: origin,
                    completed: state.completed, partial: state.partial,
                    inkColor: inkColor, showGhost: false
                )

                if showNumbers {
                    HanziDraw.drawStrokeNumbers(&ctx, strokes, box: box, origin: origin)
                }
            }
            .task(id: state.finished) {
                if state.finished, !loop, !paused { onFinish?() }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { restart() }
    }

    struct PlaybackState: Equatable {
        let completed: Int
        let partial: CGFloat
        let finished: Bool
    }

    /// 给定已播放秒数，算出画到第几笔、这一笔画了多少
    static func state(at elapsed: Double, count: Int, stopAfter: Int?, loop: Bool) -> PlaybackState {
        guard count > 0 else { return PlaybackState(completed: 0, partial: 0, finished: true) }
        let limit = min(stopAfter ?? count, count)
        let per = HanziCanvas.perStrokeMs / 1000
        let gap = HanziCanvas.strokeGapMs / 1000
        let slot = per + gap
        let total = Double(limit) * slot

        if elapsed >= total {
            if loop {
                let t = elapsed.truncatingRemainder(dividingBy: total)
                return state(at: t, count: count, stopAfter: stopAfter, loop: false)
            }
            return PlaybackState(completed: limit, partial: 0, finished: true)
        }

        let index = Int(elapsed / slot)
        let within = elapsed - Double(index) * slot
        let raw = min(max(within / per, 0), 1)

        // 起笔略快、收笔略慢，比匀速更像写字。
        // 缓动只影响观感，不影响任何判分——判分用的是用户自己的笔迹。
        let eased = CGFloat(1 - pow(1 - raw, 1.6))

        if index >= limit {
            return PlaybackState(completed: limit, partial: 0, finished: true)
        }
        return PlaybackState(completed: index, partial: eased, finished: false)
    }

    func restart() {
        startedAt = Date()
        pausedElapsed = 0
        paused = false
    }

    func togglePause() {
        if paused {
            startedAt = Date()
            paused = false
        } else {
            pausedElapsed += Date().timeIntervalSince(startedAt)
            paused = true
        }
    }
}
