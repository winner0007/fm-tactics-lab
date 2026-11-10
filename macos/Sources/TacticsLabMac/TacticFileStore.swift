import AppKit
import UniformTypeIdentifiers
import TacticsCore

extension LabStore {
    var tacticFileWorkspace:Workspace {
        var value=editing
        if editedLeagueTeam != nil {value.opponent=OpponentPlan.example()}
        else if editingSide==1 {value.opponent=OpponentPlan(workspace)}
        return value
    }
    private func tacticFileTools()throws->(URL,URL) {
        guard !processingTactic,!readingSave,!leagueRunning,!runningOriginal,
              engine.filesReady,let app=engine.appPath,
              let helper=Bundle.main.url(forAuxiliaryExecutable:"EngineRuntimeProbe") else {throw LabError("请先完成引擎接入，并等待当前导入或模拟结束。")}
        return (helper,URL(fileURLWithPath:app))
    }
    func importGameTactic() {
        do {
            let (helper,app)=try tacticFileTools()
            guard let source=choose(types:[UTType(filenameExtension:"fmf") ?? .data],message:"导入 FM27 战术到「\(editingTeamLabel)」。保留球员、属性、定位球与比赛状态；战术可撤销。") else{return}
            let before=tacticFileWorkspace,team=leagueEditingTeam,side=editingSide,ordinary=workspace
            let folder=storage.appendingPathComponent("tactic-files").appendingPathComponent(UUID().uuidString),job=TacticFileJob()
            processingTactic=true;message="正在用 Mac 原版引擎读取 FMF 战术…"
            Task {
                defer{processingTactic=false}
                do {
                    let receipt=try await Task.detached{try job.read(helper:helper,app:app,source:source,folder:folder)}.value
                    let value=try receipt.fields.applying(to:before,name:receipt.name ?? source.deletingPathExtension().lastPathComponent,opponent:(before.opponent ?? OpponentPlan.example()).workspace)
                    guard leagueEditingTeam==team,editingSide==side,editing.tactic==before.tactic,editing.players==before.players,team != nil || workspace==ordinary else {throw LabError("读取期间当前球队或对手已改变，请重新导入。")}
                    if team != nil,value.tactic.setup.nativePlayers?.values.contains(where:{$0.values.contains(34)})==true {throw LabError("这套战术指定了某名对手球员。请先导入普通对战，改为按位置盯防，再用于联赛。")}
                    change{$0.tactic=value.tactic};page="战术工作台";workbenchStep="阵型与首发"
                    message="已导入 FMF：\(value.tactic.name) · 球员与定位球已保留 · ⌘Z 撤销"
                } catch {self.error=error.localizedDescription}
            }
        } catch {self.error=error.localizedDescription}
    }
    func exportGameTactic() {
        do {
            let (helper,app)=try tacticFileTools(),scenario=try NativeScenario(workspace:tacticFileWorkspace)
            let title=String(editing.tactic.name.filter{!"/\\:*?\"<>|".contains($0) && !$0.isNewline}.prefix(80))
            guard !title.trimmingCharacters(in:.whitespaces).isEmpty else {throw LabError("请先填写战术名称。")}
            let panel=NSSavePanel();panel.allowedContentTypes=[UTType(filenameExtension:"fmf") ?? .data];panel.nameFieldStringValue=title+".fmf"
            panel.message="导出游戏可读取的双阶段阵型、角色、心态与指令。球员属性和定位球另存阵容方案；不会写入此战术文件。"
            if let folder=gameTacticsFolder() {panel.directoryURL=folder}
            guard panel.runModal() == .OK,let target=panel.url else{return}
            let folder=storage.appendingPathComponent("tactic-files").appendingPathComponent(UUID().uuidString),job=TacticFileJob()
            processingTactic=true;message="正在生成 FMF，并通过 Mac 原版引擎回读核验…"
            Task {
                defer{processingTactic=false}
                do {
                    let data=try await Task.detached{try job.write(helper:helper,app:app,scenario:scenario,title:title,folder:folder)}.value
                    try data.write(to:target,options:.atomic)
                    message="已导出并通过原版回读：\(target.lastPathComponent) · 在游戏战术页面选择载入战术"
                } catch {self.error=error.localizedDescription}
            }
        } catch {self.error=error.localizedDescription}
    }
    func gameTacticsFolder()->URL? {
        let root=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Sports Interactive/Football Manager 27")
        let tactics=root.appendingPathComponent("tactics")
        return FileManager.default.fileExists(atPath:tactics.path) ? tactics : (FileManager.default.fileExists(atPath:root.path) ? root:nil)
    }
}
