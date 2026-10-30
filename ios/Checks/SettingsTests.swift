import XCTest
@testable import HanziCore

/// 设置项的默认值与持久化。
///
/// 这些开关看起来琐碎，但它们决定了「明天打开 App 还是不是今天这个样子」：
/// 每日新字数影响学习节奏，拼音开关影响孩子是认字还是念拼音，
/// 册次决定从哪儿继续。任何一项丢了都会被用户当成 bug。
final class SettingsTests: XCTestCase {

    @MainActor
    func testDefaults() {
        let s = Progress.Settings()
        XCTAssertEqual(s.dailyNew, 5)
        XCTAssertEqual(s.book, "1a")
        XCTAssertTrue(s.showPinyin, "默认显示拼音：低年级还在学拼读")
        XCTAssertTrue(s.speakEnabled)
        XCTAssertEqual(s.speechRate, 0.85, accuracy: 0.001)
    }

    @MainActor
    func testEachFieldSurvivesRestart() {
        let store = MemoryStore()

        let a = Progress(store: store)
        var s = a.settings
        s.dailyNew = 8
        s.book = "2b"
        s.showPinyin = false
        s.speechRate = 0.6
        s.speakEnabled = false
        a.updateSettings(s)

        // 换一个实例读同一个 store，模拟重启
        let b = Progress(store: store)
        XCTAssertEqual(b.settings.dailyNew, 8)
        XCTAssertEqual(b.settings.book, "2b")
        XCTAssertFalse(b.settings.showPinyin)
        XCTAssertEqual(b.settings.speechRate, 0.6, accuracy: 0.001)
        XCTAssertFalse(b.settings.speakEnabled)
    }

    /// 五个字段必须一起存 —— 漏掉任意一个，重启后就会退回默认值
    func testEveryFieldIsPersisted() {
        let props = Mirror(reflecting: Progress.Settings()).children.compactMap(\.label).sorted()
        let expected = ["book", "dailyNew", "showPinyin", "speakEnabled", "speechRate"]
        XCTAssertEqual(props, expected,
                       "Settings 的字段变了，persistSettings/load 需要同步改")
    }

    @MainActor
    func testCorruptSettingsFallBackToDefaults() {
        let store = MemoryStore()
        // 写入类型全错的垃圾数据
        store.writeObject("settings", [
            "dailyNew": "不是数字",
            "book": 12345,
            "showPinyin": "是",
            "speechRate": "快",
            "speakEnabled": 1,
        ])
        let p = Progress(store: store)
        XCTAssertEqual(p.settings.dailyNew, 5)
        XCTAssertEqual(p.settings.book, "1a")
        XCTAssertTrue(p.settings.showPinyin)
        XCTAssertEqual(p.settings.speechRate, 0.85, accuracy: 0.001)
        XCTAssertTrue(p.settings.speakEnabled)
    }

    /// 部分字段缺失时，缺的用默认值，有的保留
    @MainActor
    func testPartialSettingsKeepWhatExists() {
        let store = MemoryStore()
        store.writeObject("settings", ["dailyNew": 9, "book": "3a"])
        let p = Progress(store: store)
        XCTAssertEqual(p.settings.dailyNew, 9)
        XCTAssertEqual(p.settings.book, "3a")
        XCTAssertTrue(p.settings.showPinyin, "缺失字段应回默认")
    }

    @MainActor
    func testSettingBookTwiceKeepsLast() {
        let store = MemoryStore()
        let a = Progress(store: store)
        for b in ["1b", "2a", "4b"] {
            var s = a.settings
            s.book = b
            a.updateSettings(s)
        }
        XCTAssertEqual(Progress(store: store).settings.book, "4b")
    }

    /// 非法册次不该被静默接受后导致后续崩（Repo 查不到书会返回空）
    @MainActor
    func testUnknownBookIsStoredButHarmless() {
        let store = MemoryStore()
        let p = Progress(store: store)
        var s = p.settings
        s.book = "9z"
        p.updateSettings(s)
        XCTAssertEqual(Progress(store: store).settings.book, "9z")
        // 不该崩，只是查不到东西
        let repo = TestRepo.make()
        XCTAssertTrue(repo.bookChars("9z").isEmpty)
    }
}
