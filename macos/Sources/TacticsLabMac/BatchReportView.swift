import SwiftUI
import Charts
import TacticsCore

struct BatchReportView:View {
    @EnvironmentObject var store:LabStore
    private var reports:[OriginalMatchReport] {store.originalReports}
    private var summary:BatchSummary {BatchSummary(reports)}
    private var config:NativeScenario? {reports.first?.configuration}
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Card {
                HStack {
                    VStack(alignment:.leading,spacing:5) {Text("战术测试报告").font(.system(size:23,weight:.bold));Text(config.map{$0.teams[0].name+"  vs  "+$0.teams[1].name} ?? "FM 原版内置基线").font(.system(size:14)).foregroundStyle(Theme.muted)}
                    Spacer();Chip(text:store.batch?.status ?? "已完成")
                    Button("导出完整报告"){store.exportSimulationReport()}
                }
                HStack {
                    Metric(title:"有效 / 计划场数",value:"\(reports.count) / \(store.batch?.requested ?? reports.count)")
                    Metric(title:"胜 / 平 / 负",value:"\(summary.wins) / \(summary.draws) / \(summary.losses)")
                    Metric(title:"胜率",value:String(format:"%.1f%%",summary.winRate*100))
                    Metric(title:"场均积分",value:String(format:"%.2f",summary.points))
                }
                let ci=summary.winInterval
                Text(String(format:"胜率 95%% 区间：%.1f%%–%.1f%%。",ci.lowerBound*100,ci.upperBound*100)+(reports.count<100 ? "样本偏少，建议增加场数，并测试不同对手。":"区间反映本配置在不同随机种子下的波动；不代表面对所有球队的胜率。")).font(.system(size:12)).foregroundStyle(Theme.muted)
                if let failure=store.batch?.failure {Text("未完成原因："+failure).font(.system(size:12)).foregroundStyle(Theme.amber)}
                Text(config==nil ? "数据来源：原版引擎的内置测试阵容。":"数据来源：FM 原版引擎；双方首发、属性、角色与指令均通过开赛前回读。").font(.system(size:11)).foregroundStyle(Theme.green)
            }
            if !reports.isEmpty {
                HStack(alignment:.top,spacing:18) {
                    Card {
                        Text("场均进球与预期进球").font(.system(size:15,weight:.semibold))
                        Chart {
                            ForEach(["goals","xg"],id:\.self) {key in
                                ForEach(0..<2,id:\.self) {side in
                                    if let value=summary.mean(key,side:side) {BarMark(x:.value("指标",key=="goals" ? "进球":"xG"),y:.value("场均",value)).foregroundStyle(by:.value("球队",side==0 ? "本队":"对手")).position(by:.value("球队",side)).annotation(position:.top){Text(String(format:"%.2f",value)).font(.system(size:10))}}
                                }
                            }
                        }.chartForegroundStyleScale(["本队":Theme.green,"对手":Theme.amber]).frame(height:200)
                    }
                    Card {
                        Text("累计胜率 · 观察结果是否稳定").font(.system(size:15,weight:.semibold))
                        Chart(cumulative) {p in LineMark(x:.value("有效场数",p.id),y:.value("胜率 %",p.value)).foregroundStyle(Theme.green)}.chartYScale(domain:0...100).frame(height:200)
                    }
                }
                if let config {
                    ForEach(0..<2,id:\.self) {side in LineupSnapshot(team:config.teams[side],side:side)}
                    DisclosureGroup("测试条件与配置指纹") {
                        VStack(alignment:.leading,spacing:7) {
                            Text("引擎：\(reports.first!.engineVersion) · Apple Silicon · 原版自然完赛")
                            Text("随机种子：\(reports.first!.seed)–\(reports.last!.seed) · 主队固定主场")
                            Text("配置 SHA-256："+config.sha256).textSelection(.enabled)
                            ForEach(config.teams[0].notes,id:\.self){Text($0)}
                        }.font(.system(size:11)).foregroundStyle(Theme.muted).frame(maxWidth:.infinity,alignment:.leading).padding(.top,8)
                    }.padding(16).background(.white,in:RoundedRectangle(cornerRadius:12))
                }
                if let e=store.experiment {TeamCharts(experiment:e);PlayerTotalsChart(experiment:e)}
            }
        }
    }
    private var cumulative:[CumulativePoint] {
        var wins=0
        return reports.enumerated().map{i,r in if r.score[0]>r.score[1] {wins+=1};return CumulativePoint(id:i+1,value:100*Double(wins)/Double(i+1))}
    }
}
private struct CumulativePoint:Identifiable {let id:Int;let value:Double}
struct LineupSnapshot:View {
    let team:NativeTeamInput
    let side:Int
    var body:some View {
        Card {
            HStack {Text((side==0 ? "本队":"对手")+" · 实际测试阵容").font(.system(size:17,weight:.semibold));Spacer();Text("\(team.players.count) 人 · "+NativeCatalog.mentalities[team.mentality-1]).font(.system(size:12)).foregroundStyle(Theme.muted)}
            Text("有球：\(team.formation)　无球：\(team.defendingFormation)").font(.system(size:12))
            HStack {Text("球员").frame(width:150,alignment:.leading);Text("生成档次 / 相关均值").frame(width:150,alignment:.leading);Text("有球位置 · 角色").frame(maxWidth:.infinity,alignment:.leading);Text("无球位置 · 角色").frame(maxWidth:.infinity,alignment:.leading)}.font(.system(size:11)).foregroundStyle(Theme.muted)
            ForEach(Array(team.players.enumerated()),id:\.element.id) {i,p in
                HStack {Text("\(i<11 ? String(i+1):"替补")  \(p.name)").frame(width:150,alignment:.leading);Text(p.abilityTier+String(format:" · %.1f",p.attributeMean)).frame(width:150,alignment:.leading);Text(cell(i,0)).frame(maxWidth:.infinity,alignment:.leading);Text(cell(i,1)).frame(maxWidth:.infinity,alignment:.leading)}.font(.system(size:11))
            }
            DisclosureGroup("球队指令快照") {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:8) {
                    ForEach(team.instructions,id:\.group){v in
                        let group=NativeCatalog.teamInstructions.first{$0.id==v.group}!
                        Text(group.label+"："+(group.options.first{$0.id==v.value}?.label ?? "—")).font(.system(size:11)).frame(maxWidth:.infinity,alignment:.leading)
                    }
                }.padding(.top,8)
            }
            DisclosureGroup("个人指令覆盖") {ForEach(team.playerInstructionLines,id:\.self){Text($0).font(.system(size:11)).frame(maxWidth:.infinity,alignment:.leading)}}
            DisclosureGroup("定位球与队长快照") {ForEach(team.setPieceLines,id:\.self){Text($0).font(.system(size:11)).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,3)}}
            DisclosureGroup("开赛状态与 CA") {ForEach(team.conditionLines,id:\.self){Text($0).font(.system(size:11)).frame(maxWidth:.infinity,alignment:.leading)}}
            Text("相关均值排除门将外场不适用项及负向／隐藏指标，仅用于查看属性分布，不是 FM 的 CA 或球队实力评分。").font(.system(size:10)).foregroundStyle(Theme.muted)
        }
    }
    private func cell(_ index:Int,_ phase:Int) -> String {
        guard index<11 else{return "—"}
        let c=team.phases[phase][index]
        return (NativeCatalog.positions.first{$0.mask==c.position}?.id ?? "?")+" · "+(NativeCatalog.roles.first{$0.phase==(phase==0 ? .possession:.defending) && String($0.flags)==c.role}?.label ?? "?")
    }
}
