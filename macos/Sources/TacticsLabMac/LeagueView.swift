import SwiftUI
import Charts
import TacticsCore

struct LeagueView:View {
    @EnvironmentObject var store:LabStore
    @State private var count=4
    @State private var tier:AbilityTier = .professional
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Picker("联赛页面",selection:$store.leagueSection){Text("球队与规则").tag("球队与规则");Text("积分与统计").tag("积分与统计")}.pickerStyle(.segmented).frame(width:280)
                Spacer()
                Menu("历史联赛实验") {ForEach(store.leagueArchives,id:\.self){url in Button(url.lastPathComponent.prefix(8)+" · "+(((try? url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast).formatted(date:.abbreviated,time:.shortened))){store.loadLeagueRun(url);store.leagueSection="积分与统计"}}}.disabled(store.leagueArchives.isEmpty || store.leagueRunning)
            }.padding(20)
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if store.leagueSection=="球队与规则" {setup;SaveImportPanel()}
                    else if let run=store.leagueRun {LeagueReportView(run:run)}
                    else {Card{Text("先加入球队、核对规则，再运行完整赛程。每场结果均由 FM 原版引擎计算。").foregroundStyle(Theme.muted)}}
                }.padding(.horizontal,24).padding(.bottom,24)
            }
            HStack {
                VStack(alignment:.leading,spacing:4) {Text(store.leagueRunning ? store.leagueProgress:"FM 原版联赛实验").font(.system(size:12,weight:.semibold));Text("\(store.leagueSetup.teams.count) 队 · 每次赛季 \(store.leagueSetup.fixtures().count) 场 · 每场固定开赛状态").font(.system(size:10)).foregroundStyle(Theme.muted)}
                Spacer()
                Text("种子").font(.system(size:11));TextField("1",text:$store.leagueSeed).frame(width:75).disabled(store.leagueRunning)
                Text("重复赛季").font(.system(size:11));TextField("1",value:$store.leagueSeasons,format:.number.grouping(.never)).frame(width:60).disabled(store.leagueRunning)
                if store.leagueRunning {Button("停止并保留结果"){store.stopLeague()}}
                else {
                    if let run=store.leagueRun,run.results.count<run.expected {Button("继续上次（原配置）"){store.runLeague(resume:true);store.leagueSection="积分与统计"}.disabled(store.runningOriginal)}
                    Button("运行联赛"){store.runLeague();store.leagueSection="积分与统计"}.buttonStyle(.borderedProminent).disabled(!store.engine.filesReady || store.runningOriginal || store.leagueSetup.teams.count<2)
                }
            }.padding(18).background(.white).overlay(alignment:.top){Divider()}
        }.onChange(of:store.leagueSetup){_,_ in store.saveLeagueSetup()}
    }
    private var setup:some View {
        VStack(spacing:18) {
            Card {
                HStack {TextField("联赛名称",text:$store.leagueSetup.name).font(.system(size:20,weight:.semibold));Spacer();Button("初始化 JSON 导入",action:store.importLeagueSetup);Button("导出初始化数据",action:store.exportLeagueSetup)}
                HStack {
                    Picker("排名规则",selection:$store.leagueSetup.rules.ranking){ForEach(LeagueRankingRule.allCases){Text($0.rawValue).tag($0)}}
                    Picker("循环",selection:$store.leagueSetup.rules.cycles){Text("主客场双循环").tag(2);Text("单循环").tag(1)}.frame(width:190).disabled(store.leagueSetup.importedSchedule != nil || [.english,.spanish].contains(store.leagueSetup.rules.ranking))
                }.onChange(of:store.leagueSetup.rules.ranking){_,v in if [.english,.spanish].contains(v) {store.leagueSetup.rules.cycles=2;store.leagueSetup.rules.winPoints=3;store.leagueSetup.rules.drawPoints=1;store.leagueSetup.rules.lossPoints=0}}
                if [.goalDifference,.headToHead].contains(store.leagueSetup.rules.ranking) {
                    HStack {Stepper("胜：\(store.leagueSetup.rules.winPoints)",value:$store.leagueSetup.rules.winPoints,in:0...10);Stepper("平：\(store.leagueSetup.rules.drawPoints)",value:$store.leagueSetup.rules.drawPoints,in:0...10);Stepper("负：\(store.leagueSetup.rules.lossPoints)",value:$store.leagueSetup.rules.lossPoints,in:0...10)}.font(.system(size:12))
                }
                if store.leagueSetup.rules.ranking == .english {
                    Text("同分时先比较总净胜球和总进球。只有跨越下列排名分界的同分组，才比较相互积分与相互客场进球；仍相同则待决。").font(.system(size:12)).foregroundStyle(Theme.muted)
                    HStack {Text("关键分界（如冠军 1、降级线 17）");TextField("1,17",text:Binding(get:{store.leagueSetup.rules.decidingPlaces.map(String.init).joined(separator:",")},set:{v in store.leagueSetup.rules.decidingPlaces=v.split(separator:",").compactMap{Int($0.trimmingCharacters(in:.whitespaces))}})).frame(width:180)}.font(.system(size:12))
                }
                if let source=store.leagueSetup.rules.ranking.source {Link("查看排名规则依据",destination:URL(string:source)!).font(.system(size:11))}
                Text(store.leagueSetup.rules.limitation).font(.system(size:11)).foregroundStyle(Theme.muted)
                if store.leagueSetup.importedSchedule != nil {HStack{Chip(text:"使用存档完整赛程");Text("按存档对阵与日期顺序重赛整个赛季；不累计存档已有比分。").font(.system(size:11));Spacer();Button("改用新循环赛程"){store.leagueSetup.importedSchedule=nil}}}
            }
            Card {
                HStack {Text("参赛球队 · \(store.leagueSetup.teams.count)").font(.system(size:17,weight:.semibold));Spacer();Button("复制普通对战主队"){store.addLeagueTeam(store.workspace)};Button("复制普通对战对手"){if let opponent=store.workspace.opponent {store.addLeagueTeam(opponent.workspace)}}}
                HStack {Stepper("随机生成 \(count) 队",value:$count,in:1...20).frame(width:190);Picker("能力档次",selection:$tier){ForEach(AbilityTier.allCases){Text($0.menuTitle).tag($0)}}.frame(width:200);Button("生成并加入"){store.addRandomTeams(count,tier:tier)};Spacer()}
                Text("每支联赛球队都有自己的阵容、战术和定位球。复制只发生一次；之后的修改只保存到所选球队。随机生成的球队也可以逐人微调，或单独重抽能力。").font(.system(size:12)).foregroundStyle(Theme.muted)
                ForEach(store.leagueSetup.teams) {team in
                    HStack {
                        VStack(alignment:.leading,spacing:4) {TextField("球队名称",text:Binding(get:{store.leagueSetup.teams.first{$0.id==team.id}?.name ?? team.name},set:{v in if let i=store.leagueSetup.teams.firstIndex(where:{$0.id==team.id}){store.leagueSetup.teams[i].displayName=v}})).font(.system(size:14,weight:.semibold)).textFieldStyle(.plain);Text("\(team.plan.players.count) 人 · \(team.plan.tactic.formation) / \(team.plan.tactic.defensiveFormation) · 战术：\(team.plan.tactic.name)").font(.system(size:11)).foregroundStyle(Theme.muted)}
                        Spacer();Text(team.savedClubID.map{"存档球队 #\($0)"} ?? "自定义球队").font(.system(size:11)).foregroundStyle(Theme.muted)
                        Button("阵容与属性"){store.editLeagueTeam(team.id,page:"球员与阵容")}
                        Button("战术与定位球"){store.editLeagueTeam(team.id)}
                        Menu("随机本队能力"){ForEach(AbilityTier.allCases){tier in Button(tier.menuTitle){store.randomizeLeagueTeam(team.id,tier:tier)}}}
                        Button("移除"){if store.leagueEditingTeam==team.id {store.leaveLeagueEditor(navigate:false)};store.leagueSetup.teams.removeAll{$0.id==team.id};store.leagueSetup.importedSchedule=nil}
                    }.padding(.vertical,5)
                    Divider()
                }
                Text(store.leagueSetup.source).font(.system(size:10)).foregroundStyle(Theme.muted).textSelection(.enabled)
            }
        }.disabled(store.leagueRunning || store.readingSave)
    }
}

