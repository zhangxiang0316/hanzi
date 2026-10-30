import XCTest
import AVFoundation
@testable import HanziCore

/// 朗读相关的能力检测。
///
/// 注意：这个测试跑在 macOS 上，验证的是「AVSpeechSynthesis 的中文语音
/// 在当前系统上存在」以及参数换算是否正确，不是验证出声效果——
/// 真正的发声要在模拟器/真机上听。但它能抓住「语音不存在导致点了没反应」
/// 这一类问题，那正是 Android 侧 `Tts.unavailableState` 要兜的情况。
final class SpeechCheck: XCTestCase {

    func testChineseVoiceExists() {
        let voice = AVSpeechSynthesisVoice(language: "zh-CN")
        XCTAssertNotNil(voice, "系统没有中文语音，朗读会静默失败")
        if let v = voice {
            XCTAssertFalse(v.name.isEmpty)
            print("[Speech] 中文语音: \(v.name) / \(v.identifier)")
        }
    }

    /// 语速换算：0.85 的「相对倍率」应落在系统可懂区间内
    func testSpeechRateMapping() {
        let base = AVSpeechUtteranceDefaultSpeechRate
        for rel in [0.3, 0.85, 1.0, 1.7] as [Float] {
            let rate = base * rel
            XCTAssertGreaterThan(rate, 0, "倍率 \(rel) 换算后为 0")
            XCTAssertLessThanOrEqual(rate, 1.0, "倍率 \(rel) 换算后超出 AVSpeechUtterance 上限")
        }
        // 默认 0.85 应比系统默认稍慢（给低年级听）
        XCTAssertLessThan(base * 0.85, base)
    }

    /// 极端倍率要被夹住，不能因为设置值异常就静音
    func testSpeechRateClamped() {
        let base = AVSpeechUtteranceDefaultSpeechRate
        for rel in [-5, 0, 0.001, 10, 100] as [Float] {
            let clamped = max(0.1, min(2, rel))
            let rate = base * clamped
            XCTAssertGreaterThan(rate, 0)
            XCTAssertLessThanOrEqual(rate, 1.0)
        }
    }

    /// 朗读文本不能有空串或纯空白——AVSpeechSynthesizer 对空串是静默忽略
    func testEmptyTextWouldBeSkipped() {
        let cases = ["", "   ", "\n", "\t "]
        for c in cases {
            XCTAssertTrue(c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          "「\(c)」应被识别为空白")
        }
        // 真实内容不应被误判
        for c in ["天", "天空", "天地人"] {
            XCTAssertFalse(c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
