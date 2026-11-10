#if canImport(XCTest)
import XCTest
#else
import Foundation
#endif
#if canImport(TacticsCore)
@testable import TacticsCore
#endif

final class WorkflowTests:XCTestCase {
    func testDropSwapsPlayersAndPreservesBothPhaseTasks() throws {
        for phase in Phase.allCases {
            var w=Workspace.example();let before=w.tactic
            let target=w.tactic.slots[8].point(phase)
            XCTAssertEqual(w.tactic.dropPlayer(slotID:10,phase:phase,point:target,width:400,height:550),8)
            XCTAssertEqual(w.tactic.slots[8].playerID,before.slots[10].playerID)
            XCTAssertEqual(w.tactic.slots[10].playerID,before.slots[8].playerID)
            for i in 0..<11 {
                XCTAssertEqual(w.tactic.slots[i].possession,before.slots[i].possession)
                XCTAssertEqual(w.tactic.slots[i].defending,before.slots[i].defending)
                XCTAssertEqual(w.tactic.slots[i].assignment,before.slots[i].assignment)
                XCTAssertEqual(w.tactic.slots[i].defensiveAssignment,before.slots[i].defensiveAssignment)
            }
            XCTAssertEqual(w.tactic.formation,before.formation);_ = try w.validated()
        }
    }
    func testFreeDropClampsAndUsesActualPitchSize() {
        var tactic=Workspace.example().tactic
        let before=tactic.slots.map(\.playerID),defending=tactic.slots.map(\.defending)
        XCTAssertNil(tactic.dropPlayer(slotID:9,phase:.possession,point:Point(-1,-1),width:400,height:550))
        XCTAssertEqual(tactic.slots[9].possession,Point(0.05,0.05))
        XCTAssertEqual(tactic.slots.map(\.playerID),before)
        XCTAssertEqual(tactic.slots.map(\.defending),defending)
        let near=Point(tactic.slots[5].possession.x+0.07,tactic.slots[5].possession.y)
        XCTAssertEqual(tactic.overlapTarget(slotID:9,phase:.possession,point:near,width:400,height:550),5)
        XCTAssertNil(tactic.overlapTarget(slotID:9,phase:.possession,point:near,width:800,height:1100))
        let saved=tactic
        XCTAssertNil(tactic.dropPlayer(slotID:99,phase:.defending,point:Point(0.2,0.2),width:400,height:550))
        XCTAssertNil(tactic.dropPlayer(slotID:9,phase:.defending,point:Point(.nan,0.2),width:400,height:550))
        XCTAssertEqual(tactic,saved)
    }
    func testAbilityTeamPositionIndividualAndBaseline() throws {
        var w=Workspace.example(),rng=SystemRandomNumberGenerator()
        let before=w;w.captureBaseline()
        XCTAssertEqual(w.applyAbility(.amateur,scope:.position("DC"),using:&rng),2)
        for i in w.players.indices {
            if w.players[i].position=="DC" { XCTAssertTrue(Attribute.allCases.allSatisfy{AbilityTier.amateur.range.contains(w.players[i].value($0))}) }
            else { XCTAssertEqual(w.players[i],before.players[i]) }
        }
        XCTAssertEqual(w.applyAbility(.international,scope:.individual(w.players[9].id),using:&rng),1)
        XCTAssertEqual(w.players[9].abilityPreset,.international)
        XCTAssertEqual(w.applyAbility(.continental,scope:.team,using:&rng),11)
        XCTAssertTrue(w.players.allSatisfy{$0.abilityPreset == .continental})
        XCTAssertEqual(w.tactic.slots,before.tactic.slots)
        w.restoreBaseline();XCTAssertEqual(w.players,before.players);_ = try w.validated()
    }
    func testRandomPresetsAndMultiPositionMatching() throws {
        var w=Workspace.example(),rng=SystemRandomNumberGenerator()
        w.players[2].position="DC / DM"
        XCTAssertTrue(AbilityScope.position("DM").contains(w.players[2]))
        XCTAssertTrue(w.positionChoices.contains("DM"))
        _ = w.applyAbility(.random,scope:.team,using:&rng)
        XCTAssertTrue(w.players.allSatisfy { p in Attribute.allCases.allSatisfy{(1...20).contains(p.value($0))} })
        let before=w
        XCTAssertEqual(w.applyAbility(.professional,scope:.position("UNKNOWN"),using:&rng),0)
        XCTAssertEqual(w,before);_ = try w.validated()
    }
    func testSetPiecesPhaseInstructionsPersistenceAndBaseline() throws {
        var w=Workspace.example(),setup=TacticalConfiguration()
        setup.team["loss"]="立即反抢"
        setup.players[TacticalConfiguration.playerKey(9,.possession)]=["shoot":"更多射门"]
        var left=SetPieceRoutine.initial(.attackingCorner)
        left.primaryTaker=w.players[8].id;left.backupTaker=w.players[10].id;left.tasks[3]="冲击近点"
        setup.setPieces[TacticalConfiguration.key(.attackingCorner,.left)]=left
        w.tactic.configuration=setup;w.captureBaseline()
        XCTAssertNil(w.tactic.setup.routine(.attackingCorner,.right).primaryTaker)
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self,from:JSONEncoder().encode(w)).validated(),w)
        setup.conditions.custom=true;setup.conditions.fatigue = .tired;w.tactic.configuration=setup
        XCTAssertTrue(w.differences().contains{$0.contains("状态与磨合")})
        w.restoreBaseline();XCTAssertFalse(w.tactic.setup.conditions.custom)
    }
    func testInvalidInstructionsTakersAndUnknownTraitsRejected() {
        var w=Workspace.example(),setup=TacticalConfiguration()
        setup.team["loss"]="凭空生成的选项";w.tactic.configuration=setup
        XCTAssertThrowsError(try w.validated())
        setup=TacticalConfiguration();var routine=SetPieceRoutine.initial(.penalty)
        routine.primaryTaker=UUID();setup.setPieces[TacticalConfiguration.key(.penalty,.left)]=routine;w.tactic.configuration=setup
        XCTAssertThrowsError(try w.validated())
        routine.primaryTaker=w.players[0].id;routine.backupTaker=w.players[0].id
        setup.setPieces[TacticalConfiguration.key(.penalty,.left)]=routine;w.tactic.configuration=setup
        XCTAssertThrowsError(try w.validated())
        w=Workspace.example();var background=PlayerBackground();background.traits["抗压"]=21;w.players[0].background=background
        XCTAssertThrowsError(try w.validated())
    }
    func testStandardConditionsIgnoreStoredCustomFatigue() throws {
        var w=Workspace.example(),setup=TacticalConfiguration()
        setup.conditions.fatigue = .exhausted;w.tactic.pressing=5;w.tactic.configuration=setup
        XCTAssertFalse(Analysis.inspect(w).contains{$0.title.contains("疲劳状态")})
        setup.conditions.custom=true;w.tactic.configuration=setup
        XCTAssertTrue(Analysis.inspect(w).contains{$0.title.contains("疲劳状态")})
        XCTAssertTrue(PlayerBackground().traits.isEmpty);_ = try w.validated()
    }
    func testOldWorkspaceWithoutNewFieldsStillLoads() throws {
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(Workspace.example())) as! [String:Any]
        object["schema"]="tactics-lab-mac/1"
        var tactic=object["tactic"] as! [String:Any];tactic.removeValue(forKey:"configuration");object["tactic"]=tactic
        var players=object["players"] as! [[String:Any]]
        for i in players.indices {players[i].removeValue(forKey:"background")};object["players"]=players
        let result=try JSONDecoder().decode(Workspace.self,from:JSONSerialization.data(withJSONObject:object)).validated()
        XCTAssertTrue(result.tactic.setup.team.isEmpty);XCTAssertFalse(result.tactic.setup.conditions.custom)
        XCTAssertEqual(result.schema,"tactics-lab-mac/3")
    }

    private func fixture(_ action:(URL,EngineSearchEnvironment)throws->Void) throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        try action(root,EngineSearchEnvironment(home:root.appendingPathComponent("home"),applicationFolders:[root.appendingPathComponent("Applications")],volumes:[root.appendingPathComponent("External")]))
    }
    private func app(_ url:URL,version:String="27.0.0.2493426",complete:Bool=true) throws {
        let contents=url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at:contents,withIntermediateDirectories:true)
        try PropertyListSerialization.data(fromPropertyList:["CFBundleShortVersionString":version],format:.xml,options:0).write(to:contents.appendingPathComponent("Info.plist"))
        if complete {
            let binary=contents.appendingPathComponent("PlugIns/game_plugin.bundle/Contents/MacOS/game_plugin")
            try FileManager.default.createDirectory(at:binary.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data([0xcf,0xfa,0xed,0xfe,0x0c,0,0,1]).write(to:binary)
        }
    }
    func testSteamLibraryAutodiscoverySkipsIncompleteInstallation() throws {
        try fixture { root,environment in
            let steam=environment.home.appendingPathComponent("Library/Application Support/Steam")
            try app(steam.appendingPathComponent("steamapps/common/Football Manager 27/fm.app"),complete:false)
            let custom=root.appendingPathComponent("Custom Game Library")
            let actual=custom.appendingPathComponent("steamapps/common/Football Manager 27/fm.app")
            try app(actual)
            try "\"libraryfolders\" { \"1\" { \"path\" \"\(custom.path)\" } }".write(to:steam.appendingPathComponent("steamapps/libraryfolders.vdf"),atomically:true,encoding:.utf8)
            let report=EngineReport.inspect(environment:environment)
            XCTAssertEqual(report.appPath,actual.resolvingSymlinksInPath().path);XCTAssertTrue(report.installationFound);XCTAssertFalse(report.canSimulate)
        }
    }
    func testApplicationsExternalAndRememberedPathSearch() throws {
        try fixture { root,environment in
            let applications=environment.applicationFolders[0].appendingPathComponent("Football Manager 27.app")
            try app(applications)
            XCTAssertEqual(EngineReport.inspect(environment:environment).appPath,applications.resolvingSymlinksInPath().path)
            let remembered=root.appendingPathComponent("Mine/fm.app");try app(remembered)
            XCTAssertEqual(EngineReport.inspect(preferredApp:remembered,environment:environment).discoverySource,"上次指定的位置")
            let external=environment.volumes[0].appendingPathComponent("SteamLibrary/steamapps/common/Football Manager 27/fm.app");try app(external)
            XCTAssertEqual(EngineReport.inspect(preferredApp:root.appendingPathComponent("stale.app"),environment:environment).appPath,external.resolvingSymlinksInPath().path)
        }
    }
    func testManualFolderWrongVersionAndMissingGame() throws {
        try fixture { root,environment in
            XCTAssertFalse(EngineReport.inspect(environment:environment).installationFound)
            let game=root.appendingPathComponent("Selected Game")
            try app(game.appendingPathComponent("fm.app"))
            XCTAssertTrue(EngineReport.inspect(app:game,environment:environment).installationFound)
            let wrong=root.appendingPathComponent("Old/fm.app");try app(wrong,version:"26.0.0")
            XCTAssertFalse(EngineReport.inspect(app:wrong,environment:environment).installationFound)
            XCTAssertTrue(EngineReport.steamLibraries("\"1\" \"/External/Steam Library\"").contains("/External/Steam Library"))
        }
    }
    func testExternalApplicationSupportSteamWithoutHomeSymlink() throws {
        try fixture { root,environment in
            let actual=environment.volumes[0].appendingPathComponent("Application Support/Steam/steamapps/common/Football Manager 27/fm.app")
            try app(actual)
            let report=EngineReport.inspect(environment:environment)
            XCTAssertEqual(report.appPath,actual.resolvingSymlinksInPath().path)
            XCTAssertTrue(report.installationFound)
            XCTAssertTrue(report.diagnostics.contains{$0.title=="Steam 动态库" && !$0.passed})
            XCTAssertFalse(report.canSimulate)
        }
    }
}
