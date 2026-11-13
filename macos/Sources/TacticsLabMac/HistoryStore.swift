import AppKit
import TacticsCore

struct HistoryEntry:Identifiable {
    enum Kind:String {case league="联赛实验",batch="普通对战",summary="导入／汇总记录"}
    let url:URL
    let kind:Kind
    let title:String
    let detail:String
    let date:Date
    let bytes:Int64
    var id:String {url.path}
}
private struct HistoryHeader:Decodable {
    struct Skip:Decodable {init(from decoder:Decoder)throws{}}
    struct Setup:Decodable {let name:String}
    struct Configuration:Decodable {
        struct Team:Decodable {let name:String}
        let teams:[Team]
    }
    let startedAt:Date?
    let status:String?
    let completed:Int?
    let requested:Int?
    let seasons:Int?
    let results:[Skip]?
    let schedule:[Skip]?
    let records:[Skip]?
    let setup:Setup?
    let source:String?
    let configuration:Configuration?
}

extension LabStore {
    var experimentStorageAvailable:Bool {
        if experimentStorage.standardizedFileURL==storage.standardizedFileURL {return true}
        var directory:ObjCBool=false
        return FileManager.default.fileExists(atPath:experimentStorage.path,isDirectory:&directory) && directory.boolValue && (try? Data(contentsOf:experimentStorage.appendingPathComponent(ExperimentStorage.markerName)))==ExperimentStorage.marker
    }
    var hasExperimentFiles:Bool {ExperimentStorage.names.contains{FileManager.default.fileExists(atPath:experimentStorage.appendingPathComponent($0).path)}}
    @discardableResult func requireExperimentStorage()->Bool {
        guard experimentStorageAvailable else {error="测试数据目录不可用，请连接保存磁盘。原路径已保留，不会改存到其他位置。";return false}
        do {try FileManager.default.createDirectory(at:experimentStorage,withIntermediateDirectories:true);return true}
        catch {self.error="无法访问测试数据目录："+error.localizedDescription;return false}
    }
    func refreshHistory() {
        guard !managingHistory else{return}
        let root=experimentStorage,scan=UUID();historyScanID=scan
        Task {
            let entries=await Task.detached(priority:.utility){Self.history(at:root)}.value
            if experimentStorage==root,historyScanID==scan,!managingHistory {historyEntries=entries}
        }
    }
    nonisolated static func history(at root:URL)->[HistoryEntry] {
        let fm=FileManager.default
        func size(_ url:URL)->Int64 {
            guard (try? url.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) != true else{return 0}
            if (try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) != true {return Int64((try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0)}
            var sum:Int64=0
            if let items=fm.enumerator(at:url,includingPropertiesForKeys:[.isRegularFileKey,.fileSizeKey,.isSymbolicLinkKey]) {
                for case let file as URL in items {
                    let info=try? file.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey,.isSymbolicLinkKey])
                    if info?.isSymbolicLink==true {items.skipDescendants();continue}
                    if info?.isRegularFile==true {sum+=Int64(info?.fileSize ?? 0)}
                }
            }
            return sum
        }
        var output:[HistoryEntry]=[]
        for (folder,kind,file) in [("league-runs",HistoryEntry.Kind.league,"run.json"),("engine-runs",.batch,"batch.json"),("experiments",.summary,"")] {
            for url in (try? fm.contentsOfDirectory(at:root.appendingPathComponent(folder),includingPropertiesForKeys:nil,options:.skipsHiddenFiles)) ?? [] {
                guard (try? ExperimentStorage.check(url,under:root)) != nil else{continue}
                if kind == .summary && url.pathExtension != "json" {continue}
                let metadata=file.isEmpty ? url:url.appendingPathComponent(file)
                let info=try? metadata.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey])
                let data=(info?.fileSize ?? Int.max)<50_000_000 ? try? Data(contentsOf:metadata):nil
                let header=data.flatMap{try? JSONDecoder().decode(HistoryHeader.self,from:$0)}
                let count=header?.results?.count ?? header?.completed ?? header?.records?.count
                let total=header?.schedule.map{$0.count*(header?.seasons ?? 1)} ?? header?.requested
                let progress=count.map{n in total.map{"\(n) / \($0) 场"} ?? "\(n) 场"} ?? "打开报告查看详情"
                let opponents=header?.configuration?.teams.map(\.name).joined(separator:" vs ")
                let title=header?.setup?.name ?? opponents ?? header?.source ?? (kind == .batch && header != nil ? "FM 原版内置基线":kind.rawValue+" · "+url.lastPathComponent.prefix(8))
                output.append(HistoryEntry(url:url,kind:kind,title:title,detail:(header?.status.map{$0+" · "} ?? "")+progress,date:header?.startedAt ?? info?.contentModificationDate ?? .distantPast,bytes:size(url)))
            }
        }
        return output.sorted{$0.date>$1.date}
    }
    func openHistory(_ entry:HistoryEntry) {
        guard !engineLocationBusy else{return}
        switch entry.kind {
        case .league:loadLeagueRun(entry.url)
        case .batch:loadNativeBatch(entry.url)
        case .summary:loadArchive(entry.url);page="实验对比"
        }
    }
    private func recycle(_ urls:[URL])async throws {
        guard !urls.isEmpty else{return}
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            NSWorkspace.shared.recycle(urls) {_,error in
                if let error {continuation.resume(throwing:error)}else{continuation.resume()}
            }
        }
    }
    func deleteHistory(_ entry:HistoryEntry?) {
        guard !engineLocationBusy,requireExperimentStorage() else{return}
        managingHistory=true;historyScanID=UUID()
        Task {
            defer{managingHistory=false;refreshArchives();refreshLeagueArchives();refreshHistory()}
            do {
                var targets:[URL]
                var clearLeague=entry==nil,clearBatch=entry==nil,clearSummary=entry==nil
                if let entry {
                    try ExperimentStorage.check(entry.url,under:experimentStorage)
                    targets=[entry.url]
                    clearLeague=entry.kind == .league && entry.url.lastPathComponent==leagueRun?.id.uuidString
                    clearBatch=entry.kind == .batch && entry.url.lastPathComponent==batch?.id.uuidString
                    if entry.kind == .summary,let current=experiment,let archived=try? JSONDecoder().decode(Experiment.self,from:Data(contentsOf:entry.url)) {clearSummary=current==archived}
                    let latestLeague=(try? Data(contentsOf:experimentStorage.appendingPathComponent("latest-league.json"))).flatMap{try? JSONDecoder().decode(UUID.self,from:$0)}
                    let removesLatestLeague=entry.kind == .league && entry.url.lastPathComponent==latestLeague?.uuidString
                    let snapshotNames=(clearLeague || removesLatestLeague ? ["latest-league.json"]:[])+(clearBatch ? ["latest-batch.json","original-matches.json","experiment.json","experiment.csv"]:[])+(clearSummary ? ["experiment.json","experiment.csv"]:[])
                    targets+=Set(snapshotNames).map{experimentStorage.appendingPathComponent($0)}.filter{FileManager.default.fileExists(atPath:$0.path)}
                } else {targets=try ExperimentStorage.entries(at:experimentStorage)}
                for url in targets {try ExperimentStorage.check(url,under:experimentStorage)}
                try await recycle(targets)
                if clearLeague {leagueRun=nil;leagueProgress=""}
                if clearBatch {originalReports=[];originalMatch=nil;batch=nil;originalLogFolder=nil;originalProgress=""}
                if clearSummary || clearBatch {experiment=nil}
                message="测试记录已移到废纸篓；战术、阵容方案和联赛配置已保留"
            } catch {self.error="清理未完成："+error.localizedDescription}
        }
    }
    func chooseExperimentStorage() {
        guard !engineLocationBusy else{return}
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.allowsMultipleSelection=false
        panel.title="选择测试数据保存位置";panel.prompt="迁移到这里"
        panel.message="将在所选位置新建测试数据文件夹。复制并校验全部历史后启用新位置，原测试数据移到废纸篓；战术与阵容方案保持原位。请先退出其他版本的工具。"
        guard panel.runModal() == .OK,let parent=panel.url else{return}
        let destination=parent.appendingPathComponent("FM 战术实验室测试数据-"+UUID().uuidString.prefix(8))
        managingHistory=true;historyScanID=UUID()
        Task {
            defer{managingHistory=false;refreshArchives();refreshLeagueArchives();refreshHistory()}
            do {try await moveExperimentStorage(to:destination);message="测试数据已迁移；后续测试保存到新位置"}
            catch {self.error=error.localizedDescription}
        }
    }
    func moveExperimentStorage(to destination:URL,removeOriginal:Bool=true)async throws {
        let source=experimentStorage
        guard requireExperimentStorage() else{throw LabError("原测试数据目录不可用。")}
        try await Task.detached(priority:.utility){try ExperimentStorage.copyHistory(from:source,to:destination)}.value
        // Commit the pointer only after every file has passed a content check.
        try FileManager.default.createDirectory(at:storage,withIntermediateDirectories:true)
        try JSONEncoder().encode(destination.path).write(to:storage.appendingPathComponent("experiment-location.json"),options:.atomic)
        experimentStorage=destination
        if let old=originalLogFolder,old.path.hasPrefix(source.path+"/") {originalLogFolder=destination.appendingPathComponent(String(old.path.dropFirst(source.path.count+1)))}
        if removeOriginal {
            do {try await recycle(ExperimentStorage.entries(at:source))}
            catch {throw LabError("新位置已启用，原目录副本未能移到废纸篓："+error.localizedDescription)}
        }
    }
}
