import Foundation
import TacticsCore

@main struct CheckSimulationFeatures {
    @MainActor static func main() async throws {
        setbuf(stdout,nil)
        let args=CommandLine.arguments
        guard args.count==4 else{throw LabError("usage: features output helper fm.app")}
        let root=URL(fileURLWithPath:args[1]),helper=URL(fileURLWithPath:args[2]),app=URL(fileURLWithPath:args[3])
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var w=Workspace.example(),rng=FixedRandom()
        w.applyAbility(.professional,scope:.team,using:&rng)
        w.createStrategy();w.matchStrategy!.enabled=true
        w.selectStrategyPlan(1);w.tactic.apply(Formation.allCases[11],phase:.possession);w.tactic.apply(Formation.allCases[11],phase:.defending)
        w.selectStrategyPlan(2);w.tactic.apply(Formation.allCases[2],phase:.possession);w.tactic.apply(Formation.allCases[2],phase:.defending)
        w.selectStrategyPlan(0)
        var early=StrategyRule();early.condition = .any;early.target=1
        var late=early;late.id=UUID();late.fromMinute=75;late.target=2
        w.matchStrategy!.rules=[late,early]
        var opponent=w;opponent.opponent=nil;opponent.tactic.name="双向临场策略";w.opponent=OpponentPlan(opponent)
        let dynamic=try NativeScenario(workspace:w)
        var controlWorkspace=w;controlWorkspace.matchStrategy!.enabled=false;controlWorkspace.opponent!.matchStrategy!.enabled=false
        let fixed=try NativeScenario(workspace:controlWorkspace)
        try dynamic.data.write(to:root.appendingPathComponent("dynamic-configuration.json"))
        func batch(_ name:String,indices:[Int],workers:Int,queue:MatchQueue=MatchQueue(),stopAfterFirst:Bool=false) async throws->[OriginalMatchReport] {
            var results:[OriginalMatchReport]=[]
            try await queue.run(indices:indices,workers:workers,helper:helper,app:app,request:{i in
                let scenario:NativeScenario?=name.hasPrefix("baseline") ? nil:(i%2==0 ? dynamic:fixed)
                return MatchRequest(index:i,seed:UInt32(i+1),log:root.appendingPathComponent(name).appendingPathComponent("\(i)/match.jsonl"),scenario:scenario)
            },accept:{input,r in
                try JSONEncoder().encode(r).write(to:input.log.deletingLastPathComponent().appendingPathComponent("result.json"),options:.atomic)
                results.append(r)
                if stopAfterFirst {queue.cancel()}
            })
            return results.sorted{$0.seed<$1.seed}
        }
        let started=Date()
        let serial=try await batch("serial",indices:Array(0..<8),workers:1)
        let serialTime=Date().timeIntervalSince(started),parallelStart=Date()
        let parallel=try await batch("parallel",indices:Array(0..<8),workers:4)
        let parallelTime=Date().timeIntervalSince(parallelStart)
        for (a,b) in zip(serial,parallel) {
            precondition(a.seed==b.seed && a.score==b.score && a.teams==b.teams && a.players==b.players && a.timeline==b.timeline && a.goals==b.goals && a.strategyEvents==b.strategyEvents)
            if a.configuration?.schemaVersion==2 {precondition(a.strategyEvents?.count==4);precondition(a.strategyEvents!.map(\.clock)==[14400,14400,18000,18000])}
        }
        print("PASS serial / 4 workers: scores, teams, players, timeline, goals and live switches identical; \(serialTime)s / \(parallelTime)s")
        let firstDynamic=serial[0],control=try OriginalMatchJob().run(helper:helper,app:app,seed:1,log:root.appendingPathComponent("control/match.jsonl"),scenario:fixed)
        precondition(firstDynamic.timeline.filter{$0.clock<14400}==control.timeline.filter{$0.clock<14400})
        print("PASS dynamic / fixed identical before the first original-command switch")
        let cancelled=try await batch("cancel",indices:Array(0..<12),workers:4,stopAfterFirst:true)
        precondition(!cancelled.isEmpty && cancelled.count<12)
        let pending=try SimulationConcurrency.missing(requested:12,firstSeed:1,seeds:cancelled.map(\.seed))
        let resumed=try await batch("resume",indices:pending,workers:2)
        let stillMissing=try SimulationConcurrency.missing(requested:12,firstSeed:1,seeds:(cancelled+resumed).map(\.seed));precondition(stillMissing.isEmpty)
        print("PASS cancellation drains owned hosts; resume fills \(pending.count) missing indices without duplicates")
        let baselines=try await batch("baseline-events",indices:Array(0..<64),workers:4)
        let varMatch=baselines.first{$0.seed==5}!
        precondition(varMatch.score==[3,3] && varMatch.goals?.count==6 && varMatch.goals!.filter{$0.type==2}.count==1)
        let methods=Dictionary(grouping:baselines.flatMap{$0.goals ?? []},by:\.method).mapValues(\.count)
        print("PASS 64 final event registries, all scorer / assist identities and totals; VAR cancellation excluded; \(methods)")
        let flipped=TacticalImpact(baselines,focusSides:Dictionary(uniqueKeysWithValues:baselines.map{($0.seed,1)})),normal=TacticalImpact(baselines)
        precondition(flipped.mean("goals",side:0)==normal.mean("goals",side:1) && flipped.mean("xg",side:0)==normal.mean("xg",side:1))
        precondition(flipped.timing.filter{$0.side==0}.map(\.count)==normal.timing.filter{$0.side==1}.map(\.count))
        print("PASS league away-team perspective swaps all score, chance and event aggregates")
        let fixture=serial[0]
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(fixture)) as! [String:Any]
        var changes=object["strategyEvents"] as! [[String:Any]];changes[0]["to"]=0;object["strategyEvents"]=changes
        let corrupted=try JSONDecoder().decode(OriginalMatchReport.self,from:JSONSerialization.data(withJSONObject:object))
        do {_ = try OriginalMatchReport.experiment([corrupted]);throw LabError("corrupted strategy accepted")}catch {precondition(error.localizedDescription != "corrupted strategy accepted")}
        let decoded=try JSONDecoder().decode(OriginalMatchReport.self,from:JSONEncoder().encode(fixture));precondition(decoded==fixture)
        let dynamicReports=serial.filter{$0.configuration==dynamic}
        let usage=StrategyUsage.aggregate(dynamicReports,side:0)
        precondition(abs(usage.reduce(0){$0+$1.minutes}-dynamicReports.reduce(0){$0+Double($1.timeline.last!.elapsedClock)/240})<0.0001)
        precondition(usage.reduce(0){$0+$1.goalsFor}==dynamicReports.reduce(0){$0+$1.score[0]})
        for key in OriginalMatchReport.segmentCounters {
            let total=dynamicReports.reduce(0.0){$0+($1.teams.first{$0.side==0}!.statistics[key] ?? -100000)}
            precondition(abs(usage.reduce(0){$0+($1.statistics[key] ?? -100000)}-total)<0.001)
        }
        precondition(usage.allSatisfy{$0.measuredMinutes==$0.minutes})
        let goalTotal=baselines.reduce(0){$0+$1.players.filter{$0.side==0}.reduce(0){$0+($1.statistics["goals"] ?? 0)}}
        let shotTotal=baselines.reduce(0){$0+($1.teams.first{$0.side==0}!.statistics["shots"] ?? 0)}
        precondition(abs(normal.ratio("scoring_goals","shots",side:0)!-goalTotal/shotTotal)<0.000001)
        precondition(TacticMatchGroup.aggregate(serial).count==2)
        precondition(TacticalMetric.crosses.value(flipped,side:0)==TacticalMetric.crosses.value(normal,side:1))
        print("PASS crosses team/player sums, segmented counters conserve final totals, shot conversion excludes own goals, tactics stay separated")
        try Data(BatchExport.html(matches:dynamicReports,batch:nil).utf8).write(to:root.appendingPathComponent("report.html"))
        try Data("PASS deterministic parallelism, cancellation/resume, live tactics, final goals, VAR and exports".utf8).write(to:root.appendingPathComponent("validation.txt"))
    }
}
private struct FixedRandom:RandomNumberGenerator {var state:UInt64=42;mutating func next()->UInt64 {state=state &* 6364136223846793005 &+ 1442695040888963407;return state}}