struct SaveImportPanel:View {
    @EnvironmentObject var store:LabStore
    @State private var search=""
    @State private var clubID:Int?
    @State private var leagueID:String?
    @State private var sourceMode="存档当前阵容"
    @State private var ranking:LeagueRankingRule = .goalDifference
    private var selectedLeague:SavedLeague? {store.saveCatalog?.leagues.first{$0.id==leagueID}}
    var body:some View {
        Card {
            HStack {Label("从 FM27 存档读取",systemImage:"externaldrive").font(.system(size:17,weight:.semibold));Spacer();Button(store.saveCatalog==nil ? "选择 .fm 存档…":"更换存档…",action:store.chooseCareerSave).disabled(store.readingSave || store.leagueRunning)}
            Picker("数据起点",selection:$sourceMode){Text("存档当前阵容").tag("存档当前阵容");Text("开档初始阵容").tag("开档初始阵容")}.pickerStyle(.segmented)
            Text(sourceMode=="存档当前阵容" ? "选择 .fm，读取该日期的真实球队、球员与已保存赛程，再选择单队测试或整联赛。" : "使用数据库初始阵容时，请在 FM 中加载所需数据库与联赛，开档后立即保存，再选择这份 .fm。直接读取安装目录 .dat 尚未实现；初始化 JSON 是本工具的联赛备份。").font(.system(size:12)).foregroundStyle(Theme.muted)
            if store.readingSave {HStack{ProgressView().controlSize(.small);Text(store.saveProgress);Spacer();Button("取消读取"){store.saveJob?.cancel()}}}
            else {Text(store.saveProgress).font(.system(size:11)).foregroundStyle(Theme.muted)}
            if let catalog=store.saveCatalog {
                Text(catalog.sourceName+" · "+catalog.gameDate+" · "+catalog.build).font(.system(size:12,weight:.semibold))
                HStack(alignment:.top,spacing:24) {
                    VStack(alignment:.leading,spacing:12) {
                        Text("选择一支球队").font(.system(size:14,weight:.semibold))
                        TextField("搜索球队名称",text:$search)
                        Picker("球队",selection:$clubID) {
                            Text("请选择球队").tag(nil as Int?)
                            ForEach(catalog.clubs.filter{(selectedLeague == nil || selectedLeague!.clubIDs.contains($0.id)) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))}.prefix(200)){Text($0.name).tag(Optional($0.id))}
                        }
                        HStack{Button("加入联赛"){if let clubID{store.importSavedClubs([clubID])}};Button("导入当前编辑球队"){if let clubID{store.importSavedClubs([clubID],toWorkbench:true)}}}.disabled(clubID==nil || store.readingSave || store.leagueRunning)
                        Text("当前替换目标："+(store.editedLeagueTeam.map{"联赛 · "+$0.name} ?? ((store.editingSide==0 ? "普通对战主队 · ":"普通对战对手 · ")+store.editing.tactic.name))).font(.system(size:11)).foregroundStyle(Theme.muted)
                    }.frame(maxWidth:.infinity)
                    VStack(alignment:.leading,spacing:12) {
                        Text("选择完整联赛").font(.system(size:14,weight:.semibold))
                        Picker("已验证完整双循环赛程",selection:$leagueID) {Text("请选择联赛").tag(nil as String?);ForEach(catalog.leagues){league in Text(leagueLabel(league,catalog)).tag(Optional(league.id))}}
                        if let league=selectedLeague {
                            Text(league.clubIDs.compactMap{id in catalog.clubs.first{$0.id==id}?.name}.joined(separator:" · ")).font(.system(size:11)).foregroundStyle(Theme.muted)
                            Picker("排名规则（请核对）",selection:$ranking){ForEach(LeagueRankingRule.allCases){Text($0.rawValue).tag($0)}}
                            Button("导入全部 \(league.clubIDs.count) 队与赛程"){store.importSavedClubs(league.clubIDs,league:league,ranking:ranking)}.disabled(store.readingSave || store.leagueRunning)
                        }
                        Text("存档未提供可直接使用的联赛名称与完整排名条款。按赛事 ID 和参赛球队识别；在此选择排名规则，导入后可继续微调。").font(.system(size:10)).foregroundStyle(Theme.muted)
                    }.frame(maxWidth:.infinity)
                }
                DisclosureGroup("读取范围与来源说明") {ForEach(catalog.notes,id:\.self){Text($0).font(.system(size:11)).foregroundStyle(Theme.muted).frame(maxWidth:.infinity,alignment:.leading)}}
            }
        }.onAppear{clubID=store.saveCatalog?.managedClubIDs.first;leagueID=store.saveCatalog?.leagues.first(where:{$0.clubIDs.contains(clubID ?? -1)})?.id}.onChange(of:leagueID){_,_ in if let league=selectedLeague, !league.clubIDs.contains(clubID ?? -1){clubID=league.clubIDs.first}}.onChange(of:store.saveCatalog?.sourceSHA256){_,_ in clubID=store.saveCatalog?.managedClubIDs.first;leagueID=store.saveCatalog?.leagues.first(where:{l in l.clubIDs.contains(clubID ?? -1)})?.id}
    }
    private func leagueLabel(_ l:SavedLeague,_ c:SaveCatalog)->String {
        let sample=l.clubIDs.prefix(2).compactMap{id in c.clubs.first{$0.id==id}?.name}.joined(separator:" / ")
        return "#\(l.competitionID) · \(l.season) · \(l.clubIDs.count) 队 · "+sample
    }
}

