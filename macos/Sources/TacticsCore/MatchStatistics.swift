import Foundation

public struct StatMetric:Identifiable {
    public let id:String
    public let title:String
    public let upper:Double
    public let count:Bool
    public let unit:String
    public init(_ id:String,_ title:String,_ upper:Double=10000,_ count:Bool=true,_ unit:String="") {self.id=id;self.title=title;self.upper=upper;self.count=count;self.unit=unit}
    public static let team:[StatMetric] = [
        .init("goals","进球",100),.init("xg","预期进球 xG",100,false),.init("possession","控球率",100,false,"%"),
        .init("shots","射门"),.init("shots_on_target","射正"),.init("passes","传球"),.init("completed_passes","成功传球"),
        .init("corners","角球"),.init("fouls","犯规"),.init("offsides","越位"),.init("tackles","抢断"),.init("interceptions","拦截"),
        .init("saves","扑救"),.init("yellow_cards","黄牌"),.init("red_cards","红牌")
    ]
    public static let player:[StatMetric] = [
        .init("minutes","出场分钟",150,false),.init("rating","评分",10,false),.init("goals","进球",100),.init("assists","助攻",100),
        .init("xg","xG",100,false),.init("xa","xA",100,false),.init("shots","射门"),.init("shots_on_target","射正"),
        .init("passes","传球"),.init("completed_passes","成功传球"),.init("key_passes","关键传球"),.init("chances_created","创造机会"),
        .init("tackles","抢断"),.init("interceptions","拦截"),.init("headers_won","争顶成功"),.init("dribbles","成功盘带"),
        .init("distance_km","跑动距离",50,false," km"),.init("saves","扑救"),.init("conceded","失球",100),
        .init("yellow_cards","黄牌",2),.init("red_cards","红牌",1)
    ]
    public func parse(_ value:String?,row:Int) throws -> Double? {
        guard let value,!value.isEmpty else {return nil}
        guard let n=Double(value),n.isFinite,(0...upper).contains(n),!count || n.rounded()==n else {throw LabError("第 \(row) 行 \(id) 无效，应为 0–\(Int(upper))\(count ? " 的整数" : "")；缺失数据请留空。")}
        return n
    }
    public func format(_ value:Double?) -> String {value.map{String(format:count ? "%.0f" : "%.2f",$0)+unit} ?? "—"}
}

extension MatchRecord {
    public func value(_ metric:String,side:String="for") -> Double? {
        if metric=="goals" {return Double(side=="for" ? goalsFor : goalsAgainst)}
        if metric=="xg" {return side=="for" ? xgFor : xgAgainst}
        return statistics?[metric+"_"+side]
    }
}

public struct PlayerMatchRecord:Codable,Equatable,Identifiable {
    public let matchID:String
    public let playerID:String
    public let name:String
    public let team:String
    public let statistics:[String:Double]
    public var id:String {matchID+"\u{1f}"+team+"\u{1f}"+playerID}
    public static func load(_ csv:String,experiment:Experiment) throws -> [Self] {
        let rows=try CSV.records(csv)
        guard (1...100000).contains(rows.count) else {throw LabError("球员比赛数据需要 1–100000 行。")}
        let valid=Set(experiment.records.map(\.id));var seen=Set<String>()
        return try rows.enumerated().map { index,row in
            guard let variant=row["variant"],let seed=UInt32(row["seed"] ?? ""),let opponent=row["opponent"],let venue=row["venue"],
                  let playerID=row["player_id"],!playerID.isEmpty,let name=row["player_name"],!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                  let team=row["team"],["for","against"].contains(team),
                  [variant,opponent,venue,playerID,name].allSatisfy({!$0.contains("\u{1f}")}) else {throw LabError("第 \(index+2) 行缺少比赛标识、球员标识、姓名或球队（for / against）。")}
            let matchID=[variant,String(seed),opponent,venue].joined(separator:"\u{1f}")
            guard valid.contains(matchID) else {throw LabError("第 \(index+2) 行找不到对应完整比赛，请先导入同一批次的球队结果。")}
            var stats:[String:Double]=[:]
            for metric in StatMetric.player {stats[metric.id]=try metric.parse(row[metric.id],row:index+2)}
            try validateStatRelations(stats,row:index+2)
            let record=Self(matchID:matchID,playerID:playerID,name:name,team:team,statistics:stats)
            guard seen.insert(record.id).inserted else {throw LabError("第 \(index+2) 行重复了同一球员的同场记录。")}
            return record
        }
    }
    public static var template:String {CSV.encode([["variant","seed","opponent","venue","player_id","player_name","team"]+StatMetric.player.map(\.id)])}
}

public func validateStatRelations(_ stats:[String:Double],row:Int) throws {
    for (part,total) in [("shots_on_target","shots"),("completed_passes","passes")] {
        if let a=stats[part],let b=stats[total],a>b {throw LabError("第 \(row) 行 \(part) 不能大于 \(total)。")}
    }
}

extension Experiment {
    public var teamCSV:String {
        let header=(try? CSV.parse(Self.statisticsTemplate).first) ?? []
        var rows:[[String]]=[header]
        for r in records {
            var row=[r.variant,r.seed,r.opponent,r.venue,String(r.goalsFor),String(r.goalsAgainst)]
            row.append(r.xgFor.map{String($0)} ?? "");row.append(r.xgAgainst.map{String($0)} ?? "")
            for metric in StatMetric.team where !["goals","xg"].contains(metric.id) {
                for side in ["for","against"] {row.append(r.value(metric.id,side:side).map{String($0)} ?? "")}
            }
            rows.append(row)
        }
        return CSV.encode(rows)
    }
    public var playerCSV:String {
        let header=(try? CSV.parse(PlayerMatchRecord.template).first) ?? []
        var rows:[[String]]=[header]
        for r in playerRecords ?? [] {
            var row=r.matchID.components(separatedBy:"\u{1f}")
            row.append(contentsOf:[r.playerID,r.name,r.team])
            for metric in StatMetric.player {row.append(r.statistics[metric.id].map{String($0)} ?? "")}
            rows.append(row)
        }
        return CSV.encode(rows)
    }
    public func validated() throws -> Self {
        guard excluded>=0,excluded<=20000 else {throw LabError("批次的排除场次无效。")}
        let known=Set(StatMetric.team.filter{!["goals","xg"].contains($0.id)}.flatMap{[$0.id+"_for",$0.id+"_against"]})
        guard records.allSatisfy({Set(($0.statistics ?? [:]).keys).isSubset(of:known)}),
              (playerRecords ?? []).allSatisfy({Set($0.statistics.keys).isSubset(of:Set(StatMetric.player.map(\.id)))}) else {throw LabError("统计批次含未支持的指标。")}
        let team=try Self.load(teamCSV,source:source)
        if let players=playerRecords,!players.isEmpty {
            _ = try PlayerMatchRecord.load(playerCSV,experiment:team)
        }
        return self
    }
    public static var statisticsTemplate:String {
        CSV.encode([["variant","seed","opponent","venue","goals_for","goals_against","xg_for","xg_against"]+StatMetric.team.filter{!["goals","xg"].contains($0.id)}.flatMap{[$0.id+"_for",$0.id+"_against"]}])
    }
}
