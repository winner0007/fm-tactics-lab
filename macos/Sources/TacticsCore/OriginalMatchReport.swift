import Foundation

public struct OriginalTeamStatistics: Codable, Equatable {
    public let side:Int
    public let statistics:[String:Double]
}
public struct OriginalPlayerStatistics: Codable, Equatable {
    public let side:Int
    public let nativeID:UInt32
    public let statistics:[String:Double]
}
public struct OriginalMatchPoint: Codable, Equatable, Identifiable {
    public let tick:Int
    public let clock:Int
    public let elapsedClock:Int
    public let score:[Int]
    public let xg:[Double]
    public var id:Int {tick}
    public var minute:Double {Double(elapsedClock)/240}
}

/// Only accepted after a successful, naturally completed original-engine child.
/// The bundled fixture is distinct from the editor's unbound workbench inputs.
public struct OriginalMatchReport: Codable, Equatable {
    public static let engineHash="774cacde63567fd3901c47719e7a6ed94cc3a0a62e9b94989dcac6b4890ec0e1"
    public let seed:UInt32
    public let engineSHA256:String
    public let completedAt:Date
    public let elapsedSeconds:Double
    public let finalTick:Int
    public let finalClock:Int
    public let score:[Int]
    public let teams:[OriginalTeamStatistics]
    public let players:[OriginalPlayerStatistics]
    public let timeline:[OriginalMatchPoint]
    public var minute:Double {Double(finalClock)/240}

    public static func parse(_ data:Data,exitCode:Int32,expectedSeed:UInt32) throws -> Self {
        guard data.count<=10_000_000,let text=String(data:data,encoding:.utf8) else {throw LabError("原版引擎日志过大或编码无效。")}
        let rows=try text.split(separator:"\n").map {try JSONDecoder().decode(EngineRuntimeEvent.self,from:Data($0.utf8))}
        if let failure=rows.last(where:{["failed","native_fault"].contains($0.event)}) {
            if failure.reason=="unsupported_engine_binary" {throw LabError("此引擎文件不在已验证的适配范围内。当前支持 FM27 27.0.0.2493426 的指定 Mac 版本；游戏更新后需要重新适配。没有执行比赛。")}
            if failure.signal==14 {throw LabError("原版比赛超过 45 秒时限，已停止独立进程；本场未计入结果。日志已保留。")}
            throw LabError("原版引擎未完成比赛：\(failure.reason ?? failure.event)（\(failure.stage ?? "未知阶段")）。日志已保留。")
        }
        guard exitCode==0,let loaded=rows.first(where:{$0.event=="original_engine_loaded"}),loaded.sha256==engineHash,loaded.architecture=="arm64",
              rows.contains(where:{$0.event=="engine_bootstrap_returned" && $0.accepted==true}),
              rows.contains(where:{$0.event=="native_fixture_deserialized" && $0.accepted==true}),
              rows.contains(where:{$0.event=="native_input_seed" && $0.effectiveSeed==expectedSeed}),
              rows.contains(where:{$0.event=="native_preparation_returned" && $0.gates == [1,1,1] && $0.tick==0}),
              rows.contains(where:{$0.event=="initial_score" && $0.score == [0,0]}),
              rows.filter({$0.event=="natural_match_finished"}).count==1,
              let end=rows.last,end.event=="natural_match_finished",end.fullMatchCompleted==true,end.matchesExecuted==1,
              end.schemaVersion==1,end.source=="fm_original_engine",end.input=="bundled_test_fixture",end.workbenchApplied==false,
              end.seed==expectedSeed,end.clockTicksPerMinute==240,
              let tick=end.tick,(1..<47996).contains(tick),let clock=end.clock,(21600...40000).contains(clock),
              let flags=end.flags,flags&4==4,let score=end.score,score.count==2,score.allSatisfy({(0...100).contains($0)}),
              let seconds=end.elapsedSeconds,seconds.isFinite,seconds>0,
              let totals=rows.last(where:{$0.event=="native_match_statistics"}),totals.totalsVerified==true,
              let teams=totals.teams,teams.map(\.side).sorted()==[0,1],let players=totals.players else {
            throw LabError("没有通过原版自然完赛校验，退出码 \(exitCode)。初始化成功或部分进度不能算作比赛结果。")
        }
        let points=rows.filter{$0.event=="native_match_progress"}.compactMap { row -> OriginalMatchPoint? in
            guard let t=row.tick,let c=row.clock,let e=row.elapsedClock,let s=row.score,let x=row.xg else {return nil}
            return OriginalMatchPoint(tick:t,clock:c,elapsedClock:e,score:s,xg:x)
        }
        guard !points.isEmpty,points.last?.tick==tick,points.last?.clock==clock,points.last?.score==score else {throw LabError("比赛进度与终场结果不一致。")}
        var lastTick=0,lastElapsed=0
        for p in points {
            guard p.tick>lastTick,p.clock>=0,p.clock<=clock,p.elapsedClock>=lastElapsed,p.elapsedClock<=40000,p.score.count==2,p.score.allSatisfy({(0...100).contains($0)}),p.xg.count==2,p.xg.allSatisfy({$0.isFinite && (0...100).contains($0)}) else {throw LabError("比赛进度记录无效。")}
            lastTick=p.tick;lastElapsed=p.elapsedClock
        }
        guard points.last?.elapsedClock==end.elapsedClock,lastElapsed>=clock else {throw LabError("累计比赛时钟校验失败。")}
        for team in teams {
            let subset=players.filter{$0.side==team.side}
            guard (11...26).contains(subset.count),Set(subset.map(\.nativeID)).count==subset.count else {throw LabError("球员统计身份或名单数量无效。")}
            for key in ["shots","shots_on_target","passes","completed_passes","xg","yellow_cards","red_cards"] {
                guard let value=team.statistics[key],value.isFinite,subset.allSatisfy({$0.statistics[key] != nil}),abs(subset.reduce(0){$0+($1.statistics[key] ?? 0)}-value)<0.001 else {throw LabError("球队与球员统计合计不一致：\(key)。")}
            }
        }
        guard players.allSatisfy({[0,1].contains($0.side)}) else {throw LabError("球员所属球队无效。")}
        let result=Self(seed:expectedSeed,engineSHA256:engineHash,completedAt:Date(),elapsedSeconds:seconds,finalTick:tick,finalClock:clock,score:score,teams:teams,players:players,timeline:points)
        _ = try Self.experiment([result]).validated()
        return result
    }

