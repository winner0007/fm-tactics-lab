import AppKit
import SwiftUI
import TacticsCore

@MainActor enum FeatureSmoke {
    static func replay(_ store:LabStore) {
        guard let i=CommandLine.arguments.firstIndex(of:"--analysis-preview"),CommandLine.arguments.count>i+1 else{return}
        let folder=URL(fileURLWithPath:CommandLine.arguments[i+1]).standardizedFileURL
        guard store.storage.standardizedFileURL==folder.appendingPathComponent("data").standardizedFileURL,!store.originalReports.isEmpty else{exit(10)}
        Task {do {try await capture(store,folder:folder);NSApplication.shared.terminate(nil)} catch {print(error);exit(11)}}
    }
    static func capture(_ store:LabStore,folder:URL) async throws {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1024,height:760),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.title="战术效果 · 布局验证";window.orderFront(nil)
        for width in [1024,1440] {
            window.setContentSize(NSSize(width:width,height:760))
            for (i,section) in ["战术统计","进攻与机会","进球分布","进球时间与方式","临场切换","逐场复盘"].enumerated() {
                window.contentView=NSHostingView(rootView:ScrollView{TacticalImpactView(reports:store.originalReports,section:section).padding(24)}.background(Theme.paper).environmentObject(store).preferredColorScheme(.light))
                try await Task.sleep(nanoseconds:250_000_000)
                let view=window.contentView!;view.layoutSubtreeIfNeeded();let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
                view.cacheDisplay(in:view.bounds,to:rep);try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("analysis-\(i)-\(width).png"))
            }
        }
        window.setContentSize(NSSize(width:1100,height:850))
        window.contentView=NSHostingView(rootView:VStack(spacing:0){StrategyPlanTabs();MatchStrategyView();SimulationBar()}.background(Theme.paper).environmentObject(store).preferredColorScheme(.light))
        try await Task.sleep(nanoseconds:250_000_000)
        let view=window.contentView!,rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
        view.cacheDisplay(in:view.bounds,to:rep);try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("strategy-editor.png"))
        window.orderOut(nil)
    }
}
