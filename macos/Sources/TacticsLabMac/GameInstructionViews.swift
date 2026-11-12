import SwiftUI
import TacticsCore

struct PhaseSelector:View {
    @EnvironmentObject var store:LabStore
    var body:some View {Picker("比赛阶段",selection:$store.phase){ForEach(Phase.allCases){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented)}
}
struct GameInstructionPane:View {
    @EnvironmentObject var store:LabStore
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            PhaseSelector()
            Picker("指令类型",selection:$store.instructionTab){Text("球队指令").tag("球队指令");Text("角色与球员指令").tag("角色与球员指令")}.pickerStyle(.segmented)
            if store.instructionTab=="球队指令" {NativeTeamInstructions()}else{NativePlayerInstructions()}
        }
    }
}
struct NativeTeamInstructions:View {
    @EnvironmentObject var store:LabStore
    var body:some View {
        Card {
            Text(store.editing.tactic.name).font(.system(size:19,weight:.semibold))
            if store.editing.tactic.setup.hasLegacyInstructions {
                DisclosureGroup("旧版指令需要核对后重新设置") {
                    ForEach(store.editing.tactic.setup.legacyInstructionLines,id:\.self){Text($0).font(.caption)}
                    Button("清除旧指令草稿，采用当前原版指令"){store.editSetup{$0.team=[:];$0.players=[:]}}
                    Text("可用 ⌘Z 撤销。原始方案文件不改动。").font(.caption).foregroundStyle(Theme.muted)
                }.foregroundStyle(Theme.amber)
            }
            Picker("比赛心态",selection:Binding(get:{store.editing.tactic.gameMentality},set:{v in store.editSetup{$0.nativeMentality=v}})) {
                ForEach(1...7,id:\.self){Text(NativeCatalog.mentalities[$0-1]).tag($0)}
            }
            Text("\(store.phase.rawValue) · \(NativeCatalog.teamInstructions.filter{$0.phase==store.phase}.count) 组指令").font(.system(size:11)).foregroundStyle(Theme.muted)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:10)],spacing:10) {
                ForEach(NativeCatalog.teamInstructions.filter{$0.phase==store.phase}) {g in
                    InstructionTile(group:g,selected:Binding(get:{store.editing.tactic.teamOption(g).id},set:{v in store.editSetup{if $0.nativeTeam==nil {$0.nativeTeam=[:]};$0.nativeTeam?[g.id]=v}}),policy:nil)
                }
            }
        }
    }

}
struct NativePlayerInstructions:View {
    @EnvironmentObject var store:LabStore
    private var slot:Slot {store.editing.tactic.slots[store.selectedSlot]}
    private var role:NativeRole {store.editing.tactic.role(store.selectedSlot,store.phase)}
    var body:some View {
        Card {
            HStack {Text(store.player(slot).name).font(.system(size:19,weight:.semibold));Spacer();Button("属性 ↗"){store.page="球员与阵容"}}
            Text("\(store.phase.rawValue) · \(slot.position(store.phase).label)").font(.system(size:11)).foregroundStyle(Theme.muted)
            Picker("首发球员",selection:Binding(get:{slot.playerID},set:{store.assign($0,slot:store.selectedSlot)})) {ForEach(store.editing.players){Text($0.name).tag($0.id)}}
            Picker("位置",selection:Binding(get:{slot.position(store.phase).id},set:{v in store.change{$0.tactic.setPosition(v,slot:store.selectedSlot,phase:store.phase)}})) {
                ForEach(NativeCatalog.positions.filter{($0.id=="GK")==((slot.id)==0)}){Text($0.label+" · "+$0.id).tag($0.id)}
            }
            Picker("角色",selection:Binding(get:{role.id},set:{v in store.change{$0.tactic.setRole(v,slot:store.selectedSlot,phase:store.phase)};store.message="角色已更新；不适用的个人覆盖指令已还原，可 ⌘Z 撤销"})) {
                ForEach(NativeCatalog.allowedRoles(positions:store.editing.tactic.slots.map{$0.position(store.phase).id},position:slot.position(store.phase).id,phase:store.phase)){Text($0.label).tag($0.id)}
            }
            Divider()
            HStack {Text("球员指令").font(.system(size:14,weight:.semibold));Spacer();Text("按位置与角色锁定").font(.system(size:10)).foregroundStyle(Theme.muted)}
            LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:10)],spacing:10) {
                ForEach(NativeCatalog.playerInstructions.filter{$0.phase==store.phase}) {g in
                    let key=TacticalConfiguration.playerKey(slot.id,store.phase)
                    InstructionTile(group:g,selected:Binding(get:{store.editing.tactic.setup.nativePlayers?[key]?[g.id] ?? 0},set:{v in store.editSetup{var p=$0.nativePlayers ?? [:];p[key,default:[:]][g.id]=v;$0.nativePlayers=p}}),policy:{store.editedLeagueTeam != nil && $0==34 ? 2:NativeCatalog.policy(position:slot.position(store.phase).id,role:role,option:$0)})
                }
            }
            marking
        }
    }
    @ViewBuilder private var marking:some View {
        let key=TacticalConfiguration.playerKey(slot.id,store.phase)
        let value=store.editing.tactic.setup.nativePlayers?[key]?[14] ?? 0
        if value==34 && store.editedLeagueTeam != nil {
            Text("联赛每轮对手不同，不能固定盯防普通对战中的某个人。请改用按位置盯防或取消指定目标。").font(.caption).foregroundStyle(Theme.amber)
            Button("取消指定球员"){store.editSetup{var p=$0.nativePlayers ?? [:];p[key,default:[:]][14]=0;$0.nativePlayers=p;$0.markTargets?[key]=nil}}
        } else if value==34 {
            let other=store.editingSide==0 ? store.workspace.opponent!.workspace:store.workspace
            Picker("指定盯防球员",selection:Binding(get:{store.editing.tactic.setup.markTargets?[key]?.playerID},set:{v in store.editSetup{var targets=$0.markTargets ?? [:];targets[key,default:MarkTarget()].playerID=v;$0.markTargets=targets}})) {
                Text("请选择对方球员").tag(nil as UUID?)
                ForEach(NativeTeamInput.matchPlayers(other.players,tactic:other.tactic)){Text($0.name).tag(Optional($0.id))}
            }
        } else if value==35 {
            Picker("指定盯防位置",selection:Binding(get:{store.editing.tactic.setup.markTargets?[key]?.position},set:{v in store.editSetup{var targets=$0.markTargets ?? [:];targets[key,default:MarkTarget()].position=v;$0.markTargets=targets}})) {
                Text("请选择对方位置").tag(nil as String?)
                ForEach(NativeCatalog.positions){Text($0.label+" · "+$0.id).tag(Optional($0.id))}
            }
        }
    }
}
struct InstructionTile:View {
    let group:NativeInstruction
    @Binding var selected:UInt32
    let policy:((UInt32)->Int)?
    private var fixed:NativeOption? {group.options.first{$0.id>0 && policy?($0.id)==3}}
    private var editable:Bool {policy==nil || group.options.contains{$0.id>0 && policy?($0.id)==0}}
    private var symbol:String {group.label.contains("射门") ? "arrow.up.forward.square" : group.label.contains("宽度") ? "arrow.left.and.right" : group.phase == .defending ? "shield.lefthalf.filled" : "arrow.triangle.branch"}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text(group.label).font(.system(size:12,weight:.medium));Spacer();if !editable || fixed != nil {Image(systemName:"lock.fill").foregroundStyle(Theme.amber).font(.system(size:10))}}
            Image(systemName:symbol).font(.system(size:30,weight:.ultraLight)).foregroundStyle(Theme.muted.opacity(0.65)).frame(maxWidth:.infinity,minHeight:48)
            Picker(group.label,selection:Binding(get:{fixed?.id ?? selected},set:{selected=$0})) {
                ForEach(group.options) {o in Text(o.label).tag(o.id).disabled(o.id>0 && policy != nil && policy?(o.id) != 0 && fixed?.id != o.id)}
            }.labelsHidden().disabled(!editable || fixed != nil)
            if fixed != nil {Text("角色固定").font(.system(size:9)).foregroundStyle(Theme.muted)}
            else if !editable {Text("该角色不使用此指令").font(.system(size:9)).foregroundStyle(Theme.muted)}
        }.padding(12).frame(maxWidth:.infinity,minHeight:135,alignment:.topLeading).background(Theme.ink.opacity(0.025),in:RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(Theme.ink.opacity(0.1))).opacity(!editable ? 0.65:1)
    }
}
struct SimulationBar:View {
    @EnvironmentObject var store:LabStore
    var body:some View {
        HStack(spacing:12) {
            VStack(alignment:.leading,spacing:3) {Text(store.runningOriginal ? store.originalProgress:"FM 原版比赛测试").font(.system(size:11,weight:.semibold));Text("保存双方配置 · 开赛前回读校验").font(.system(size:10)).foregroundStyle(Theme.muted)}
            Spacer()
            Text("起始种子").font(.system(size:11)).foregroundStyle(Theme.muted)
            TextField("1",text:$store.originalSeed).frame(width:78).disabled(store.runningOriginal)
            Text("场数").font(.system(size:11)).foregroundStyle(Theme.muted)
            TextField("100",value:$store.originalCount,format:.number.grouping(.never)).frame(width:70).disabled(store.runningOriginal).help("可自定义 1–2000 场；场数越多，越能观察随机波动。")
            ConcurrencyControl()
            if store.runningOriginal {Button("停止"){store.cancelOriginalMatches()}}
            else {Button("运行比赛"){store.useWorkbench=true;store.runOriginalMatches()}.buttonStyle(.borderedProminent).disabled(!store.engine.adapterSupported || store.leagueRunning)}
        }.textFieldStyle(.roundedBorder).padding(.horizontal,22).padding(.vertical,13).background(.white).overlay(alignment:.top){Divider()}
    }
}
