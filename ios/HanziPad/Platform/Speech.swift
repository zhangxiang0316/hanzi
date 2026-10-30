import Foundation
import AVFoundation

/// 中文朗读。
///
/// Android 用系统 TTS，iOS 用 `AVSpeechSynthesizer`，两者都是「第一次出声
/// 可能延迟」的行为。这带来两个必须处理的问题：
///
/// 1. `AVSpeechSynthesizer` 如果在 `speak` 时音频会话还没配好，第一声会丢失。
///    所以这里在初始化时就把会话设成 `.playback` 并激活。
/// 2. 设备没有安装中文语音时 `speak` 会静默失败。Android 侧有
///    `Tts.unavailableState` 兜底提示，iOS 这边同样要能报出来——
///    否则孩子点喇叭没反应，以为是坏了。
@MainActor
final class Speech {
    static let shared = Speech()

    private let synthesizer = AVSpeechSynthesizer()
    private var sessionConfigured = false

    private init() {}

    /// 中文语音是否可用
    var hasChineseVoice: Bool {
        AVSpeechSynthesisVoice(language: "zh-CN") != nil
    }

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        do {
            // .playback 而不是 .ambient：朗读是主要内容，别被静音开关吞掉；
            // 同时 .duckOthers 让背景音乐让路而不是被完全打断
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[Speech] 音频会话配置失败: \(error)")
        }
    }

    /// 朗读一段文本
    /// - Parameter rate: 0...1，0.5 是系统默认。默认用 0.85 让语速偏慢，
    ///   与 Android 侧保持一致——给一二年级听，正常语速偏快。
    func speak(_ text: String, rate: Float = 0.85) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        configureSessionIfNeeded()

        // 正在读就先停：连续点几个喇叭时不该叠着念
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        // AVSpeechUtterance 的 rate 范围是 0...1，但实际可懂区间是
        // AVSpeechUtteranceDefaultSpeechRate(0.5) 附近，直接映射会过快
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * max(0.1, min(2, rate))
        utterance.pitchMultiplier = 1.05
        utterance.postUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}

/// 朗读入口的薄封装。
///
/// 单独包一层是因为「朗读开关」在设置里，调用点不该每次都去查设置。
/// 以后要换成别的声音引擎，也只需要改这里。
enum SpareParts {
    @MainActor
    static func speak(_ text: String, rate: Float) {
        let enabled = AppStateHolder.shared?.progress.settings.speakEnabled ?? true
        guard enabled else { return }
        Speech.shared.speak(text, rate: rate)
    }
}

/// 让 SpareParts 能拿到全局状态。
///
/// 这是个不得已的妥协：SwiftUI 的 Environment 在 `Canvas` 或按钮闭包里
/// 拿不到，而朗读调用点散落在各处。用一个弱引用持有根状态，
/// 比在每个调用点都传一遍更实际。
@MainActor
enum AppStateHolder {
    static weak var shared: AppState?
}
