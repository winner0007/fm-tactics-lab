#if canImport(XCTest)
import XCTest
#else
import Foundation
#endif
#if canImport(TacticsCore)
@testable import TacticsCore
#endif

final class TacticSelectionTests:XCTestCase {
    func testModesLocksAndLegacyLeague()throws {
        var a=Workspace.example(includeOpponent:false),b=a
        a.tactic.name="A";b.tactic.name="B"
        var setup=LeagueSetup();setup.teams=[LeagueTeam(plan:a),LeagueTeam(plan:b)];setup.testTeamID=setup.teams[0].id
        let fixture=setup.fixtures().first!,input=try setup.scenario(fixture)
        XCTAssertEqual(input.teams.filter{$0.generation != nil}.count,1)
        setup.teams[1].plan.management.tacticLocked=true
        let locked=try setup.scenario(fixture);XCTAssertTrue(locked.teams.allSatisfy{$0.generation==nil})
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(setup)) as! [String:Any]
        object.removeValue(forKey:"defaultTactics");object.removeValue(forKey:"testTeamID")
        let legacy=try JSONDecoder().decode(LeagueSetup.self,from:JSONSerialization.data(withJSONObject:object))
        let old=try legacy.scenario(fixture);XCTAssertNil(legacy.defaultTactics);XCTAssertTrue(old.teams.allSatisfy{$0.generation==nil})
    }
    func testRandomAndCopyPreservePersonnelAndConditions()throws {
        var source=Workspace.example(),target=Workspace.example()
        source.management.selection = .random;source.management.tacticSeed=671
        let before=source.players,random=source.selectedTactics()
        XCTAssertEqual(random,source.selectedTactics());XCTAssertEqual(random.players,before)
        source.management.selection = .fixed;source.createStrategy();source.matchStrategy!.enabled=true
        source.selectStrategyPlan(1);source.tactic.apply(.threeFiveTwo,phase:.possession);source.selectStrategyPlan(0)
        target.tactic.configuration!.conditions.condition=76
        let copy=try target.copyingTactics(from:source)
        XCTAssertEqual(copy.players,target.players);XCTAssertEqual(copy.tactic.slots.map(\.playerID),target.tactic.slots.map(\.playerID))
        XCTAssertTrue(copy.matchStrategy!.plans.allSatisfy{$0.setup.conditions==target.tactic.setup.conditions})
        XCTAssertEqual(copy.strategyPlans[1].formation,source.strategyPlans[1].formation)
        target.management.tacticLocked=true;XCTAssertThrowsError(try target.copyingTactics(from:source))
    }
    func testGenerationReceiptRejectsIdentityAndInputTampering()throws {
        var w=Workspace.example();w.management.selection = .originalAI
        let input=try NativeScenario(workspace:w)
        let teams=try input.teams.enumerated().map{side,t in GeneratedTeamTactic(side:side,order:Array(t.players.indices),fields:try FMFTacticFields.expected(t),coachProfile:String(repeating:"00",count:52))}
        let receipt=TacticGenerationReceipt(event:"native_tactics_generated",accepted:true,teams:teams,seed:42,configurationSHA256:input.sha256,tick:0)
        let resolved=try receipt.resolve(input)
        XCTAssertNil(resolved.teams[0].generation);XCTAssertEqual(resolved.teams[1],input.teams[1])
        XCTAssertEqual(resolved.teams[0].players,input.teams[0].players)
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(receipt)) as! [String:Any]
        var rows=object["teams"] as! [[String:Any]];rows[0]["order"]=Array(repeating:0,count:11);object["teams"]=rows
        let bad=try JSONDecoder().decode(TacticGenerationReceipt.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertThrowsError(try bad.resolve(input))
        object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(receipt)) as! [String:Any];object["tick"]=1
        XCTAssertThrowsError(try JSONDecoder().decode(TacticGenerationReceipt.self,from:JSONSerialization.data(withJSONObject:object)).resolve(input))
        var changed=input;changed.teams[0].name="changed"
        XCTAssertThrowsError(try receipt.resolve(changed))
    }
    func testReportFocusNeverChangesFrozenSetup()throws {
        var a=Workspace.example(includeOpponent:false),b=a;a.tactic.name="<A>";b.tactic.name="B"
        var setup=LeagueSetup();setup.defaultTactics = .fixed;setup.teams=[LeagueTeam(plan:a),LeagueTeam(plan:b)];setup.testTeamID=setup.teams[0].id
        var run=try LeagueRun(setup:setup,seasons:1,seed:42);let frozen=run.setup
        run.reportTeamID=setup.teams[1].id
        let restored=try JSONDecoder().decode(LeagueRun.self,from:JSONEncoder().encode(run)).validated()
        XCTAssertEqual(restored.setup,frozen);XCTAssertEqual(restored.testTeam?.id,setup.teams[1].id)
        let html=LeagueExport.html(restored)
        XCTAssertTrue(html.contains("★ 我的球队 · B"));XCTAssertTrue(html.contains("&lt;A&gt;"));XCTAssertFalse(html.contains("★ 我的球队 · &lt;A&gt;"))
        run.reportTeamID=UUID();XCTAssertThrowsError(try run.validated())
    }
}
