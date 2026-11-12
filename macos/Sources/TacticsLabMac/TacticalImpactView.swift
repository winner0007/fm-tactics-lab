import SwiftUI
import Charts
import TacticsCore

struct TacticalImpactView:View {
    let reports:[OriginalMatchReport]
    var focusSides:[UInt32:Int]=[:]
    @State var section="战术统计"
    @State private var selectedTime:String?
    private var impact:TacticalImpact {TacticalImpact(reports,focusSides:focusSides)}
    private let columns=[GridItem(.adaptive(minimum:360),spacing:18,alignment:.top)]
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {Text("战术效果").font(.system(size:20,weight:.bold));Spacer();teamLegend}
            Picker("战术分析",selection:$section) {ForEach(["战术统计","进攻与机会","进球分布","进球时间与方式","临场切换","逐场复盘"],id:\.self){Text($0).tag($0)}}.pickerStyle(.segmented)
            switch section {
            case "战术统计":TacticMetricsView(reports:reports,focusSides:focusSides)
            case "进球分布":distribution
            case "进球时间与方式":timing
            case "临场切换":StrategyUsageView(reports:reports,focusSides:focusSides)
            case "逐场复盘":MatchReviewView(reports:reports,focusSides:focusSides)
            default:creation
            }
        }
    }
    private var teamLegend:some View {HStack(spacing:14){Label("本队",systemImage:"circle.fill").foregroundStyle(Theme.green);Label("对手",systemImage:"circle.fill").foregroundStyle(Theme.amber)}.font(.system(size:11))}
    private func number(_ value:Double?,percent:Bool=false)->String {value.map{String(format:percent ? "%.1f%%":"%.2f",$0*(percent ? 100:1))} ?? "—"}
    private var creation:some View {
        LazyVGrid(columns:columns,spacing:18) {
            Card {
                Text("创造机会与把握机会").font(.system(size:15,weight:.semibold))
                HStack {Text("指标");Spacer();Text("本队").frame(width:65);Text("对手").frame(width:65)}.font(.caption).foregroundStyle(Theme.muted)
                ForEach([("场均进球","goals"),("场均预期进球 · xG","xg"),("场均射门","shots"),("场均射正","shots_on_target")],id:\.1){label,key in
                    statRow(label,(0...1).map{number(impact.mean(key,side:$0))})
                }
                Divider()
                statRow("每次射门 xG",(0...1).map{number(impact.ratio("xg","shots",side:$0))})
                statRow("射门转化率",(0...1).map{number(impact.ratio("scoring_goals","shots",side:$0),percent:true)})
                statRow("射正率",(0...1).map{number(impact.ratio("shots_on_target","shots",side:$0),percent:true)})
                Text("每次射门 xG 反映平均机会质量。比率按全部比赛的总量计算；没有射门时显示 —。").font(.system(size:11)).foregroundStyle(Theme.muted)
            }
            Card {
                Text("每场射门与 xG").font(.system(size:15,weight:.semibold))
                Text("越靠右射门越多，越靠上创造的总机会质量越高。").font(.system(size:11)).foregroundStyle(Theme.muted)
                Chart {
                    ForEach(reports,id:\.seed){r in ForEach(r.teams,id:\.side){t in
                        if let shots=t.statistics["shots"],let xg=t.statistics["xg"] {
                            let own=impact.nativeSide(0,report:r)==t.side
                            PointMark(x:.value("射门",shots),y:.value("xG",xg)).foregroundStyle(own ? Theme.green.opacity(0.65):Theme.amber.opacity(0.65)).symbol(own ? .circle:.square).symbolSize(30)
                                .accessibilityLabel("种子 \(r.seed)，\(own ? "本队":"对手")，射门 \(Int(shots))，xG \(number(xg))")
                        }
                    }}
                }.chartXScale(domain:0...max(1,reports.flatMap(\.teams).compactMap{$0.statistics["shots"]}.max() ?? 1))
                    .chartYScale(domain:0...max(1,reports.flatMap(\.teams).compactMap{$0.statistics["xg"]}.max() ?? 1))
                    .chartXAxisLabel("射门次数").chartYAxisLabel("预期进球 · xG").frame(height:260)
            }
        }
    }
    private func statRow(_ title:String,_ values:[String])->some View {HStack{Text(title);Spacer();Text(values[0]).foregroundStyle(Theme.green).frame(width:65);Text(values[1]).foregroundStyle(Theme.amber).frame(width:65)}.font(.system(size:12)).monospacedDigit().padding(.vertical,3)}
    private var distribution:some View {
        LazyVGrid(columns:columns,spacing:18) {
            Card {
                Text("每场进球数").font(.system(size:15,weight:.semibold))
                Text("\(reports.count) 场有效比赛 · 5 球及以上合并显示").font(.system(size:11)).foregroundStyle(Theme.muted)
                Chart(impact.goalDistribution){bar in
                    BarMark(x:.value("进球数",bar.label),y:.value("场次",bar.count)).foregroundStyle(by:.value("球队",bar.side==0 ? "本队":"对手")).position(by:.value("球队",bar.side==0 ? "本队":"对手"))
                        .annotation(position:.top){if bar.count>0 {Text("\(bar.count)").font(.system(size:10)).monospacedDigit()}}
                }.chartForegroundStyleScale(["本队":Theme.green,"对手":Theme.amber]).chartLegend(.hidden).chartYAxisLabel("场次").chartXAxisLabel("进球数").frame(height:245)
            }
            Card {
                Text("比分分布 · 本队 : 对手").font(.system(size:15,weight:.semibold))
                Text("高频比分前 10 项；每项同时显示场次与占比。").font(.system(size:11)).foregroundStyle(Theme.muted)
                Chart(Array(impact.scores.prefix(10).enumerated()),id:\.offset){_,item in
                    BarMark(x:.value("场次",item.1),y:.value("比分",item.0),height:.fixed(12)).foregroundStyle(Theme.green)
                        .annotation(position:.trailing){Text("\(item.1) · "+number(Double(item.1)/Double(max(1,reports.count)),percent:true)).font(.system(size:10)).monospacedDigit()}
                }.chartXScale(domain:0...Double(max(1,impact.scores.first?.1 ?? 1))*1.45)
                    .chartYAxis {AxisMarks(preset:.aligned,position:.leading){_ in AxisValueLabel(anchor:.trailing)}}
                    .chartXAxisLabel("场次").frame(height:280)
            }
        }
    }
    private var timing:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("终场确认进球 · 明细覆盖 \(impact.detailed.count) / \(reports.count) 场，已排除取消的进球。旧报告未记录的明细不会按零填入。").font(.system(size:12)).foregroundStyle(Theme.muted)
            if impact.detailed.isEmpty {Card{Text("这个批次没有保存进球事件。使用新版宿主重新模拟后即可查看。").foregroundStyle(Theme.muted)}}
            else {
                LazyVGrid(columns:columns,spacing:18) {
                    Card {
                        Text("进球与失球时段").font(.system(size:15,weight:.semibold))
                        Chart(impact.timing){bar in
                            BarMark(x:.value("时段",bar.label),y:.value("进球",bar.count)).foregroundStyle(by:.value("球队",bar.side==0 ? "本队":"对手")).position(by:.value("球队",bar.side==0 ? "本队":"对手"))
                                .annotation(position:.top){if bar.count>0{Text("\(bar.count)").font(.system(size:10))}}
                        }.chartForegroundStyleScale(["本队":Theme.green,"对手":Theme.amber]).chartLegend(.hidden).chartYAxisLabel("进球数").chartXSelection(value:$selectedTime).frame(height:240)
                        Text("上、下半场补时分别归入 31–45+、76–90+。"+(selectedTime.map{" 当前：\($0) 分钟。"} ?? "")).font(.system(size:11)).foregroundStyle(Theme.muted)
                    }
                    Card {
                        Text("进球方式 · 原版已核实分类").font(.system(size:15,weight:.semibold))
                        Chart(impact.methods){bar in
                            BarMark(x:.value("类型",bar.label),y:.value("进球",bar.count)).foregroundStyle(by:.value("球队",bar.side==0 ? "本队":"对手")).position(by:.value("球队",bar.side==0 ? "本队":"对手"))
                                .annotation(position:.top){if bar.count>0{Text("\(bar.count)").font(.system(size:10))}}
                        }.chartForegroundStyleScale(["本队":Theme.green,"对手":Theme.amber]).chartLegend(.hidden).chartYAxisLabel("进球数").frame(height:240)
                        Text("非点球进球包含运动战、任意球等。头球、角球和进攻路线尚未单独验证；乌龙球归入受益球队。").font(.system(size:11)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }
}

struct StrategyUsageView:View {
    let reports:[OriginalMatchReport]
    var focusSides:[UInt32:Int]=[:]
    var body:some View {
        VStack(spacing:18) {
            ForEach(0..<(focusSides.isEmpty ? 2:1),id:\.self){side in
                let rows=StrategyUsage.aggregate(reports,side:side,focusSides:focusSides)
                Card {
                    Text((side==0 ? "本队":"对手")+" · 临场方案表现").font(.system(size:15,weight:.semibold))
                    if rows.isEmpty {Text("该队使用固定战术，没有启用临场策略。").foregroundStyle(Theme.muted).font(.system(size:12))}
                    else {
                        Grid(alignment:.leading,horizontalSpacing:22,verticalSpacing:12) {
                            GridRow {ForEach(["方案","使用场次","累计分钟","进 / 失球","xG / 对手 xG"],id:\.self){Text($0).foregroundStyle(Theme.muted)}}
                            ForEach(rows){r in GridRow {Text("\(r.slot+1) · "+r.name);Text("\(r.matches)");Text(String(format:"%.1f",r.minutes));Text("\(r.goalsFor) / \(r.goalsAgainst)");Text(String(format:"%.2f / %.2f",r.xgFor,r.xgAgainst))}}
                        }.font(.system(size:12)).monospacedDigit()
                        ScrollView(.horizontal) {
                            Grid(alignment:.leading,horizontalSpacing:22,verticalSpacing:12) {
                                GridRow {ForEach(["方案","统计覆盖分钟","控球率","传球 / 90","成功传球率","传中 / 90","成功传中率","射门 / 90","射正 / 90"],id:\.self){Text($0).foregroundStyle(Theme.muted)}}
                                ForEach(rows){r in GridRow {
                                    Text("\(r.slot+1) · "+r.name)
                                    Text(String(format:"%.1f",r.measuredMinutes))
                                    Text(format(r.possession,percent:true));Text(format(r.per90("passes")))
                                    Text(format(r.ratio("completed_passes","passes"),percent:true));Text(format(r.per90("crosses")))
                                    Text(format(r.ratio("completed_crosses","crosses"),percent:true));Text(format(r.per90("shots")));Text(format(r.per90("shots_on_target")))
                                }}
                            }.font(.system(size:12)).monospacedDigit().padding(.bottom,6)
                        }
                        Text("分段传球、传中和射门换算为每 90 分钟；控球率按生效期间的双方控球时长计算。旧报告无统计快照时显示 —。不同完整策略的同名方案分别统计。").font(.system(size:11)).foregroundStyle(Theme.muted)
                        Text("按每套方案实际生效的时间统计，含补时。方案面对的比分和时段不同，这里用于观察临场表现，不能直接认定哪套战术更强。").font(.system(size:11)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }
    private func format(_ value:Double?,percent:Bool=false)->String {value.map{String(format:percent ? "%.1f%%":"%.2f",$0*(percent ? 100:1))} ?? "—"}
}

struct MatchReviewView:View {
    let reports:[OriginalMatchReport]
    var focusSides:[UInt32:Int]=[:]
    @State private var seed:UInt32?
    private var report:OriginalMatchReport? {reports.first{$0.seed==seed} ?? reports.first}
    private func own(_ side:Int,_ report:OriginalMatchReport)->Bool {side==(focusSides[report.seed] ?? 0)}
    var body:some View {
        if let report {
            Card {
                HStack {
                    Text("逐场复盘").font(.system(size:16,weight:.semibold));Spacer()
                    Picker("比赛",selection:Binding(get:{seed ?? reports.first?.seed ?? 0},set:{seed=$0})) {ForEach(reports,id:\.seed){r in Text("种子 \(r.seed) · \(r.score[0]) : \(r.score[1])").tag(r.seed)}}.frame(width:270)
                }
                Text("\(report.configuration?.teams[0].name ?? "本队")  \(report.score[0]) : \(report.score[1])  \(report.configuration?.teams[1].name ?? "对手")").font(.system(size:20,weight:.bold))
                Text("主队在左，客队在右；图表颜色按本队与对手区分。").font(.system(size:11)).foregroundStyle(Theme.muted)
                Chart {
                    ForEach(0..<2,id:\.self){side in
                        LineMark(x:.value("分钟",0),y:.value("xG",0)).foregroundStyle(by:.value("球队",own(side,report) ? "本队":"对手"))
                        ForEach(report.timeline){p in LineMark(x:.value("分钟",p.minute),y:.value("xG",p.xg[side])).foregroundStyle(by:.value("球队",own(side,report) ? "本队":"对手")).interpolationMethod(.stepEnd)}
                    }
                    ForEach(report.strategyEvents ?? []){e in RuleMark(x:.value("切换",Double(e.elapsedClock)/240)).foregroundStyle((own(e.side,report) ? Theme.green:Theme.amber).opacity(0.4)).lineStyle(StrokeStyle(lineWidth:1,dash:[3,3]))}
                }.chartForegroundStyleScale(["本队":Theme.green,"对手":Theme.amber]).chartXScale(domain:0...max(90,report.timeline.last?.minute ?? 90)).chartYAxisLabel("累计 xG").chartXAxisLabel("实际经过分钟（含补时）· 竖线为战术切换").frame(height:230)
                Text("进球记录").font(.system(size:13,weight:.semibold))
                if let goals=report.goals {
                    if goals.isEmpty {Text("本场没有进球。").font(.caption).foregroundStyle(Theme.muted)}
                    ForEach(goals){g in HStack {
                        Text(g.timeLabel).monospacedDigit().frame(width:56,alignment:.leading)
                        Text(own(g.side,report) ? "本队":"对手").foregroundStyle(own(g.side,report) ? Theme.green:Theme.amber)
                        Text(report.playerName(g.nativeID));Text(g.method).foregroundStyle(Theme.muted)
                        Spacer();Text(g.assistID.map{"助攻："+report.playerName($0)} ?? "无助攻").foregroundStyle(Theme.muted)
                    }.font(.system(size:12))}
                } else {Text("旧报告没有保存进球明细。").font(.caption).foregroundStyle(Theme.muted)}
                if let events=report.strategyEvents,!events.isEmpty {
                    Divider();Text("临场切换 · 均已通过引擎回读").font(.system(size:13,weight:.semibold))
                    ForEach(events){e in
                        let strategy=report.configuration!.teams[e.side].strategy!
                        HStack(alignment:.top){Text(e.timeLabel).monospacedDigit().frame(width:56,alignment:.leading);Text(own(e.side,report) ? "本队":"对手").foregroundStyle(own(e.side,report) ? Theme.green:Theme.amber);Text(strategy.plans[e.from].name+" → "+strategy.plans[e.to].name);Spacer();Text("\(e.score[0]):\(e.score[1]) · "+(strategy.rules.first{$0.id==e.ruleID}?.label ?? "回到开场方案")).foregroundStyle(Theme.muted)}.font(.system(size:12))
                    }
                }
            }
        }
    }
}
