import SwiftUI
import TacticsCore

/// Both editor pages resolve this selection through LabStore.editing/change.
struct EditingTeamBar:View {
    @EnvironmentObject var store:LabStore
    @State private var showManagement=false
    private var league:Bool {store.editedLeagueTeam != nil}
    var body:some View {
        HStack(spacing:14) {
            Picker("编辑范围",selection:Binding(get:{league},set:{v in
                if v,let id=store.leagueSetup.teams.first?.id {store.editLeagueTeam(id,page:store.page)}
                else {store.leaveLeagueEditor(navigate:false)}
            })) {Text("普通对战").tag(false);Text("联赛球队").tag(true).disabled(store.leagueSetup.teams.isEmpty)}.pickerStyle(.segmented).labelsHidden().frame(width:180)
            if league {
                Picker("球队",selection:Binding(get:{store.leagueEditingTeam},set:{if let id=$0 {store.editLeagueTeam(id,page:store.page)}})) {
                    Text("请选择球队").tag(nil as UUID?)
                    ForEach(store.leagueSetup.teams){Text($0.name).tag(Optional($0.id))}
                }.frame(width:280)
                Text("战术、球员和定位球共用这支球队，修改自动保存。").font(.system(size:11)).foregroundStyle(Theme.muted)
                Spacer()
                Button("返回联赛"){store.leaveLeagueEditor()}
            } else {
                Picker("球队",selection:$store.editingSide) {Text("主队 · "+store.workspace.tactic.name).tag(0);Text("对手 · "+(store.workspace.opponent?.tactic.name ?? "对手")).tag(1)}.frame(width:320)
                Text("修改当前对战球队；复制到联赛后，两份配置各自保存。").font(.system(size:11)).foregroundStyle(Theme.muted)
                Spacer()
            }
            Button(store.editing.management.tacticLocked ? "战术已锁定":"教练与锁定"){showManagement=true}
        }.padding(.horizontal,24).padding(.vertical,12).background(league ? Theme.green.opacity(0.08):Color.white).disabled((store.leagueRunning && league) || store.readingSave || store.processingTactic)
        .sheet(isPresented:$showManagement){TeamManagementView().environmentObject(store)}
    }
}
