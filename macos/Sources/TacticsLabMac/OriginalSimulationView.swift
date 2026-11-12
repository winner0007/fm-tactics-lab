import SwiftUI
import Charts
import TacticsCore

struct OriginalSimulationCard:View {
    @EnvironmentObject var store:LabStore
    var body:some View {
        Card {
            HStack {
                Label("FM 原版比赛模拟",systemImage:"play.circle").font(.system(size:18,weight:.semibold))
                Spacer()
                Chip(text:store.engine.adapterSupported ? "已匹配适配版本":"当前版本待适配")
            }
            Text("使用本机 FM 原版引擎。工作台模式会保存并回读双方配置；内置基线用于检查引擎运行。").font(.system(size:12)).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
            Toggle("使用工作台双方配置",isOn:$store.useWorkbench).disabled(store.runningOriginal)
            HStack(spacing:15) {
                Text("起始种子").font(.system(size:12))
                TextField("0–4294967295",text:$store.originalSeed).frame(width:130).textFieldStyle(.roundedBorder).disabled(store.runningOriginal)
                Text("场数")
                TextField("1–2000",value:$store.originalCount,format:.number.grouping(.never)).frame(width:80).textFieldStyle(.roundedBorder).disabled(store.runningOriginal)
                ConcurrencyControl()
                Button(store.runningOriginal ? "原版引擎计算中…" : "开始原版模拟",action:store.runOriginalMatches).buttonStyle(.borderedProminent).disabled(store.editedLeagueTeam != nil || store.runningOriginal || store.leagueRunning || !store.engine.adapterSupported || store.engineSearching)
                if store.runningOriginal {
                    ProgressView().controlSize(.small)
                    Button("停止",action:store.cancelOriginalMatches)
                }
                Spacer()
                if store.originalLogFolder != nil {Button("查看运行日志",action:store.revealOriginalLogs)}
            }.disabled(store.checkingNative)
            if store.editedLeagueTeam != nil {Text("当前编辑的是联赛球队，请到“联赛实验”运行；普通对战需先切换编辑范围。").font(.caption).foregroundStyle(Theme.muted)}
            if store.runningOriginal {Text(store.originalProgress).font(.system(size:12)).foregroundStyle(Theme.green)}
            if !store.engine.adapterSupported {Text(store.engine.compatibilityMessage).font(.system(size:12)).foregroundStyle(Theme.amber)}
            if let batch=store.batch,batch.completed<batch.requested,!store.runningOriginal {Button("继续本批次（保留原配置，只补缺失比赛）",action:store.resumeOriginalMatches).disabled(store.leagueRunning)}
            Text("各通道使用独立引擎进程，种子按比赛编号固定。停止后可续跑，已完成场次会保留。").font(.system(size:11)).foregroundStyle(Theme.muted)
            if let report=store.originalMatch {
                Divider()
                HStack {
                    Metric(title:"最近一场 · 测试主队 : 客队",value:"\(report.score[0]) : \(report.score[1])")
                    Metric(title:"比赛时钟",value:String(format:"%.1f 分钟",report.minute))
                    Metric(title:"计算用时",value:String(format:"%.2f 秒",report.elapsedSeconds))
                    Metric(title:"随机种子",value:String(report.seed))
                }
                HStack {
                    Text("自然终场 · 原版统计合计已核验 · "+report.completedAt.formatted()).font(.system(size:11)).foregroundStyle(Theme.green)
                    Spacer()
                    Button("查看本批次统计与球员数据") {store.showOriginalResults()}
                }
                Text("最近一场累计 xG").font(.system(size:13,weight:.semibold))
                Chart {
                    ForEach(report.timeline) {p in
                        ForEach(0..<2,id:\.self) {side in
                            LineMark(x:.value("分钟",p.minute),y:.value("累计 xG",p.xg[side]))
                                .foregroundStyle(by:.value("球队",side==0 ? "测试主队" : "测试客队"))
                                .interpolationMethod(.stepEnd)
                        }
                    }
                }.chartForegroundStyleScale(["测试主队":Theme.green,"测试客队":Color.orange])
                    .chartXScale(domain:0...max(90,report.timeline.last?.minute ?? report.minute)).chartXAxisLabel("累计比赛分钟（含上下半场补时）· 约每分钟采样").frame(height:185)
                Text("球队页记录比分、xG、控球率、射门、射正、传球及红黄牌；球员页可切换本队与对手。工作台模式使用自定义姓名；未验证的统计留空。").font(.system(size:11)).foregroundStyle(Theme.muted)
            }
        }
    }
}
