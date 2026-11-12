import Foundation
import TacticsCore

/// Real-save smoke check. Uses private output and never opens the user's app data.
@main struct CheckSaveImport {
    static func main() throws {
        let a = CommandLine.arguments
        guard a.count == 6 || (a.count==7 && a[6]=="--preflight-only") else { throw LabError("usage: check-save-import catalog.json rosters.json output helper fm.app [--preflight-only]") }
        let catalog = try JSONDecoder().decode(SaveCatalog.self, from: Data(contentsOf: URL(fileURLWithPath:a[1]))).validated()
        let data = try JSONDecoder().decode(SavedRosterExport.self, from: Data(contentsOf: URL(fileURLWithPath:a[2])))
        guard catalog.sourceSHA256 == data.sourceSHA256,
              let league = catalog.leagues.first(where:{Set($0.clubIDs)==Set(data.rosters.map(\.clubID))}) else {throw LabError("存档来源或联赛成员不一致。")}
        let folder = URL(fileURLWithPath:a[3])
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var setup = LeagueSetup()
        setup.name = "存档导入验证 · #\(league.competitionID)"
        setup.source = catalog.sourceName+" · "+catalog.sourceSHA256
        setup.teams = try data.rosters.map { roster in
            do { return LeagueTeam(plan:try roster.workspace(source:catalog.sourceName),savedClubID:roster.clubID) }
            catch {throw LabError("\(roster.name)：\(error.localizedDescription)")}
        }
        let ids = Dictionary(uniqueKeysWithValues:setup.teams.map{($0.savedClubID!,$0.id)})
        let dates = Array(Set(league.fixtures.compactMap(\.date))).sorted()
        setup.importedSchedule = league.fixtures.map{f in LeagueFixture(home:ids[f.home]!,away:ids[f.away]!,round:(f.date.flatMap{dates.firstIndex(of:$0)} ?? 0)+1,date:f.date)}
        var run = try LeagueRun(setup:setup,seasons:1,seed:20261112)
        try JSONEncoder().encode(setup).write(to:folder.appendingPathComponent("league-setup.json"),options:.atomic)
        print("PASS \(setup.teams.count) teams / \(setup.teams.reduce(0){$0+$1.plan.players.count}) players / \(run.schedule.count) fixture preflights")
        fflush(stdout)
        if a.count==7 {
            run.status="尚未运行"
            try JSONEncoder().encode(run).write(to:folder.appendingPathComponent("run.json"),options:.atomic)
            print("PASS import and scenario validation only; no match engine executed")
            return
        }
        // One complete opening round exercises every imported squad.
        var seen = Set<UUID>()
        for (i,fixture) in run.schedule.enumerated() {
            if seen.count == setup.teams.count {break}
            let scenario = try setup.scenario(fixture)
            let result = try OriginalMatchJob().run(helper:URL(fileURLWithPath:a[4]),app:URL(fileURLWithPath:a[5]),seed:run.firstSeed+UInt32(i),log:folder.appendingPathComponent("matches/\(i)/match.jsonl"),scenario:scenario)
            guard result.configurationSHA256 == scenario.sha256 else {throw LabError("引擎回读来源不一致。")}
            run.results.append(LeagueResult(season:1,fixture:fixture,report:result))
            seen.formUnion([fixture.home,fixture.away])
            print("PASS \(scenario.teams[0].name) \(result.score) \(scenario.teams[1].name)");fflush(stdout)
        }
        run.status = "已停止"
        _ = try run.validated()
        try JSONEncoder().encode(run).write(to:folder.appendingPathComponent("run.json"),options:.atomic)
        try Data(LeagueExport.html(run).utf8).write(to:folder.appendingPathComponent("report.html"),options:.atomic)
        print("PASS \(run.results.count) original-engine matches; all \(seen.count) imported teams played")
    }
}
