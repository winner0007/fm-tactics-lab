import AppKit
import SwiftUI
import TacticsCore

@MainActor enum StorageSmoke {
    static func start(_ store:LabStore) {
        let args=CommandLine.arguments
        guard let mode=["--league-progress-smoke","--league-ui-preview","--storage-smoke"].first(where:{args.contains($0)}),let i=args.firstIndex(of:mode),args.count>i+1 else{return}
        let folder=URL(fileURLWithPath:args[i+1]).standardizedFileURL
        guard store.storage.standardizedFileURL==folder.appendingPathComponent("data").standardizedFileURL else{exit(30)}
        Task {
            do {
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                for _ in 0..<200 {if !store.engineSearching {break};try await Task.sleep(nanoseconds:100_000_000)}
                try JSONEncoder().encode(store.engine).write(to:folder.appendingPathComponent("initial-engine.json"))
                guard !store.engineLocationBusy else{throw LabError("初始化仍忙：查找 \(store.engineSearching) / 历史 \(store.managingHistory) / 导入 \(store.readingSave)")}
                if mode=="--league-ui-preview" {try await leagueUI(store,folder:folder)}
                else if mode=="--league-progress-smoke" {try await leagueRun(store,folder:folder)}
                else {try await storage(store,folder:folder)}
                NSApplication.shared.terminate(nil)
            } catch {try? Data(error.localizedDescription.utf8).write(to:folder.appendingPathComponent("failure.txt"));exit(31)}
        }
    }
    private static func capture(_ store:LabStore,view:AnyView,file:URL,width:Int=1440)async throws {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:900),styleMask:[.titled],backing:.buffered,defer:false)
        window.contentView=NSHostingView(rootView:view.environmentObject(store).preferredColorScheme(.light));window.orderFront(nil)
        defer{window.orderOut(nil)}
        try await Task.sleep(nanoseconds:250_000_000)
        let content=window.contentView!;content.layoutSubtreeIfNeeded()
        let rep=content.bitmapImageRepForCachingDisplay(in:content.bounds)!
        content.cacheDisplay(in:content.bounds,to:rep);try rep.representation(using:.png,properties:[:])!.write(to:file)
    }
    private static func leagueRun(_ store:LabStore,folder:URL)async throws {
        let legacy=try JSONDecoder().decode(LeagueRun.self,from:Data(contentsOf:folder.appendingPathComponent("legacy-run.json"))).validated()
        let baseline=legacy.setup
        store.leagueSetup=baseline;store.leagueSeasons=1;store.leagueSeed=String(legacy.firstSeed);store.simulationWorkers=8
        let start=Date();store.runLeague()
        for _ in 0..<200 {if store.leagueRun != nil {break};try await Task.sleep(nanoseconds:50_000_000)}
        if let run=store.leagueRun {try await capture(store,view:AnyView(ScrollView{LeagueReportView(run:run).padding(24)}),file:folder.appendingPathComponent("preparing.png"))}
        for _ in 0..<1200 {if (store.leagueRun?.results.count ?? 0)>0 || !store.leagueRunning {break};try await Task.sleep(nanoseconds:50_000_000)}
        guard let partial=store.leagueRun,!partial.results.isEmpty,(partial.preparedTactics?.count ?? 0)<partial.schedule.count else {throw LabError("首场仍等待全赛季战术或未能开赛："+(store.error ?? ""))}
        let firstSeconds=Date().timeIntervalSince(start),preparedAtFirst=partial.preparedTactics?.count ?? 0
        store.stopLeague()
        for _ in 0..<200 {if !store.leagueRunning {break};try await Task.sleep(nanoseconds:50_000_000)}
        guard store.leagueRun?.setup==baseline,store.leagueRun?.status=="已停止" else{throw LabError("首批停止或冻结配置失败。")}
        _ = try store.leagueRun!.validated()
        let oldFolder=store.experimentStorage.appendingPathComponent("league-runs").appendingPathComponent(legacy.id.uuidString)
        try FileManager.default.createDirectory(at:oldFolder,withIntermediateDirectories:true)
        try JSONEncoder().encode(legacy).write(to:oldFolder.appendingPathComponent("run.json"))
        store.loadLeagueRun(oldFolder);guard store.error==nil else{throw LabError(store.error!)}
        store.runLeague(resume:true)
        for _ in 0..<18000 {if !store.leagueRunning {break};try await Task.sleep(nanoseconds:100_000_000)}
        guard !store.leagueRunning,store.error==nil,let result=store.leagueRun,result.status=="已完成",result.results.count==result.expected,result.setup==baseline else {throw LabError("旧实验续跑失败："+(store.error ?? "timeout"))}
        for (id,prep) in legacy.preparedTactics ?? [:] {guard result.preparedTactics?[id]==prep else{throw LabError("旧 AI 战术被重新生成。")}}
        _ = try result.validated()
        let reloaded=LabStore();guard reloaded.leagueRun==result else{throw LabError("报告重开不一致。")}
        try await leagueUI(store,folder:folder)
        try Data("PASS first result after \(String(format:"%.2f",firstSeconds))s with \(preparedAtFirst) / \(partial.schedule.count) AI fixtures prepared; stop retained frozen setup. Legacy resumed to \(result.results.count) matches, reused \(legacy.preparedTactics?.count ?? 0) preparations, validated/reopened; real player inputs unchanged.\n".utf8).write(to:folder.appendingPathComponent("validation.txt"))
    }
    private static func leagueUI(_ store:LabStore,folder:URL)async throws {
        guard let result=store.leagueRun else{throw LabError("没有可预览的联赛报告。")}
        store.leagueSetup=result.setup;store.page="联赛实验"
        for width in [1180,1440] {
            store.leagueSection="球队与规则"
            try await capture(store,view:AnyView(RootView()),file:folder.appendingPathComponent("league-settings-\(width).png"),width:width)
            store.leagueSection="积分与统计"
            try await capture(store,view:AnyView(RootView()),file:folder.appendingPathComponent("league-report-\(width).png"),width:width)
        }
        store.editLeagueTeam(result.setup.teams[0].id,page:"球员与阵容")
        try await capture(store,view:AnyView(AbilityPresetsView().padding(24)),file:folder.appendingPathComponent("ability-default.png"))
    }
    private static func storage(_ store:LabStore,folder:URL)async throws {
        store.save();let original=store.workspace,setup=store.leagueSetup
        var batch=SimulationBatch(requested:3,firstSeed:1,configuration:nil);batch.status="已停止"
        let batchFolder=store.experimentStorage.appendingPathComponent("engine-runs").appendingPathComponent(batch.id.uuidString)
        try FileManager.default.createDirectory(at:batchFolder,withIntermediateDirectories:true)
        try JSONEncoder().encode(batch).write(to:batchFolder.appendingPathComponent("batch.json"))
        try Data("log".utf8).write(to:batchFolder.appendingPathComponent("match.log"))
        store.loadNativeBatch(batchFolder)
        guard store.error==nil else{throw LabError(store.error!)}
        let target=folder.appendingPathComponent("chosen-disk/测试数据")
        store.managingHistory=true;try await store.moveExperimentStorage(to:target);store.managingHistory=false
        guard store.experimentStorage.path==target.path,!FileManager.default.fileExists(atPath:batchFolder.path),store.originalLogFolder?.path==target.appendingPathComponent("engine-runs").appendingPathComponent(batch.id.uuidString).path else {throw LabError("目录迁移不完整：\(store.originalLogFolder?.path ?? "nil")，旧文件仍在 \(FileManager.default.fileExists(atPath:batchFolder.path))。")}
        let reloaded=LabStore();guard reloaded.experimentStorage.path==target.path,reloaded.batch?.id==batch.id,reloaded.workspace==original else{throw LabError("新目录未记住或影响了工作台：路径 \(reloaded.experimentStorage.path==target.path)，索引 \(reloaded.batch?.id==batch.id)，工作台 \(reloaded.workspace==original)。")}
        let moved=folder.appendingPathComponent("temporarily-unmounted")
        try FileManager.default.moveItem(at:target,to:moved)
        guard !store.experimentStorageAvailable,!store.requireExperimentStorage(),!FileManager.default.fileExists(atPath:target.path) else{throw LabError("断开的数据目录被静默重建。")}
        try FileManager.default.moveItem(at:moved,to:target);store.error=nil
        store.historyEntries=LabStore.history(at:target)
        guard let entry=store.historyEntries.first else{throw LabError("迁移后未列出历史。")}
        store.page="历史与存储"
        try await capture(store,view:AnyView(RootView()),file:folder.appendingPathComponent("history-before.png"),width:1180)
        store.deleteHistory(entry)
        for _ in 0..<300 {if !store.managingHistory{break};try await Task.sleep(nanoseconds:50_000_000)}
        guard store.error==nil,store.batch==nil,!FileManager.default.fileExists(atPath:entry.url.path),store.workspace==original else{throw LabError("单次清理失败。")}
        var a=Workspace.example(includeOpponent:false),b=a;a.tactic.name="A";b.tactic.name="B"
        var testSetup=LeagueSetup();testSetup.teams=[LeagueTeam(plan:a),LeagueTeam(plan:b)]
        let deletedRun=try LeagueRun(setup:testSetup,seasons:1,seed:1),viewedRun=try LeagueRun(setup:testSetup,seasons:1,seed:2)
        let oldRunFolder=target.appendingPathComponent("league-runs").appendingPathComponent(deletedRun.id.uuidString)
        try FileManager.default.createDirectory(at:oldRunFolder,withIntermediateDirectories:true)
        try JSONEncoder().encode(deletedRun).write(to:oldRunFolder.appendingPathComponent("run.json"))
        try JSONEncoder().encode(deletedRun.id).write(to:target.appendingPathComponent("latest-league.json"))
        store.leagueRun=viewedRun
        let oldEntry=LabStore.history(at:target).first{$0.kind == .league}!
        store.deleteHistory(oldEntry)
        for _ in 0..<300 {if !store.managingHistory{break};try await Task.sleep(nanoseconds:50_000_000)}
        guard store.error==nil,store.leagueRun==viewedRun,!FileManager.default.fileExists(atPath:target.appendingPathComponent("latest-league.json").path) else{throw LabError("历史联赛索引未清除或误清当前报告。")}
        let unrelated=target.appendingPathComponent("keep-user-file.txt");try Data("keep".utf8).write(to:unrelated)
        let reports=target.appendingPathComponent("experiments");try FileManager.default.createDirectory(at:reports,withIntermediateDirectories:true)
        try Data("test".utf8).write(to:reports.appendingPathComponent("invalid-old.json"))
        store.deleteHistory(nil)
        for _ in 0..<300 {if !store.managingHistory{break};try await Task.sleep(nanoseconds:50_000_000)}
        guard store.error==nil,try ExperimentStorage.entries(at:target).isEmpty,FileManager.default.fileExists(atPath:unrelated.path),store.workspace==original,store.leagueSetup==setup else{throw LabError("全部清理越界或未完成。")}
        store.originalCount=3;store.originalSeed="1";store.useWorkbench=false;store.runOriginalMatches()
        for _ in 0..<1200 {if !store.runningOriginal {break};try await Task.sleep(nanoseconds:100_000_000)}
        guard store.error==nil,store.originalReports.count==3,store.originalLogFolder?.path.hasPrefix(target.path+"/")==true else{throw LabError("迁移后的新测试没有写入指定目录。")}
        store.deleteHistory(nil)
        for _ in 0..<300 {if !store.managingHistory{break};try await Task.sleep(nanoseconds:50_000_000)}
        let final=LabStore();guard final.experiment==nil,final.batch==nil,final.leagueRun==nil,final.workspace==original else{throw LabError("清理后旧记录重新出现。")}
        store.page="历史与存储"
        try await capture(store,view:AnyView(RootView()),file:folder.appendingPathComponent("history-after.png"),width:1180)
        try Data("PASS migration/copy hash verification, old test files recycled, pointer persisted, missing disk rejected, single/all history recycled, stale league pointer removed, three new original matches saved to chosen directory, unrelated file and workspace/league settings preserved, reopening stays cleared.\n".utf8).write(to:folder.appendingPathComponent("validation.txt"))
    }
}
