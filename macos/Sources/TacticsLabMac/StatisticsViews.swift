import SwiftUI
import Charts
import TacticsCore

struct ExperimentTools:View {
    @EnvironmentObject var store:LabStore
    var body:some View {
        HStack {
            Menu("原版测试历史 · \(store.nativeBatchArchives.count)") {
                ForEach(store.nativeBatchArchives,id:\.self) {url in Button(url.lastPathComponent.prefix(8)+" · "+(((try? url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast).formatted(date:.abbreviated,time:.shortened))){store.loadNativeBatch(url)}}
            }.frame(width:185).disabled(store.nativeBatchArchives.isEmpty || store.runningOriginal)
            Menu("历史批次 · \(store.experimentArchives.count)") {
                ForEach(store.experimentArchives,id:\.self) { url in Button(url.deletingPathExtension().lastPathComponent){store.loadArchive(url)} }
            }.frame(width:180).disabled(store.experimentArchives.isEmpty)
            Button("导入球员赛后数据",action:store.importPlayerResults).disabled(store.experiment==nil)
            Menu("数据模板 / 导出") {
                Button("球队统计 CSV 模板"){store.export(Data(Experiment.statisticsTemplate.utf8),name:"球队比赛统计.csv",type:.commaSeparatedText)}
                Button("球员统计 CSV 模板"){store.export(Data(PlayerMatchRecord.template.utf8),name:"球员比赛统计.csv",type:.commaSeparatedText)}
                if let e=store.experiment {
                    Button("导出球队逐场 CSV"){store.export(Data(e.teamCSV.utf8),name:"球队逐场结果.csv",type:.commaSeparatedText)}
                    Button("导出球员逐场 CSV"){store.export(Data(e.playerCSV.utf8),name:"球员逐场结果.csv",type:.commaSeparatedText)}.disabled(e.playerRecords?.isEmpty != false)
                    Button("导出完整批次 JSON") {do {store.export(try JSONEncoder().encode(e),name:"实验批次.json",type:.json)} catch {store.error=error.localizedDescription}}
                }
            }.frame(width:150)
            Spacer()
        }
    }
}

struct TeamCharts:View {
    let experiment:Experiment
    @State private var selected="goals"
    private var metric:StatMetric {StatMetric.team.first{$0.id==selected} ?? StatMetric.team[0]}
    private var points:[TeamChartPoint] {
        experiment.variants.flatMap { variant in
            ["for","against"].compactMap { side in
                let values=experiment.records.filter{$0.variant==variant}.compactMap{$0.value(selected,side:side)}
                guard !values.isEmpty else {return nil}
                return TeamChartPoint(variant:variant,side:side=="for" ? "本队" : "对手",value:values.reduce(0,+)/Double(values.count),count:values.count)
            }
        }
    }
    var body:some View {
        Card {
            HStack {
                Text("球队数据 · 场均对比").font(.system(size:17,weight:.semibold));Spacer()
                Picker("指标",selection:$selected){ForEach(StatMetric.team){Text($0.title).tag($0.id)}}.frame(width:230)
            }
            if points.isEmpty {Text("该指标尚无记录。导入包含相应列的比赛数据后展示；缺失值不按零计算。").foregroundStyle(Theme.muted).frame(height:160)}
            else {
                Chart(points) { point in
                    BarMark(x:.value("方案",point.variant),y:.value(metric.title,point.value))
                        .foregroundStyle(by:.value("球队",point.side)).position(by:.value("球队",point.side))
                        .annotation(position:.top){Text(String(format:"%.2f",point.value)+metric.unit).font(.system(size:10))}
                }.chartForegroundStyleScale(["本队":Theme.green,"对手":Theme.amber]).frame(height:210)
                Text(points.map{"\($0.variant) · \($0.side)：\($0.count) 场有记录"}.joined(separator:"　")).font(.system(size:10)).foregroundStyle(Theme.muted)
            }
            Text("按原始记录分别计算双方均值，未补全的指标不进入分母。不同方案的记录覆盖范围不同，请谨慎比较。").font(.system(size:11)).foregroundStyle(Theme.muted)
            Divider()
            Text("胜 / 平 / 负分布").font(.system(size:14,weight:.semibold))
            Chart {
                ForEach(experiment.variants,id:\.self) { variant in
                    let records=experiment.records.filter{$0.variant==variant}
                    ForEach(["胜","平","负"],id:\.self) { result in
                        let n=records.filter{result=="胜" ? $0.goalsFor>$0.goalsAgainst : (result=="平" ? $0.goalsFor==$0.goalsAgainst : $0.goalsFor<$0.goalsAgainst)}.count
                        BarMark(x:.value("完整场次",n),y:.value("方案",variant)).foregroundStyle(by:.value("结果",result))
                    }
                }
            }.chartForegroundStyleScale(["胜":Theme.green,"平":Color.gray.opacity(0.6),"负":Theme.amber]).frame(height:CGFloat(max(100,experiment.variants.count*35)))
        }
    }
}
private struct TeamChartPoint:Identifiable {
    let variant:String;let side:String;let value:Double;let count:Int
    var id:String {variant+"\u{1f}"+side}
}

struct MatchDetails:View {
    let experiment:Experiment
    var showTeams=true
    @State private var chosen:String=""
    @State private var offset=0
    private var current:MatchRecord? {experiment.records.first{$0.id==chosen} ?? experiment.records.first}
    var body:some View {
        Card {
            HStack {
                Text("逐场球队与球员数据").font(.system(size:17,weight:.semibold));Spacer()
                Button("上一页"){offset=max(0,offset-50)}.disabled(offset==0)
                Text("\(min(offset+1,experiment.records.count))–\(min(offset+50,experiment.records.count)) / \(experiment.records.count)").font(.system(size:11))
                Button("下一页"){offset+=50}.disabled(offset+50>=experiment.records.count)
            }
            Picker("比赛",selection:Binding(get:{current?.id ?? ""},set:{chosen=$0})) {
                if let c=current,!Array(experiment.records.dropFirst(offset).prefix(50)).contains(where:{$0.id==c.id}) {Text(label(c)).tag(c.id)}
                ForEach(Array(experiment.records.dropFirst(offset).prefix(50))) {record in Text(label(record)).tag(record.id)}
            }
            if let record=current {
                if showTeams {
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),alignment:.leading),count:3),alignment:.leading,spacing:14) {
                    ForEach(StatMetric.team) { metric in
                        VStack(alignment:.leading,spacing:4) {
                            Text(metric.title).font(.system(size:11)).foregroundStyle(Theme.muted)
                            Text(metric.format(record.value(metric.id))+"  :  "+metric.format(record.value(metric.id,side:"against"))).font(.system(size:15,weight:.medium,design:.rounded))
                        }
                    }
                }
                Text("本队 : 对手 · — 为未记录；控球率使用 0–100 百分数。").font(.system(size:11)).foregroundStyle(Theme.muted)
                }
                let players=(experiment.playerRecords ?? []).filter{$0.matchID==record.id}
                if players.isEmpty {Text("本场暂无球员逐场记录。可导入球员比赛 CSV，与本批次比赛关联。").font(.system(size:12)).foregroundStyle(Theme.muted)}
                else {PlayerStatisticsTable(records:players)}
            }
        }.onChange(of:experiment) {_,_ in offset=0;chosen=""}
    }
    private func label(_ r:MatchRecord)->String {"\(r.variant) · 种子 \(r.seed) · \(r.opponent) · \(r.venue=="home" ? "主场" : "客场") · \(r.goalsFor):\(r.goalsAgainst)"}
}

