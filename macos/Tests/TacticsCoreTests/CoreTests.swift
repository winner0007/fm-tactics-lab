#if canImport(XCTest)
import XCTest
#else
import Foundation
#endif
#if canImport(TacticsCore)
@testable import TacticsCore
#endif

final class CoreTests: XCTestCase {
    func testWorkspaceRoundTripAndPhaseIndependence() throws {
        var workspace = Workspace.example()
        let original = workspace.tactic.slots.map(\.defending)
        workspace.baseline = workspace.tactic
        workspace.tactic.apply(.threeFourTwoOne,phase:.possession)
        XCTAssertEqual(workspace.tactic.slots.map(\.defending),original)
        XCTAssertEqual(workspace.baseline?.formation,"4-3-3")
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self,from:JSONEncoder().encode(workspace)).validated(),workspace)
    }
    func testRejectsInvalidLineupAndAttributes() throws {
        var workspace = Workspace.example()
        workspace.tactic.slots[1].playerID = workspace.tactic.slots[0].playerID
        XCTAssertThrowsError(try workspace.validated())
        workspace = .example(); workspace.players[0].attributes["pace"] = 21
        XCTAssertThrowsError(try workspace.validated())
        workspace = .example(); workspace.tactic.slots.swapAt(0,1)
        XCTAssertThrowsError(try workspace.validated())
        workspace = .example(); workspace.tactic.slots[0].defending.x = .nan
        XCTAssertThrowsError(try workspace.validated())
    }
    func testBaselineDiffDetectsInstructionsAndLineup() {
        var workspace = Workspace.example(); workspace.baseline = workspace.tactic
        XCTAssertTrue(workspace.differences().isEmpty)
        workspace.tactic.pressing += 1
        XCTAssertEqual(workspace.differences(),["逼抢：3 → 4"])
        workspace.tactic.slots[0].assignment = .connect
        XCTAssertEqual(workspace.differences().count,2)
    }
    func testBaselineRestoresPlayerAttributes() throws {
        var workspace = Workspace.example()
        workspace.captureBaseline()
        let initial = workspace.players
        workspace.players[0].attributes["pace"] = 1
        XCTAssertTrue(workspace.differences().contains { $0.contains("球员的属性") })
        workspace.restoreBaseline()
        XCTAssertEqual(workspace.players, initial)
        _ = try workspace.validated()
    }
    func testAnalysisRespondsToActualPlayersAndInstructions() {
        var workspace = Workspace.example()
        for i in workspace.players.indices { workspace.players[i].attributes["stamina"] = 9 }
        XCTAssertFalse(Analysis.inspect(workspace).contains { $0.title == "高压迫的体能门槛" })
        workspace.tactic.pressing = 5
        XCTAssertTrue(Analysis.inspect(workspace).contains { $0.title == "高压迫的体能门槛" && $0.detail.contains("9.0") })
        for i in workspace.players.indices { workspace.players[i].attributes["stamina"] = 20 }
        XCTAssertFalse(Analysis.inspect(workspace).contains { $0.title == "高压迫的体能门槛" })
    }
    func testCSVHandlesBOMQuotesCommasNewlinesAndTrailingEmptyCells() throws {
        let text = "\u{feff}name,note,last\r\n\"张,三\",\"line 1\nline \"\"2\"\"\",\r\n"
        XCTAssertEqual(try CSV.parse(text),[["name","note","last"],["张,三","line 1\nline \"2\"",""]])
        XCTAssertEqual(try CSV.parse(CSV.encode([["a","b"],["\"name\"","x,y"]])),[["a","b"],["\"name\"","x,y"]])
    }
    func testCSVRejectsBrokenAndDuplicateHeaders() {
        for text in ["a,b\n1", "a,a\n1,2", "a,b\n\"x,2", "a,b\n\"x\"bad,2", ""] { XCTAssertThrowsError(try CSV.parse(text),text) }
    }
    func testPlayerCSVTemplateAndValidation() throws {
        XCTAssertEqual(try CSV.players(CSV.playerTemplate()).count,11)
        var rows = try CSV.parse(CSV.playerTemplate()); rows[1][2] = "0"
        XCTAssertThrowsError(try CSV.players(CSV.encode(rows)))
        rows[1][2] = "10.5"; XCTAssertThrowsError(try CSV.players(CSV.encode(rows)))
    }
    func testUpstreamChineseCSVAndUnpairedResults() throws {
        let text = "模式,方案,种子,主队进球,客队进球,耗时秒,尝试次数,日志\n完整,对照,1,1,1,2,1,a\n完整,改动,1,3,1,2,1,b\n完整,改动,2,1,0,2,1,c\n"
        let e = try Experiment.load(text,source:"upstream.csv")
        XCTAssertFalse(e.hasContext)
        XCTAssertEqual(e.summary("改动").winRate,1)
        let comparison = e.compare(baseline:"对照",candidate:"改动")
        XCTAssertEqual(comparison.mean,2); XCTAssertEqual(comparison.unpaired,1); XCTAssertNil(comparison.interval())
    }
    func testPairingSeparatesOpponentAndVenue() throws {
        let text = "variant,seed,goals_for,goals_against,opponent,venue\nA,1,1,0,X,home\nB,1,2,0,Y,home\nB,1,3,0,X,away\nB,1,4,0,X,home"
        let e = try Experiment.load(text,source:"context.csv")
        XCTAssertTrue(e.hasContext)
        let result = e.compare(baseline:"A",candidate:"B")
        XCTAssertEqual(result.differences,[3]); XCTAssertEqual(result.unpaired,2)
    }
    func testFailuresExcludedAndDuplicateKeysRejected() throws {
        let header="variant,seed,goals_for,goals_against,status\n"
        let e = try Experiment.load(header+"A,1,1,0,complete\nA,2,,,failed",source:"x")
        XCTAssertEqual(e.excluded,1); XCTAssertEqual(e.records.count,1)
        XCTAssertThrowsError(try Experiment.load(header+"A,1,1,0,complete\nA,01,2,0,complete",source:"x"))
        XCTAssertThrowsError(try Experiment.load(header+"A,2,,,failed",source:"x"))
        XCTAssertThrowsError(try Experiment.load(header+"A,1,1,0,mystery",source:"x"))
    }
    func testScoresAndXGValidation() {
        for value in ["-1","1.5","nan"] { XCTAssertThrowsError(try Experiment.load("variant,seed,goals_for,goals_against\nA,1,\(value),0",source:"x")) }
        XCTAssertThrowsError(try Experiment.load("variant,seed,goals_for,goals_against,xg_for\nA,1,1,0,nan",source:"x"))
    }
    func testBootstrapRequiresEnoughPairsAndIsDeterministic() {
        XCTAssertNil(PairedComparison(differences:Array(repeating:1,count:19),unpaired:0).interval())
        let same = PairedComparison(differences:Array(repeating:2,count:20),unpaired:0)
        XCTAssertEqual(same.interval(),2...2)
        let mixed = PairedComparison(differences:(0..<40).map { Double($0%5-2) },unpaired:0)
        XCTAssertEqual(mixed.interval(),mixed.interval()); XCTAssertTrue(mixed.interval()!.contains(0))
    }
    func testMachOArchitecturesAndTruncation() {
        var bytes = [UInt8](repeating:0,count:48)
        bytes.replaceSubrange(0..<8,with:[0xca,0xfe,0xba,0xbe,0,0,0,2])
        bytes.replaceSubrange(8..<12,with:[1,0,0,7]); bytes.replaceSubrange(28..<32,with:[1,0,0,12])
        XCTAssertEqual(EngineReport.machArchitectures(Data(bytes)),["x86_64","arm64"])
        XCTAssertTrue(EngineReport.machArchitectures(Data(bytes.prefix(20))).isEmpty)
        XCTAssertTrue(EngineReport.machArchitectures(Data()).isEmpty)
    }
    func testEngineNeverClaimsSimulationFromFilePresence() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("fm.app")
        defer { try? FileManager.default.removeItem(at:folder.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at:folder.appendingPathComponent("Contents"),withIntermediateDirectories:true)
        let plist = try PropertyListSerialization.data(fromPropertyList:["CFBundleShortVersionString":"27.0.0.2493426"],format:.xml,options:0)
        try plist.write(to:folder.appendingPathComponent("Contents/Info.plist"))
        let report = EngineReport.inspect(app:folder)
        XCTAssertEqual(report.version,"27.0.0.2493426"); XCTAssertFalse(report.canSimulate); XCTAssertFalse(report.pluginFound)
    }
}
