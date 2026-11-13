// Licensed under GPL-3.0. See LICENSE.
import Foundation
import Testing
@testable import NookTabsCore

struct SyncTests {
    let macA = UUID(), macB = UUID()
    let later = fixedNow.addingTimeInterval(60)

    /// What each Mac does on a tick: read the other's file, apply what is newer.
    func exchange(_ a: inout TabTree, _ b: inout TabTree) {
        let sa = SyncMerge.snapshot(of: a, deviceID: macA, deviceName: "A", now: later)
        let sb = SyncMerge.snapshot(of: b, deviceID: macB, deviceName: "B", now: later)
        a.apply(SyncMerge.change(applying: sb, to: a))
        b.apply(SyncMerge.change(applying: sa, to: b))
    }

    @Test func aFavoriteAddedOnOneMacReachesTheOther() throws {
        var f = Fixture()
        var other = f.tree
        f.tab("one", in: .favorites(spaceID: f.spaceA))
        exchange(&f.tree, &other)
        #expect(other.favorites(of: f.spaceA).map(\.displayTitle) == ["one"])
    }

    @Test func aNewSpaceReachesTheOther() throws {
        var f = Fixture()
        var other = f.tree
        let id = UUID()
        f.tree.createSpace(id: id, name: "Work", icon: "w", accentHex: "#123", after: f.spaceB, now: later)
        exchange(&f.tree, &other)
        #expect(other.space(id)?.name == "Work")
    }

    @Test func theNewerEditWins() throws {
        var f = Fixture()
        let tab = f.tab("x", in: .pinned(spaceID: f.spaceA))
        var other = f.tree
        try f.tree.rename(tab, customTitle: "older", now: later)
        try other.rename(tab, customTitle: "newer", now: later.addingTimeInterval(5))
        exchange(&f.tree, &other)
        #expect(f.tree.item(tab)?.customTitle == "newer")
        #expect(other.item(tab)?.customTitle == "newer")
    }

    @Test func aDeletionTravelsAndDoesNotComeBack() throws {
        var f = Fixture()
        let tab = f.tab("gone", in: .favorites(spaceID: f.spaceA))
        var other = f.tree
        try f.tree.close(tab, now: later)
        exchange(&f.tree, &other)
        #expect(other.item(tab) == nil)
        exchange(&f.tree, &other)
        #expect(f.tree.item(tab) == nil && other.item(tab) == nil)
    }

    @Test func openTabsStayOnTheirMac() throws {
        var f = Fixture()
        var other = f.tree
        let open = f.tab("open", in: .tabs(spaceID: f.spaceA))
        exchange(&f.tree, &other)
        #expect(other.item(open) == nil)
    }

    @Test func twoMacsThatExchangedEverythingStopChanging() throws {
        var f = Fixture()
        var other = f.tree
        f.tab("a", in: .favorites(spaceID: f.spaceA))
        f.tab("b", in: .pinned(spaceID: f.spaceB))
        exchange(&f.tree, &other)
        let again = SyncMerge.change(applying: SyncMerge.snapshot(of: f.tree, deviceID: macA, deviceName: "A", now: later), to: other)
        #expect(again.isEmpty)
    }

    @Test func oldTombstonesAreLeftOut() throws {
        var f = Fixture()
        let tab = f.tab("old", in: .favorites(spaceID: f.spaceA))
        try f.tree.close(tab, now: fixedNow)
        let snap = SyncMerge.snapshot(of: f.tree, deviceID: macA, deviceName: "A", now: fixedNow.addingTimeInterval(40 * 86_400))
        #expect(!snap.items.contains { $0.id == tab })
    }

    @Test func folderRoundTripAndBadFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var f = Fixture()
        f.tab("one", in: .favorites(spaceID: f.spaceA))
        let folder = SyncFolder(url: dir)
        try folder.write(SyncMerge.snapshot(of: f.tree, deviceID: macA, deviceName: "A", now: later))
        try Data("not json".utf8).write(to: dir.appendingPathComponent("devices/junk.json"))
        let read = folder.readOthers(excluding: macB)
        #expect(read.snapshots.count == 1 && read.snapshots[0].deviceID == macA)
        #expect(folder.readOthers(excluding: macA).snapshots.isEmpty, "never reads its own file")
    }
}
