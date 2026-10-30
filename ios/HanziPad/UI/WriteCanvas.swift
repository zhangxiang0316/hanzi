import SwiftUI

/// 描红画布：田字格 + 底字 + 已写笔画 + 用户当前笔迹。
///
/// 触点采集用 `DragGesture(minimumDistance: 0)`。
/// 默认的拖拽手势要等超过滑动阈值才回调 `onChanged`，笔画开头的几毫米会被吞掉；
/// 描红恰恰最讲究起笔位置，那个位置直接参与评分。设成 0 就能从按下那一刻开始采样。
struct WriteCanvas: View {
    @ObservedObject var session: WriteSession
    /// 当前正在写的笔迹（画布坐标），抬手后清空
    @Binding var current: [Float]
    let onStrokeEnd: ([Float]) -> Void

    var body: some View {
        GeometryReader { geo in
            let box = min(geo.size.width, geo.size.height)
            let origin = CGPoint(x: (geo.size.width - box) / 2,
                                 y: (geo.size.height - box) / 2)

            Canvas { ctx, _ in
                HanziDraw.drawGrid(&ctx, box: box, origin: origin)

                guard let strokes = session.strokes else {
                    HanziDraw.drawGlyphChar(&ctx, ch: session.ch, box: box, origin: origin)
                    return
                }

                // 底字：与判分中线同一批轮廓
                HanziDraw.drawGhostChar(&ctx, strokes, box: box, origin: origin)

                // 已完成的笔画实心，当前这一笔的轮廓用配色提示
                for i in 0..<min(session.index, strokes.count) {
                    let p = Path(HanziCanvas.path(for: strokes.strokes[i], box: box, origin: origin))
                    ctx.fill(p, with: .color(HanziDraw.ink))
                }

                // 当前笔的起点红点：告诉孩子从哪儿起笔
                if !session.isDone, session.index < strokes.count,
                   let target = session.targetPoints(for: session.index),
                   target.count >= 2 {
                    let x = origin.x + CGFloat(target[0])
                    let y = origin.y + CGFloat(target[1])
                    let r = max(box * 0.018, 4)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(.red.opacity(0.75)))
                }

                // 用户笔迹
                if current.count >= 4 {
                    var path = Path()
                    path.move(to: CGPoint(x: origin.x + CGFloat(current[0]),
                                          y: origin.y + CGFloat(current[1])))
                    var k = 2
                    while k < current.count {
                        path.addLine(to: CGPoint(x: origin.x + CGFloat(current[k]),
                                                 y: origin.y + CGFloat(current[k + 1])))
                        k += 2
                    }
                    ctx.stroke(path, with: .color(HanziDraw.accent),
                               style: StrokeStyle(lineWidth: max(box * 0.055, 8),
                                                  lineCap: .round, lineJoin: .round))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                // minimumDistance: 0 —— 从按下就开始采样，别丢掉起笔
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !session.isDone else { return }
                        current.append(Float(value.location.x - origin.x))
                        current.append(Float(value.location.y - origin.y))
                    }
                    .onEnded { _ in
                        guard !session.isDone else { return }
                        let pts = StrokeSmoothing.smooth(current)
                        let clean = StrokeSmoothing.dedupe(pts)
                        current = []
                        onStrokeEnd(clean)
                    }
            )
            .onAppear { session.updateBox(box) }
            .onChange(of: box) { _, newBox in session.updateBox(newBox) }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 描红页主体：状态机 + 画布 + 提示条。M5 接进导航后直接复用。
struct WritePadView: View {
    @ObservedObject private var session: WriteSession
    @State private var current: [Float] = []
    private let onSave: ((Int) -> Void)?

    init(ch: String, strokes: StrokeCodec.CharStrokes?, onSave: ((Int) -> Void)? = nil) {
        _session = ObservedObject(
            wrappedValue: WriteSession(ch: ch, strokes: strokes, box: 400))
        self.onSave = onSave
    }

    /// 用外部会话构造，便于自检脚本驱动同一套 UI 与判定链路
    init(session: WriteSession, onSave: ((Int) -> Void)? = nil) {
        _session = ObservedObject(wrappedValue: session)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            WriteCanvas(session: session, current: $current) { pts in
                handle(session.submit(pts))
            }
            .id(session.index)   // 换笔时重置画布手势，避免上一笔的终点被当成新笔起点
            .frame(maxWidth: 560, maxHeight: 560)

            footer
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.984, green: 0.965, blue: 0.925))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text(session.ch).font(.system(size: 34, weight: .semibold))
            if let m = Repo.shared.meta(session.ch) {
                Text(m.py).font(.title3).foregroundStyle(HanziDraw.accent)
            }
            Spacer()
            Text("第 \(min(session.index + 1, session.count)) / \(session.count) 笔")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 560)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if !session.message.isEmpty {
                Label(session.message, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            } else if !session.isDone {
                Text("沿着淡灰色的字，按笔顺慢慢写")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("重写") {
                    session.restart()
                    current = []
                }
                .buttonStyle(.bordered)

                Button("跳过这一笔") { session.skip() }
                    .buttonStyle(.bordered)
                    .disabled(session.isDone)

                Spacer()

                if session.isDone {
                    Button("完成") {
                        onSave?(session.finalScore)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HanziDraw.accent)
                }

                // 自检：不碰触摸，直接把「沿中线的完美笔迹」喂进和手势同一个回调。
                // 用来确认「采集 → 平滑 → 判定」这条链路通，而不只是状态机单测通。
                Button("自检描一遍") {
                    autoTrace()
                }
                .buttonStyle(.bordered)
                .disabled(session.isDone)
            }
            .frame(maxWidth: 560)
        }
        .animation(.easeOut(duration: 0.2), value: session.message)
        .animation(.easeOut(duration: 0.2), value: session.isDone)
    }

    private func handle(_ outcome: WriteSession.Outcome) {
        // 结果由 session 的 @Published 状态驱动界面，
        // 这里只留一个钩子给「写完保存」用
        if case .finished(let score, _) = outcome {
            onSave?(score)
        }
    }

    /// 沿当前笔的中线造一条笔迹，走与手势完全相同的处理路径
    private func autoTrace() {
        guard let target = session.targetPoints(for: session.index) else { return }
        let pts = StrokeSmoothing.dedupe(StrokeSmoothing.smooth(target))
        handle(session.submit(pts))
    }
}
