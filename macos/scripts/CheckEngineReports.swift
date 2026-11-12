import Foundation

@main struct EngineReportsCheck {
    static func main() throws {
        let folder=URL(fileURLWithPath:CommandLine.arguments[1])
        let input=try Data(contentsOf:folder.appendingPathComponent("match-1-seed-1.jsonl"))
        let report=try OriginalMatchReport.parse(input,exitCode:0,expectedSeed:1)
        precondition(report.score == [2,1] && report.players.count==40)
        precondition(zip(report.timeline,report.timeline.dropFirst()).contains{$0.clock>$1.clock},"fixture must exercise halftime clock reset")
        precondition(zip(report.timeline,report.timeline.dropFirst()).allSatisfy{$0.elapsedClock<=$1.elapsedClock},"elapsed chart time must not run backwards")
        let experiment=try OriginalMatchReport.experiment([report]).validated()
        precondition(experiment.records.count==1 && experiment.playerRecords?.count==40)
        precondition(experiment.records[0].value("shots")==8)
        precondition(experiment.records[0].value("shots",side:"against")==11)
        let roundTrip=try JSONDecoder().decode(OriginalMatchReport.self,from:JSONEncoder().encode(report))
        precondition(roundTrip==report)
        func rejected(_ value:Data,exit:Int32=0,seed:UInt32=1) {
            do {_ = try OriginalMatchReport.parse(value,exitCode:exit,expectedSeed:seed)} catch {return}
            fatalError("Invalid engine result accepted")
        }
        rejected(input,exit:9);rejected(input,seed:2)
        let text=String(decoding:input,as:UTF8.self)
        rejected(Data(text.split(separator:"\n").dropLast().joined(separator:"\n").utf8))
        rejected(Data(text.replacingOccurrences(of:"\"fullMatchCompleted\":true",with:"\"fullMatchCompleted\":false").utf8))
        rejected(Data(text.replacingOccurrences(of:report.engineSHA256,with:"wrong-profile").utf8))
        rejected(Data(text.replacingOccurrences(of:"\"workbenchApplied\":false",with:"\"workbenchApplied\":true").utf8))
        rejected(Data(text.replacingOccurrences(of:"\"totalsVerified\":true",with:"\"totalsVerified\":false").utf8))
        var rows=try text.split(separator:"\n").map {try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
        let index=rows.firstIndex{$0["event"] as? String=="native_match_statistics"}!
        var teams=rows[index]["teams"] as! [[String:Any]]
        var stats=teams[0]["statistics"] as! [String:Any];stats["shots"]=999
        teams[0]["statistics"]=stats;rows[index]["teams"]=teams
        let corrupted=try rows.map{String(decoding:try JSONSerialization.data(withJSONObject:$0),as:UTF8.self)}.joined(separator:"\n")
        rejected(Data(corrupted.utf8))
        rejected(Data((text+"{\"event\":\"failed\",\"reason\":\"late failure\"}\n").utf8))
        rejected(try Data(contentsOf:folder.appendingPathComponent("missing-engine.jsonl")),exit:65)
        rejected(try Data(contentsOf:folder.appendingPathComponent("cancelled.jsonl")),exit:15)
        precondition(report.engineVersion==OriginalMatchReport.version(for:report.engineSHA256))
        var other=try JSONSerialization.jsonObject(with:JSONEncoder().encode(report)) as! [String:Any]
        other["engineSHA256"]=report.engineSHA256==OriginalMatchReport.engineHash ? OriginalMatchReport.updatedEngineHash:OriginalMatchReport.engineHash
        let alternate=try JSONDecoder().decode(OriginalMatchReport.self,from:JSONSerialization.data(withJSONObject:other))
        do {_ = try OriginalMatchReport.experiment([report,alternate]);fatalError("mixed engine versions accepted")}catch{}
        print("PASS real result parse, statistics, persistence, experiment linkage, 11 invalid/incomplete result gates")
    }
}
