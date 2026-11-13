#if canImport(XCTest)
import XCTest
#else
import Foundation
#endif
#if canImport(TacticsCore)
@testable import TacticsCore
#endif

final class StorageWorkflowTests:XCTestCase {
    func testMigrationCopiesOnlyHistoryAndKeepsOriginal()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),source=root.appendingPathComponent("source"),target=root.appendingPathComponent("target")
        defer{try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:source.appendingPathComponent("league-runs/run"),withIntermediateDirectories:true)
        try Data("report".utf8).write(to:source.appendingPathComponent("league-runs/run/run.json"))
        try Data("latest".utf8).write(to:source.appendingPathComponent("latest-league.json"))
        try Data("keep".utf8).write(to:source.appendingPathComponent("workspace.json"))
        try FileManager.default.createDirectory(at:source.appendingPathComponent("team-presets"),withIntermediateDirectories:true)
        try ExperimentStorage.copyHistory(from:source,to:target)
        XCTAssertEqual(try ExperimentStorage.inventory(source),try ExperimentStorage.inventory(target))
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.appendingPathComponent("workspace.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.appendingPathComponent("team-presets").path))
        XCTAssertEqual(try Data(contentsOf:source.appendingPathComponent("workspace.json")),Data("keep".utf8))
        XCTAssertThrowsError(try ExperimentStorage.copyHistory(from:source,to:target))
        XCTAssertThrowsError(try ExperimentStorage.copyHistory(from:source,to:source.appendingPathComponent("nested")))
    }
    func testHistoryRejectsEscapesAndSymlinks()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),outside=root.appendingPathComponent("outside"),source=root.appendingPathComponent("source")
        defer{try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true)
        try Data("untouched".utf8).write(to:outside.appendingPathComponent("private.txt"))
        try FileManager.default.createSymbolicLink(at:source.appendingPathComponent("league-runs"),withDestinationURL:outside)
        XCTAssertThrowsError(try ExperimentStorage.entries(at:source))
        XCTAssertThrowsError(try ExperimentStorage.check(outside,under:source))
        XCTAssertThrowsError(try ExperimentStorage.copyHistory(from:source,to:root.appendingPathComponent("new")))
        XCTAssertEqual(try Data(contentsOf:outside.appendingPathComponent("private.txt")),Data("untouched".utf8))
    }
    func testTacticModeLabelsRespectInheritanceAndLocks() {
        var management=TeamManagement();management.tacticSource="工具初始模板 · 未读取存档 AI 战术"
        XCTAssertTrue(management.selectionDescription(inherited:.originalAI).contains("原版 AI"))
        XCTAssertFalse(management.selectionDescription(inherited:.originalAI).contains("未读取"))
        management.selection = .random
        XCTAssertTrue(management.selectionDescription(inherited:.originalAI).contains("随机战术"))
        management.tacticLocked=true
        XCTAssertTrue(management.selectionDescription(inherited:.originalAI).contains("已锁定"))
        XCTAssertFalse(management.workbenchSource.contains("未读取"))
    }
    func testLeagueTacticModesNeverRandomizePlayerAttributes()throws {
        var first=Workspace.example(includeOpponent:false),second=first
        first.tactic.name="Imported A";second.tactic.name="Imported B"
        for i in first.players.indices {first.players[i].sourceIdentity="saved-\(i)"}
        var setup=LeagueSetup();setup.teams=[LeagueTeam(plan:first),LeagueTeam(plan:second)];setup.testTeamID=setup.teams[0].id
        let originals=setup.teams.map{ $0.plan.players }
        for mode in TacticSelection.allCases {
            setup.defaultTactics=mode
            for fixture in setup.fixtures() {
                let input=try setup.scenario(fixture)
                XCTAssertEqual(input,try setup.scenario(fixture))
                XCTAssertEqual(setup.teams.map{$0.plan.players},originals)
                for team in input.teams {
                    let saved=setup.teams.first{$0.name==team.name}!.plan
                    let baseline=try NativeTeamInput(players:saved.players,tactic:saved.startingTactic,opponent:second)
                    XCTAssertEqual(team.players,baseline.players)
                }
            }
        }
        XCTAssertEqual(first.abilitySourceDescription,"使用导入的球员属性")
        XCTAssertTrue(first.players.allSatisfy{$0.abilityPreset==nil})
    }
}
