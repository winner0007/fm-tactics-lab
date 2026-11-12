import AppKit
import SwiftUI
import TacticsCore

/// A packaged-app import check that deliberately runs no native match. This is
/// usable when a game update changes the binary but the save reader is adapted.
@MainActor enum SaveImportSmoke {
    static func start(_ store:LabStore) {
        let args=CommandLine.arguments
        guard let i=args.firstIndex(of:"--save-import-smoke"),args.count>i+1,
              let s=args.firstIndex(of:"--save-smoke"),args.count>s+1 else{return}
        let folder=URL(fileURLWithPath:args[i+1]).standardizedFileURL
        guard store.storage.standardizedFileURL==folder.appendingPathComponent("data").standardizedFileURL else {exit(10)}
        Task {
            do {
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                store.readCareerSave(URL(fileURLWithPath:args[s+1]))
                for _ in 0..<3200 {if !store.readingSave{break};try await Task.sleep(nanoseconds:100_000_000)}
                guard store.error==nil,let catalog=store.saveCatalog,let own=catalog.managedClubIDs.first else {throw LabError(store.error ?? "目录读取未完成")}
                store.importSavedClubs([own],toWorkbench:true)
                for _ in 0..<3200 {if !store.readingSave{break};try await Task.sleep(nanoseconds:100_000_000)}
                guard store.error==nil,store.editing.players.allSatisfy({$0.nativeAttributes != nil}) else {throw LabError(store.error ?? "球员读取未完成")}
                let ownCount=store.editing.players.count
                let ownName=store.editing.tactic.name
                _ = try NativeScenario(workspace:store.workspace)
                guard let league=catalog.leagues.first(where:{$0.clubIDs.contains(own)}) else {throw LabError("当前联赛缺少完整赛程")}
                store.importSavedClubs(league.clubIDs,league:league)
                for _ in 0..<3200 {if !store.readingSave{break};try await Task.sleep(nanoseconds:100_000_000)}
                guard store.error==nil else {throw LabError(store.error!)}
                let setup=try store.leagueSetup.validated()
                _ = try LeagueRun(setup:setup,seasons:1,seed:1)
                let restored=LabStore();guard restored.leagueSetup==setup else {throw LabError("重开后的联赛设置不一致")}
                store.editLeagueTeam(setup.teams[0].id)
                store.change{$0.management.coach=CoachProfile(name:"锁定验证教练")}
                store.change(allowLockChanges:true){$0.management.coachLocked=true;$0.management.tacticLocked=true}
                let locked=store.editing
                store.change{$0.tactic.configuration!.nativeMentality=7}
                guard store.error != nil,store.editing==locked else {throw LabError("锁定战术未阻止修改")};store.error=nil
                store.change{$0.management.coach=CoachProfile(name:"不可替换的教练")}
                guard store.error != nil,store.editing==locked else {throw LabError("锁定教练未阻止替换")};store.error=nil
                store.change{$0.players[0].setAttribute("reflexes",15)}
                guard store.error==nil,store.editing.management==locked.management else {throw LabError("锁定误阻止球员编辑")}
                let lockedRestore=LabStore();guard lockedRestore.editing.management==locked.management else {throw LabError("锁定未保存")}
                store.leaveLeagueEditor();store.page="引擎与接入"
                for _ in 0..<100 {if !store.engineSearching{break};try await Task.sleep(nanoseconds:100_000_000)}
                if !store.engine.adapterSupported {
                    store.runOriginalMatches()
                    guard !store.runningOriginal,store.error != nil else {throw LabError("新版引擎没有被正确拦截")};store.error=nil
                }
                guard let view=NSApplication.shared.windows.first(where:{$0.isVisible && !$0.isSheet})?.contentView else {throw LabError("应用窗口缺失")}
                for (page,file) in [("引擎与接入","engine-compatibility.png"),("联赛实验","imported-league.png")] {
                    store.page=page;try await Task.sleep(nanoseconds:500_000_000)
                    view.layoutSubtreeIfNeeded();let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
                    view.cacheDisplay(in:view.bounds,to:rep);try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(file))
                }
                if let r=args.firstIndex(of:"--report-smoke"),args.count>r+1 {
                    let run=try JSONDecoder().decode(LeagueRun.self,from:Data(contentsOf:URL(fileURLWithPath:args[r+1]))).validated()
                    try Data(LeagueExport.html(run).utf8).write(to:folder.appendingPathComponent("historical-tactics-report.html"))
                    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:750),styleMask:[.titled],backing:.buffered,defer:false)
                    window.contentView=NSHostingView(rootView:VStack{TacticPerformanceView(run:run,season:1);Spacer()}.padding().environmentObject(store));window.orderFront(nil)
                    try await Task.sleep(nanoseconds:600_000_000)
                    let chart=window.contentView!,rep=chart.bitmapImageRepForCachingDisplay(in:chart.bounds)!
                    chart.cacheDisplay(in:chart.bounds,to:rep);try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("historical-tactics.png"));window.orderOut(nil)
                }
                let summary="PASS packaged app import: \(catalog.build), \(ownName) \(ownCount) players; \(setup.teams.count) teams / \(setup.teams.reduce(0){$0+$1.plan.players.count}) players / \(setup.fixtures().count) fixtures; all scenario preflights; persistence and lock controls. Current binary supported: \(store.engine.adapterSupported). No native match executed."
                try Data(summary.utf8).write(to:folder.appendingPathComponent("validation.txt"));exit(0)
            }catch {try? Data(error.localizedDescription.utf8).write(to:folder.appendingPathComponent("error.txt"));exit(13)}
        }
    }
}
