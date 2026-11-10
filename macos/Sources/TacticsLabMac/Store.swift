import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TacticsCore

@MainActor final class LabStore: ObservableObject {
    @Published var workspace = Workspace.example()
    @Published var page = "战术工作台"
    @Published var selectedSlot = 9
    @Published var phase: Phase = .possession
    @Published var message = "所有更改自动保存在本机"
    @Published var error: String?
    @Published var engine = EngineReport.searching
    @Published var engineSearching = false
    @Published var checkingNative = false
    @Published var nativeCheck:NativeEngineCheck?
    @Published var originalSeed="1"
    @Published var originalCount=1
    @Published var runningOriginal=false
    @Published var originalProgress=""
    @Published var originalMatch:OriginalMatchReport?
    @Published var originalLogFolder:URL?
    private var originalReports:[OriginalMatchReport]=[]
    private var originalJob:OriginalMatchJob?
    private var originalCancelled=false
    @Published var workbenchStep = "阵型与首发"
    @Published var resultSection="总览"
    @Published var experiment: Experiment?
    @Published var experimentArchives:[URL] = []
    @Published var baselineVariant = ""
    @Published var candidateVariant = ""
    private var history: [Workspace] = []
    private var future: [Workspace] = []
    private var writable = true
    let storage: URL
    let preview: Bool

