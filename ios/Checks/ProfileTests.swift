import XCTest
@testable import HanziCore

/// 多孩子档案。
///
/// 一间屋里两个孩子共用一个 iPad 学字是常态。之前所有数据挤在一套文件里，
/// 弟弟写几个字就把哥哥的进度、错题本、描红星级全搅在一起。
///
/// 最要紧的一条：**老用户升级上来不能丢进度**。默认档案的 id 是空串，
/// 文件名和加档案功能之前完全一样。
///
/// 与 Android `ProfileTest`、小程序 `tests/profile.test.mjs` 对应。
@MainActor
final class ProfileTests: XCTestCase {

    private func fresh() -> (ProfileManager, HanziCore.Progress, MemoryStore) {
        let store = MemoryStore()
        let pm = ProfileManager(store: store)
        let prog = HanziCore.Progress(store: store)
        prog.resetAll()
        return (pm, prog, store)
    }

    /// 默认档案的键名必须和老版本完全一样，否则升级上来进度全丢
    func testDefaultProfileUsesBareKeys() {
        let (pm, _, store) = fresh()
        XCTAssertEqual(pm.activeId, "")
        store.setProfile("")
        XCTAssertEqual(store.currentProfile, "")
    }

    func testStartsWithOneProfile() {
        let (pm, _, _) = fresh()
        XCTAssertEqual(pm.count, 1)
        XCTAssertEqual(pm.active.name, "我")
    }

    func testTwoProfilesAreIsolated() {
        let (pm, prog, _) = fresh()
        prog.learn("日")
        XCTAssertEqual(prog.totalLearned, 1)

        let p = pm.add("弟弟")!
        XCTAssertTrue(pm.setActive(p.id))
        prog.reload()
        XCTAssertEqual(prog.totalLearned, 0, "弟弟不该看到哥哥的进度")

        prog.learn("月")
        prog.saveWrite("月", score: 90)
        XCTAssertEqual(prog.totalLearned, 1)

        XCTAssertTrue(pm.setActive(""))
        prog.reload()
        XCTAssertEqual(prog.totalLearned, 1)
        XCTAssertFalse(prog.hasLearned("月"), "弟弟学的字不该串到哥哥这边")
        XCTAssertNil(prog.writeRecord("月"))
    }

    func testWrongAndWeakAreIsolated() {
        let (pm, prog, _) = fresh()
        prog.grade("日", correct: false, lesson: nil)
        prog.recordStroke("日", index: 1, passed: false)
        prog.recordStroke("日", index: 1, passed: false)

        let p = pm.add("弟弟")!
        pm.setActive(p.id)
        prog.reload()
        XCTAssertEqual(prog.wrongCount, 0, "弟弟的错题本应该是空的")
        XCTAssertTrue(prog.allWeakStrokes().isEmpty)

        pm.setActive("")
        prog.reload()
        XCTAssertEqual(prog.wrongCount, 1)
        XCTAssertEqual(prog.allWeakStrokes().count, 1)
    }

    func testSettingsAreIsolated() {
        let (pm, prog, _) = fresh()
        let p = pm.add("妹妹")!
        pm.setActive(p.id)
        prog.reload()
        prog.updateSettings(HanziCore.Progress.Settings(book: "2a"))
        XCTAssertEqual(prog.settings.book, "2a")

        pm.setActive("")
        prog.reload()
        XCTAssertEqual(prog.settings.book, "1a", "哥哥的册次不该被改")
    }

    func testSwitchToUnknownReturnsFalse() {
        let (pm, _, _) = fresh()
        XCTAssertFalse(pm.setActive("nope"))
        XCTAssertEqual(pm.activeId, "")
        // 切到当前档案也返回 false，避免无意义的 reload
        XCTAssertFalse(pm.setActive(""))
    }

    func testMaxFourProfiles() {
        let (pm, _, _) = fresh()
        XCTAssertEqual(ProfileManager.max, 4)
        pm.add("老二")
        pm.add("老三")
        pm.add("老四")
        XCTAssertEqual(pm.count, 4)
        XCTAssertFalse(pm.canAdd)
        XCTAssertNil(pm.add("老五"), "超上限应该拒绝")
        XCTAssertEqual(pm.count, 4)
    }

    func testNameTrimming() {
        let (pm, _, _) = fresh()
        XCTAssertEqual(pm.add("  小明  ")!.name, "小明")
        XCTAssertEqual(pm.add("一二三四五六七八九十")!.name.count, 8)
    }

