import SwiftUI
import TacticsCore

struct TeamPresetView: View {
    @EnvironmentObject var store: LabStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var query = ""
    @State private var selected: UUID?
    @State private var failure: String?
    private var selection: TeamPreset? { store.teamPresets.first { $0.id == selected } }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { failure = error.localizedDescription } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("阵容方案库").font(.title2.bold()); Spacer()
                Button("导入方案 JSON…") {
                    guard let url = store.choose(types: [.json], message: "导入本工具导出的阵容方案 JSON；先加入方案库，不替换当前球队。") else { return }
                    perform { selected = try store.importTeamPreset(store.read(url)).id }
                }
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("当前球队：" + store.editingTeamLabel).font(.headline)
            Text("保存球员与候补、属性和性格、双阶段战术、定位球及比赛状态。载入或加入联赛都是复制，后续编辑各自保存。").font(.callout).foregroundStyle(Theme.muted)
            HStack {
                TextField("方案名称，例如：主力阵容 / 杯赛轮换", text: $name)
                Button("保存当前球队为新方案") { perform { selected = try store.saveTeamPreset(name: name).id } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Divider()
            TextField("搜索已保存的方案", text: $query)
            List(selection: $selected) {
                ForEach(store.teamPresets.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { preset in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(preset.name).font(.headline)
                        Text("\(preset.plan.players.count) 人 · \(preset.plan.tactic.formation) / \(preset.plan.tactic.defensiveFormation) · 战术：\(preset.plan.tactic.name)").font(.caption)
                        Text(preset.savedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.muted)
                    }.padding(.vertical, 5).tag(preset.id)
                }
            }.overlay { if store.teamPresets.isEmpty { Text("还没有保存的阵容方案").foregroundStyle(Theme.muted) } }
            HStack {
                Button("载入当前球队") { if let preset = selection { perform { try store.loadTeamPreset(preset); dismiss() } } }.buttonStyle(.borderedProminent).disabled(selection == nil || !store.canLoadTeamPreset)
                Button("复制为新联赛球队") { if let preset = selection { perform { try store.addTeamPresetToLeague(preset) } } }.disabled(selection == nil || store.leagueRunning || store.readingSave || store.leagueSetup.teams.count >= 40)
                Button("导出方案 JSON…") { if let preset = selection { perform { try store.export(preset.data, name: "阵容方案.json", type: .json) } } }.disabled(selection == nil)
                Menu("管理") {
                    Button("用上方名称重命名") { if let preset = selection { perform { try store.renameTeamPreset(preset, name: name) } } }.disabled(selection == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("归档所选方案") { if let preset = selection { perform { try store.archiveTeamPreset(preset); selected = nil } } }.disabled(selection == nil)
                    Button("打开方案库文件夹", action: store.revealTeamPresets)
                }
            }
            Text("载入会替换上方当前球队的阵容与战术，可用 ⌘Z 撤销；已完成和正在运行的实验仍使用开赛时的配置。指定球员盯人需按当前对手重新检查。").font(.caption).foregroundStyle(Theme.muted)
            DisclosureGroup("游戏内使用：在工作台导入／导出 FMF 战术") {
                Text("在工作台的“战术文件”中导入或导出游戏战术 FMF。导出由本机 FM27 写入并回读核验，包含双阶段阵型、角色、心态与指令；球员属性和定位球请保存在这里的完整阵容方案中。").font(.caption).foregroundStyle(Theme.muted)
            }
            if let warning = store.presetLibraryWarning { Text(warning).font(.caption).foregroundStyle(Theme.amber) }
            Text(store.message).font(.caption).foregroundStyle(Theme.muted)
        }.padding(24).frame(width: 850, height: 650).background(Theme.paper)
        .onAppear { name = store.editedLeagueTeam?.name ?? store.editing.tactic.name; store.refreshTeamPresets() }
        .alert("操作未完成", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) { Button("知道了") { failure = nil } } message: { Text(failure ?? "") }
    }
}
