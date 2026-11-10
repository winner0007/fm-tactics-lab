import AppKit
import SwiftUI
import TacticsCore

@main struct TacticsLabApplication: App {
    @StateObject private var store = LabStore()
    var body: some Scene {
        WindowGroup("FM 战术实验室") {
            RootView().environmentObject(store)
                .frame(minWidth: 1180, minHeight: 760)
                .preferredColorScheme(.light)
                .onAppear { captureIfRequested(); originalEngineSmokeIfRequested(); sheetCaptureIfRequested() }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("阵容方案库…") { store.showTeamPresets = true }.keyboardShortcut("l",modifiers:[.command,.shift])
                Button("导入游戏战术 FMF…",action:store.importGameTactic)
                Button("导出游戏战术 FMF…",action:store.exportGameTactic)
                Button("从 FM 存档导入球队…") {store.showSaveImporter=true}
                Button("打开方案…", action:store.importWorkspace).keyboardShortcut("o")
                Button("导出方案…", action:store.exportWorkspace).keyboardShortcut("s",modifiers:[.command,.shift])
                Button("保存", action:store.save).keyboardShortcut("s")
                Divider()
                Button("导入球员 CSV…", action:store.importPlayers)
                Button("导入实验结果…", action:store.importExperiment)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销", action:store.undo).keyboardShortcut("z").disabled(!store.canUndo)
                Button("重做", action:store.redo).keyboardShortcut("z",modifiers:[.command,.shift]).disabled(!store.canRedo)
            }
        }
    }
    private func originalEngineSmokeIfRequested() {
        let custom=CommandLine.arguments.contains("--scenario-smoke")
        guard let i=CommandLine.arguments.firstIndex(of:custom ? "--scenario-smoke":"--engine-smoke"),CommandLine.arguments.count>i+1 else {return}
        let folder=URL(fileURLWithPath:CommandLine.arguments[i+1]).standardizedFileURL
        // Smoke mode is only allowed with isolated data; never modify the user's workspace.
        guard store.storage.standardizedFileURL==folder.appendingPathComponent("data").standardizedFileURL else {exit(10)}
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                for _ in 0..<100 {
                    if !store.engineSearching {break}
                    try await Task.sleep(nanoseconds:100_000_000)
                }
                precondition(store.engine.filesReady)
                if custom {store.applyAbility(.professional,scope:.team)}
                let before=store.workspace,count=custom ? 26:5
                store.page="引擎与接入";store.originalSeed="1";store.originalCount=count;store.useWorkbench=custom
                store.runOriginalMatches()
                for _ in 0..<2400 {
                    if !store.runningOriginal {break}
                    try await Task.sleep(nanoseconds:100_000_000)
                }
                precondition(!store.runningOriginal && store.error==nil,store.error ?? "runtime timed out")
                precondition(store.workspace==before)
                precondition(store.experiment?.records.count==count && store.experiment?.playerRecords?.count==count*(custom ? 22:40))
                precondition(store.originalMatch?.seed==UInt32(count))
                let restored=LabStore()
                precondition(restored.originalMatch==store.originalMatch)
                precondition(restored.experiment==store.experiment)
                if custom {
                    // Recover a batch whose aggregate metadata was not updated.
                    let batchFolder=store.nativeBatchArchives.first!,batchURL=batchFolder.appendingPathComponent("batch.json"),oldBatch=try Data(contentsOf:batchURL)
                    var stale=store.batch!;stale.status="运行中";stale.completed=0
                    try JSONEncoder().encode(stale).write(to:batchURL,options:.atomic)
                    store.loadNativeBatch(batchFolder);precondition(store.error==nil && store.batch?.completed==count && store.batch?.status=="已完成")
                    try oldBatch.write(to:batchURL,options:.atomic)
                    let preset=try store.saveTeamPreset(name:"主力阵容")
                    let duplicate=try store.importTeamPreset(preset.data)
                    precondition(preset.id != duplicate.id && preset.plan==duplicate.plan)
                    try store.renameTeamPreset(duplicate,name:"轮换备份")
                    let library=LabStore();precondition(library.teamPresets.count==2)
                    let snapshot=store.workspace
                    store.editingSide=1;try store.loadTeamPreset(preset)
                    precondition(store.workspace.players==snapshot.players && store.workspace.tactic==snapshot.tactic && store.workspace.opponent!.players==preset.plan.players)
                    store.undo();precondition(store.workspace==snapshot);store.editingSide=0
                    try store.archiveTeamPreset(duplicate);precondition(store.teamPresets.count==1)
                    try Data(BatchExport.html(matches:store.originalReports,batch:store.batch).utf8).write(to:folder.appendingPathComponent("batch-report.html"))
                    store.leagueSetup=LeagueSetup();store.addRandomTeams(4,tier:.professional);store.leagueSeasons=2;store.leagueSeed="200"
                    let ordinary=store.workspace,first=store.leagueSetup.teams[0],other=store.leagueSetup.teams[1]
                    store.editLeagueTeam(first.id,page:"球员与阵容")
                    try store.loadTeamPreset(preset)
                    precondition(store.editing.players==preset.plan.players && store.editedLeagueTeam?.name==first.name && store.workspace==ordinary && store.leagueSetup.teams[1]==other)
                    store.undo();precondition(store.editing==first.plan)
                    store.change{$0.players[0].name="测试门将"}
                    precondition(store.editing.players[0].name=="测试门将" && store.workspace==ordinary && store.leagueSetup.teams[1]==other)
                    store.page="战术工作台";store.change{$0.tactic.name="高压战术"}
                    precondition(store.editedLeagueTeam?.name==first.name && store.editing.tactic.name=="高压战术")
                    store.undo();precondition(store.editing.tactic==first.plan.tactic)
                    store.redo();precondition(store.editing.tactic.name=="高压战术")
                    let shared=LabStore();precondition(shared.editing==store.editing && shared.workspace==ordinary && shared.leagueEditingTeam==first.id)
                    let oldTactic=store.editing.tactic,ids=store.editing.players.map(\.id)
                    store.randomizeLeagueTeam(first.id,tier:.amateur)
                    precondition(store.editing.tactic==oldTactic && store.editing.players.map(\.id)==ids && store.leagueSetup.teams[1]==other && store.workspace==ordinary)
                    store.editLeagueTeam(other.id);precondition(!store.canUndo)
                    store.change{$0.tactic.name="另一队战术"};store.undo();precondition(store.editing==other.plan)
                    store.leaveLeagueEditor();precondition(store.workspace==ordinary && store.editedLeagueTeam==nil)
                    store.runLeague()
                    for _ in 0..<1200 {if (store.leagueRun?.results.count ?? 0)>=2 {break};try await Task.sleep(nanoseconds:100_000_000)}
                    store.stopLeague()
                    for _ in 0..<200 {if !store.leagueRunning {break};try await Task.sleep(nanoseconds:100_000_000)}
                    precondition(store.leagueRun?.status=="已停止")
                    let partial=store.leagueRun!.results.count
                    precondition(partial>=2 && partial<24)
                    let frozen=store.leagueRun!.setup
                    store.randomizeLeagueTeam(first.id,tier:.international)
                    precondition(store.leagueRun!.setup==frozen && store.leagueSetup != frozen)
                    store.runLeague(resume:true)
                    for _ in 0..<2400 {if !store.leagueRunning {break};try await Task.sleep(nanoseconds:100_000_000)}
                    precondition(!store.leagueRunning && store.error==nil,store.error ?? "league timeout")
                    precondition(store.leagueRun?.results.count==24)
                    precondition(store.leagueRun!.table(season:1).allSatisfy{$0.played==6})
                    _ = try store.leagueRun!.validated()
                    let reopened=LabStore();precondition(reopened.leagueRun==store.leagueRun)
                    // Simulate a crash after durable match files but before the
                    // aggregate checkpoint; reopening must recover exactly once.
                    var checkpoint=store.leagueRun!;checkpoint.results.removeLast(3);checkpoint.status="运行中"
                    let checkpointURL=store.storage.appendingPathComponent("league-runs").appendingPathComponent(checkpoint.id.uuidString).appendingPathComponent("run.json")
                    try JSONEncoder().encode(checkpoint).write(to:checkpointURL,options:.atomic)
                    let recovered=LabStore();precondition(recovered.leagueRun==store.leagueRun)
                    try JSONEncoder().encode(store.leagueRun!).write(to:checkpointURL,options:.atomic)
                    try Data(LeagueExport.html(store.leagueRun!).utf8).write(to:folder.appendingPathComponent("league-report.html"))
                }
                guard let window=NSApplication.shared.windows.first(where:{$0.contentView != nil}),let view=window.contentView else {exit(11)}
                window.setContentSize(NSSize(width:1440,height:1050))
                let pages=[("引擎与接入","总览","original-engine.png"),("实验对比",custom ? "测试报告":"总览","original-results.png"),("实验对比","球员数据","original-players.png"),("战术工作台","阵型与首发","workbench.png"),("战术工作台","定位球","set-pieces.png"),("球员与阵容","阵型与首发","squad.png"),("联赛实验","阵型与首发","league.png")]
                for (page,section,file) in pages {
                    store.page=page;store.resultSection=section
                    store.workbenchStep=section
                    try await Task.sleep(nanoseconds:600_000_000)
                    view.layoutSubtreeIfNeeded()
                    guard let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else {exit(12)}
                    view.cacheDisplay(in:view.bounds,to:rep)
                    try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(file))
                }
                if custom {
                    store.leagueSection="球队与规则";store.page="联赛实验"
                    for (page,file) in [("联赛实验","league-setup.png"),("战术工作台","league-team-tactics.png"),("球员与阵容","league-team-squad.png")] {
                        if page != "联赛实验" {store.editLeagueTeam(store.leagueSetup.teams[0].id,page:page);store.workbenchStep="阵型与首发"}
                        try await Task.sleep(nanoseconds:600_000_000);view.layoutSubtreeIfNeeded()
                        let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
                        try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(file))
                    }
                    store.leaveLeagueEditor()
                    try Data("PASS named presets save/reload/import/archive, target-only loading and undo; shared league roster/tactics, isolated ordinary match, per-team random/undo, persisted editor context, frozen experiment inputs and batch/league checkpoint recovery".utf8).write(to:folder.appendingPathComponent("ui-workflow-validation.txt"))
                }
                if let i=CommandLine.arguments.firstIndex(of:"--save-smoke"),CommandLine.arguments.count>i+1 {
                    store.readCareerSave(URL(fileURLWithPath:CommandLine.arguments[i+1]))
                    for _ in 0..<3200 {if !store.readingSave{break};try await Task.sleep(nanoseconds:100_000_000)}
                    precondition(store.error==nil && store.saveCatalog != nil,store.error ?? "save catalog timeout")
                    let catalog=store.saveCatalog!,club=catalog.managedClubIDs.first!
                    store.importSavedClubs([club],toWorkbench:true)
                    for _ in 0..<3200 {if !store.readingSave{break};try await Task.sleep(nanoseconds:100_000_000)}
                    precondition(store.error==nil && store.editing.players.allSatisfy{$0.nativeAttributes != nil},store.error ?? "save roster timeout")
                    _ = try NativeScenario(workspace:store.workspace)
                    try Data("PASS bundled SaveReader via app: catalog, selected club, original attributes and native scenario preflight".utf8).write(to:folder.appendingPathComponent("ui-save-validation.txt"))
                }
                if custom {
                    for (isLibrary,file) in [(true,"team-preset-library.png"),(false,"real-team-import.png")] {
                        store.showTeamPresets=isLibrary;store.showSaveImporter = !isLibrary
                        try await Task.sleep(nanoseconds:800_000_000)
                        if let window=NSApplication.shared.windows.first(where:{$0.isSheet}),let view=window.contentView {
                            view.layoutSubtreeIfNeeded();let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
                            try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(file))
                        } else {throw LabError("Sheet capture missing: "+file)}
                        store.showTeamPresets=false;store.showSaveImporter=false;try await Task.sleep(nanoseconds:500_000_000)
                    }
                }
                try Data("PASS \(count) original FM matches, persisted result restore, 7 views; custom mode also checks 24 league matches, cancellation/resume and rankings".utf8).write(to:folder.appendingPathComponent("ui-engine-validation.txt"))
                exit(0)
            } catch {
                try? Data(error.localizedDescription.utf8).write(to:folder.appendingPathComponent("ui-engine-error.txt"));exit(13)
            }
        }
    }
    private func captureIfRequested() {
        guard let i = CommandLine.arguments.firstIndex(of:"--snapshot"), CommandLine.arguments.count > i+1 else { return }
        let target = URL(fileURLWithPath:CommandLine.arguments[i+1])
        // Exercise store transitions without touching the user's saved workspace.
        let initial = store.workspace
        store.change { $0.captureBaseline(); $0.tactic.pressing = 5 }
        store.undo(); precondition(store.workspace == initial)
        store.redo(); precondition(store.workspace.tactic.pressing == 5)
        let oldFirst = store.workspace.tactic.slots[0].playerID
        let oldSecond = store.workspace.tactic.slots[1].playerID
        store.assign(oldSecond,slot:0)
        precondition(store.workspace.tactic.slots[1].playerID == oldFirst)
        precondition(Set(store.workspace.tactic.slots.map(\.playerID)).count == 11)
        store.move(2,phase:.possession,point:Point(-1,2))
        precondition(NativeCatalog.positions.contains{$0.point==store.workspace.tactic.slots[2].possession})
        store.workspace=initial
        let firstID=initial.tactic.slots[8].playerID
        store.move(8,phase:.possession,point:initial.tactic.slots[10].possession)
        precondition(store.workspace.tactic.slots[8].playerID==firstID)
        precondition(store.workspace.tactic.slots[8].possession==initial.tactic.slots[10].possession)
        store.undo();precondition(store.workspace==initial)
        store.applyAbility(.national,scope:.position("DC"))
        precondition(store.workspace.players.filter{$0.position=="DC"}.allSatisfy{$0.abilityPreset == .national})
        store.undo();precondition(store.workspace==initial)
        store.applyAbility(.professional,scope:.team)
        store.editSetup { setup in
            var routine=SetPieceRoutine.initial(.attackingCorner)
            routine.primaryTaker=initial.players[8].id;routine.backupTaker=initial.players[10].id
            var personnel=SetPiecePersonnel.initial(.attackingCorner)
            personnel.suggest(players:store.workspace.players,kind:.attackingCorner)
            routine.personnel=personnel;routine.swing="内旋"
            setup.setPieces[TacticalConfiguration.key(.attackingCorner,.left)]=routine
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+2) {
            guard let window = NSApplication.shared.windows.first(where: { $0.contentView != nil }), let view = window.contentView else { exit(2) }
            window.setContentSize(NSSize(width:1440,height:900))
            let folder=target.deletingLastPathComponent()
            let pages:[(String,String,URL)] = [
                ("战术工作台","阵型与首发",target),
                ("球员与阵容","阵型与首发",folder.appendingPathComponent("squad.png")),
                ("战术工作台","球队指令",folder.appendingPathComponent("team-instructions.png")),
                ("战术工作台","球员指令",folder.appendingPathComponent("player-instructions.png")),
                ("战术工作台","定位球",folder.appendingPathComponent("set-pieces.png")),
                ("战术工作台","状态与磨合",folder.appendingPathComponent("conditions.png")),
                ("引擎与接入","阵型与首发",folder.appendingPathComponent("engine.png")),
                ("实验对比","阵型与首发",folder.appendingPathComponent("experiments-empty.png")),
                ("实验对比","阵型与首发",folder.appendingPathComponent("experiments-demo.png")),
                ("实验对比","阵型与首发",folder.appendingPathComponent("team-stats.png")),
                ("实验对比","阵型与首发",folder.appendingPathComponent("player-stats.png"))]
            @MainActor func capture(_ index:Int) {
                guard index < pages.count else { try? Data("Passed 11 view captures and store assertions; artificial data only; 0 matches simulated.".utf8).write(to:folder.appendingPathComponent("ui-validation.txt")); print("PASS UI store undo/redo, drag swap, ability scopes, drag bounds, 11 rendered pages"); exit(0) }
                store.page = pages[index].0
                store.workbenchStep=pages[index].1
                if index == 5 {
                    store.editSetup { $0.conditions.custom=true;$0.conditions.condition=85;$0.conditions.fatigue = .tired;$0.conditions.executionEnabled=true;$0.conditions.understanding=35 }
                }
                if index == 6 { store.checkNativeEngine() }
                if index == 9 {store.resultSection="球队明细"}
                if index == 10 {store.resultSection="球员数据"}
                if index == 8 {
                    var csv = "variant,seed,goals_for,goals_against,opponent,venue,xg_for,xg_against,shots_for,shots_on_target_for,passes_for,completed_passes_for,possession_for,possession_against\n"
                    for seed in 1...30 {
                        csv += "A,\(seed),\(seed%3),1,示例对手,home,1.7,1.1,12,4,410,350,55,45\n"
                        csv += "B,\(seed),\(seed%4),1,示例对手,home,1.7,1.1,12,4,410,350,55,45\n"
                    }
                    var e=try! Experiment.load(csv,source:"截图测试数据 · 非真实比赛结果")
                    let pcsv="variant,seed,opponent,venue,player_id,player_name,team,minutes,rating,goals,assists,xg,shots,shots_on_target\nA,1,示例对手,home,9,示例前锋,for,90,7.4,1,0,0.9,4,2\nA,1,示例对手,home,8,示例中场,for,90,7.1,0,1,0.1,1,0\n"
                    e.playerRecords=try! PlayerMatchRecord.load(pcsv,experiment:e)
                    store.setExperiment(e)
                }
                DispatchQueue.main.asyncAfter(deadline:.now()+1) {
                    view.layoutSubtreeIfNeeded()
                    guard let rep = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { exit(3) }
                    view.cacheDisplay(in:view.bounds,to:rep)
                    guard let png = rep.representation(using:.png,properties:[:]) else { exit(4) }
                    do { try png.write(to:pages[index].2); capture(index+1) }
                    catch { fputs("\(error)\n",stderr); exit(5) }
                }
            }
            capture(0)
        }
    }
    private func sheetCaptureIfRequested() {
        guard let i=CommandLine.arguments.firstIndex(of:"--capture-sheets"),CommandLine.arguments.count>i+1 else{return}
        let folder=URL(fileURLWithPath:CommandLine.arguments[i+1]).standardizedFileURL
        guard store.storage.standardizedFileURL==folder.appendingPathComponent("data").standardizedFileURL else{exit(10)}
        Task { @MainActor in
            do {
                // Reuse the isolated workflow evidence; no simulation or edits.
                let imports=store.storage.appendingPathComponent("save-imports")
                for directory in (try? FileManager.default.contentsOfDirectory(at:imports,includingPropertiesForKeys:nil)) ?? [] {
                    let url=directory.appendingPathComponent("data.json")
                    if let data=try? Data(contentsOf:url),let catalog=try? JSONDecoder().decode(SaveCatalog.self,from:data).validated() {store.saveCatalog=catalog;break}
                }
                for (library,file) in [(true,"team-preset-library.png"),(false,"real-team-import.png")] {
                    store.showTeamPresets=library;store.showSaveImporter = !library
                    try await Task.sleep(nanoseconds:1_000_000_000)
                    guard let view=NSApplication.shared.windows.first(where:{$0.isSheet})?.contentView,let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{exit(15)}
                    view.cacheDisplay(in:view.bounds,to:rep);try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(file))
                    store.showTeamPresets=false;store.showSaveImporter=false;try await Task.sleep(nanoseconds:500_000_000)
                };exit(0)
            } catch {exit(16)}
        }
    }
}