struct PlayerStatisticsTable:View {
    let records:[PlayerMatchRecord]
    var body:some View {
        ScrollView(.horizontal) {
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    Text("球员 / 球队").frame(width:160,alignment:.leading)
                    ForEach(StatMetric.player){Text($0.title).frame(width:80)}
                }.foregroundStyle(Theme.muted)
                ForEach(records) {record in
                    HStack {
                        Text(record.name+" · "+(record.team=="for" ? "本队" : "对手")).frame(width:160,alignment:.leading)
                        ForEach(StatMetric.player){Text($0.format(record.statistics[$0.id])).monospacedDigit().frame(width:80)}
                    }
                }
            }.font(.system(size:11))
        }
    }
}

struct PlayerTotalsChart:View {
    let experiment:Experiment
    @State private var variant=""
    @State private var metricID="goals"
    @State private var teamSide="for"
    private var metric:StatMetric {StatMetric.player.first{$0.id==metricID} ?? StatMetric.player[0]}
    private var activeVariant:String {experiment.variants.contains(variant) ? variant : experiment.variants.first ?? ""}
    private var rows:[PlayerChartPoint] {
        let matches=Set(experiment.records.filter{$0.variant==activeVariant}.map(\.id))
        let records=(experiment.playerRecords ?? []).filter{$0.team==teamSide && matches.contains($0.matchID)}
        return Dictionary(grouping:records,by:\.playerID).compactMap { id,records in
            let values=records.compactMap{$0.statistics[metricID]}
            guard !values.isEmpty else {return nil}
            let sum=values.reduce(0,+)
            return PlayerChartPoint(id:id,name:records[0].name,value:metricID=="rating" ? sum/Double(values.count) : sum,count:values.count)
        }.sorted {a,b in a.value==b.value ? a.id<b.id : a.value>b.value}
    }
    var body:some View {
        Card {
            HStack {
                Text("球员 · \(metricID=="rating" ? "平均评分" : "累计数据")").font(.system(size:16,weight:.semibold));Spacer()
                Picker("球队",selection:$teamSide){Text("本队").tag("for");Text("对手").tag("against")}.frame(width:100)
                Picker("方案",selection:Binding(get:{activeVariant},set:{variant=$0})){ForEach(experiment.variants,id:\.self){Text($0).tag($0)}}.frame(width:160)
                Picker("指标",selection:$metricID){ForEach(StatMetric.player){Text($0.title).tag($0.id)}}.frame(width:180)
            }
            if rows.isEmpty {Text("该指标暂无球员记录。").font(.system(size:12)).foregroundStyle(Theme.muted)}
            else {
                Chart(Array(rows.prefix(10))) { r in
                    BarMark(x:.value(metric.title,r.value),y:.value("球员",r.id)).foregroundStyle(Theme.green)
                        .annotation(position:.trailing){Text(metric.format(r.value)+" · \(r.count) 条记录").font(.system(size:10))}
                }.chartYAxis {
                    AxisMarks { value in AxisValueLabel {if let id=value.as(String.self) {Text(rows.first{$0.id==id}?.name ?? id)}} }
                }.frame(height:CGFloat(max(130,min(rows.count,10)*32)))
            }
            Text("显示前 10 人；按球员 ID 聚合。评分取有记录场次的均值，其他指标累计；不把缺失记录视为零，不跨方案相加。").font(.system(size:11)).foregroundStyle(Theme.muted)
        }
    }
}
private struct PlayerChartPoint:Identifiable {let id:String;let name:String;let value:Double;let count:Int}
