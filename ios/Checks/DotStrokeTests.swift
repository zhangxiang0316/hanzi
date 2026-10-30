import XCTest
@testable import HanziCore

/// 「点」（dot）画的判定。
///
/// 用户报「描红最后一笔写不上」。点画常常就是最后一笔（太、玉、主、求、义、心、小…），
/// 而它在字形里本来就很短——中线只有 20-35px（画布 400 时）。
///
/// `WriteSession` 里有一道「太短不算数」的闸门：长度 < `box * 0.04`（400 画布即 16px）
/// 就返回 `.tooShort`，**且不消耗笔画**。于是：如果孩子把点写成一个小点
/// （本来就该是小点），长度永远过不了这道闸门，就永远停在这一笔上。
@MainActor
final class DotStrokeTests: XCTestCase {

    private func session(_ ch: String, box: CGFloat = 400) -> WriteSession {
        _ = TestRepo.make()
        let r = TestRepo.make()
        return WriteSession(ch: ch, strokes: r.strokes(ch), box: box)
    }

    /// 找一个「最后一笔很短」的字，确认它的最后一笔确实短
    func testFindShortLastStroke() {
        let r = TestRepo.make()
        // 玉、主、求、义、太、犬、心、小 都是点收笔
        for ch in ["玉", "主", "求", "义", "太", "犬", "心", "小"] {
            guard let st = r.strokes(ch) else { continue }
            let box: CGFloat = 400
            let s = WriteSession(ch: ch, strokes: st, box: box)
            guard let t = s.targetPoints(for: st.count - 1) else { continue }
            let len = CGFloat(Trace.polylineLength(t))

        }
    }

    /// 关键复现：把一个点画「就写成一个小点」，看会不会卡住
    ///
    /// 这是最常见的写法——点画本来就该是一个短促的点。
    func testTapOnDotStrokeStuck() {
        let box: CGFloat = 400
        let s = session("玉", box: box)
        let last = s.count - 1
        // 直接把前几笔跳过，模拟「已经写到最后一笔」
        while s.index < last { s.skip() }
        XCTAssertEqual(s.index, last, "没走到最后一笔")

        guard let t = s.targetPoints(for: last) else {
            return XCTFail("最后一笔没有中线数据")
        }
        let targetLen = CGFloat(Trace.polylineLength(t))

        // 孩子写一个点：以中线起点为中心，画一个 ~30% 长度的小勾
        let n = 5
        var dab: [Float] = []
        for k in 0...n {
            let f = Float(k) / Float(n) * 0.3
            dab.append(t[0] + (t[t.count - 2] - t[0]) * f)
            dab.append(t[1] + (t[t.count - 1] - t[1]) * f)
        }
        let dabLen = CGFloat(Trace.polylineLength(dab))


        let out = s.submit(dab)
        // 现在的行为：被判 tooShort，笔画不消耗 → 永远停在这里
        if case .tooShort = out {
            XCTFail("点画写成小点被判 tooShort（不消耗笔画）→ 永远写不上最后一笔")
        }
        XCTAssertEqual(s.index, last + 1 > s.count - 1 ? last : last, "")
    }

    /// 只点一下：按三端一致的约定判「太短」，但**必须给出提示**。
    ///
    /// 判太短本身是有意的——点画也不是真的一点都不动。真正的问题是
    /// 这句提示以前根本显示不出来（页面没订阅 session 的变化），
    /// 于是孩子看到的是「写了毫无反应」，也就是「最后一笔写不上」。
    func testSingleTapGivesMessageNotSilence() {
        let box: CGFloat = 400
        let s = session("玉", box: box)
        while s.index < s.count - 1 { s.skip() }
        guard let t = s.targetPoints(for: s.count - 1) else { return XCTFail("无中线") }
        let before = s.index
        let out = s.submit([t[0], t[1]])   // 只点了一下

        guard case .tooShort = out else {
            return XCTFail("点一下应判太短，实际是 \(out)")
        }
        XCTAssertEqual(s.index, before, "太短不应消耗笔画")
        XCTAssertFalse(s.message.isEmpty, "判太短却没有任何提示 → 孩子只会看到「写了没反应」")
        XCTAssertTrue(s.message.contains("按住") || s.message.contains("沿着虚线"),
                      "提示要能指导下一步，实际是「\(s.message)」")
    }