struct LeagueReportView:View {
    @EnvironmentObject var store:LabStore
    let run:LeagueRun
    @State private var season=1
    @State private var playerTeam:UUID?
    private var table:[LeagueStanding] {run.table(season:season)}
    private var games:[LeagueResult] {run.results.filter{$0.season==season}}
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Card {
                HStack {Text(run.setup.name).font(.system(size:23,weight:.bold));Spacer();Chip(text:run.status);Button("打开保存位置"){store.revealLeagueRun()};Button("完整 JSON"){store.exportLeagueResults()};Button("导出联赛报告"){store.exportLeagueReport()}}
                Text("有效 \(run.results.count) / \(run.expected) 场 · 完整赛季 \(run.completedSeasons.count) / \(run.seasons)").font(.system(size:14))
                Text("本报告使用开赛时保存的球队与规则。修改球队只影响新实验；继续上次实验仍用原配置。").font(.system(size:12)).foregroundStyle(Theme.muted)
                Text(run.setup.rules.description).font(.system(size:12)).foregroundStyle(Theme.muted)
                Text(run.setup.rules.limitation).font(.system(size:11)).foregroundStyle(Theme.muted)
                if let error=run.failure {Text(error).font(.system(size:12)).foregroundStyle(Theme.amber)}
                Picker("查看赛季",selection:$season){ForEach(1...run.seasons,id:\.self){Text("第 \($0) 次赛季").tag($0)}}.frame(width:240)
            }
            Card {
                HStack {Text(run.completedSeasons.contains(season) ? "赛季积分榜":"进行中积分榜 · \(games.count) / \(run.schedule.count) 场").font(.system(size:17,weight:.semibold));Spacer();Text("同名次标记为并列／待决").font(.system(size:11)).foregroundStyle(Theme.muted)}
                HStack {Text("排名").frame(width:55);Text("球队").frame(maxWidth:.infinity,alignment:.leading);ForEach(["赛","胜","平","负","进","失","净胜","积分"],id:\.self){Text($0).frame(width:49)}}.font(.system(size:11)).foregroundStyle(Theme.muted)
                ForEach(table){r in HStack{Text("\(r.rank)"+(r.tied ? " ≈":"")).frame(width:55);Text(r.name).frame(maxWidth:.infinity,alignment:.leading);ForEach([r.played,r.wins,r.draws,r.losses,r.goalsFor,r.goalsAgainst,r.goalDifference,r.points].indices,id:\.self){i in Text(String([r.played,r.wins,r.draws,r.losses,r.goalsFor,r.goalsAgainst,r.goalDifference,r.points][i])).frame(width:49)}}.font(.system(size:12)).monospacedDigit();Divider()}
            }
            Card {
                Text("积分分布").font(.system(size:17,weight:.semibold))
                Chart(table){row in BarMark(x:.value("积分",row.points),y:.value("球队",row.name)).foregroundStyle(Theme.green)}.frame(height:CGFloat(max(200,table.count*25)))
            }
            if run.completedSeasons.count>1 {
                Card {
                    Text("重复赛季 · 排名范围").font(.system(size:17,weight:.semibold))
                    Text("只纳入完整赛季；范围反映固定阵容下的随机波动。").font(.system(size:11)).foregroundStyle(Theme.muted)
                    ForEach(run.setup.teams){team in let ranks=run.completedSeasons.compactMap{run.table(season:$0).first{$0.id==team.id}?.rank};HStack{Text(team.name);Spacer();Text("平均 "+String(format:"%.1f",Double(ranks.reduce(0,+))/Double(max(1,ranks.count)))+" · 最好 \(ranks.min() ?? 0) / 最差 \(ranks.max() ?? 0)")}.font(.system(size:12))}
                }
            }
            LeagueTeamStatisticsTable(run:run,season:season)
            LeaguePlayerTable(run:run,season:season)
            Card {
                Text("逐场成绩 · 最近 100 场").font(.system(size:17,weight:.semibold))
                ForEach(Array(games.suffix(100))){g in HStack{Text(g.fixture.date ?? "第 \(g.fixture.round) 轮").foregroundStyle(Theme.muted).frame(width:95);Text(g.report.configuration?.teams[0].name ?? "主队").frame(maxWidth:.infinity,alignment:.trailing);Text("\(g.report.score[0]) : \(g.report.score[1])").fontWeight(.semibold).frame(width:75);Text(g.report.configuration?.teams[1].name ?? "客队").frame(maxWidth:.infinity,alignment:.leading);Text("种子 \(g.report.seed)").foregroundStyle(Theme.muted).frame(width:100)}.font(.system(size:12))}
                Text("完整成绩、球员数据与配置快照随报告导出；每场原始日志保存在本机。").font(.system(size:11)).foregroundStyle(Theme.muted)
            }
        }.onChange(of:run.id){_,_ in season=1}
    }
}

