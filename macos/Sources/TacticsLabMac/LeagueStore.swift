import AppKit
import UniformTypeIdentifiers
import TacticsCore

extension LabStore {
    func loadLeagueStorage() {
        if let data=try? Data(contentsOf:storage.appendingPathComponent("league-setup.json")),let value=try? JSONDecoder().decode(LeagueSetup.self,from:data) {leagueSetup=value}
        refreshLeagueArchives()
        if let data=try? Data(contentsOf:experimentStorage.appendingPathComponent("latest-league.json")),let id=try? JSONDecoder().decode(UUID.self,from:data) {loadLeagueRun(experimentStorage.appendingPathComponent("league-runs").appendingPathComponent(id.uuidString),navigate:false)}
    }
    func saveLeagueSetup() {
        guard !preview else{return}
        do {try FileManager.default.createDirectory(at:storage,withIntermediateDirectories:true);try JSONEncoder().encode(leagueSetup).write(to:storage.appendingPathComponent("league-setup.json"),options:.atomic)}catch{self.error=error.localizedDescription}
    }
    func addLeagueTeam(_ plan:Workspace,savedClubID:Int?=nil,markAsTestTeam:Bool=false) {
        guard leagueSetup.teams.count<40 else {error="联赛最多 40 支球队。";return}
        var own=plan;own.opponent=nil
        let names=Set(leagueSetup.teams.map(\.name));let base=own.tactic.name
        var i=2;while names.contains(own.tactic.name) {own.tactic.name=base+" \(i)";i+=1}
        let team=LeagueTeam(plan:own,savedClubID:savedClubID)
        leagueSetup.teams.append(team)
        if markAsTestTeam || (leagueSetup.testTeamID==nil && savedClubID.map{saveCatalog?.managedClubIDs.contains($0)==true}==true) {leagueSetup.testTeamID=team.id}
        leagueSetup.importedSchedule=nil;saveLeagueSetup()
    }
    func setLeagueTestTeam(_ id:UUID?) {
        guard !leagueRunning,id.map({v in leagueSetup.teams.contains{$0.id==v}}) ?? true else{return}
        leagueSetup.testTeamID=id;saveLeagueSetup()
    }
    func setReportTestTeam(_ id:UUID) {
        guard !leagueRunning,var run=leagueRun,run.setup.teams.contains(where:{$0.id==id}) else{return}
        run.reportTeamID=id
        do {
            let folder=experimentStorage.appendingPathComponent("league-runs").appendingPathComponent(run.id.uuidString)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            try JSONEncoder().encode(run).write(to:folder.appendingPathComponent("run.json"),options:.atomic)
            leagueRun=run
        } catch {self.error="球队标记未能保存："+error.localizedDescription}
    }
    func removeLeagueTeam(_ id:UUID) {
        guard !leagueRunning else{return}
        if leagueEditingTeam==id {leaveLeagueEditor(navigate:false)}
        leagueSetup.teams.removeAll{$0.id==id}
        if leagueSetup.testTeamID==id {leagueSetup.testTeamID=nil}
        leagueSetup.importedSchedule=nil;saveLeagueSetup()
    }
    func addRandomTeams(_ count:Int,tier:AbilityTier) {
        guard leagueSetup.teams.count+count<=40 else {error="联赛最多 40 支球队。";return}
        var rng=SystemRandomNumberGenerator()
        for _ in 0..<count {
            var w=Workspace.example(includeOpponent:false)
            let f=Formation.allCases.randomElement(using:&rng)!
            w.tactic.apply(f,phase:.possession);w.tactic.apply(f,phase:.defending)
            for i in 0..<11 {w.players[i].position=f.positions[i];w.players[i].name=String(format:"球员 %02d",i+1)}
            for _ in 0..<9 {w.addCandidate(using:&rng)}
            w.applyAbility(tier,scope:.team,using:&rng);w.tactic.name="随机球队 \(leagueSetup.teams.count+1)";w.rosterSource="按位置生成 · "+tier.rawValue+" · 隐藏属性和性格独立随机"
            w.management.tacticSource="工具随机阵型"
            addLeagueTeam(w)
        }
    }
    func persistEditingContext() {
        guard !preview else{return}
        do {try FileManager.default.createDirectory(at:storage,withIntermediateDirectories:true);try JSONEncoder().encode(leagueEditingTeam).write(to:storage.appendingPathComponent("editing-league-team.json"),options:.atomic)}catch{self.error=error.localizedDescription}
    }
    func editLeagueTeam(_ id:UUID,page target:String="战术工作台") {
        guard !leagueRunning,let team=leagueSetup.teams.first(where:{$0.id==id}) else{return}
        if let i=leagueSetup.teams.firstIndex(where:{$0.id==id}),leagueSetup.teams[i].displayName==nil {leagueSetup.teams[i].displayName=team.name;saveLeagueSetup()}
        leagueEditingTeam=id;page=target;persistEditingContext()
        message="正在编辑联赛球队："+team.name+" · 修改自动保存"
    }
    func leaveLeagueEditor(navigate:Bool=true) {
        leagueEditingTeam=nil;persistEditingContext()
        if navigate {leagueSection="球队与规则";page="联赛实验"}
        message="普通对战的主队与对手配置已保留"
    }
    func randomizeLeagueTeam(_ id:UUID,tier:AbilityTier) {
        guard !leagueRunning,let i=leagueSetup.teams.firstIndex(where:{$0.id==id}) else{return}
        // Use this team's undo stack; do not select or overwrite another editor.
        let previous=leagueEditingTeam;leagueEditingTeam=id
        applyAbility(tier,scope:.team)
        leagueEditingTeam=previous;saveLeagueSetup()
        message="已重新随机「"+leagueSetup.teams[i].name+"」的能力与性格；阵型、名单和其他球队不变"
    }
    func revealLeagueRun() {
        if let run=leagueRun {NSWorkspace.shared.activateFileViewerSelecting([experimentStorage.appendingPathComponent("league-runs").appendingPathComponent(run.id.uuidString)])}
    }
    func importLeagueSetup() {
        guard let url=choose(types:[.json],message:"选择本工具导出的联赛方案 JSON，包含球队阵容、战术与规则。") else{return}
        do {let setup=try JSONDecoder().decode(LeagueSetup.self,from:read(url)).validated();try archiveLeagueSetup();leagueSetup=setup;leaveLeagueEditor(navigate:false);saveLeagueSetup();showSaveImporter=false;page="联赛实验";leagueSection="球队与规则"}catch{self.error=error.localizedDescription}
    }
    func archiveLeagueSetup()throws {
        guard !preview,!leagueSetup.teams.isEmpty else{return}
        let folder=storage.appendingPathComponent("league-setup-backups");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let stamp=ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-")
        try JSONEncoder().encode(leagueSetup).write(to:folder.appendingPathComponent(stamp+"-"+UUID().uuidString.prefix(8)+".json"),options:.atomic)
    }
    func exportLeagueSetup() {
        do {let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys];export(try e.encode(leagueSetup.validated()),name:"联赛初始化.json",type:.json)}catch{self.error=error.localizedDescription}
    }
    func chooseCareerSave() {
        guard !readingSave else{return}
        guard let url=choose(types:[UTType(filenameExtension:"fm") ?? .data],message:"只读导入 FM27 职业生涯存档。先选球队或联赛，再读取一线队阵容。原始数据库请使用“读取游戏数据库”。") else{return}
        readCareerSave(url)
    }
    func chooseDatabase(automatic:Bool=true) {
        guard !readingSave,!leagueRunning else{return}
        if automatic,let app=engine.appPath {
            let root=URL(fileURLWithPath:app).appendingPathComponent("Contents/PlugIns/game_plugin.bundle/Contents/Resources/shared/data/database/db/2700/2700_fm")
            if FileManager.default.fileExists(atPath:root.appendingPathComponent("server_db.dat").path) {readCareerSave(root);return}
        }
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=true;panel.allowsMultipleSelection=false
        panel.message="选择完整的 2700_fm 数据库目录，或其中的 .dat 文件。组件需保存在同一目录。"
        if panel.runModal() == .OK,let url=panel.url {readCareerSave(url)}
    }
    func readerHelper()->URL? {Bundle.main.url(forResource:"SaveReader",withExtension:nil,subdirectory:"SaveReader")}
    func readCareerSave(_ source:URL) {
        guard !readingSave,let helper=readerHelper() else {error="安装包缺少存档读取组件。";return}
        readingSave=true;saveProgress="正在读取球队与联赛目录…"
        let folder=storage.appendingPathComponent("save-imports").appendingPathComponent(UUID().uuidString),job=SaveReaderJob();saveJob=job
        Task {
            defer{readingSave=false;saveJob=nil}
            do {
                let data=try await Task.detached{try job.run(helper:helper,source:source,folder:folder)}.value
                saveCatalog=try JSONDecoder().decode(SaveCatalog.self,from:data).validated();saveSource=source
                saveProgress="目录已读取；请选择球队或联赛。"
            } catch {self.error=error.localizedDescription;saveProgress="读取未完成"}
        }
    }
    func importSavedClubs(_ ids:[Int],league:SavedLeague?=nil,toWorkbench:Bool=false,ranking:LeagueRankingRule?=nil) {
        guard !readingSave,let source=saveSource,let catalog=saveCatalog,let helper=readerHelper() else{return}
        let destinationTeam=leagueEditingTeam,destinationSide=editingSide
        readingSave=true;saveProgress="正在读取 \(ids.count) 支球队的球员与教练资料…"
        let folder=storage.appendingPathComponent("save-imports").appendingPathComponent(UUID().uuidString),job=SaveReaderJob();saveJob=job
        Task {
            defer{readingSave=false;saveJob=nil}
            do {
                let data=try await Task.detached{try job.run(helper:helper,source:source,folder:folder,clubs:ids,hash:catalog.sourceSHA256)}.value
                let decoded=try JSONDecoder().decode(SavedRosterExport.self,from:data)
                guard decoded.sourceSHA256==catalog.sourceSHA256,Set(decoded.rosters.map(\.clubID))==Set(ids) else {throw LabError("阵容来源与所选存档不一致。")}
                let teams=try decoded.rosters.map{LeagueTeam(plan:try $0.workspace(source:catalog.sourceName+" · "+catalog.gameDate),savedClubID:$0.clubID)}
                if toWorkbench,let first=teams.first {
                    guard destinationTeam==nil || leagueSetup.teams.contains(where:{$0.id==destinationTeam}) else {throw LabError("要替换的联赛球队已移除，请重新选择。")}
                    leagueEditingTeam=destinationTeam;editingSide=destinationSide;persistEditingContext()
                    var replacement=first.plan;replacement.opponent=editing.opponent;try editing.checkReplacement(replacement)
                    change{w in let other=w.opponent;w=first.plan;w.opponent=other};page="球员与阵容";showSaveImporter=false
                } else if let league {
                    var setup=LeagueSetup();if let ranking {setup.rules.ranking=ranking};setup.teams=teams;setup.name=(league.name ?? "存档联赛 #\(league.competitionID)")+" · \(league.season)"
                    setup.source=catalog.sourceName+" · "+catalog.gameDate+" · "+catalog.sourceSHA256
                    let lookup=Dictionary(uniqueKeysWithValues:teams.map{($0.savedClubID!,$0.id)})
                    setup.testTeamID=catalog.managedClubIDs.compactMap{lookup[$0]}.first
                    let dates=Array(Set(league.fixtures.compactMap(\.date))).sorted()
                    setup.importedSchedule=league.fixtures.isEmpty ? nil:league.fixtures.map{LeagueFixture(home:lookup[$0.home]!,away:lookup[$0.away]!,round:($0.date.flatMap{dates.firstIndex(of:$0)} ?? 0)+1,date:$0.date)}
                    _ = try setup.validated();try archiveLeagueSetup();leagueSetup=setup;leaveLeagueEditor(navigate:false);saveLeagueSetup();showSaveImporter=false;page="联赛实验";leagueSection="球队与规则"
                } else {
                    guard leagueSetup.teams.count+teams.count<=40 else {throw LabError("加入后超过 40 队，请先减少参赛球队。")}
                    for team in teams {addLeagueTeam(team.plan,savedClubID:team.savedClubID)}
                }
                saveProgress="已导入 \(teams.count) 支球队；在球队行打开阵容或战术核对，修改会自动保存。"
            } catch {self.error=error.localizedDescription;saveProgress="导入未完成；当前阵容未替换。"}
        }
    }
    func refreshLeagueArchives() {
        let root=experimentStorage.appendingPathComponent("league-runs")
        leagueArchives=((try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.contentModificationDateKey])) ?? []).filter{FileManager.default.fileExists(atPath:$0.appendingPathComponent("run.json").path)}.sorted{((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)>((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)}
    }
    func loadLeagueRun(_ folder:URL,navigate:Bool=true) {
        guard !leagueRunning else{return}
        do {
            let data=try Data(contentsOf:folder.appendingPathComponent("run.json"));guard data.count<=500_000_000 else{throw LabError("联赛报告过大。")}
            var run=try JSONDecoder().decode(LeagueRun.self,from:data).validated()
            // Matches are committed individually before the aggregate checkpoint.
            // Parallel workers may leave holes anywhere in the schedule.
            let missing=try SimulationConcurrency.missing(requested:run.expected,firstSeed:run.firstSeed,seeds:run.results.map{$0.report.seed})
            for i in missing {
                let file=folder.appendingPathComponent("matches").appendingPathComponent(String(format:"%05d",i)).appendingPathComponent("result.json")
                if !FileManager.default.fileExists(atPath:file.path){continue}
                let result=try JSONDecoder().decode(LeagueResult.self,from:Data(contentsOf:file))
                guard result.report.seed==run.firstSeed+UInt32(i) else {throw LabError("逐场文件与比赛编号不一致。")}
                run.results.append(result)
            }
            if run.status=="运行中" {run.status=run.results.count==run.expected ? "已完成":"已中断，可继续"}
            leagueRun=try run.validated()
            leagueSection="积分与统计";if navigate{page="联赛实验"}
        }catch{self.error=error.localizedDescription}
    }
    func runLeague(resume:Bool=false) {
        guard requireExperimentStorage() else{return}
        guard engine.adapterSupported else {error=engine.compatibilityMessage;return}
        guard !engineLocationBusy,engine.filesReady,let path=engine.appPath,let helper=Bundle.main.url(forAuxiliaryExecutable:"EngineRuntimeProbe") else{return}
        guard let seed=UInt32(leagueSeed),(1...256).contains(simulationWorkers) else {error="请输入有效的 32 位随机种子，并行通道应为 1–256。";return}
        let setup=leagueSetup,seasons=leagueSeasons,previous=leagueRun,expectedEngine=engine.binarySHA256!
        let workers=simulationWorkers,queue=MatchQueue();leagueQueue=queue
        error=nil;leagueSection="积分与统计";leagueRunning=true;leagueCancelled=false;leagueProgress="正在校验全部球队与赛程…"
        Task {
            var activeRunStarted=false
            do {
                var run:LeagueRun
                if resume,let previous {run=try await Task.detached{try previous.validated()}.value;run.status="运行中";run.failure=nil}
                else {run=try await Task.detached{try LeagueRun(setup:setup,seasons:seasons,seed:seed)}.value}
                try run.validateEngine(expectedEngine);run.engineSHA256=expectedEngine
                run.workers=workers
                leagueRun=run
                activeRunStarted=true
                let folder=experimentStorage.appendingPathComponent("league-runs").appendingPathComponent(run.id.uuidString)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                try JSONEncoder().encode(run).write(to:folder.appendingPathComponent("run.json"),options:.atomic)
                try JSONEncoder().encode(run.id).write(to:experimentStorage.appendingPathComponent("latest-league.json"),options:.atomic)
                let indices=try SimulationConcurrency.missing(requested:run.expected,firstSeed:run.firstSeed,seeds:run.results.map{$0.report.seed})
                var cursor=0
                while cursor<indices.count,!leagueCancelled,!queue.isStopped {
                    // Deliver the first results quickly, then use the requested concurrency.
                    let width=run.results.isEmpty ? min(workers,8):workers
                    let chunk=Array(indices[cursor..<min(indices.count,cursor+width)])
                    for index in chunk {
                        let fixtureIndex=index % run.schedule.count,fixture=run.schedule[fixtureIndex]
                        if run.preparedTactics?[fixture.id] != nil {continue}
                        let requested=try run.setup.scenario(fixture)
                        if requested.teams.contains(where:{$0.generation != nil}) {
                            guard !leagueCancelled else {throw LabError("已停止战术准备。")}
                            leaguePreparing=true
                            leagueProgress="准备 AI 战术 · 第 \(fixtureIndex+1) 个对阵 · 已完赛 \(run.results.count) / \(run.expected)"
                            let generationSeed=run.firstSeed+UInt32(fixtureIndex),target=folder.appendingPathComponent("tactics").appendingPathComponent(fixture.id.uuidString)
                            let job=TacticGenerationJob();tacticGenerationJob=job
                            let prep=try await Task.detached{try job.run(helper:helper,app:URL(fileURLWithPath:path),scenario:requested,seed:generationSeed,folder:target)}.value
                            if run.preparedTactics==nil {run.preparedTactics=[:]};run.preparedTactics?[fixture.id]=prep
                            try JSONEncoder().encode(run).write(to:folder.appendingPathComponent("run.json"),options:.atomic);leagueRun=run
                        }
                    }
                    tacticGenerationJob=nil;leaguePreparing=false
                    guard !leagueCancelled else{break}
                    leagueProgress="比赛计算中 · \(min(workers,chunk.count)) 路并行 · 已完赛 \(run.results.count) / \(run.expected)"
                    do {
                        try await queue.run(indices:chunk,workers:workers,helper:helper,app:URL(fileURLWithPath:path),request:{index in
                            let fixture=run.schedule[index%run.schedule.count],scenario=try run.scenario(fixture)
                            let log=folder.appendingPathComponent("matches").appendingPathComponent(String(format:"%05d",index)).appendingPathComponent("match.jsonl")
                            return MatchRequest(index:index,seed:run.firstSeed+UInt32(index),log:log,scenario:scenario)
                        },accept:{input,report in
                            guard report.engineSHA256==expectedEngine else {throw LabError("游戏引擎在实验期间发生变化，已保留完成结果，请新建实验。") }
                            let season=input.index/run.schedule.count+1,fixture=run.schedule[input.index%run.schedule.count]
                            let result=LeagueResult(season:season,fixture:fixture,report:report)
                            try JSONEncoder().encode(result).write(to:input.log.deletingLastPathComponent().appendingPathComponent("result.json"),options:.atomic)
                            run.results.append(result);run.results.sort{$0.report.seed<$1.report.seed};self.leagueRun=run
                            self.leagueProgress="比赛计算中 · 已完赛 \(run.results.count) / \(run.expected)"
                            if run.results.count%10==0 {try JSONEncoder().encode(run).write(to:folder.appendingPathComponent("run.json"),options:.atomic)}
                        })
                    } catch {if !leagueCancelled{run.failure=error.localizedDescription};break}
                    cursor+=chunk.count
                    try JSONEncoder().encode(run).write(to:folder.appendingPathComponent("run.json"),options:.atomic)
                }
                run.status=run.results.count==run.expected ? "已完成":leagueCancelled ? "已停止":"未完成"
                leagueRun=run;try JSONEncoder().encode(run).write(to:folder.appendingPathComponent("run.json"),options:.atomic)
                leagueProgress="\(run.status) · \(run.results.count) / \(run.expected) 场";refreshLeagueArchives()
                if let failure=run.failure {error=failure}
            } catch {
                if !leagueCancelled {self.error=error.localizedDescription}
                if activeRunStarted,var run=leagueRun {
                    run.status=leagueCancelled ? "已停止":"未完成";run.failure=leagueCancelled ? nil:error.localizedDescription
                    let file=experimentStorage.appendingPathComponent("league-runs").appendingPathComponent(run.id.uuidString).appendingPathComponent("run.json")
                    do {try JSONEncoder().encode(run).write(to:file,options:.atomic);leagueRun=run}catch{self.error=error.localizedDescription}
                    leagueProgress="\(run.status) · 已保留战术准备与比赛结果";refreshLeagueArchives()
                }
            }
            tacticGenerationJob=nil;leagueQueue=nil;leaguePreparing=false;leagueRunning=false
        }
    }
    func stopLeague(){leagueCancelled=true;tacticGenerationJob?.cancel();leagueQueue?.cancel()}
    func exportLeagueReport() {
        guard let leagueRun else{return}
        export(Data(LeagueExport.html(leagueRun).utf8),name:"联赛实验报告.html",type:.html)
    }
    func exportLeagueResults() {
        guard let leagueRun else{return}
        do{export(try JSONEncoder().encode(leagueRun),name:"联赛实验完整数据.json",type:.json)}catch{self.error=error.localizedDescription}
    }
}
