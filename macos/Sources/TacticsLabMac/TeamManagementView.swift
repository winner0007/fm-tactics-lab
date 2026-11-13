import SwiftUI
import TacticsCore

struct TeamManagementView:View {
    @EnvironmentObject var store:LabStore
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var style = -1
    private var management:TeamManagement {store.editing.management}
    private var coaches:[CoachProfile] {
        var seen=Set<String>()
        return ([store.workspace.management.coach,store.workspace.opponent?.workspace.management.coach]+store.leagueSetup.teams.map{$0.plan.management.coach}).compactMap{$0}.filter{seen.insert($0.id).inserted}.sorted{$0.name<$1.name}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {Text("教练与锁定").font(.title2.bold());Spacer();Button("完成"){dismiss()}.keyboardShortcut(.defaultAction)}
            Text(store.editingTeamLabel).font(.headline)
            Text("主教练："+(management.coach?.name ?? "未指定／未读取")).font(.headline)
            if let coach=management.coach {Text(coach.source+" · "+coach.styleName).font(.caption).foregroundStyle(Theme.muted)}
            Toggle("锁定主教练",isOn:Binding(get:{management.coachLocked},set:{v in store.change(allowLockChanges:true){$0.management.coachLocked=v}})).disabled(management.coach==nil && !management.coachLocked)
            HStack {
                Menu("选择已有教练") {ForEach(coaches){c in Button(c.name+" · "+c.styleName){store.change{$0.management.coach=c}}}}.disabled(coaches.isEmpty)
                TextField("指定教练姓名",text:$name)
                Picker("偏好",selection:$style) {Text("偏好未确认").tag(-1);ForEach(CoachProfile.styles.indices,id:\.self){Text(CoachProfile.styles[$0]).tag($0)}}.frame(width:175)
                Button("指定"){let c=CoachProfile(name:String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80)),styleID:style<0 ? nil:style);store.change{$0.management.coach=c};name=""}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }.disabled(management.coachLocked)
            TacticSelectionControl(management:Binding(get:{management},set:{v in store.change{$0.management=v}}))
            Divider()
            Toggle("锁定战术",isOn:Binding(get:{management.tacticLocked},set:{v in store.change(allowLockChanges:true){$0.management.tacticLocked=v}}))
            Text("锁定后保留阵型、角色、球队与个人指令、定位球套路；仍可换首发、主罚人、球员能力和开赛状态。修改或导入其他战术前需先解锁。").font(.callout).foregroundStyle(Theme.muted)
            Text(management.selectionDescription(inherited:store.editedLeagueTeam.map{$0.id==store.leagueSetup.testTeamID ? .fixed:store.leagueSetup.defaultTactics ?? .fixed} ?? .fixed)).font(.callout)
            DisclosureGroup("工作台方案来源") {Text(management.workbenchSource).font(.caption).foregroundStyle(Theme.muted)}
            Text("原版 AI 使用导入的教练参数制定赛前战术；缺少或无法唯一确认时，使用原版测试教练参数并标明来源。手填姓名和风格标签不等于导入教练能力。实验不运行董事会换帅；指定战术的临场切换按你的规则执行。").font(.caption).foregroundStyle(Theme.muted)
        }.padding(24).frame(width:770).disabled(store.leagueRunning && store.editedLeagueTeam != nil)
    }
}
