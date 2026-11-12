import AppKit
import TacticsCore

extension LabStore {
    var editingTeamLabel: String {
        editedLeagueTeam.map { "联赛球队 · " + $0.name } ?? ((editingSide == 0 ? "普通对战主队 · " : "普通对战对手 · ") + editing.tactic.name)
    }
    var canLoadTeamPreset: Bool { !processingTactic && !readingSave && !(leagueRunning && editedLeagueTeam != nil) }
    var teamPresetFolder: URL { storage.appendingPathComponent("team-presets") }

    func refreshTeamPresets() {
        guard FileManager.default.fileExists(atPath: teamPresetFolder.path) else { teamPresets = []; return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: teamPresetFolder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            var entries: [TeamPreset] = [], invalid: [String] = []
            for file in files {
                do {
                    let value = try TeamPreset.decode(read(file))
                    guard file.lastPathComponent == value.id.uuidString + ".json" else { throw LabError("方案标识与文件名不符。") }
                    entries.append(value)
                } catch { invalid.append(file.lastPathComponent) }
            }
            teamPresets = entries.sorted { $0.savedAt > $1.savedAt }
            presetLibraryWarning = invalid.isEmpty ? nil : "\(invalid.count) 个方案未能读取，原文件已保留：" + invalid.joined(separator: "、")
        } catch { presetLibraryWarning = "方案库读取失败：" + error.localizedDescription }
    }

    @discardableResult func saveTeamPreset(name: String) throws -> TeamPreset {
        let value = try TeamPreset(name: name, plan: editing)
        try writeTeamPreset(value)
        message = "已保存阵容方案：" + value.name
        return value
    }
    func writeTeamPreset(_ value: TeamPreset) throws {
        let data = try value.data
        try FileManager.default.createDirectory(at: teamPresetFolder, withIntermediateDirectories: true)
        try data.write(to: teamPresetFolder.appendingPathComponent(value.id.uuidString + ".json"), options: .atomic)
        refreshTeamPresets()
    }
    @discardableResult func importTeamPreset(_ data: Data) throws -> TeamPreset {
        var value = try TeamPreset.decode(data)
        // Import always adds a copy, even when the same file was imported before.
        value.id = UUID()
        try writeTeamPreset(value)
        message = "已导入方案库：" + value.name
        return value
    }
    func loadTeamPreset(_ preset: TeamPreset) throws {
        guard canLoadTeamPreset else { throw LabError("请等球队导入或联赛运行结束后，再载入阵容方案。") }
        let value = try preset.validated()
        let destination = editingTeamLabel
        try editing.checkReplacement(value.plan)
        change { w in let opponent = w.opponent; w = value.plan; w.opponent = opponent }
        selectedSlot = 0
        message = "已将「\(value.name)」载入\(destination) · ⌘Z 撤销"
    }
    func addTeamPresetToLeague(_ preset: TeamPreset) throws {
        guard !leagueRunning, !readingSave else { throw LabError("请等导入或联赛运行结束后，再添加球队。") }
        guard leagueSetup.teams.count < 40 else { throw LabError("联赛最多 40 支球队。") }
        let value = try preset.validated()
        addLeagueTeam(value.plan)
        let names = Set(leagueSetup.teams.dropLast().map(\.name))
        var name = value.name, suffix = 2
        while names.contains(name) { name = String(value.name.prefix(70)) + " \(suffix)"; suffix += 1 }
        let i = leagueSetup.teams.count - 1
        leagueSetup.teams[i].displayName = name
        leagueSetup.teams[i].plan.tactic.name = value.plan.tactic.name
        saveLeagueSetup()
        message = "已复制为联赛球队：" + name
    }
    func renameTeamPreset(_ preset: TeamPreset, name: String) throws {
        var value = preset; value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try writeTeamPreset(value)
    }
    func archiveTeamPreset(_ preset: TeamPreset) throws {
        let folder = teamPresetFolder.appendingPathComponent("archived")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: teamPresetFolder.appendingPathComponent(preset.id.uuidString + ".json"), to: folder.appendingPathComponent(preset.id.uuidString + "-" + UUID().uuidString.prefix(8) + ".json"))
        refreshTeamPresets(); message = "已归档方案；原文件保留在方案库的 archived 文件夹，可重新导入。"
    }
    func revealTeamPresets() {
        do { try FileManager.default.createDirectory(at: teamPresetFolder, withIntermediateDirectories: true); NSWorkspace.shared.activateFileViewerSelecting([teamPresetFolder]) }
        catch { self.error = error.localizedDescription }
    }
}
