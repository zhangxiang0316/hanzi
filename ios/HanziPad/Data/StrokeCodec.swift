import Foundation

/// 笔顺二进制解码器。
///
/// 与 Android 侧 `data/StrokeCodec.kt`、小程序 `utils/stroke-codec.js` 必须逐字节等价：
///
///     u8  version(3)
///     u8  strokeCount
///     strokeCount × { u16 byteLength(小端), pathBytes }
///     pathBytes: [op, coords...]，op: 0=M 1=L 2=Q 3=C 4=Z，
///               每字节存 (原坐标 / SCALE(6))，解码时乘回 SCALE 还原 0..1024
///     u8  medianCount
///     medianCount × { u8 pointCount, [x,y] × pointCount }
///
/// 坐标在构建时已翻转为屏幕坐标（y' = 900 - y），解码后直接可用于 Canvas。
enum StrokeCodec {
    static let version: UInt8 = 3
    static let scale: Float = 6

    static let opM: UInt8 = 0
    static let opL: UInt8 = 1
    static let opQ: UInt8 = 2
    static let opC: UInt8 = 3
    static let opZ: UInt8 = 4

    /// 一条绘制指令：op 加坐标
    struct Cmd {
        let op: UInt8
        let coords: [Float]
    }

    /// 一个字的完整笔顺
    struct CharStrokes {
        let count: Int
        let strokes: [[Cmd]]
        /// 每一笔的中线折线，扁平存放 [x0,y0,x1,y1,...]
        let medians: [[Float]]
    }

    enum DecodeError: Error {
        case badBase64
        case unsupportedVersion(UInt8)
        case truncated
    }

    static func decode(base64: String) throws -> CharStrokes {
        guard let data = Data(base64Encoded: base64) else {
            throw DecodeError.badBase64
        }
        return try decode(data: data)
    }

    static func decode(data: Data) throws -> CharStrokes {
        // 用数组按下标读，比 Data 的切片方便；2.4MB 全量解码也只发生一次
        let buf = [UInt8](data)
        var p = 0

        func need(_ n: Int) throws {
            if p + n > buf.count { throw DecodeError.truncated }
        }

        try need(1)
        let ver = buf[p]; p += 1
        if ver != version { throw DecodeError.unsupportedVersion(ver) }

        try need(1)
        let n = Int(buf[p]); p += 1

        var strokes: [[Cmd]] = []
        strokes.reserveCapacity(n)

        for _ in 0..<n {
            try need(2)
            let len = Int(buf[p]) | (Int(buf[p + 1]) << 8)
            p += 2
            try need(len)
            let end = p + len

            var cmds: [Cmd] = []
            while p < end {
                let op = buf[p]; p += 1
                switch op {
                case opM, opL:
                    try need(2)
                    cmds.append(Cmd(op: op, coords: [
                        Float(buf[p]) * scale, Float(buf[p + 1]) * scale
                    ]))
                    p += 2
                case opQ:
                    try need(4)
                    cmds.append(Cmd(op: op, coords: [
                        Float(buf[p]) * scale, Float(buf[p + 1]) * scale,
                        Float(buf[p + 2]) * scale, Float(buf[p + 3]) * scale
                    ]))
                    p += 4
                case opC:
                    try need(6)
                    cmds.append(Cmd(op: op, coords: [
                        Float(buf[p]) * scale, Float(buf[p + 1]) * scale,
                        Float(buf[p + 2]) * scale, Float(buf[p + 3]) * scale,
                        Float(buf[p + 4]) * scale, Float(buf[p + 5]) * scale
                    ]))
                    p += 6
                case opZ:
                    cmds.append(Cmd(op: op, coords: []))
                default:
                    throw DecodeError.truncated
                }
            }
            // 对齐到 end（防御：编码若留了填充字节）
            p = end
            strokes.append(cmds)
        }

        try need(1)
        let medianCount = Int(buf[p]); p += 1
        var medians: [[Float]] = []
        medians.reserveCapacity(medianCount)
        for _ in 0..<medianCount {
            try need(1)
            let ptCount = Int(buf[p]); p += 1
            try need(ptCount * 2)
            var arr: [Float] = []
            arr.reserveCapacity(ptCount * 2)
            for _ in 0..<ptCount {
                arr.append(Float(buf[p]) * scale)
                arr.append(Float(buf[p + 1]) * scale)
                p += 2
            }
            medians.append(arr)
        }

        return CharStrokes(count: n, strokes: strokes, medians: medians)
    }
}
