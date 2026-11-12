#if canImport(XCTest)
import XCTest
#else
import Foundation
#endif
#if canImport(TacticsCore)
@testable import TacticsCore
#endif

final class ManagementAnalysisTests:XCTestCase {
    func testLocksProtectReplacementAndAllowPersonnel()throws {
        var w=Workspace.example()
        w.management.coach=CoachProfile(name:"主教练 A",styleID:1)
        w.management.coachLocked=true;w.management.tacticLocked=true
        var next=w;next.management=TeamManagement();next.tactic.apply(.fourFourTwo,phase:.possession)
        XCTAssertThrowsError(try w.protectingLocks(in:next))
        next=w;next.management.coach=CoachProfile(name:"主教练 B")
        XCTAssertThrowsError(try w.checkReplacement(next))
        next=w;next.tactic.configuration!.nativeMentality=7
        XCTAssertThrowsError(try w.checkReplacement(next))
        next=w;var pieces=GameSetPieces();pieces.routines["5"]![0].strategy=2;next.tactic.configuration!.gameSetPieces=pieces
        XCTAssertThrowsError(try w.checkReplacement(next))
        next=w;next.players[1].setAttribute("pace",20)
        let first=next.tactic.slots[1].playerID;next.tactic.slots[1].playerID=next.tactic.slots[2].playerID;next.tactic.slots[2].playerID=first
        next.tactic.configuration!.conditions.condition=75
        try w.checkReplacement(next)
        next=w;next.management.tacticLocked=false;next.management.coachLocked=false
        XCTAssertEqual(try w.protectingLocks(in:next).management.tacticLocked,true)
        XCTAssertEqual(try w.protectingLocks(in:next,allowLockChanges:true).management.tacticLocked,false)
        let encoded=try JSONEncoder().encode(w),decoded=try JSONDecoder().decode(Workspace.self,from:encoded).validated()
        XCTAssertEqual(decoded.management,w.management)
        XCTAssertEqual(OpponentPlan(w).workspace.management,w.management)
        XCTAssertEqual(try TeamPreset(name:"锁定实验",plan:w).plan.management,w.management)
        var object=try JSONSerialization.jsonObject(with:encoded) as! [String:Any];object.removeValue(forKey:"teamManagement")
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self,from:JSONSerialization.data(withJSONObject:object)).management.tacticLocked,false)
    }

    func testTacticFingerprintUsesExecutionNotNamesOrAbility()throws {
        var w=Workspace.example();let before=try NativeScenario(workspace:w).teams[0]
        w.tactic.name="相同战术的别名";w.players[0].name="另一位门将";w.players[0].setAttribute("reflexes",20)
        let renamed=try NativeScenario(workspace:w).teams[0]
        XCTAssertEqual(before.tacticKey(),renamed.tacticKey())
        var pieces=GameSetPieces();pieces.routines["5"]![0].name="同样的近门柱套路";pieces.routines["5"]![0].id=UUID()
        w.tactic.configuration!.gameSetPieces=pieces
        XCTAssertEqual(before.tacticKey(),try NativeScenario(workspace:w).teams[0].tacticKey())
        w.tactic.configuration!.nativeMentality=7
        let changed=try NativeScenario(workspace:w).teams[0]
        XCTAssertFalse(before.tacticKey()==changed.tacticKey())
        XCTAssertEqual(before.tacticKey(.shape),changed.tacticKey(.shape))
        w.tactic.apply(.fourFourTwo,phase:.defending)
        w.tactic.apply(.fiveFourOne,phase:.possession)
        let different=try NativeScenario(workspace:w).teams[0]
        XCTAssertFalse(before.tacticKey(.shape)==different.tacticKey(.shape))
    }

    func testInstalledFilesDoNotAuthorizeNewEngine() {
        var engine=EngineReport(appPath:"/test/fm.app",version:"27.0.1.2503222",architectures:["arm64"],pluginFound:true,canSimulate:false,reason:"找到安装",diagnostics:[EngineDiagnostic(title:"资源",passed:true)])
        XCTAssertTrue(engine.filesReady);XCTAssertFalse(engine.adapterSupported)
        engine.binarySHA256="68adfde2e0588458c1830cb7e688855d9c61237973a7eb7a105af5ac4ed112a4"
        XCTAssertTrue(engine.adapterSupported);XCTAssertFalse(engine.canSimulate)
        engine.binarySHA256=String(repeating:"a",count:64)
        XCTAssertFalse(engine.adapterSupported);XCTAssertTrue(engine.compatibilityMessage.contains("尚未适配"))
        engine.binarySHA256=OriginalMatchReport.engineHash
        XCTAssertTrue(engine.adapterSupported);XCTAssertFalse(engine.canSimulate)
    }

    func testLeagueVersionPinSurvivesPersistence()throws {
        var setup=LeagueSetup();setup.teams=(0..<2).map {i in var w=Workspace.example(includeOpponent:false);w.tactic.name="球队 \(i)";return LeagueTeam(plan:w)}
        var run=try LeagueRun(setup:setup,seasons:1,seed:1)
        try run.validateEngine(OriginalMatchReport.updatedEngineHash)
        run.engineSHA256=OriginalMatchReport.updatedEngineHash
        let restored=try JSONDecoder().decode(LeagueRun.self,from:JSONEncoder().encode(run))
        try restored.validateEngine(OriginalMatchReport.updatedEngineHash)
        XCTAssertThrowsError(try restored.validateEngine(OriginalMatchReport.engineHash))
        XCTAssertThrowsError(try restored.validateEngine("unknown"))
        var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(run)) as! [String:Any]
        legacy.removeValue(forKey:"engineSHA256")
        let old=try JSONDecoder().decode(LeagueRun.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertNil(old.engineSHA256)
        try old.validateEngine(OriginalMatchReport.engineHash)
    }

    func testOpponentBreakdownCountsBothSidesAndKeepsSnapshots()throws {
        var a=Workspace.example(includeOpponent:false),b=a,c=a
        a.tactic.name="A";b.tactic.name="B";c.tactic.name="C"
        var setup=LeagueSetup();setup.teams=[LeagueTeam(plan:a),LeagueTeam(plan:b),LeagueTeam(plan:c)]
        var run=try LeagueRun(setup:setup,seasons:2,seed:1)
        let own=setup.teams[0].id
        func add(_ home:Int,_ away:Int,_ goals:[Int],_ season:Int,_ withXG:Bool=true)throws {
            let fixture=LeagueFixture(home:setup.teams[home].id,away:setup.teams[away].id,round:1)
            let config=try setup.scenario(fixture)
            let stats=[OriginalTeamStatistics(side:0,statistics:withXG ? ["xg":1.5]:[:]),OriginalTeamStatistics(side:1,statistics:withXG ? ["xg":0.5]:[:])]
            var report=OriginalMatchReport(seed:1,engineSHA256:OriginalMatchReport.engineHash,completedAt:Date(),elapsedSeconds:1,finalTick:22000,finalClock:22000,score:goals,teams:stats,players:[],timeline:[])
            report.configuration=config;report.configurationSHA256=config.sha256
            run.results.append(LeagueResult(season:season,fixture:fixture,report:report))
        }
        try add(0,1,[2,0],1);try add(2,0,[1,1],1);try add(1,0,[3,1],2,false)
        let all=TacticPerformance.aggregate(run:run,teamID:own)
        XCTAssertEqual(all.count,1);let r=all[0]
        XCTAssertEqual(r.games,3);XCTAssertEqual(r.wins,1);XCTAssertEqual(r.draws,1);XCTAssertEqual(r.losses,1)
        XCTAssertEqual(r.goalsFor,4);XCTAssertEqual(r.goalsAgainst,4)
        XCTAssertEqual(r.homeGames,1);XCTAssertEqual(r.awayGames,2);XCTAssertEqual(r.opponents,Set(["B","C"]))
        XCTAssertEqual(r.xgGames,2);XCTAssertEqual(r.xgFor,2);XCTAssertEqual(r.xgAgainst,2)
        XCTAssertEqual(TacticPerformance.aggregate(run:run,teamID:own,season:1,venue:.away)[0].games,1)
        setup.teams[1].plan.tactic.configuration!.nativeMentality=7
        try add(0,1,[0,1],2)
        XCTAssertEqual(TacticPerformance.aggregate(run:run,teamID:own).count,2)
        XCTAssertEqual(TacticPerformance.aggregate(run:run,teamID:own,grouping:.shape).count,1)
        setup.teams[0].plan.tactic.configuration!.nativeMentality=7
        try add(0,2,[0,0],2)
        XCTAssertEqual(TacticPerformance.aggregate(run:run,teamID:own,grouping:.shape).count,2)
        XCTAssertEqual(run.setup.teams[0].plan.tactic.gameMentality,4)
        let html=LeagueExport.html(run)
        XCTAssertTrue(html.contains("面对不同战术的表现"));XCTAssertTrue(html.contains(r.opponentKey))
    }
}