    /// 空名字用「孩子N」，N 是加入时的档案数 +1（默认档案已经占 1）
    func testBlankNameGetsDefault() {
        let (pm, _, _) = fresh()
        XCTAssertEqual(pm.add("   ")!.name, "孩子2")
    }

    func testRename() {
        let (pm, _, _) = fresh()
        let p = pm.add("老二")!
        XCTAssertTrue(pm.rename(p.id, " 弟弟 "))
        XCTAssertEqual(pm.list.first { $0.id == p.id }!.name, "弟弟")
        // 空名字拒绝
        XCTAssertFalse(pm.rename(p.id, ""))
        XCTAssertEqual(pm.list.first { $0.id == p.id }!.name, "弟弟")
    }

    func testCanRenameDefaultProfile() {
        let (pm, _, _) = fresh()
        XCTAssertTrue(pm.rename("", "哥哥"))
        XCTAssertEqual(pm.active.name, "哥哥")
    }

    func testRemoveDeletesDataButNotSiblings() {
        let (pm, prog, store) = fresh()
        let p = pm.add("弟弟")!
        pm.setActive(p.id)
        prog.reload()
        prog.learn("月")
        prog.saveWrite("月", score: 88)

        pm.setActive("")
        prog.reload()
        let before = prog.totalLearned

        pm.remove(p.id)
        prog.reload()
        XCTAssertEqual(prog.totalLearned, before, "删弟弟不该影响哥哥")

        // 弟弟的文件应该真的没了
        store.setProfile(p.id)
        XCTAssertNil(store.readObject("progress"), "弟弟的数据应该被清空")
        store.setProfile("")
    }

    func testRemovingActiveFallsBackToFirst() {
        let (pm, prog, _) = fresh()
        let p = pm.add("弟弟")!
        pm.setActive(p.id)
        prog.reload()
        XCTAssertEqual(pm.activeId, p.id)

        let next = pm.remove(p.id)
        XCTAssertEqual(next, "", "应该切回默认档案")
        XCTAssertEqual(pm.activeId, "")
    }

    func testRemovingNonActiveReturnsNil() {
        let (pm, _, _) = fresh()
        let p = pm.add("弟弟")!
        XCTAssertNil(pm.remove(p.id))
    }

    func testCannotRemoveLastProfile() {
        let (pm, _, _) = fresh()
        XCTAssertEqual(pm.count, 1)
        XCTAssertNil(pm.remove(""))
        XCTAssertEqual(pm.count, 1)
    }

    /// 一键把弟弟的进度也清掉是不可接受的
    func testClearAllOnlyClearsCurrentProfile() {
        let (pm, prog, _) = fresh()
        let p = pm.add("弟弟")!
        pm.setActive(p.id)
        prog.reload()
        prog.learn("月")

        pm.setActive("")
        prog.reload()
        prog.learn("日")
        prog.resetAll()
        XCTAssertEqual(prog.totalLearned, 0, "当前档案应该清空")

        pm.setActive(p.id)
        prog.reload()
        XCTAssertEqual(prog.totalLearned, 1, "弟弟的进度不该被清掉")
    }

    func testProfileListSurvivesRestart() {
        let (_, _, store) = fresh()
        let pm = ProfileManager(store: store)
        let p = pm.add("弟弟")!
        pm.rename(p.id, "小明")
        pm.setActive(p.id)

        // 新建一个 ProfileManager 读同一个 store，模拟重启
        let pm2 = ProfileManager(store: store)
        XCTAssertEqual(pm2.activeId, p.id)
        XCTAssertEqual(pm2.active.name, "小明")
    }

    func testActivePointingAtDeletedFallsBack() {
        let (pm, _, store) = fresh()
        let p = pm.add("弟弟")!
        pm.setActive(p.id)

        // 手工把档案表改坏，模拟异常退出留下的脏数据
        var obj = store.readObjectUnscoped("profiles")!
        let arr = (obj["list"] as! [[String: Any]]).filter { ($0["id"] as? String) != p.id }
        obj["list"] = arr
        store.writeObjectUnscoped("profiles", obj)

        let pm2 = ProfileManager(store: store)
        XCTAssertEqual(pm2.activeId, "", "应该回落到第一个档案")
    }

    func testMissingProfileListRecovers() {
        let (_, _, store) = fresh()
        store.remove("profiles")
        let pm = ProfileManager(store: store)
        XCTAssertEqual(pm.count, 1)
        XCTAssertEqual(pm.activeId, "")
    }

    func testProfileIdsAreUnique() {
        let (pm, _, _) = fresh()
        let a = pm.add("A")!
        let b = pm.add("B")!
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(pm.count, 3)
    }
}