struct LeagueTeamStatisticsTable:View {
    let run:LeagueRun;let season:Int
    var body:some View {
        Card {
            Text("球队场均表现 · 己方 / 对手").font(.system(size:17,weight:.semibold))
            ScrollView(.horizontal) {
                VStack(spacing:10) {
                    HStack {Text("球队").frame(width:180,alignment:.leading);ForEach(["xG","射门","射正","传球","成功传球","控球 %","黄牌","红牌"],id:\.self){Text($0).frame(width:98)}}.font(.system(size:11)).foregroundStyle(Theme.muted)
                    ForEach(LeagueTeamTotal.aggregate(run:run,season:season)){t in
                        HStack {Text(t.name).frame(width:180,alignment:.leading);ForEach(["xg","shots","shots_on_target","passes","completed_passes","possession","yellow_cards","red_cards"],id:\.self){key in Text([t.mean(key),t.mean(key,against:true)].map{$0.map{String(format:"%.1f",$0)} ?? "—"}.joined(separator:" / ")).monospacedDigit().frame(width:98)}}.font(.system(size:11));Divider()
                    }
                }
            }
        }
    }
}

struct LeaguePlayerTable:View {
    let run:LeagueRun;let season:Int
    @State private var team:UUID?
    var body:some View {
        Card {
            HStack {Text("球员数据榜").font(.system(size:17,weight:.semibold));Spacer();Picker("球队",selection:$team){Text("全部球队").tag(nil as UUID?);ForEach(run.setup.teams){Text($0.name).tag(Optional($0.id))}}.frame(width:240)}
            Text("累计数据；列出前 50 人。替补名单记录不视为出场，未验证的助攻、评分、分钟数不补零。").font(.system(size:11)).foregroundStyle(Theme.muted)
            HStack {Text("球员 / 球队").frame(maxWidth:.infinity,alignment:.leading);ForEach(["进球","xG","射门","射正","传球","成功","黄牌","红牌"],id:\.self){Text($0).frame(width:60)}}.font(.system(size:11)).foregroundStyle(Theme.muted)
            ForEach(LeaguePlayerTotal.aggregate(run:run,season:season).filter{team==nil || $0.teamID==team}.prefix(50)) {p in
                HStack {VStack(alignment:.leading,spacing:3){Text(p.name);Text(p.teamName).font(.system(size:10)).foregroundStyle(Theme.muted)}.frame(maxWidth:.infinity,alignment:.leading);ForEach(["goals","xg","shots","shots_on_target","passes","completed_passes","yellow_cards","red_cards"],id:\.self){key in Text(p.statistics[key].map{String(format:key=="xg" ? "%.2f":"%.0f",$0)} ?? "—").monospacedDigit().frame(width:60)}}.font(.system(size:12));Divider()
            }
        }
    }
}
