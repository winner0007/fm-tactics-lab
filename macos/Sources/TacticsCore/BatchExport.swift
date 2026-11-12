import Foundation

public enum BatchExport {
    public static func html(matches:[OriginalMatchReport],batch:SimulationBatch?) throws -> String {
        let e=try OriginalMatchReport.experiment(matches),s=BatchSummary(matches),config=matches[0].configuration
        func escape(_ text:String)->String {text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;")}
        func number(_ n:Double?)->String {n.map{String(format:"%.2f",$0)} ?? "—"}
        func table(_ headers:[String],_ rows:[[String]])->String {
            let head=headers.map{"<th>"+escape($0)+"</th>"}.joined()
            let cells=rows.map {row -> String in
                let values=row.map{"<td>"+escape($0)+"</td>"}.joined()
                return "<tr>"+values+"</tr>"
            }.joined()
            return "<table><thead><tr>"+head+"</tr></thead><tbody>"+cells+"</tbody></table>"
        }
        let title=(config?.teams[0].name ?? "内置测试主队")+" vs "+(config?.teams[1].name ?? "内置测试客队")
        var body="<h1>战术测试报告</h1><h2>"+escape(title)+"</h2>"
        body+="<p>FM 原版引擎 "+escape(matches.first?.engineVersion ?? "")+" · "+escape(batch?.status ?? "已完成")+" · 有效 \(matches.count) / 计划 \(batch?.requested ?? matches.count) 场</p>"
        body+=table(["胜 / 平 / 负","胜率","95% 胜率区间","场均积分"],[["\(s.wins) / \(s.draws) / \(s.losses)",number(s.winRate*100)+"%",number(s.winInterval.lowerBound*100)+"% – "+number(s.winInterval.upperBound*100)+"%",number(s.points)]])
        body+="<p>固定阵容、对手和主客场；不同种子只衡量该配置的随机波动。小样本不能证明战术的普遍优势。未记录指标用 — 表示，不按零补全。</p>"
        if let failure=batch?.failure {body+="<p>未完成原因："+escape(failure)+"</p>"}
        body+="<h2>双方场均数据</h2>"+table(["指标","本队","对手"],StatMetric.team.map{[$0.title,number(s.mean($0.id,side:0)),number(s.mean($0.id,side:1))]})
        var wins=0
        let points=matches.enumerated().map{i,r -> String in
            if r.score[0]>r.score[1] {wins+=1}
            let x=40+680*Double(i)/Double(max(1,matches.count-1)),y=210-180*Double(wins)/Double(i+1)
            return String(format:"%.2f,%.2f",x,y)
        }.joined(separator:" ")
        body+="<h2>累计胜率</h2><svg viewBox='0 0 760 245' role='img' aria-label='累计胜率'><path d='M40 30V210H720' fill='none' stroke='#cbd5ce'/><text x='0' y='35'>100%</text><text x='12' y='212'>0%</text><polyline points='"+points+"' fill='none' stroke='#217258' stroke-width='2'/><text x='40' y='237'>第 1 场</text><text x='620' y='237'>第 \(matches.count) 场</text></svg>"
        if let config {
            for side in 0...1 {
                let t=config.teams[side]
                body+="<h2>"+escape((side==0 ? "本队":"对手")+"阵容 · "+t.name)+"</h2><p>有球："+escape(t.formation)+"；无球："+escape(t.defendingFormation)+"；心态："+escape(NativeCatalog.mentalities[t.mentality-1])+"</p>"
                let rows=t.players.enumerated().map{i,p -> [String] in
                    var row=[i<11 ? String(i+1):"候补",p.name,p.abilityTier,number(p.attributeMean)]
                    for phase in 0...1 {
                        if i>=11 {row.append("—");continue}
                        let c=t.phases[phase][i]
                        row.append((NativeCatalog.positions.first{$0.mask==c.position}?.id ?? "?")+" · "+(NativeCatalog.roles.first{$0.phase==(phase==0 ? .possession:.defending)&&String($0.flags)==c.role}?.label ?? "?"))
                    }
                    return row
                }
                body+=table(["位置号","球员","生成档次","相关属性均值","有球角色","无球角色"],rows)
                body+="<details><summary>球队指令与测试条件</summary>"
                for v in t.instructions {let g=NativeCatalog.teamInstructions.first{$0.id==v.group}!;body+="<p>"+escape(g.label+"："+(g.options.first{$0.id==v.value}?.label ?? "—"))+"</p>"}
                for n in t.notes {body+="<p>"+escape(n)+"</p>"};body+="</details>"
                for (title,lines) in [("个人指令覆盖（其余遵循角色）",t.playerInstructionLines),("定位球与队长",t.setPieceLines),("开赛状态与 CA",t.conditionLines)] {
                    body+="<details><summary>"+title+"</summary>"+lines.map{"<p>"+escape($0)+"</p>"}.joined()+"</details>"
                }
                let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
                body+="<details><summary>完整配置（含属性、隐藏资料和原始值）</summary><pre style='white-space:pre-wrap;overflow-wrap:anywhere'>"+escape(String(decoding:try encoder.encode(t),as:UTF8.self))+"</pre></details>"
            }
            body+="<p class='hash'>配置 SHA-256："+config.sha256+"</p>"
        }
        for team in ["for","against"] {
            body+="<h2>"+(team=="for" ? "本队":"对手")+"球员累计数据</h2>"
            let metrics=StatMetric.player.filter{m in (e.playerRecords ?? []).contains{$0.team==team && $0.statistics[m.id] != nil}}
            let grouped=Dictionary(grouping:(e.playerRecords ?? []).filter{$0.team==team},by:\.playerID)
            let rows=grouped.keys.sorted().map{id -> [String] in
                let records=grouped[id]!
                return [records[0].name]+metrics.map{m in let values=records.compactMap{$0.statistics[m.id]};return values.isEmpty ? "—":number(values.reduce(0,+)/(m.id=="rating" ? Double(values.count):1))}
            }
            body+=table(["球员"]+metrics.map(\.title),rows)
        }
        body+="<h2>逐场结果</h2>"+table(["种子","比分","本队 xG","对手 xG"],matches.map{[String($0.seed),"\($0.score[0]):\($0.score[1])",number($0.teams.first{$0.side==0}?.statistics["xg"]),number($0.teams.first{$0.side==1}?.statistics["xg"])]})
        return "<!doctype html><html lang='zh-CN'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>战术测试报告</title><style>body{max-width:1100px;margin:40px auto;padding:0 24px;color:#20362c;background:#f7f8f5;font:15px/1.6 -apple-system,sans-serif}h1{font-size:32px}h2{margin-top:32px}table{width:100%;border-collapse:collapse;background:white;font-size:12px;margin:16px 0}th,td{text-align:left;padding:10px;border-bottom:1px solid #e4e9e5}th{background:#eaf1eb}svg{max-width:760px;width:100%;background:white;padding:12px}p{color:#56695e}.hash{word-break:break-all}summary{cursor:pointer}@media print{body{background:white;margin:0}details{display:block}tr{break-inside:avoid}}</style>"+body+"</html>"
    }
}
