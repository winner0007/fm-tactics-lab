import Foundation
import TacticsCore

@main struct CheckLeagueReport {
    static func main()throws {
        let path=URL(fileURLWithPath:CommandLine.arguments[1]),data=try Data(contentsOf:path)
        let run=try JSONDecoder().decode(LeagueRun.self,from:data).validated()
        precondition(run.results.count==run.expected && run.completedSeasons.count==run.seasons)
        for s in run.completedSeasons {
            let table=run.table(season:s),totals=LeagueTeamTotal.aggregate(run:run,season:s)
            precondition(table.allSatisfy{$0.played==(run.setup.teams.count-1)*run.setup.rules.cycles})
            precondition(totals.allSatisfy{$0.games==(run.setup.teams.count-1)*run.setup.rules.cycles})
        }
        var object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        var results=object["results"] as! [[String:Any]]
        results[0]["season"]=999;object["results"]=results
        let corrupt=try JSONDecoder().decode(LeagueRun.self,from:JSONSerialization.data(withJSONObject:object))
        do {_ = try corrupt.validated();fatalError("accepted wrong season")}catch{}
        object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        results=object["results"] as! [[String:Any]]
        var report=results[0]["report"] as! [String:Any];report["score"]=[99,98];results[0]["report"]=report;object["results"]=results
        let wrongScore=try JSONDecoder().decode(LeagueRun.self,from:JSONSerialization.data(withJSONObject:object))
        do {_ = try wrongScore.validated();fatalError("accepted wrong score")}catch{}
        let html=LeagueExport.html(run)
        precondition(html.contains("球队场均数据") && html.contains("参赛球队阵容") && html.contains("球员累计数据"))
        try Data(html.utf8).write(to:path.deletingLastPathComponent().appendingPathComponent("validated-league-report.html"))
        let config=run.results[0].report.configuration!
        for key in ["20","11"] {
            var bad=try JSONSerialization.jsonObject(with:config.data) as! [String:Any],teams=bad["teams"] as! [[String:Any]],players=teams[0]["players"] as! [[String:Any]],profile=players[0]["profile"] as! [String:Any]
            profile[key]=999;players[0]["profile"]=profile;teams[0]["players"]=players;bad["teams"]=teams
            let c=try JSONDecoder().decode(NativeScenario.self,from:JSONSerialization.data(withJSONObject:bad))
            do {_ = try c.validated();fatalError("accepted out-of-range profile")}catch{}
        }
        print("PASS \(run.results.count) archived matches: identities, configurations, seed order, standings, totals; rejected altered score/season/profile; exported complete report")
    }
}
