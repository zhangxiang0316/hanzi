import SwiftUI

/// M4 探针：描红交互。选中一个字就能直接写。
struct M4ProbeView: View {
    @State private var ch = "天"

    private let samples = ["天", "地", "人", "永", "国", "一", "口", "十"]

    /// 启动时在后台跑一遍全链路自检，结果打到控制台。
    ///
    /// 沙箱里无法注入真实触摸事件，所以用「沿中线造一条笔迹、经过和小手势
    /// 完全相同的平滑/去重/判定路径」来验证接线。这不是 UI 测试的替代品，
    /// 但能证明「采集回调 → 状态机 → 评分」这条线是通的。
    private func runSelfCheck() {
        Task { @MainActor in
            var report: [String] = []
            for c in samples {
                guard let st = Repo.shared.strokes(c) else { continue }
                let s = WriteSession(ch: c, strokes: st, box: 400)
                var ok = 0
                while !s.isDone {
                    guard let target = s.targetPoints(for: s.index) else { break }
                    let pts = StrokeSmoothing.dedupe(StrokeSmoothing.smooth(target))
                    let outcome = s.submit(pts)
                    switch outcome {
                    case .passed, .finished: ok += 1
                    case .rejected(let r): report.append("\(c) 第\(s.index+1)笔 拒绝:\(r)"); break
                    case .tooShort: report.append("\(c) 第\(s.index+1)笔 太短"); break
                    }
                }
                report.append("\(c) \(ok)/\(s.count) 笔 → \(s.finalScore) 分 \(s.finalStars) 星")
            }
            let text = report.joined(separator: "\n")
            print("[M4 自检] " + text.replacingOccurrences(of: "\n", with: " | "))
            // 沙箱里读不到控制台，落盘再拉出来
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("m4-selfcheck.txt")
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("M4 描红").font(.title3.bold())
                Text("触点采集 · 平滑 · 逐笔判定")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()

                ForEach(samples, id: \.self) { c in
                    Button { ch = c } label: {
                        HStack {
                            Text(c).font(.system(size: 22, weight: .medium))
                            Spacer()
                            if let s = Repo.shared.strokes(c) {
                                Text("\(s.count) 笔").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(c == ch ? HanziDraw.accent.opacity(0.16) : .white)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(20)
            .frame(width: 240)
            .background(.white.opacity(0.5))

            Divider()

            WritePadView(ch: ch, strokes: Repo.shared.strokes(ch)) { score in
                print("[M4] \(ch) 得分 \(score)")
            }
            .id(ch)   // 换字时重建会话，避免残留上一笔的状态
            .onAppear { runSelfCheck() }
        }
    }
}
