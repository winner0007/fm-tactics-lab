import SwiftUI

struct HistoryView:View {
    @EnvironmentObject var store:LabStore
    @State private var pending:HistoryEntry?
    @State private var confirm=false
    @State private var clearAll=false
    @State private var filter="全部"
    private var entries:[HistoryEntry] {store.historyEntries.filter{filter=="全部" || $0.kind.rawValue==filter}}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Card {
                    HStack {Text("测试数据保存位置").font(.headline);Spacer();Button("在 Finder 中打开"){NSWorkspace.shared.open(store.experimentStorage)}.disabled(!store.experimentStorageAvailable);Button("更改位置并迁移…",action:store.chooseExperimentStorage).disabled(store.engineLocationBusy)}
                    Text(store.experimentStorage.path).font(.system(size:12,design:.monospaced)).textSelection(.enabled)
                    if !store.experimentStorageAvailable {Label("目录不可用，请连接保存磁盘。",systemImage:"externaldrive.badge.exclamationmark").foregroundStyle(Theme.amber)}
                    Text("这里保存测试结果、开赛配置和原始日志；战术工作台、阵容方案库与联赛设置单独保留。").font(.caption).foregroundStyle(Theme.muted)
                    if store.managingHistory {ProgressView("正在处理文件，请稍候…")}
                }
                Card {
                    HStack {Text("历史测试 · \(store.historyEntries.count) 条").font(.headline);Spacer();Text(ByteCountFormatter.string(fromByteCount:store.historyEntries.reduce(0){$0+$1.bytes},countStyle:.file)).foregroundStyle(Theme.muted);Button("刷新",action:store.refreshHistory).disabled(store.managingHistory);Button("清理全部测试记录…",role:.destructive){pending=nil;clearAll=true;confirm=true}.disabled(store.engineLocationBusy || !store.hasExperimentFiles)}
                    Picker("记录类型",selection:$filter){ForEach(["全部","联赛实验","普通对战","导入／汇总记录"],id:\.self){Text($0).tag($0)}}.pickerStyle(.segmented)
                    Text("清理会把所选记录及其日志移到废纸篓，清空废纸篓后才释放空间。旧版另存的汇总副本会单独列出。").font(.caption).foregroundStyle(Theme.muted)
                    if entries.isEmpty {Text(filter=="全部" ? "暂无测试记录":"没有这类测试记录").foregroundStyle(Theme.muted).padding(.vertical,24)}
                    ForEach(entries){entry in
                        HStack(alignment:.center,spacing:16) {
                            VStack(alignment:.leading,spacing:6) {Text(entry.title).fontWeight(.medium);Text(entry.kind.rawValue+" · "+entry.detail+" · "+entry.date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(Theme.muted)}
                            Spacer();Text(ByteCountFormatter.string(fromByteCount:entry.bytes,countStyle:.file)).font(.caption).foregroundStyle(Theme.muted)
                            Button("查看报告"){store.openHistory(entry)}.disabled(store.engineLocationBusy)
                            Button("清理…",role:.destructive){pending=entry;clearAll=false;confirm=true}.disabled(store.engineLocationBusy)
                        }.padding(.vertical,6)
                        Divider()
                    }
                }
            }.padding(26)
        }.onAppear{store.refreshHistory()}
        .alert(clearAll ? "清理全部测试记录？":"清理这次测试？",isPresented:$confirm) {
            Button("取消",role:.cancel){}
            Button("移到废纸篓",role:.destructive){store.deleteHistory(clearAll ? nil:pending)}
        } message:{Text(clearAll ? "全部测试报告、进度与日志将移到废纸篓。当前战术、球员、阵容方案库与联赛配置保留。":"“\(pending?.title ?? "")”的测试记录将移到废纸篓。当前阵容与战术配置保留。")}
    }
}
