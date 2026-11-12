import Foundation

public enum MatchAnalysisExport {
    private static func e(_ value:String)->String {LeagueExport.escape(value)}
    private static func n(_ value:Double?)->String {value.map{String(format:"%.2f",$0)} ?? "—"}
    private static func bars(_ title:String,_ bars:[AnalysisBar],unit:String)->String {
        var labels:[String]=[];for bar in bars where !labels.contains(bar.label) {labels.append(bar.label)}
        let maxValue=max(1,bars.map(\.count).max() ?? 1),height=60+labels.count*52
        var svg="<svg viewBox='0 0 760 \(height)' role='img' aria-label='"+e(title)+"'><text x='140' y='18' fill='#217258'>本队</text><text x='220' y='18' fill='#ad681b'>对手</text><text x='610' y='18'>单位："+unit+"</text>"
        for (i,label) in labels.enumerated() {
            let y=40+i*52;svg+="<text x='8' y='\(y+20)'>"+e(label)+"</text>"
            for side in 0...1 {
                let value=bars.first{$0.label==label && $0.side==side}?.count ?? 0
                let width=Double(value)/Double(maxValue)*500,color=side==0 ? "#217258":"#ad681b",top=y+side*20
                svg+="<rect x='140' y='\(top)' width='\(width)' height='16' fill='\(color)'/><text x='\(148+width)' y='\(top+12)'>\(value)</text>"
            }
        }
        return "<h3>"+e(title)+"</h3>"+svg+"</svg>"
    }
    public static func html(_ reports:[OriginalMatchReport],focusSides:[UInt32:Int]=[:])->String {
        let impact=TacticalImpact(reports,focusSides:focusSides)
        var body="<h2>按战术统计</h2>"
        for (index,group) in TacticMatchGroup.aggregate(reports,focusSides:focusSides).enumerated() {
            body+="<h3>战术 \(index+1) · "+e(group.shape)+" · \(group.reports.count) 场 · \(group.id.prefix(8))</h3>"
            body+=LeagueExport.table(["指标","本队","对手"],TacticalMetric.allCases.map{m in [m.title]+(0...1).map{m.format(m.value(group.impact,side:$0))}})
        }
        body+="<p>场均值只统计有该项数据的完赛记录；成功率按总量相除。射门转化率＝本队球员进球 ÷ 射门，不含对方乌龙球。控球率逐场等权平均。有进球场次占比＝至少进一球的场次 ÷ 完赛场次。缺失数据或分母为零显示 —。</p><h2>进攻效率与进球分布</h2>"
        body+=LeagueExport.table(["指标","本队","对手"],[
            ["每次射门 xG"]+(0...1).map{n(impact.ratio("xg","shots",side:$0))},
            ["射门转化率"]+(0...1).map{impact.ratio("scoring_goals","shots",side:$0).map{n($0*100)+"%"} ?? "—"},
            ["射正率"]+(0...1).map{impact.ratio("shots_on_target","shots",side:$0).map{n($0*100)+"%"} ?? "—"}])
        body+=bars("每场进球数（5+ 合并）",impact.goalDistribution,unit:"场")
        body+=LeagueExport.table(["高频比分 · 本队 : 对手","场次","占比"],impact.scores.prefix(10).map{[$0.0,String($0.1),n(Double($0.1)*100/Double(max(1,reports.count)))+"%"]})
        body+="<p>进球明细覆盖 \(impact.detailed.count) / \(reports.count) 场。只统计终场确认的进球；取消的进球已排除，旧报告缺失的明细不补零。</p>"
        if !impact.detailed.isEmpty {
            body+=bars("进球与失球时段",impact.timing,unit:"球")
            body+="<p>上、下半场补时分别归入 31–45+、76–90+。</p>"
            body+=bars("进球方式",impact.methods,unit:"球")
            body+="<p>非点球进球包含运动战、任意球等；头球、角球和进攻路线尚未单独验证。乌龙球归入受益球队。</p>"
        }
        for side in 0...1 {
            if side==1 && !focusSides.isEmpty {continue}
            let rows=StrategyUsage.aggregate(reports,side:side,focusSides:focusSides);guard !rows.isEmpty else{continue}
            body+="<h3>"+(side==0 ? "本队":"对手")+"临场方案表现</h3>"
            body+=LeagueExport.table(["方案","使用场次","累计分钟","进球","失球","xG","对手 xG"],rows.map{[$0.name,String($0.matches),n($0.minutes),String($0.goalsFor),String($0.goalsAgainst),n($0.xgFor),n($0.xgAgainst)]})
            body+=LeagueExport.table(["方案","策略编号","统计覆盖分钟","控球率","传球 / 90","传球成功率","传中 / 90","传中成功率","射门 / 90","射正 / 90"],rows.map{r in
                [r.name,String(r.tacticKey.prefix(8)),n(r.measuredMinutes),r.possession.map{n($0*100)+"%"} ?? "—",n(r.per90("passes")),r.ratio("completed_passes","passes").map{n($0*100)+"%"} ?? "—",n(r.per90("crosses")),r.ratio("completed_crosses","crosses").map{n($0*100)+"%"} ?? "—",n(r.per90("shots")),n(r.per90("shots_on_target"))]
            })
            body+="<p>分段次数按有快照的实际生效分钟换算每 90 分钟；控球率按双方控球时长计算。缺少快照的旧报告不补零。不同完整策略的同名方案分别统计。</p>"
            body+="<p>各方案面对的比分和时段不同，这些统计不构成方案优劣的因果比较。分钟数包含补时。</p>"
        }
        body+="<details><summary>逐场进球与临场切换记录</summary>"
        for r in reports {
            guard r.goals != nil || r.strategyEvents != nil else{continue}
            body+="<h3>种子 \(r.seed) · "+e(r.configuration?.teams[0].name ?? "主队")+" \(r.score[0]):\(r.score[1]) "+e(r.configuration?.teams[1].name ?? "客队")+"</h3>"
            if let goals=r.goals {
                body+=goals.isEmpty ? "<p>本场没有进球。</p>":LeagueExport.table(["时间","球队","进球者","方式","助攻"],goals.map{[$0.timeLabel,$0.side==impact.nativeSide(0,report:r) ? "本队":"对手",r.playerName($0.nativeID),$0.method,$0.assistID.map{r.playerName($0)} ?? "无助攻"]})
            }
            if let changes=r.strategyEvents,!changes.isEmpty {
                body+=LeagueExport.table(["时间","球队","比分","切换","原因"],changes.map{c in
                    let s=r.configuration!.teams[c.side].strategy!
                    return[c.timeLabel,c.side==impact.nativeSide(0,report:r) ? "本队":"对手","\(c.score[0]):\(c.score[1])",s.plans[c.from].name+" → "+s.plans[c.to].name,s.rules.first{$0.id==c.ruleID}?.label ?? "回到开场方案"]
                })
            }
        }
        return body+"</details>"
    }
}