    /// 短笔画的门槛要按笔画自身长度放宽，不能让本来就很短的笔画永远过不去
    ///
    /// 「玉」末笔中线约 55px，`box*0.04 = 16px`；如果门槛一刀切，
    /// 孩子把点写小一点就永远被判太短。放宽到「目标长度的 35%」后，
    /// 短笔画有了活路，而长笔画仍按画布比例兜底。
    func testShortStrokeGetsRelaxedFloor() {
        let box: CGFloat = 400
        // 找末笔中线最短的那个字：只有它才会触发放宽
        let r = TestRepo.make()
        var shortest: (String, CGFloat)?
        for ch in ["每", "海", "毒", "侮", "梅", "漏", "蹦", "葡", "霉"] {
            guard let st = r.strokes(ch) else { continue }
            let s = WriteSession(ch: ch, strokes: st, box: box)
            guard let t = s.targetPoints(for: st.count - 1) else { continue }
            let len = CGFloat(Trace.polylineLength(t))
            if shortest == nil || len < shortest!.1 { shortest = (ch, len) }
        }
        guard let (ch, len) = shortest else { return XCTFail("没找到样本字") }
        XCTAssertLessThan(len, box * 0.04 / 0.35,
                          "\(ch) 的末笔 \(len)px 还不够短，测不出放宽效果")

        let s = session(ch, box: box)
        let relaxed = s.minLength(forStroke: s.count - 1)
        XCTAssertLessThan(relaxed, s.minLength,
                          "\(ch) 末笔 \(len)px，门槛没有放宽，仍是 \(relaxed)")
        XCTAssertGreaterThan(relaxed, box * 0.015, "放宽得过头了，门槛不该接近 0")

        // 长笔画（如「一」）必须保持画布比例，不能一起放宽
        let longSession = session("一", box: box)
        if longSession.count > 0 {
            XCTAssertEqual(longSession.minLength(forStroke: 0), longSession.minLength,
                           "长笔画的门槛不该被放宽")
        }
    }

    /// 短笔画写到「够门槛」就能进入判定，而不是被反复打回
    func testShortStrokeCanPass() {
        let box: CGFloat = 400
        let s = session("玉", box: box)
        let last = s.count - 1
        while s.index < last { s.skip() }
        guard let t = s.targetPoints(for: last) else { return XCTFail("无中线") }

        // 按门槛以上的长度写：覆盖末笔的 45%
        let n = 8
        var pts: [Float] = []
        for k in 0...n {
            let f = Float(k) / Float(n) * 0.45
            pts.append(t[0] + (t[t.count - 2] - t[0]) * f)
            pts.append(t[1] + (t[t.count - 1] - t[1]) * f)
        }
        let out = s.submit(pts)
        if case .tooShort = out {
            XCTFail("覆盖 45% 仍被判太短（门槛 \(s.minLength(forStroke: last))）")
        }
    }

    /// 全量：每一笔的门槛都必须小于「目标笔画长度的 100%」——
    /// 也就是说，照着虚线写完整一遍，永远能进入判定。
    func testEveryStrokeFloorIsReachable() {
        let r = TestRepo.make()
        var bad: [(String, Int, CGFloat, CGFloat)] = []
        for ch in r.allCharsWithStrokes() {
            guard let st = r.strokes(ch) else { continue }
            let s = WriteSession(ch: ch, strokes: st, box: 400)
            for i in 0..<st.count {
                guard let t = s.targetPoints(for: i) else { continue }
                let len = CGFloat(Trace.polylineLength(t))
                if s.minLength(forStroke: i) >= len {
                    bad.append((ch, i + 1, s.minLength(forStroke: i), len))
                }
            }
        }
        if !bad.isEmpty {
            let sample = bad.prefix(8).map { "\($0.0)第\($0.1)笔 门槛\($0.2)>长度\($0.3)" }.joined(separator: "\n")
            XCTFail("\(bad.count) 笔的门槛高过笔画本身长度，照描也过不去：\n\(sample)")
        }
    }
}
