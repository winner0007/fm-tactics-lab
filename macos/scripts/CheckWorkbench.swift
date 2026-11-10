import Foundation
import TacticsCore

@main struct CheckWorkbench {
    static func main()throws {
        let args=CommandLine.arguments
        guard args.count>=4 else {throw LabError("usage: check-workbench output helper fm.app [save-rosters.json save-catalog.json]")}
        let folder=URL(fileURLWithPath:args[1]),helper=URL(fileURLWithPath:args[2]),app=URL(fileURLWithPath:args[3])
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var scenarios:[NativeScenario]=[]
        var w=Workspace.example(),rng=FixedRandom()
        w.applyAbility(.professional,scope:.team,using:&rng)
        for f in Formation.allCases {var candidate=w;candidate.tactic.apply(f,phase:.possession);candidate.tactic.apply(f,phase:.defending);scenarios.append(try NativeScenario(workspace:candidate))}
        w.tactic.configuration!.conditions.custom=true
        w.tactic.configuration!.conditions.condition=85;w.tactic.configuration!.conditions.sharpness=90
        w.tactic.configuration!.conditions.fatigueRaw=20;w.tactic.configuration!.conditions.morale=15;w.tactic.configuration!.conditions.cohesion=35
        var sp=GameSetPieces();sp.priorities["0"]=[w.players[10].id];sp.priorities["2"]=[w.players[8].id];sp.throwStyles=[1,1,1]
        var extra=sp.routines["5"]![0];extra.id=UUID();extra.name="远点变化";extra.frequency=2;extra.strategy=2;extra.swing=1
        sp.routines["5"]!.append(extra);w.tactic.configuration!.gameSetPieces=sp
        let key=TacticalConfiguration.playerKey(2,.defending);var target=MarkTarget();target.playerID=w.opponent!.players[10].id
        w.tactic.configuration!.nativePlayers=[key:[14:34]];w.tactic.configuration!.markTargets=[key:target]
        scenarios.append(try NativeScenario(workspace:w))
        for (i,scenario) in scenarios.enumerated() {
            let dir=folder.appendingPathComponent("case-\(i)")
            let result=try OriginalMatchJob().run(helper:helper,app:app,seed:42,log:dir.appendingPathComponent("match.jsonl"),scenario:scenario)
            precondition(result.configurationSHA256==scenario.sha256)
            try JSONEncoder().encode(result).write(to:dir.appendingPathComponent("result.json"),options:.atomic)
            print("PASS native case \(i+1)/\(scenarios.count) · \(scenario.teams[0].formation) · \(result.score)")
        }
        let replay=try OriginalMatchJob().run(helper:helper,app:app,seed:42,log:folder.appendingPathComponent("replay/match.jsonl"),scenario:scenarios.last!)
        let previous=try JSONDecoder().decode(OriginalMatchReport.self,from:Data(contentsOf:folder.appendingPathComponent("case-\(scenarios.count-1)/result.json")))
        precondition(replay.score==previous.score && replay.teams==previous.teams && replay.players==previous.players && replay.timeline==previous.timeline)
        print("PASS exact seed replay with conditions, marking, captain and routine variants")
        if args.count>=6 {
            let data=try JSONDecoder().decode(SavedRosterExport.self,from:Data(contentsOf:URL(fileURLWithPath:args[4])))
            let catalog=try JSONDecoder().decode(SaveCatalog.self,from:Data(contentsOf:URL(fileURLWithPath:args[5]))).validated()
            let clubs=Set(data.rosters.map(\.clubID))
            guard let league=catalog.leagues.first(where:{Set($0.clubIDs)==clubs}),catalog.sourceSHA256==data.sourceSHA256 else {throw LabError("Imported league identity mismatch")}
            var setup=LeagueSetup();setup.name="存档完整赛程验证";setup.rules.ranking = .spanish
            setup.teams=try data.rosters.map{LeagueTeam(plan:try $0.workspace(source:data.sourceName+" · "+data.gameDate),savedClubID:$0.clubID)}
            setup.source="只读存档 · "+data.sourceSHA256
            let lookup=Dictionary(uniqueKeysWithValues:setup.teams.map{($0.savedClubID!,$0.id)})
            setup.importedSchedule=league.fixtures.enumerated().map{i,f in LeagueFixture(home:lookup[f.home]!,away:lookup[f.away]!,round:i/max(1,setup.teams.count/2)+1,date:f.date)}
            var run=try LeagueRun(setup:setup,seasons:1,seed:1000)
            try JSONEncoder().encode(setup).write(to:folder.appendingPathComponent("imported-league.json"),options:.atomic)
            for (i,fixture) in run.schedule.enumerated() {
                let scenario=try setup.scenario(fixture),dir=folder.appendingPathComponent("league-\(i)")
                let report=try OriginalMatchJob().run(helper:helper,app:app,seed:1000+UInt32(i),log:dir.appendingPathComponent("match.jsonl"),scenario:scenario)
                run.results.append(LeagueResult(season:1,fixture:fixture,report:report))
                try JSONEncoder().encode(report).write(to:dir.appendingPathComponent("result.json"),options:.atomic)
                if (i+1)%10==0 {print("PASS imported league \(i+1)/\(run.expected)");fflush(stdout)}
            }
            run.status="已完成"
            let table=run.table(season:1)
            precondition(table.allSatisfy{$0.played==2*(setup.teams.count-1)})
            precondition(table.reduce(0,{$0+$1.goalsFor})==table.reduce(0,{$0+$1.goalsAgainst}))
            try JSONEncoder().encode(run).write(to:folder.appendingPathComponent("league-run.json"),options:.atomic)
            try Data(LeagueExport.html(run).utf8).write(to:folder.appendingPathComponent("league-report.html"),options:.atomic)
            print("PASS complete real-roster league: \(table.count) clubs, \(run.results.count) original-engine matches")
        }
    }
}
private struct FixedRandom:RandomNumberGenerator {
    var state:UInt64=424242
    mutating func next()->UInt64 {state=state &* 6364136223846793005 &+ 1442695040888963407;return state}
}
