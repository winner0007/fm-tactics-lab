// Opt-in integration check using the user's installed game and private inputs.
// Arguments: output folder, helper executable, fm.app, optional roster-export JSON.
import Foundation
import TacticsCore
@main struct CheckTactics {
    static func main()throws {
        let a=CommandLine.arguments,root=URL(fileURLWithPath:a[1]),helper=URL(fileURLWithPath:a[2]),app=URL(fileURLWithPath:a[3])
        var candidates:[Workspace]=[]
        for mode in 0..<3 {
            var w=Workspace.example();w.management.selection = .originalAI
            if mode>0 {var o=w.opponent!.workspace;o.management.selection = .originalAI;w.opponent=OpponentPlan(o)}
            if mode==2 {var rng=SystemRandomNumberGenerator();for _ in 0..<9 {w.addCandidate(using:&rng)};var o=w.opponent!.workspace;for _ in 0..<9{o.addCandidate(using:&rng)};w.opponent=OpponentPlan(o)}
            candidates.append(w)
        }
        if a.count>4 {
            let imported=try JSONDecoder().decode(SavedRosterExport.self,from:Data(contentsOf:URL(fileURLWithPath:a[4])))
            let teams=try imported.rosters.map{LeagueTeam(plan:try $0.workspace(source:imported.sourceName),savedClubID:$0.clubID)}
            var setup=LeagueSetup();setup.teams=teams
            let run=try LeagueRun(setup:setup,seasons:1,seed:42)
            print("PASS imported",teams.count,"clubs",teams.reduce(0){$0+$1.plan.players.count},"players",run.schedule.count,"fixtures")
            for i in 0..<min(2,teams.count-1) {
                var w=teams[i].plan,o=teams[i+1].plan;w.management.selection = .originalAI;o.management.selection = .originalAI;w.opponent=OpponentPlan(o);candidates.append(w)
            }
        }
        for (i,w) in candidates.enumerated() {
            let requested=try NativeScenario(workspace:w),folder=root.appendingPathComponent("case-\(i)")
            let prep=try TacticGenerationJob().run(helper:helper,app:app,scenario:requested,seed:42,folder:folder)
            let resolved=try prep.resolved
            let repeatPrep=try TacticGenerationJob().run(helper:helper,app:app,scenario:requested,seed:42,folder:folder.appendingPathComponent("repeat"))
            guard try repeatPrep.resolved==resolved else {throw LabError("Identical generation seed changed output")}
            let report=try OriginalMatchJob().run(helper:helper,app:app,seed:42,log:folder.appendingPathComponent("match.jsonl"),scenario:resolved)
            guard report.configuration==resolved,report.players.count==resolved.teams.reduce(0,{$0+$1.players.count}) else {throw LabError("Roster linkage failed")}
            try JSONEncoder().encode(report).write(to:folder.appendingPathComponent("report.json"))
            print("PASS original AI",i,resolved.teams.map{$0.formation+" / "+$0.defendingFormation},report.score,report.players.count,"players; deterministic preparation")
        }
    }
}