    public static func experiment(_ reports:[Self]) throws -> Experiment {
        guard !reports.isEmpty,reports.allSatisfy({r in
            r.engineSHA256==engineHash && r.score.count==2 && r.teams.map(\.side).sorted()==[0,1] &&
            r.timeline.allSatisfy({$0.xg.count==2 && $0.score.count==2 && $0.xg.allSatisfy({$0.isFinite && $0>=0})})
        }) else {throw LabError("保存的原版比赛报告不完整。")}
        let variant="FM 原版内置基线",opponent="内置测试客队 · 27.0.0.2493426"
        let metrics=StatMetric.team.filter{$0.id != "goals"}
        let header=["variant","seed","opponent","venue","goals_for","goals_against"]+metrics.flatMap{[$0.id+"_for",$0.id+"_against"]}
        var rows=[[String]]();rows.append(header)
        for r in reports {
            var values=[variant,String(r.seed),opponent,"home",String(r.score[0]),String(r.score[1])]
            for metric in metrics {for side in 0...1 {values.append(r.teams.first{$0.side==side}?.statistics[metric.id].map{String($0)} ?? "")}}
            rows.append(values)
        }
        var e=try Experiment.load(CSV.encode(rows),source:"FM 原版引擎 · 内置测试阵容（未使用工作台配置）")
        var playerRows=[["variant","seed","opponent","venue","player_id","player_name","team"]+StatMetric.player.map(\.id)]
        for r in reports {for p in r.players {
            var values=[variant,String(r.seed),opponent,"home",String(p.nativeID),"测试球员 #\(p.nativeID)",p.side==0 ? "for" : "against"]
            for m in StatMetric.player {values.append(p.statistics[m.id].map{String($0)} ?? "")}
            playerRows.append(values)
        }}
        e.playerRecords=try PlayerMatchRecord.load(CSV.encode(playerRows),experiment:e)
        return e
    }
}

private struct EngineRuntimeEvent:Decodable {
    let event:String
    let reason:String?,stage:String?,sha256:String?,architecture:String?,source:String?,input:String?
    let accepted:Bool?,fullMatchCompleted:Bool?,workbenchApplied:Bool?,totalsVerified:Bool?
    let seed:UInt32?,effectiveSeed:UInt32?
    let tick:Int?,clock:Int?,elapsedClock:Int?,flags:UInt32?,matchesExecuted:Int?,schemaVersion:Int?,clockTicksPerMinute:Int?,signal:Int?
    let elapsedSeconds:Double?
    let gates:[Int]?,score:[Int]?,xg:[Double]?
    let teams:[OriginalTeamStatistics]?,players:[OriginalPlayerStatistics]?
}
