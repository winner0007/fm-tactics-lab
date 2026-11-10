import SwiftUI
import TacticsCore

struct ExperimentsView: View {
    @EnvironmentObject var store: LabStore
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                ExperimentTools()
                if let experiment = store.experiment {
                    HStack { Text(experiment.source).font(.system(size:18,weight:.semibold)); Spacer(); Chip(text:"\(experiment.records.count) 场完整结果"); Chip(text:"排除 \(experiment.excluded) 场",color:Theme.amber) }
                    if !experiment.hasContext {
                        Text("此 CSV 未记录对手和主客场。按单一批次、同一对手、主队视角比较；请确认实验条件一致。原项目 CSV 只含比分，不会补造 xG。").font(.system(size:12)).foregroundStyle(Theme.amber)
                    }
                    Picker("数据视图",selection:$store.resultSection) {ForEach(["测试报告","总览","球队明细","球员数据"],id:\.self){Text($0).tag($0)}}.pickerStyle(.segmented).frame(width:430)
                    if store.resultSection=="测试报告" {
                        if store.originalReports.isEmpty {Text("该导入批次没有原版引擎配置快照，请查看总览与明细。").foregroundStyle(Theme.muted)}else{BatchReportView()}
                    } else if store.resultSection=="总览" {
                    TeamCharts(experiment:experiment)
                    ForEach(experiment.variants,id:\.self) { variant in
                        let summary = experiment.summary(variant)
                        Card {
                            Text(variant).font(.system(size:15,weight:.semibold))
                            HStack {
                                Metric(title:"完整场数",value:"\(summary.count)")
                                Metric(title:"胜率",value:String(format:"%.1f%%",summary.winRate*100))
                                Metric(title:"场均进球",value:String(format:"%.2f",summary.goalsFor))
                                Metric(title:"场均失球",value:String(format:"%.2f",summary.goalsAgainst))
                                Metric(title:"场均积分",value:String(format:"%.2f",summary.points))
                            }
                        }
                    }
                    if experiment.variants.count >= 2 { comparison(experiment) }
                    else { Card { Text("只有一个方案。导入包含至少两套方案的同一批次结果，才能做配对比较。").font(.system(size:13)) } }
                    } else if store.resultSection=="球队明细" {
                        MatchDetails(experiment:experiment)
                    } else {
                        PlayerTotalsChart(experiment:experiment)
                        MatchDetails(experiment:experiment,showTeams:false)
                    }
                } else {
                    VStack(spacing:18) {
                        Image(systemName:"chart.xyaxis.line").font(.system(size:52,weight:.ultraLight)).foregroundStyle(Theme.green).padding(.top,50)
                        Text("让结果回答战术问题").font(.system(size:25,weight:.semibold))
                        Text("在战术工作台设置双方阵容并运行比赛，\n或导入已有逐场结果，查看球队与球员数据。").font(.system(size:14)).multilineTextAlignment(.center).foregroundStyle(Theme.muted)
                        Button("导入实验结果",action:store.importExperiment).buttonStyle(.borderedProminent).controlSize(.large)
                        Button("前往原版模拟") {store.page="引擎与接入"}
                        Text("当前没有比赛数据").font(.system(size:11)).foregroundStyle(Theme.muted)
                    }.frame(maxWidth:.infinity).padding(.bottom,48)
                    HStack(alignment:.top,spacing:16) {
                        step("01","固定输入","同一阵容、对手、主客场和开赛状态；每次只调整一个因素。")
                        step("02","同种子配对","基线与改动方案使用相同种子；无对应结果的比赛不进入配对分析。")
                        step("03","检查不确定性","至少 20 对结果才展示探索性区间。换种子、换对手再测试。")
                    }
                }
            }.padding(26)
        }
    }
    private func step(_ number:String,_ title:String,_ description:String) -> some View {
        Card { Text(number).font(.system(size:24,weight:.light,design:.rounded)).foregroundStyle(Theme.green); Text(title).font(.system(size:14,weight:.semibold)); Text(description).font(.system(size:12)).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true) }.frame(maxWidth:.infinity)
    }
    private func comparison(_ experiment: Experiment) -> some View {
        let result = experiment.compare(baseline:store.baselineVariant,candidate:store.candidateVariant)
        let interval = result.interval()
        return Card {
            HStack {
                Text("配对比较").font(.system(size:16,weight:.semibold))
                Spacer()
                Picker("对照",selection:$store.baselineVariant) { ForEach(experiment.variants,id:\.self) { Text($0).tag($0) } }.frame(width:230)
                Picker("改动",selection:$store.candidateVariant) { ForEach(experiment.variants,id:\.self) { Text($0).tag($0) } }.frame(width:230)
            }
            if store.baselineVariant == store.candidateVariant {
                Text("请选择两个不同的方案。").foregroundStyle(Theme.amber)
            } else {
                HStack {
                    Metric(title:"有效配对",value:"\(result.differences.count)")
                    Metric(title:"未配对场次",value:"\(result.unpaired)")
                    Metric(title:"场均净胜球变化",value:result.differences.isEmpty ? "—" : String(format:"%+.2f",result.mean))
                    Metric(title:"探索性 95% 区间",value:interval.map { String(format:"%+.2f ~ %+.2f",$0.lowerBound,$0.upperBound) } ?? "样本不足")
                }.padding(.vertical,10)
                if let interval {
                    Text(interval.contains(0) ? "区间包含零：本组样本还不能区分两套方案的优劣。" : "本组样本呈现方向性差异；换一组种子和对手复测，再判断能否推广。")
                        .font(.system(size:13,weight:.medium)).foregroundStyle(Theme.green)
                } else { Text("少于 20 对完整结果，只描述均值，不给出优劣结论。").font(.system(size:12)).foregroundStyle(Theme.amber) }
                Text("按种子、对手和场地配对；指标为改动方案净胜球减去对照净胜球。区间来自 1,000 次配对 bootstrap，仅用于探索，不代表真实比赛胜率；多方案筛选还需独立验证。").font(.system(size:11)).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
}

struct Metric: View {
    var title:String; var value:String
    var body: some View { VStack(alignment:.leading,spacing:8) { Text(title).font(.system(size:11)).foregroundStyle(Theme.muted); Text(value).font(.system(size:24,weight:.medium,design:.rounded)).minimumScaleFactor(0.65).lineLimit(1) }.frame(maxWidth:.infinity,alignment:.leading) }
}

struct EngineView: View {
    @EnvironmentObject var store: LabStore
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Card {
                    HStack {
                        Label("FM27 本机安装",systemImage:"desktopcomputer").font(.system(size:18,weight:.semibold)); Spacer()
                        if store.engineSearching { ProgressView().controlSize(.small); Text("正在自动查找…").font(.system(size:12)) }
                        else {
                            Button("重新自动查找") { store.searchEngine() }
                            if !store.engine.filesReady { Button("指定游戏位置…",action:store.chooseGame).buttonStyle(.borderedProminent) }
                        }
                    }
                    HStack { Metric(title:"游戏版本",value:store.engine.version); Metric(title:"引擎架构",value:store.engine.architectures.joined(separator:" + ")); Metric(title:"原版比赛",value:store.originalMatch == nil ? "待运行验证" : "已自然完赛") }
                    Text(store.engine.appPath ?? "未找到 FM27 应用").font(.system(size:11,design:.monospaced)).textSelection(.enabled).foregroundStyle(Theme.muted)
                    Label(store.engine.reason,systemImage:store.engine.filesReady ? "checkmark.circle" : "info.circle").font(.system(size:12)).foregroundStyle(store.engine.filesReady ? Theme.green : Theme.amber)
                    if !store.engine.discoverySource.isEmpty { Chip(text:store.engine.discoverySource) }
                    DisclosureGroup("自动查找范围：Steam 游戏库、应用程序目录、外置磁盘") {
                        ScrollView { Text(store.engine.searchedLocations.joined(separator:"\n")).font(.system(size:10,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:170)
                    }.font(.system(size:11)).foregroundStyle(Theme.muted)
                }
                OriginalSimulationCard()
                Card {
                    HStack {Text("Mac 引擎接入状态").font(.system(size:17,weight:.semibold));Spacer();Chip(text:"工作台输入已接通")}
                    Text("独立比赛宿主已支持原版初始化、测试输入、自然完赛及基础统计读取。下方保留单独的动态库加载检查，供运行失败时诊断。").font(.system(size:12)).foregroundStyle(Theme.muted)
                    HStack {
                        Button(store.checkingNative ? "正在验证加载…" : "验证原版引擎加载",action:store.checkNativeEngine).disabled(store.checkingNative || store.runningOriginal || !store.engine.filesReady)
                        Text("每场验证双方阵容、角色、指令、定位球与状态").font(.system(size:11)).foregroundStyle(Theme.green)
                    }
                    if let check=store.nativeCheck {
                        Label(check.loaded ? "原版动态库已成功加载（仅加载检查）" : "原版动态库加载失败",systemImage:check.loaded ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(check.loaded ? Theme.green : Theme.amber)
                        if !check.error.isEmpty {Text(check.error).font(.system(size:10,design:.monospaced)).textSelection(.enabled)}
                        Text("验证时间："+Date(timeIntervalSince1970:check.timestamp).formatted()+" · "+check.architecture).font(.system(size:10)).foregroundStyle(Theme.muted)
                    }
                    if !store.engine.diagnostics.isEmpty {
                        LazyVGrid(columns:[GridItem(.flexible(),alignment:.leading),GridItem(.flexible(),alignment:.leading)],alignment:.leading,spacing:12) {
                            ForEach(store.engine.diagnostics) { diagnostic in
                                Label(diagnostic.title + (diagnostic.passed ? " · 已找到" : " · 缺失／不可识别"),systemImage:diagnostic.passed ? "checkmark.circle" : "exclamationmark.circle").font(.system(size:11)).foregroundStyle(diagnostic.passed ? Theme.green : Theme.amber)
                            }
                        }
                    }
                }
                Card {
                    Text("当前可用").font(.system(size:17,weight:.semibold))
                    feature("双阶段战术板","12 种阵型、79 个阶段角色、29 组球队指令、17 组球员指令及角色锁定。",ready:true)
                    feature("双方阵容与定位球","按位置生成随机球员、独立隐藏数据；10 种定位球情形、任务、候选顺序与主罚人。",ready:true)
                    feature("实验结果报告","自定义 1–2000 场；双方配置快照、球队和球员数据、趋势图与 HTML 导出。",ready:true)
                    feature("本地方案文件","自动保存、JSON 导入导出，重新打开继续编辑。",ready:true)
                }
                Card {
                    Text("存档与联赛").font(.system(size:17,weight:.semibold))
                    feature("1. 只读存档导入","复用原项目读取组件，选择球队或完整双循环联赛，保留原始属性与来源。",ready:true)
                    feature("2. 独立引擎进程","已跑通初始化、资源、线程上下文、自然完赛和基础统计。",ready:true)
                    feature("3. 自定义联赛实验","自建或导入球队、选择积分与排名规则、主客场赛程与重复赛季。",ready:true)
                    feature("4. 尚未接入的范围","原始 .dat 数据库、FMF 战术文件、完整生涯状态演进与自动战术优化搜索。",ready:false)
                }
                Text("比赛在独立进程执行，使用游戏自身文件；不会修改安装包或存档。仅适配已验证的 Mac arm64 引擎指纹，游戏更新后需要重新适配。存档阵容与工具初始战术会明确区分，未解析数据不冒充真实值。").font(.system(size:12)).foregroundStyle(Theme.muted)
            }.padding(26)
        }
    }
    private func feature(_ title:String,_ detail:String,ready:Bool) -> some View {
        HStack(alignment:.top,spacing:13) { Image(systemName:ready ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(ready ? Theme.green : Theme.muted); VStack(alignment:.leading,spacing:5) { Text(title).font(.system(size:13,weight:.semibold)); Text(detail).font(.system(size:12)).foregroundStyle(Theme.muted) } }
    }
}
