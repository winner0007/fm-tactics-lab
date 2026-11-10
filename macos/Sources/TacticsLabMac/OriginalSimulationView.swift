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
                Chip(text:store.originalMatch == nil ? "内置基线可运行" : "已验证自然完赛")
            }
            Text("使用本机 FM 原版引擎和游戏自带测试阵容。可更换随机种子；工作台的战术、球员与定位球配置尚未应用到这组比赛。").font(.system(size:12)).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
            HStack(spacing:15) {
                Text("起始种子").font(.system(size:12))
                TextField("0–4294967295",text:$store.originalSeed).frame(width:130).textFieldStyle(.roundedBorder)
                Picker("比赛场数",selection:$store.originalCount) {ForEach([1,5,10,20],id:\.self){Text("\($0) 场").tag($0)}}.frame(width:145)
                Button(store.runningOriginal ? "原版引擎计算中…" : "开始原版模拟",action:store.runOriginalMatches).buttonStyle(.borderedProminent).disabled(store.runningOriginal || !store.engine.filesReady || store.engineSearching)
                if store.runningOriginal {
                    ProgressView().controlSize(.small)
                    Button("停止",action:store.cancelOriginalMatches)
                }
                Spacer()
                if store.originalLogFolder != nil {Button("查看运行日志",action:store.revealOriginalLogs)}
            }.disabled(store.checkingNative)
            if store.runningOriginal {Text(store.originalProgress).font(.system(size:12)).foregroundStyle(Theme.green)}
            Text("每场使用独立进程；多场依次递增种子。适配版本：27.0.0.2493426 / Apple Silicon，其他二进制版本会停止运行。").font(.system(size:11)).foregroundStyle(Theme.muted)
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
                Text("球队页记录比分、xG、控球率、射门、射正、传球及红黄牌；球员页记录已核验的基础统计。姓名暂按原版球员 ID 显示，评分、助攻等未接入的字段留空。").font(.system(size:11)).foregroundStyle(Theme.muted)
            }
        }
    }
}
