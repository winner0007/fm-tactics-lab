#if canImport(XCTest)
import XCTest
#else
import Foundation
#endif
#if canImport(TacticsCore)
@testable import TacticsCore
#endif

final class NativeWorkflowTests:XCTestCase {
    func testFormationsAndRoleContexts()throws {
        XCTAssertEqual(Formation.allCases.count,12)
        XCTAssertEqual(NativeCatalog.roles.count,79)
        for formation in Formation.allCases {
            var w=Workspace.example()
            for phase in Phase.allCases {w.tactic.apply(formation,phase:phase);let positions=w.tactic.slots.map{$0.position(phase).id};XCTAssertEqual(Set(positions).count,11);XCTAssertEqual(positions[0],"GK");for slot in w.tactic.slots {XCTAssertTrue(NativeCatalog.allowedRoles(positions:positions,position:slot.position(phase).id,phase:phase).contains{$0.id==w.tactic.role(slot.id,phase).id})}}
            _ = try NativeScenario(workspace:w)
        }
        let two=NativeCatalog.allowedRoles(positions:Formation.fourThreeThree.positions,position:"DCR",phase:.possession)
        let three=NativeCatalog.allowedRoles(positions:Formation.threeFiveTwo.positions,position:"DCR",phase:.possession)
        XCTAssertFalse(two.contains{$0.id=="WideCentreBack"});XCTAssertTrue(three.contains{$0.id=="WideCentreBack"})
    }
    func testDragMatchesUpstreamCellsAndKeepsOtherPhase()throws {
        var w=Workspace.example();let a=TacticalConfiguration.playerKey(8,.possession),b=TacticalConfiguration.playerKey(10,.possession)
        w.tactic.configuration!.nativePlayers=[a:[1:0],b:[2:0]]
        let before=w.tactic
        w.tactic.setPosition(before.slots[10].position(.possession).id,slot:8,phase:.possession)
        XCTAssertEqual(w.tactic.slots.map(\.playerID),before.slots.map(\.playerID))
        XCTAssertEqual(w.tactic.slots.map(\.defending),before.slots.map(\.defending))
        XCTAssertEqual(w.tactic.slots[8].possession,before.slots[10].possession)
        XCTAssertEqual(w.tactic.slots[8].possessionRole,before.slots[10].possessionRole)
        XCTAssertEqual(w.tactic.setup.nativePlayers?[a],before.setup.nativePlayers?[b])
        XCTAssertEqual(w.tactic.slots[10].possession,before.slots[8].possession)
        _ = try w.validated()
    }
    func testScenarioDeterminismAndTargets()throws {
        var w=Workspace.example()
        let first=try NativeScenario(workspace:w),second=try NativeScenario(workspace:w)
        XCTAssertEqual(first.sha256,second.sha256);XCTAssertEqual(first.data,second.data)
        let key=TacticalConfiguration.playerKey(2,.defending)
        var target=MarkTarget();target.playerID=w.opponent!.players[10].id
        w.tactic.configuration!.nativePlayers=[key:[14:34]];w.tactic.configuration!.markTargets=[key:target]
        let marked=try NativeScenario(workspace:w)
        XCTAssertEqual(marked.teams[0].phases[1][2].targetPlayer,10)
        w.opponent!.tactic.slots.swapAt(9,10)
        // Malformed slot IDs are rejected before resolving identities.
        XCTAssertThrowsError(try NativeScenario(workspace:w))
        var obj=try JSONSerialization.jsonObject(with:first.data) as! [String:Any]
        obj["teams"]=[]
        let invalid=try JSONDecoder().decode(NativeScenario.self,from:JSONSerialization.data(withJSONObject:obj))
        XCTAssertThrowsError(try invalid.validated())
    }
    func testNativeSetPieceValidationAndDefaultIDs()throws {
        let a=GameSetPieces(),b=GameSetPieces();XCTAssertEqual(a,b)
        try a.validate(ids:[])
        for kind in GameSetPieceKind.allCases {let r=a.routines[String(kind.id)]![0];XCTAssertEqual(r.groups.reduce(0,{$0+$1.count}),kind.taskCount)}
        var draft=a;draft.routines["5"]![0].groups[4].removeLast();draft.routines["5"]![0].backups[4].removeLast()
        try draft.validate(ids:[],complete:false);XCTAssertThrowsError(try draft.validate(ids:[]))
        draft=a;draft.priorities["2"]=[UUID()];XCTAssertThrowsError(try draft.validate(ids:[]))
    }
    func testPositionSpecificRandomAndHiddenIndependence()throws {
        var w=Workspace.example(),rng=StatisticsWorkflowTests.Seeded()
        _ = w.applyAbility(.international,scope:.team,using:&rng)
        XCTAssertTrue(w.players[0].attributes["reflexes"]!>=15)
        XCTAssertTrue(w.players.dropFirst().allSatisfy{$0.attributes["reflexes"]!<=5})
        XCTAssertTrue(Set(w.players.map{$0.attributes["injury_proneness"]!}).count>1)
        XCTAssertTrue(w.players.contains{$0.attributes["consistency"]!<15})
        let scenario=try NativeScenario(workspace:w)
        XCTAssertEqual(scenario.teams[0].players[0].attributes[63],w.players[0].attributes["injury_proneness"]!*5)
        XCTAssertEqual(scenario.teams[0].players[0].profile["2"],UInt32(w.players[0].background!.traits["职业素养"]!))
    }
    func testImportedEditsAndInputBoundaries()throws {
        var w=Workspace.example(),p=w.players[1]
        p.nativeAttributes=Array(repeating:10,count:15)+Array(repeating:50,count:54)
        p.setFoot("左脚");p.setPositionDescription("ST");p.setAttribute("finishing",19)
        w.players[1]=p
        let input=try NativeScenario(workspace:w).teams[0].players[1]
        XCTAssertEqual(input.attributes[39],100);XCTAssertEqual(input.attributes[40],50)
        XCTAssertEqual(input.attributes[12],20);XCTAssertEqual(input.attributes[4],1)
        XCTAssertEqual(input.attributes[17],95)
        w.players[1].nativeProfile=["11":201]
        XCTAssertThrowsError(try NativeScenario(workspace:w))
        w.players[1].nativeProfile=nil
        w.tactic.configuration!.team["loss"]="立即反抢"
        XCTAssertThrowsError(try NativeScenario(workspace:w))
        w.tactic.configuration!.team=[:]
        for c in [25,35,80,82] {w.tactic.configuration!.conditions.custom=true;w.tactic.configuration!.conditions.cohesion=c;_ = try NativeScenario(workspace:w)}
        w.tactic.configuration!.conditions.cohesion=24
        XCTAssertThrowsError(try NativeScenario(workspace:w))
    }
    func testRoundRobinAndScheduleValidation()throws {
        for count in [2,3,4,5,20] {
            var setup=LeagueSetup()
            for i in 0..<count {var w=Workspace.example(includeOpponent:false);w.tactic.name="队\(i)";setup.teams.append(LeagueTeam(plan:w))}
            for cycles in [1,2] {
                setup.rules.cycles=cycles;_ = try setup.validated();let games=setup.fixtures()
                XCTAssertEqual(games.count,count*(count-1)*cycles/2)
                for round in Set(games.map(\.round)) {let teams=games.filter{$0.round==round}.flatMap{[$0.home,$0.away]};XCTAssertEqual(teams.count,Set(teams).count)}
                if cycles==2 {for team in setup.teams {XCTAssertEqual(games.filter{$0.home==team.id}.count,count-1);XCTAssertEqual(games.filter{$0.away==team.id}.count,count-1)}}
            }
        }
    }
    private func report(_ a:Int,_ b:Int)->OriginalMatchReport {
        OriginalMatchReport(seed:1,engineSHA256:OriginalMatchReport.engineHash,completedAt:Date(timeIntervalSince1970:0),elapsedSeconds:1,finalTick:22000,finalClock:21600,score:[a,b],teams:[],players:[],timeline:[])
    }
    func testSpanishTieReapplicationAndUnresolvedTies()throws {
        var setup=LeagueSetup();setup.rules.ranking = .spanish
        for name in ["A","B","C","D"] {var w=Workspace.example(includeOpponent:false);w.tactic.name=name;setup.teams.append(LeagueTeam(plan:w))}
        let t=setup.teams
        func game(_ h:Int,_ a:Int,_ hg:Int,_ ag:Int)->LeagueResult {LeagueResult(season:1,fixture:LeagueFixture(home:t[h].id,away:t[a].id,round:1),report:report(hg,ag))}
        let results=[game(0,1,3,0),game(1,0,0,3),game(1,2,1,0),game(2,1,0,1),game(2,0,2,0),game(0,2,0,2),game(0,3,10,0),game(3,0,0,10),game(1,3,1,0),game(3,1,0,1),game(2,3,1,0),game(3,2,0,1)]
        let rows=LeagueTable.calculate(teams:t,rules:setup.rules,results:results,complete:true)
        XCTAssertEqual(rows.map(\.name),["C","A","B","D"])
        XCTAssertEqual(rows.map(\.points),[12,12,12,0])
        XCTAssertEqual(rows.reduce(0,{$0+$1.goalsFor}),rows.reduce(0,{$0+$1.goalsAgainst}))
        let ties=LeagueTable.calculate(teams:t,rules:setup.rules,results:[],complete:false)
        XCTAssertTrue(ties.allSatisfy{$0.rank==1 && $0.tied})
    }
}