    init() {
        preview = CommandLine.arguments.contains("--snapshot")
        if let i = CommandLine.arguments.firstIndex(of: "--data-dir"), CommandLine.arguments.count > i+1 {
            storage = URL(fileURLWithPath: CommandLine.arguments[i+1])
        } else {
            storage = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FM Tactics Lab Mac")
        }
        if preview { searchEngine(); return }
        let file = storage.appendingPathComponent("workspace.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let data=try Data(contentsOf:file)
                let decoded=try JSONDecoder().decode(Workspace.self,from:data)
                workspace=try decoded.validated()
                if decoded.schema != workspace.schema {
                    let backup=storage.appendingPathComponent("workspace-before-v03-"+UUID().uuidString.prefix(8)+".json")
                    try data.write(to:backup,options:.atomic)
                }
            }
            catch { self.error = "本机方案读取失败，原文件已保留。请导入备份或另存方案。\n\(error.localizedDescription)"; writable = false }
        }
        if let data = try? Data(contentsOf: storage.appendingPathComponent("experiment.csv")), let csv = String(data: data, encoding: .utf8), let e = try? Experiment.load(csv, source: "上次导入的实验") { setExperiment(e) }
        if let data=try? Data(contentsOf:storage.appendingPathComponent("experiment.json")),let value=try? JSONDecoder().decode(Experiment.self,from:data).validated() {setExperiment(value)}
        refreshArchives()
        if let data=try? Data(contentsOf:storage.appendingPathComponent("original-matches.json")),let reports=try? JSONDecoder().decode([OriginalMatchReport].self,from:data),!reports.isEmpty,
           reports.allSatisfy({$0.engineSHA256==OriginalMatchReport.engineHash}),
           (try? OriginalMatchReport.experiment(reports).validated()) != nil {
            originalReports=reports;originalMatch=reports.last
            let logs=storage.appendingPathComponent("engine-runs")
            if FileManager.default.fileExists(atPath:logs.path) {originalLogFolder=logs}
        }
        searchEngine()
    }
    var canUndo: Bool { !history.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    func change(_ edit: (inout Workspace) -> Void) {
        let before = workspace
        edit(&workspace)
        guard workspace != before else { return }
        history.append(before); if history.count > 80 { history.removeFirst() }; future.removeAll(); save()
    }
    func undo() { if let value = history.popLast() { future.append(workspace); workspace = value; save() } }
    func redo() { if let value = future.popLast() { history.append(workspace); workspace = value; save() } }
    func save() {
        guard !preview && writable else { return }
        guard let valid = try? workspace.validated() else { message = "请补全方案与球员姓名，随后会自动保存"; return }
        do {
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            try encoder.encode(valid).write(to: storage.appendingPathComponent("workspace.json"), options: .atomic)
            message = "已自动保存 · \(Date().formatted(date: .omitted, time: .shortened))"
        } catch { self.error = error.localizedDescription }
    }
    func field<T>(_ key: WritableKeyPath<Tactic,T>) -> Binding<T> {
        Binding(get: { self.workspace.tactic[keyPath:key] }, set: { value in self.change { $0.tactic[keyPath:key] = value } })
    }
    func player(_ slot: Slot) -> Player { workspace.players.first { $0.id == slot.playerID } ?? workspace.players[0] }
    func assign(_ id: UUID, slot: Int) {
        change { w in
            let previous = w.tactic.slots[slot].playerID
            if let other = w.tactic.slots.firstIndex(where: { $0.playerID == id }) { w.tactic.slots[other].playerID = previous }
            w.tactic.slots[slot].playerID = id
        }
    }
    func move(_ slot: Int, phase: Phase, point: Point, width:Double=340, height:Double=466) {
        var swapped:Int?
        change { w in
            swapped=w.tactic.dropPlayer(slotID:slot,phase:phase,point:point,width:width,height:height)
        }
        if let swapped { selectedSlot=swapped; message="已交换两名球员 · 两阶段首发同步 · ⌘Z 撤销" }
    }
    func applyAbility(_ tier:AbilityTier,scope:AbilityScope) {
        var rng=SystemRandomNumberGenerator(),count=0
        change { count=$0.applyAbility(tier,scope:scope,using:&rng) }
        message="已将 \(count) 名球员设为\(tier.rawValue)档次 · ⌘Z 撤销"
    }
    func editSetup(_ edit:(inout TacticalConfiguration)->Void) {
        change { w in var setup=w.tactic.setup; edit(&setup); w.tactic.configuration=setup }
    }
    func condition<T>(_ key:WritableKeyPath<MatchConditions,T>) -> Binding<T> {
        Binding(get:{self.workspace.tactic.setup.conditions[keyPath:key]},set:{value in self.editSetup { $0.conditions[keyPath:key]=value }})
    }
    func read(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 10_000_000 else { throw LabError("文件超过 10 MB，请拆分后导入。") }
        return try Data(contentsOf: url)
    }
    func choose(types: [UTType], message: String) -> URL? {
        let panel = NSOpenPanel(); panel.allowedContentTypes = types; panel.message = message; panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
    func export(_ data: Data, name: String, type: UTType) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name; panel.allowedContentTypes = [type]
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url, options: .atomic); message = "已导出 \(url.lastPathComponent)" }
            catch { self.error = error.localizedDescription }
        }
    }
    func exportWorkspace() {
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; export(try encoder.encode(workspace.validated()),name:"战术方案.json",type:.json) }
        catch { self.error = error.localizedDescription }
    }
    func importWorkspace() {
        guard let url = choose(types:[.json],message:"打开 Mac 版方案 JSON，将替换当前工作台；可用 ⌘Z 撤销。") else { return }
        do {
            let value = try JSONDecoder().decode(Workspace.self,from:read(url)).validated()
            change { $0 = value }; selectedSlot = 9
        } catch { self.error = error.localizedDescription }
    }
    func importPlayers() {
        guard let url = choose(types:[.commaSeparatedText,.plainText],message:"导入球员 CSV。前 11 人成为首发，保留站位，清除原对照；可撤销。") else { return }
        do {
            guard let text = String(data: try read(url),encoding:.utf8) else { throw LabError("请使用 UTF-8 编码的 CSV。") }
            let players = try CSV.players(text)
            change { w in
                w.players = players; w.baseline = nil; w.baselinePlayers = nil; w.baselineRosterSource = nil; w.rosterSource = url.lastPathComponent
                for i in 0..<11 { w.tactic.slots[i].playerID = players[i].id }
                if var setup=w.tactic.configuration {
                    for key in Array(setup.setPieces.keys) { setup.setPieces[key]?.primaryTaker=nil; setup.setPieces[key]?.backupTaker=nil; setup.setPieces[key]?.personnel=nil }
                    w.tactic.configuration=setup
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    func setExperiment(_ value: Experiment) {
        experiment = value; baselineVariant = value.variants.first ?? ""; candidateVariant = value.variants.dropFirst().first ?? ""
    }
    func importExperiment() {
        guard let url = choose(types:[.commaSeparatedText,.plainText,.json],message:"导入完整实验 JSON 或逐场 CSV。当前结果会存为历史批次，兼容原项目的中文表头。") else { return }
        do {
            let data = try read(url)
            guard let text = String(data:data,encoding:.utf8) else { throw LabError("请使用 UTF-8 编码的 CSV。") }
            let e = try url.pathExtension.lowercased()=="json" ? JSONDecoder().decode(Experiment.self,from:data).validated() : Experiment.load(text,source:url.lastPathComponent)
            try FileManager.default.createDirectory(at: storage,withIntermediateDirectories:true)
            try Data(e.teamCSV.utf8).write(to:storage.appendingPathComponent("experiment.csv"),options:.atomic)
            try archiveExperiment(e);setExperiment(e); page = "实验对比"
        } catch { self.error = error.localizedDescription }
    }
    func refreshArchives() {
        let folder=storage.appendingPathComponent("experiments")
        experimentArchives=((try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? []).filter{$0.pathExtension=="json"}.sorted{$0.lastPathComponent>$1.lastPathComponent}
    }
    func archiveExperiment(_ value:Experiment) throws {
        guard !preview else {return}
        let folder=storage.appendingPathComponent("experiments")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let data=try JSONEncoder().encode(value)
        let date=ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-")
        try data.write(to:folder.appendingPathComponent(date+"-"+UUID().uuidString.prefix(8)+".json"),options:.atomic)
        try data.write(to:storage.appendingPathComponent("experiment.json"),options:.atomic)
        refreshArchives()
    }
    func loadArchive(_ url:URL) {
        do {let e=try JSONDecoder().decode(Experiment.self,from:read(url)).validated();setExperiment(e);if !preview {try JSONEncoder().encode(e).write(to:storage.appendingPathComponent("experiment.json"),options:.atomic)}} catch {self.error=error.localizedDescription}
    }
    func importPlayerResults() {
        guard var e=experiment else {error="请先导入对应批次的球队比赛结果。";return}
        guard let url=choose(types:[.commaSeparatedText,.plainText],message:"导入同批次的球员逐场统计 CSV。按方案、种子、对手、场地与球员 ID 关联。") else {return}
        do {
            guard let csv=String(data:try read(url),encoding:.utf8) else {throw LabError("请使用 UTF-8 CSV。")}
            e.playerRecords=try PlayerMatchRecord.load(csv,experiment:e)
            try archiveExperiment(e);setExperiment(e)
        } catch {self.error=error.localizedDescription}
    }
    func checkNativeEngine() {
        guard !checkingNative,!runningOriginal,let path=engine.appPath,engine.filesReady else {return}
        guard let helper=Bundle.main.url(forAuxiliaryExecutable:"EngineLoadProbe") else {error="安装包缺少引擎验证进程，请重新构建应用。";return}
        checkingNative=true
        Task {
            do {
                let result=try await Task.detached {try NativeEngineCheck.run(helper:helper,app:URL(fileURLWithPath:path))}.value
                nativeCheck=result
                if !preview {
                    try FileManager.default.createDirectory(at:storage,withIntermediateDirectories:true)
                    try JSONEncoder().encode(result).write(to:storage.appendingPathComponent("engine-load-check.json"),options:.atomic)
                }
            } catch {self.error=error.localizedDescription}
            checkingNative=false
        }
    }
    func runOriginalMatches() {
        guard !runningOriginal,!checkingNative,let path=engine.appPath,engine.filesReady else {return}
        guard let seed=UInt32(originalSeed),[1,5,10,20].contains(originalCount),UInt64(seed)+UInt64(originalCount-1)<=UInt64(UInt32.max) else {error="种子应为 0–4294967295 的整数，且整个批次不能超出范围。";return}
        guard let helper=Bundle.main.url(forAuxiliaryExecutable:"EngineRuntimeProbe") else {error="安装包缺少原版比赛宿主，请重新构建 0.4 版。";return}
        let count=originalCount
        let folder=storage.appendingPathComponent("engine-runs").appendingPathComponent(UUID().uuidString)
        originalLogFolder=folder;runningOriginal=true;originalCancelled=false
        originalProgress="正在校验原版引擎与测试输入…"
        Task {
            var completed:[OriginalMatchReport]=[]
            for i in 0..<count {
                if originalCancelled {break}
                let current=seed+UInt32(i),job=OriginalMatchJob();originalJob=job
                originalProgress="第 \(i+1) / \(count) 场 · 随机种子 \(current) · 已完成 \(completed.count) 场"
                do {
                    let report=try await Task.detached(priority:.userInitiated) {
                        try job.run(helper:helper,app:URL(fileURLWithPath:path),seed:current,log:folder.appendingPathComponent("seed-\(current).jsonl"))
                    }.value
                    completed.append(report);originalMatch=report;originalReports=completed
                    let e=try OriginalMatchReport.experiment(completed)
                    setExperiment(e)
                    try JSONEncoder().encode(e).write(to:storage.appendingPathComponent("experiment.json"),options:.atomic)
                    try JSONEncoder().encode(completed).write(to:storage.appendingPathComponent("original-matches.json"),options:.atomic)
                } catch {
                    if !originalCancelled {self.error=error.localizedDescription}
                    break
                }
            }
            originalJob=nil;runningOriginal=false
            if !completed.isEmpty {
                do {try archiveExperiment(OriginalMatchReport.experiment(completed))} catch {self.error=error.localizedDescription}
            }
            originalProgress="本批次完成 \(completed.count) / \(count) 场"
            message=originalCancelled ? "模拟已停止 · 已完成 \(completed.count) 场已保留" : "原版模拟完成 \(completed.count) / \(count) 场 · 结果与日志已保存"
        }
    }
    func cancelOriginalMatches() {originalCancelled=true;originalJob?.cancel()}
    func showOriginalResults() {
        do {setExperiment(try OriginalMatchReport.experiment(originalReports));page="实验对比";resultSection="总览"} catch {self.error=error.localizedDescription}
    }
    func revealOriginalLogs() {if let folder=originalLogFolder {NSWorkspace.shared.activateFileViewerSelecting([folder])}}
    func chooseGame() {
        let panel=NSOpenPanel(); panel.canChooseFiles=true; panel.canChooseDirectories=true
        panel.allowedContentTypes=[.applicationBundle,.folder]; panel.message="自动查找未找到完整安装。请选择 fm.app 或包含它的游戏文件夹，成功后会记住位置。"
        if panel.runModal() == .OK,let url=panel.url { searchEngine(selected:url) }
    }
    func searchEngine(selected:URL?=nil) {
        guard !engineSearching else { return }
        engineSearching=true
        let preference=storage.appendingPathComponent("engine-location.json")
        let preferred=(try? Data(contentsOf:preference)).flatMap { try? JSONDecoder().decode(String.self,from:$0) }.map { URL(fileURLWithPath:$0) }
        Task {
            let report=await Task.detached(priority:.userInitiated) { EngineReport.inspect(app:selected,preferredApp:preferred) }.value
            engine=report; engineSearching=false
            if selected != nil,report.installationFound,let path=report.appPath,!preview {
                do {
                    try FileManager.default.createDirectory(at:storage,withIntermediateDirectories:true)
                    try JSONEncoder().encode(path).write(to:preference,options:.atomic)
                } catch { self.error="已识别游戏，但无法保存位置：\(error.localizedDescription)" }
            }
        }
    }
}
