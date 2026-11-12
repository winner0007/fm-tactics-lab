import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TacticsCore

@MainActor final class LabStore: ObservableObject {
    @Published var workspace = Workspace.example()
    @Published var editingSide=0
    @Published var instructionTab="角色与球员指令"
    @Published var useWorkbench=true
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
    @Published var originalCount=100
    @Published var simulationWorkers=SimulationConcurrency.recommended {
        didSet {if (1...256).contains(simulationWorkers),!preview {
            do {try FileManager.default.createDirectory(at:storage,withIntermediateDirectories:true);try JSONEncoder().encode(simulationWorkers).write(to:storage.appendingPathComponent("simulation-workers.json"),options:.atomic)}
            catch {self.error="并行设置未能保存："+error.localizedDescription}
        }}
    }
    @Published var batch:SimulationBatch?
    @Published var runningOriginal=false
    @Published var originalProgress=""
    @Published var originalMatch:OriginalMatchReport?
    @Published var originalLogFolder:URL?
    @Published var originalReports:[OriginalMatchReport]=[]
    private var originalQueue:MatchQueue?
    var tacticGenerationJob:TacticGenerationJob?
    private var originalCancelled=false
    @Published var workbenchStep = "阵型与首发"
    @Published var resultSection="总览"
    @Published var experiment: Experiment?
    @Published var experimentArchives:[URL] = []
    @Published var nativeBatchArchives:[URL] = []
    @Published var leagueSetup=LeagueSetup()
    @Published var leagueSection="球队与规则"
    @Published var leagueRun:LeagueRun?
    @Published var leagueSeasons=1
    @Published var leagueSeed="1"
    @Published var leagueRunning=false
    @Published var leagueProgress=""
    @Published var leagueEditingTeam:UUID?
    @Published var saveCatalog:SaveCatalog?
    @Published var saveSource:URL?
    @Published var readingSave=false
    @Published var saveProgress=""
    @Published var leagueArchives:[URL]=[]
    @Published var teamPresets:[TeamPreset]=[]
    @Published var showTeamPresets=false
    @Published var presetLibraryWarning:String?
    @Published var processingTactic=false
    @Published var showSaveImporter=false
    var leagueQueue:MatchQueue?
    var leagueCancelled=false
    var saveJob:SaveReaderJob?
    @Published var baselineVariant = ""
    @Published var candidateVariant = ""
    private var history: [Workspace] = []
    private var future: [Workspace] = []
    private var leagueHistory:[UUID:[Workspace]]=[:]
    private var leagueFuture:[UUID:[Workspace]]=[:]
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
        workspace=(try? workspace.validated()) ?? workspace
        if preview { searchEngine(); return }
        if let data=try? Data(contentsOf:storage.appendingPathComponent("simulation-workers.json")),let count=try? JSONDecoder().decode(Int.self,from:data),(1...256).contains(count) {simulationWorkers=count}
        let file = storage.appendingPathComponent("workspace.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let data=try Data(contentsOf:file)
                let decoded=try JSONDecoder().decode(Workspace.self,from:data)
                workspace=try decoded.validated()
                if decoded.schema != workspace.schema {
                    let backup=storage.appendingPathComponent("workspace-before-v05-"+UUID().uuidString.prefix(8)+".json")
                    try data.write(to:backup,options:.atomic)
                }
            }
            catch { self.error = "本机方案读取失败，原文件已保留。请导入备份或另存方案。\n\(error.localizedDescription)"; writable = false }
        }
        if let data = try? Data(contentsOf: storage.appendingPathComponent("experiment.csv")), let csv = String(data: data, encoding: .utf8), let e = try? Experiment.load(csv, source: "上次导入的实验") { setExperiment(e) }
        if let data=try? Data(contentsOf:storage.appendingPathComponent("experiment.json")),let value=try? JSONDecoder().decode(Experiment.self,from:data).validated() {setExperiment(value)}
        refreshArchives()
        if let data=try? Data(contentsOf:storage.appendingPathComponent("latest-batch.json")) {batch=try? JSONDecoder().decode(SimulationBatch.self,from:data)}
        if let data=try? Data(contentsOf:storage.appendingPathComponent("original-matches.json")),let reports=try? JSONDecoder().decode([OriginalMatchReport].self,from:data),!reports.isEmpty,
           reports.allSatisfy({OriginalMatchReport.supportsEngine($0.engineSHA256)}),
           (try? OriginalMatchReport.experiment(reports).validated()) != nil {
            originalReports=reports;originalMatch=reports.last
            let logs=storage.appendingPathComponent("engine-runs")
            if FileManager.default.fileExists(atPath:logs.path) {originalLogFolder=logs}
            if let id=batch?.id {let folder=logs.appendingPathComponent(id.uuidString);if FileManager.default.fileExists(atPath:folder.appendingPathComponent("batch.json").path) {originalLogFolder=folder}}
        }
        loadLeagueStorage()
        refreshTeamPresets()
        if let data=try? Data(contentsOf:storage.appendingPathComponent("editing-league-team.json")),let id=try? JSONDecoder().decode(UUID.self,from:data),leagueSetup.teams.contains(where:{$0.id==id}) {leagueEditingTeam=id;page="战术工作台"}
        searchEngine()
    }
    var editedLeagueTeam:LeagueTeam? {leagueSetup.teams.first{$0.id==leagueEditingTeam}}
    var canUndo: Bool {if let id=editedLeagueTeam?.id{return !(leagueHistory[id] ?? []).isEmpty};return !history.isEmpty}
    var canRedo: Bool {if let id=editedLeagueTeam?.id{return !(leagueFuture[id] ?? []).isEmpty};return !future.isEmpty}
    var editing:Workspace {editedLeagueTeam?.plan ?? (editingSide==0 ? workspace : (workspace.opponent ?? OpponentPlan.example()).workspace)}
    func change(allowLockChanges:Bool=false,_ edit: (inout Workspace) -> Void) {
        if let id=editedLeagueTeam?.id,let i=leagueSetup.teams.firstIndex(where:{$0.id==id}) {
            guard !leagueRunning else{return}
            let before=leagueSetup.teams[i].plan;var value=before;edit(&value);value.opponent=nil
            do {value=try before.protectingLocks(in:value,allowLockChanges:allowLockChanges)} catch {self.error=error.localizedDescription;return}
            guard value != before else{return}
            leagueHistory[id,default:[]].append(before);if leagueHistory[id]!.count>80 {leagueHistory[id]!.removeFirst()};leagueFuture[id]=[]
            leagueSetup.teams[i].plan=value;save();return
        }
        let before=workspace
        var value=editing;edit(&value)
        do {value=try editing.protectingLocks(in:value,allowLockChanges:allowLockChanges)} catch {self.error=error.localizedDescription;return}
        if editingSide==0 {workspace=value}else{workspace.opponent=OpponentPlan(value)}
        guard workspace != before else{return}
        history.append(before);if history.count>80 {history.removeFirst()};future.removeAll();save()
    }
    func undo() {
        if let id=editedLeagueTeam?.id,let i=leagueSetup.teams.firstIndex(where:{$0.id==id}) {
            guard !leagueRunning,let value=leagueHistory[id]?.last else{return}
            do {try leagueSetup.teams[i].plan.checkReplacement(value)}catch{self.error=error.localizedDescription;return}
            leagueHistory[id]?.removeLast();leagueFuture[id,default:[]].append(leagueSetup.teams[i].plan);leagueSetup.teams[i].plan=value;save();return
        }
        if let value=history.last {
            do {try workspace.checkReplacement(value)}catch{self.error=error.localizedDescription;return}
            history.removeLast();future.append(workspace);workspace=value;save()
        }
    }
    func redo() {
        if let id=editedLeagueTeam?.id,let i=leagueSetup.teams.firstIndex(where:{$0.id==id}) {
            guard !leagueRunning,let value=leagueFuture[id]?.last else{return}
            do {try leagueSetup.teams[i].plan.checkReplacement(value)}catch{self.error=error.localizedDescription;return}
            leagueFuture[id]?.removeLast();leagueHistory[id,default:[]].append(leagueSetup.teams[i].plan);leagueSetup.teams[i].plan=value;save();return
        }
        if let value=future.last {
            do {try workspace.checkReplacement(value)}catch{self.error=error.localizedDescription;return}
            future.removeLast();history.append(workspace);workspace=value;save()
        }
    }
    func save() {
        if let team=editedLeagueTeam {
            guard (try? team.plan.validated(includeOpponent:false)) != nil else {message="请补全球队资料，随后会自动保存";return}
            saveLeagueSetup();message="已保存到联赛球队："+team.name;return
        }
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
        Binding(get: { self.editing.tactic[keyPath:key] }, set: { value in self.change { $0.tactic[keyPath:key] = value } })
    }
    func player(_ slot: Slot) -> Player { editing.players.first { $0.id == slot.playerID } ?? editing.players[0] }
    func assign(_ id: UUID, slot: Int) {
        change { w in
            let previous = w.tactic.slots[slot].playerID
            if let other = w.tactic.slots.firstIndex(where: { $0.playerID == id }) { w.tactic.slots[other].playerID = previous }
            w.tactic.slots[slot].playerID = id
        }
    }
    func move(_ slot: Int, phase: Phase, point: Point, width:Double=340, height:Double=466) {
        let target=NativeCatalog.nearest(point,goalkeeper:slot==0)
        change{$0.tactic.setPosition(target.id,slot:slot,phase:phase)}
        message="已调整\(phase.rawValue)站位与适用角色 · ⌘Z 撤销"
    }
    func autoLineup() {
        change {w in
            var used=Set<UUID>()
            for i in w.tactic.slots.indices {
                let position=w.tactic.slots[i].position(.possession).id
                let family=position.hasPrefix("DC") ? "DC":position.hasPrefix("DM") ? "DM":position.hasPrefix("MC") ? "MC":position.hasPrefix("ST") ? "ST":position
                let available=w.players.filter{!used.contains($0.id)}
                let candidate=available.first{$0.positionKeys.contains(position)||$0.positionKeys.contains(family)} ?? available[0]
                w.tactic.slots[i].playerID=candidate.id;used.insert(candidate.id)
            }
        }
        message="已按位置安排首发；同位置按名单顺序选择 · ⌘Z 撤销"
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
        Binding(get:{self.editing.tactic.setup.conditions[keyPath:key]},set:{value in self.editSetup { $0.conditions[keyPath:key]=value }})
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
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys];let value=editedLeagueTeam == nil ? try workspace.validated():try editing.validated(includeOpponent:false);export(try encoder.encode(value),name:editedLeagueTeam == nil ? "战术方案.json":"联赛球队方案.json",type:.json) }
        catch { self.error = error.localizedDescription }
    }
    func importWorkspace() {
        guard let url = choose(types:[.json],message:editedLeagueTeam == nil ? "打开 Mac 版方案 JSON，替换普通对战的双方配置；可用 ⌘Z 撤销。":"将方案中的主队阵容与战术导入当前联赛球队；可用 ⌘Z 撤销。") else { return }
        do {
            let value = try JSONDecoder().decode(Workspace.self,from:read(url)).validated()
            if editedLeagueTeam==nil {editingSide=0};change { $0 = value }; selectedSlot = 9
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
                    setup.gameSetPieces?.priorities=[:]
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
            try archiveExperiment(e);clearOriginalSelection();setExperiment(e); page = "实验对比"
        } catch { self.error = error.localizedDescription }
    }
    func refreshArchives() {
        let folder=storage.appendingPathComponent("experiments")
        experimentArchives=((try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? []).filter{$0.pathExtension=="json"}.sorted{$0.lastPathComponent>$1.lastPathComponent}
        let runs=storage.appendingPathComponent("engine-runs")
        nativeBatchArchives=((try? FileManager.default.contentsOfDirectory(at:runs,includingPropertiesForKeys:[.contentModificationDateKey])) ?? []).filter{FileManager.default.fileExists(atPath:$0.appendingPathComponent("batch.json").path)}.sorted{((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)>((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)}
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
        do {let e=try JSONDecoder().decode(Experiment.self,from:read(url)).validated();clearOriginalSelection();setExperiment(e);if !preview {try JSONEncoder().encode(e).write(to:storage.appendingPathComponent("experiment.json"),options:.atomic)}} catch {self.error=error.localizedDescription}
    }
    func clearOriginalSelection() {
        originalReports=[];originalMatch=nil;batch=nil
        if !preview {try? Data("[]".utf8).write(to:storage.appendingPathComponent("original-matches.json"),options:.atomic);try? Data("null".utf8).write(to:storage.appendingPathComponent("latest-batch.json"),options:.atomic)}
    }
    func loadNativeBatch(_ folder:URL) {
        guard !runningOriginal else{return}
        do {
            var meta=try JSONDecoder().decode(SimulationBatch.self,from:read(folder.appendingPathComponent("batch.json")))
            let files=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.hasPrefix("match-") && $0.pathExtension=="json"}
            let reports=try files.map{try JSONDecoder().decode(OriginalMatchReport.self,from:read($0))}.sorted{$0.seed<$1.seed}
            guard (1...2000).contains(meta.requested),reports.count<=meta.requested,reports.allSatisfy({$0.configuration==meta.configuration}) else {throw LabError("历史批次的配置或场数不一致。")}
            if let prep=meta.preparation {guard try prep.resolved==meta.configuration,prep.receipt.seed==meta.firstSeed,prep.engineSHA256==meta.engineSHA256 else {throw LabError("历史批次的 AI 战术快照不一致。")}}
            _ = try SimulationConcurrency.missing(requested:meta.requested,firstSeed:meta.firstSeed,seeds:reports.map(\.seed))
            if let hash=meta.engineSHA256 {guard reports.allSatisfy({$0.engineSHA256==hash}) else {throw LabError("历史批次混用了引擎版本。")}}
            if meta.status=="运行中" {meta.status=reports.count==meta.requested ? "已完成":"已中断"}
            meta.completed=reports.count
            let e=reports.isEmpty ? nil:try OriginalMatchReport.experiment(reports)
            originalReports=reports;originalMatch=reports.last;batch=meta;originalLogFolder=folder;if let e {setExperiment(e)}else{experiment=nil};resultSection="测试报告";page="实验对比"
            try JSONEncoder().encode(reports).write(to:storage.appendingPathComponent("original-matches.json"),options:.atomic)
            try JSONEncoder().encode(meta).write(to:storage.appendingPathComponent("latest-batch.json"),options:.atomic)
            if let e {try JSONEncoder().encode(e).write(to:storage.appendingPathComponent("experiment.json"),options:.atomic)}
        } catch {self.error=error.localizedDescription}
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
    func runOriginalMatches() {startOriginalBatch(resume:false)}
    func resumeOriginalMatches() {startOriginalBatch(resume:true)}
    private func startOriginalBatch(resume:Bool) {
        guard engine.adapterSupported else {error=engine.compatibilityMessage;return}
        guard editedLeagueTeam==nil else {error="当前正在编辑联赛球队。请返回联赛运行，或切换到普通对战后测试。";return}
        guard !runningOriginal,!leagueRunning,!checkingNative,let path=engine.appPath,engine.filesReady else {return}
        guard let seed=resume ? batch?.firstSeed:UInt32(originalSeed),(1...2000).contains(resume ? (batch?.requested ?? 0):originalCount),(1...256).contains(simulationWorkers) else {error="场数应为 1–2000，并行通道应为 1–256，种子应为有效的 32 位整数。";return}
        guard let helper=Bundle.main.url(forAuxiliaryExecutable:"EngineRuntimeProbe") else {error="安装包缺少原版比赛宿主，请重新构建应用。";return}
        var scenario:NativeScenario?
        do {scenario=resume ? batch?.configuration:(useWorkbench ? try NativeScenario(workspace:workspace):nil)} catch {self.error=error.localizedDescription;return}
        let count=resume ? batch!.requested:originalCount,expectedEngine=engine.binarySHA256
        let existing=resume ? originalReports:[]
        let indices:[Int]
        do {
            indices=try SimulationConcurrency.missing(requested:count,firstSeed:seed,seeds:existing.map(\.seed))
            if resume {guard let meta=batch,meta.engineSHA256.map({$0==expectedEngine}) ?? true,existing.allSatisfy({$0.engineSHA256==expectedEngine && $0.configuration==scenario}),let folder=originalLogFolder,FileManager.default.fileExists(atPath:folder.appendingPathComponent("batch.json").path) else {throw LabError("无法使用当前引擎续跑此批次，请打开对应历史批次或新建实验。")}}
        } catch {self.error=error.localizedDescription;return}
        let folder=resume ? originalLogFolder!:storage.appendingPathComponent("engine-runs").appendingPathComponent(UUID().uuidString)
        if !resume {clearOriginalSelection();experiment=nil;batch=SimulationBatch(requested:count,firstSeed:seed,configuration:scenario);batch?.id=UUID(uuidString:folder.lastPathComponent)!}
        originalLogFolder=folder;runningOriginal=true;originalCancelled=false
        let workers=simulationWorkers,queue=MatchQueue();originalQueue=queue
        batch?.status="运行中";batch?.failure=nil;batch?.finishedAt=nil;batch?.engineSHA256=expectedEngine;batch?.workers=workers
        originalProgress="正在校验原版引擎与测试输入…"
        Task {
            var completed=existing
            do {
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                try JSONEncoder().encode(batch).write(to:folder.appendingPathComponent("batch.json"),options:.atomic)
                if let requested=scenario,requested.teams.contains(where:{$0.generation != nil}) {
                    originalProgress="原版 AI 正在制定本批战术…"
                    let job=TacticGenerationJob();tacticGenerationJob=job
                    let prep=try await Task.detached{try job.run(helper:helper,app:URL(fileURLWithPath:path),scenario:requested,seed:seed,folder:folder.appendingPathComponent("tactics"))}.value
                    guard !originalCancelled else {throw LabError("已停止战术准备。")}
                    scenario=try prep.resolved;batch?.configuration=scenario;batch?.preparation=prep
                }
                try JSONEncoder().encode(batch).write(to:folder.appendingPathComponent("batch.json"),options:.atomic)
            } catch {
                if !originalCancelled {self.error=error.localizedDescription}
                batch?.failure=originalCancelled ? nil:error.localizedDescription;batch?.status=originalCancelled ? "已停止":"未完成";batch?.finishedAt=Date()
                do {try JSONEncoder().encode(batch).write(to:folder.appendingPathComponent("batch.json"),options:.atomic);try JSONEncoder().encode(batch).write(to:storage.appendingPathComponent("latest-batch.json"),options:.atomic)}catch{self.error=error.localizedDescription}
                tacticGenerationJob=nil;originalQueue=nil;runningOriginal=false;originalProgress="战术准备已停止，输入已保留，可继续";refreshArchives();return
            }
            tacticGenerationJob=nil
            do {
                try await queue.run(indices:indices,workers:workers,helper:helper,app:URL(fileURLWithPath:path),request:{i in
                    let current=seed+UInt32(i)
                    self.originalProgress="\(min(workers,indices.count)) 路并行 · 已完成 \(completed.count) / \(count) 场"
                    return MatchRequest(index:i,seed:current,log:folder.appendingPathComponent("seed-\(current).jsonl"),scenario:scenario)
                },accept:{input,report in
                    guard report.engineSHA256==expectedEngine else {throw LabError("游戏引擎在检测后发生变化，请重新检查引擎并新建实验。") }
                    // One immutable result per match is durable before updating the UI.
                    try JSONEncoder().encode(report).write(to:folder.appendingPathComponent("match-\(input.seed).json"),options:.atomic)
                    completed.append(report);completed.sort{$0.seed<$1.seed};self.originalMatch=report;self.originalReports=completed
                    self.batch?.completed=completed.count
                    if completed.count%25==0 || completed.count==count {self.setExperiment(try OriginalMatchReport.experiment(completed))}
                })
            } catch {
                if !originalCancelled {self.error=error.localizedDescription}
                batch?.failure=originalCancelled ? nil:error.localizedDescription
            }
            originalMatch=completed.last;originalQueue=nil;runningOriginal=false
            batch?.status=completed.count==count ? "已完成":originalCancelled ? "已停止":"未完成"
            batch?.finishedAt=Date()
            if let batch {
                do {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try JSONEncoder().encode(batch).write(to:folder.appendingPathComponent("batch.json"),options:.atomic);try JSONEncoder().encode(batch).write(to:storage.appendingPathComponent("latest-batch.json"),options:.atomic)} catch {self.error=error.localizedDescription}
            }
            if !completed.isEmpty {
                do {let e=try OriginalMatchReport.experiment(completed);setExperiment(e);try archiveExperiment(e);try JSONEncoder().encode(completed).write(to:storage.appendingPathComponent("original-matches.json"),options:.atomic);resultSection="测试报告";page="实验对比"} catch {self.error=error.localizedDescription}
            }
            originalProgress="本批次完成 \(completed.count) / \(count) 场"
            refreshArchives()
            message=originalCancelled ? "模拟已停止 · 已完成 \(completed.count) 场已保留" : "原版模拟完成 \(completed.count) / \(count) 场 · 结果与日志已保存"
        }
    }
    func cancelOriginalMatches() {originalCancelled=true;tacticGenerationJob?.cancel();originalQueue?.cancel()}
    func showOriginalResults() {
        do {setExperiment(try OriginalMatchReport.experiment(originalReports));page="实验对比";resultSection="测试报告"} catch {self.error=error.localizedDescription}
    }
    func exportSimulationReport() {
        do {export(Data(try BatchExport.html(matches:originalReports,batch:batch).utf8),name:"战术测试报告.html",type:.html)} catch {self.error=error.localizedDescription}
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
            if engine.binarySHA256 != report.binarySHA256 {nativeCheck=nil}
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
