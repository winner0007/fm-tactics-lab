import Foundation

public struct LeagueTeamTotal:Identifiable {
    public let id:UUID
    public let name:String
    public var games=0
    public var forTotals:[String:Double]=[:],againstTotals:[String:Double]=[:]
    public func mean(_ key:String,against:Bool=false)->Double? {(against ? againstTotals:forTotals)[key].map{$0/Double(max(1,games))}}
    public static func aggregate(run:LeagueRun,season:Int)->[Self] {
        var teams=Dictionary(uniqueKeysWithValues:run.setup.teams.map{($0.id,Self(id:$0.id,name:$0.name))})
        for game in run.results where game.season==season {
            for (side,id) in [(0,game.fixture.home),(1,game.fixture.away)] {
                teams[id]!.games+=1
                for (k,v) in game.report.teams.first(where:{$0.side==side})!.statistics {teams[id]!.forTotals[k,default:0]+=v}
                for (k,v) in game.report.teams.first(where:{$0.side==1-side})!.statistics {teams[id]!.againstTotals[k,default:0]+=v}
            }
        }
        return run.table(season:season).compactMap{teams[$0.id]}
    }
}
public struct LeaguePlayerTotal:Identifiable {
    public let id:String
    public let teamID:UUID
    public let teamName:String
    public let name:String
    public var statistics:[String:Double]=[:]
    public static func aggregate(run:LeagueRun,season:Int)->[Self] {
        var values:[String:Self]=[:]
        for game in run.results where game.season==season {
            for player in game.report.players {
                guard let identity=game.report.roster?.first(where:{$0.side==player.side && $0.nativeID==player.nativeID}),let config=game.report.configuration else{continue}
                let team=player.side==0 ? game.fixture.home:game.fixture.away,key=team.uuidString+":"+identity.playerID
                var value=values[key] ?? Self(id:key,teamID:team,teamName:config.teams[player.side].name,name:identity.name)
                for (metric,total) in player.statistics {value.statistics[metric,default:0]+=total}
                values[key]=value
            }
        }
        return values.values.sorted {a,b in
            let ga=a.statistics["goals"] ?? 0,gb=b.statistics["goals"] ?? 0
            if ga != gb{return ga>gb};let xa=a.statistics["xg"] ?? 0,xb=b.statistics["xg"] ?? 0
            return xa==xb ? a.id<b.id:xa>xb
        }
    }
}
public enum LeagueExport {
    static func escape(_ s:String)->String {s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;")}
    static func table(_ heads:[String],_ rows:[[String]])->String {
        let header=heads.map{"<th>"+escape($0)+"</th>"}.joined()
        let body=rows.map{row in "<tr>"+row.map{"<td>"+escape($0)+"</td>"}.joined()+"</tr>"}.joined()
        return "<table><thead><tr>"+header+"</tr></thead><tbody>"+body+"</tbody></table>"
    }
    public static func html(_ run:LeagueRun)->String {
        var body="<h1>"+escape(run.setup.name)+" · 联赛实验报告</h1>"
        body+="<p>FM 原版引擎 "+escape(run.results.first?.report.engineVersion ?? "")+" · "+escape(run.status)+" · 有效 \(run.results.count) / \(run.expected) 场 · 完整赛季 \(run.completedSeasons.count) / \(run.seasons)</p>"
        body+="<p>"+escape(run.setup.rules.description)+"</p><p>"+escape(run.setup.rules.limitation)+"</p><p>来源："+escape(run.setup.source)+"</p>"
        if let failure=run.failure {body+="<p>未完成原因："+escape(failure)+"</p>"}
        if let source=run.setup.rules.ranking.source {body+="<p><a href='"+escape(source)+"'>积分与排名规则依据</a></p>"}
        for season in 1...run.seasons {
            let results=run.results.filter{$0.season==season},standings=run.table(season:season)
            if results.isEmpty {continue}
            body+="<h2>第 \(season) 次赛季 · "+(run.completedSeasons.contains(season) ? "完整赛季":"尚未完成")+"</h2>"
            body+=table(["排名","球队","赛","胜","平","负","进","失","净胜","积分"],standings.map{[String($0.rank)+($0.tied ? " 并列／待决":""),$0.name,String($0.played),String($0.wins),String($0.draws),String($0.losses),String($0.goalsFor),String($0.goalsAgainst),String($0.goalDifference),String($0.points)]})
            let maxPoints=max(1,standings.map(\.points).max() ?? 1)
            body+="<h3>积分分布</h3><svg viewBox='0 0 900 \(standings.count*32+20)' role='img' aria-label='积分分布'>"
            for (i,row) in standings.enumerated() {let y=i*32+12,width=580*row.points/maxPoints;body+="<text x='0' y='\(y+15)'>"+escape(row.name)+"</text><rect x='220' y='\(y)' width='\(width)' height='22' fill='#267353'/><text x='\(230+width)' y='\(y+15)'>\(row.points)</text>"};body+="</svg>"
            let keys=["goals","xg","shots","shots_on_target","passes","completed_passes","yellow_cards","red_cards"]
            body+="<h3>球队场均数据（己方 / 对手）</h3>"+table(["球队","有效场次","xG","射门","射正","传球","成功传球","控球 %","黄牌","红牌"],LeagueTeamTotal.aggregate(run:run,season:season).map{t in [t.name,String(t.games)]+["xg","shots","shots_on_target","passes","completed_passes","possession","yellow_cards","red_cards"].map{k in [t.mean(k),t.mean(k,against:true)].map{$0.map{String(format:"%.2f",$0)} ?? "—"}.joined(separator:" / ")}})
            body+="<h3>球员累计数据</h3>"+table(["球员","球队","进球","xG","射门","射正","传球","成功传球","黄牌","红牌"],LeaguePlayerTotal.aggregate(run:run,season:season).map{p in [p.name,p.teamName]+keys.map{key in p.statistics[key].map{String(format:key=="xg" ? "%.2f":"%.0f",$0)} ?? "—"}})
            body+="<h3>全部逐场成绩</h3>"+table(["日期／轮次","主队","比分","客队","种子","配置指纹"],results.map{g in [g.fixture.date ?? String(g.fixture.round),g.report.configuration?.teams[0].name ?? "主队","\(g.report.score[0]):\(g.report.score[1])",g.report.configuration?.teams[1].name ?? "客队",String(g.report.seed),g.report.configurationSHA256 ?? "缺失"]})
        }
        if run.completedSeasons.count>1 {
            body+="<h2>重复赛季排名范围</h2>"
            let rows=run.setup.teams.map{t -> [String] in let ranks=run.completedSeasons.compactMap{run.table(season:$0).first{$0.id==t.id}?.rank};return [t.name,String(format:"%.2f",Double(ranks.reduce(0,+))/Double(max(1,ranks.count))),String(ranks.min() ?? 0),String(ranks.max() ?? 0)]}
            body+=table(["球队","平均排名","最好","最差"],rows)
        }
        body+="<h2>面对不同战术的表现（全部已完成比赛）</h2><p>按实际开赛的完整战术分组，己方战术不同另列。CA 为首发平均当前能力（0–200）。样本数、主客场和球员强度都会影响结果，不能仅凭胜率断定战术克制。</p>"
        for team in run.setup.teams {
            let rows=TacticPerformance.aggregate(run:run,teamID:team.id)
            body+="<h3>"+escape(team.name)+"</h3>"
            body+=table(["对手有球 / 无球","对手战术指纹","己方战术指纹","对手球队","场次（主 / 客）","胜 / 平 / 负","胜率","场均进 / 失球","场均 xG / 失 xG","己方 / 对手首发 CA","对手 CA 范围"],rows.map {r in
                [r.opponentShape,r.opponentKey,r.ownKey,r.opponents.sorted().joined(separator:"、"),"\(r.games)（\(r.homeGames) / \(r.awayGames)）","\(r.wins) / \(r.draws) / \(r.losses)",String(format:"%.1f%%",r.winRate*100),String(format:"%.2f / %.2f",Double(r.goalsFor)/Double(r.games),Double(r.goalsAgainst)/Double(r.games)),r.xgGames>0 ? String(format:"%.2f / %.2f",r.xgFor/Double(r.xgGames),r.xgAgainst/Double(r.xgGames)):"—",String(format:"%.1f / %.1f",r.ownAbility,r.opponentAbility),String(format:"%.1f–%.1f",r.opponentAbilityMin,r.opponentAbilityMax)]
            })
        }
        body+="<h2>球队阵容、教练与战术快照</h2>"
        for team in run.setup.teams {
            body+="<h3>"+escape(team.name)+"</h3><p>"+escape(team.plan.rosterSource)+"</p>"
            let m=team.plan.management
            body+="<p>主教练："+escape(m.coach?.name ?? "未指定／未读取")+" · "+(m.coachLocked ? "教练已锁定":"教练未锁定")+" · "+(m.tacticLocked ? "战术已锁定":"战术未锁定")+" · "+escape(m.tacticSource)+"</p>"
            if let config=run.results.lazy.compactMap({g in g.fixture.home==team.id ? g.report.configuration?.teams[0]:g.fixture.away==team.id ? g.report.configuration?.teams[1]:nil}).first {
                body+="<p>有球 "+escape(config.formation)+" / 无球 "+escape(config.defendingFormation)+"</p>"
                body+=table(["名单","球员","生成档次","相关属性均值","CA"],config.players.enumerated().map{i,p in [i<11 ? "首发 \(i+1)":"候补",p.name,p.abilityTier,String(format:"%.1f",p.attributeMean),String(p.profile["11"] ?? 0)]})
                for (title,lines) in [("开赛状态",config.conditionLines),("个人指令",config.playerInstructionLines),("定位球与队长",config.setPieceLines)] {body+="<details><summary>"+title+"</summary>"+lines.map{"<p>"+escape($0)+"</p>"}.joined()+"</details>"}
            }
        }
        body+="<p>结果仅描述本次固定阵容实验。并列名次未做虚假的字母排序决胜；未完赛比赛不计入积分或球员统计。完整 JSON 保留双方阵容与每场原版回读记录。</p>"
        return "<!doctype html><html lang='zh-CN'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>联赛实验报告</title><style>body{max-width:1200px;margin:36px auto;padding:0 24px;font:14px/1.6 -apple-system,sans-serif;color:#20372b}table{border-collapse:collapse;width:100%;font-size:11px;margin:20px 0}td,th{padding:8px;border-bottom:1px solid #ddd;text-align:left;overflow-wrap:anywhere}th{background:#e8f1eb}p{color:#52675c}svg{width:100%;font-size:12px}h2{margin-top:36px}@media print{tr{break-inside:avoid}}</style>"+body+"</html>"
    }
}