enum Theme {
    static let ink = Color(red:0.11,green:0.19,blue:0.17)
    static let green = Color(red:0.12,green:0.43,blue:0.32)
    static let paper = Color(red:0.96,green:0.97,blue:0.95)
    static let muted = Color(red:0.43,green:0.49,blue:0.45)
    static let amber = Color(red:0.77,green:0.48,blue:0.13)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment:.leading,spacing:14) { content }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(.white,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(Theme.ink.opacity(0.07))) }
}

struct Chip: View {
    var text: String
    var color: Color = Theme.green
    var body: some View { Text(text).font(.system(size:11,weight:.medium)).padding(.horizontal,10).padding(.vertical,5).foregroundStyle(color).background(color.opacity(0.09),in:Capsule()) }
}

struct RootView: View {
    @EnvironmentObject var store: LabStore
    private let pages = [("战术工作台","sportscourt"),("球员与阵容","person.3"),("实验对比","chart.bar.xaxis"),("联赛实验","trophy"),("引擎与接入","cpu")]
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:10) {
                    Image(systemName:"soccerball").font(.system(size:28))
                    VStack(alignment:.leading,spacing:4) { Text("TACTICS LAB").font(.system(size:14,weight:.bold,design:.rounded)); Text("战术实验室 / MAC").font(.system(size:10)).tracking(1.3).opacity(0.6) }
                }.padding(.vertical,30).padding(.horizontal,20)
                Text("工作空间").font(.system(size:10,weight:.semibold)).foregroundStyle(.white.opacity(0.4)).padding(.leading,22).padding(.bottom,13)
                ForEach(pages,id:\.0) { name,icon in
                    Button { store.page = name } label: {
                        HStack(spacing:12) { Image(systemName:icon).frame(width:20); Text(name).font(.system(size:13,weight:.medium)); Spacer(); if store.page == name { Circle().fill(Color(red:0.76,green:0.89,blue:0.53)).frame(width:5,height:5) } }
                            .padding(13).background(store.page == name ? Color.white.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:9))
                    }.buttonStyle(.plain).padding(.horizontal,10).padding(.bottom,5)
                }
                Spacer()
                VStack(alignment:.leading,spacing:9) {
                    HStack { Circle().fill(Color.orange.opacity(0.8)).frame(width:6,height:6); Text("本地编辑与分析").font(.system(size:12,weight:.medium)) }
                    Text(store.runningOriginal || store.leagueRunning ? "原版比赛计算中" : "原版引擎 · 自定义测试").font(.system(size:11)).foregroundStyle(.white.opacity(0.55))
                    Divider().overlay(.white.opacity(0.1)).padding(.vertical,7)
                    Text("v0.5 · 原生 macOS").font(.system(size:10)).foregroundStyle(.white.opacity(0.4))
                }.padding(22)
            }.frame(width:202).foregroundStyle(.white).background(Theme.ink)
            VStack(spacing:0) {
                header
                Divider().opacity(0.4)
                if ["战术工作台","球员与阵容"].contains(store.page) {EditingTeamBar()}
                Group {
                    switch store.page {
                    case "球员与阵容": SquadView()
                    case "实验对比": ExperimentsView()
                    case "联赛实验": LeagueView()
                    case "引擎与接入": EngineView()
                    default: WorkbenchView()
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity).disabled(store.processingTactic)
                HStack { Circle().fill(Theme.green).frame(width:5,height:5); Text(store.message); Spacer(); Text("⌘Z 撤销   ·   ⇧⌘S 导出方案") }.font(.system(size:10)).foregroundStyle(Theme.muted).padding(.horizontal,24).padding(.vertical,10)
            }.background(Theme.paper)
        }.tint(Theme.green).foregroundStyle(Theme.ink)
        .sheet(isPresented:$store.showTeamPresets) { TeamPresetView().environmentObject(store) }
        .sheet(isPresented:$store.showSaveImporter) { VStack(alignment:.leading,spacing:16) { HStack{Text("真实球队快速开始").font(.title2.bold());Spacer();Button("完成"){store.showSaveImporter=false}};Text("选择来源 → 选择球队或联赛 → 核对阵容与规则 → 调整战术 → 开始模拟").foregroundStyle(Theme.muted);ScrollView{SaveImportPanel()} }.padding(24).frame(width:960,height:680).background(Theme.paper).environmentObject(store) }
        .alert("操作未完成",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error=nil}})) { Button("知道了") { store.error=nil } } message: { Text(store.error ?? "") }
    }
    private var header: some View {
        HStack(alignment:.center) {
            VStack(alignment:.leading,spacing:5) {
                Text(store.page).font(.system(size:25,weight:.semibold))
                Text(subtitle).font(.system(size:12)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if ["战术工作台","球员与阵容","联赛实验"].contains(store.page) { Button("阵容方案库") { store.showTeamPresets = true } }
            if ["战术工作台","球员与阵容","联赛实验"].contains(store.page) {Button("从 FM 存档导入"){store.showSaveImporter=true}.disabled(store.processingTactic)}
            if store.page == "战术工作台" {
                Button(action:store.undo) { Image(systemName:"arrow.uturn.backward") }.disabled(!store.canUndo).help("撤销 ⌘Z")
                Menu("战术文件") {
                    Button("导入游戏战术 FMF…",action:store.importGameTactic)
                    Button("导出游戏战术 FMF…",action:store.exportGameTactic)
                    Divider()
                    Button("打开完整工具方案 JSON…",action:store.importWorkspace)
                    Button("导出完整工具方案 JSON…",action:store.exportWorkspace)
                }.disabled(store.processingTactic).menuStyle(.borderedButton)
            } else if store.page == "球员与阵容" { Button("导入球员 CSV",action:store.importPlayers).buttonStyle(.borderedProminent) }
            else if store.page == "实验对比" { Button("导入实验 CSV",action:store.importExperiment).buttonStyle(.borderedProminent) }
        }.controlSize(.large).padding(.horizontal,26).padding(.vertical,22)
    }
    private var subtitle: String {
        switch store.page {
        case "球员与阵容": return "把你的球员带进来，让战术适应阵容。"
        case "实验对比": return "固定条件，成对比较，让每次改动有据可查。"
        case "联赛实验": return "选择球队与规则，运行完整赛程，检查积分与排名。"
        case "引擎与接入": return "检查本机 FM27，并查看真实比赛计算的接入状态。"
        default: return "从一个战术问题开始，每次只改变一个变量。"
        }
    }
}
