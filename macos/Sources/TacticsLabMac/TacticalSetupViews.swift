import SwiftUI
import TacticsCore

struct TeamInstructionsView:View {
    @EnvironmentObject var store:LabStore
    var body:some View {ScrollView {VStack(alignment:.leading,spacing:18) {PhaseSelector();NativeTeamInstructions()}.padding(22)}}
}
struct PlayerInstructionsView:View {
    @EnvironmentObject var store:LabStore
    var body:some View {ScrollView {HStack(alignment:.top,spacing:24) {PitchPanel(phase:store.phase).frame(width:310);VStack {PhaseSelector();NativePlayerInstructions()}}.padding(22)}}
}

struct SetPieceMap:View {
    @EnvironmentObject var store:LabStore
    let kind:SetPieceKind; let side:SetPieceSide; let routine:SetPieceRoutine
    var body:some View {
        VStack(spacing:0) {
            GeometryReader { geometry in
                ZStack {
                    PitchLines()
                    ForEach(store.editing.tactic.slots) { slot in
                        let p=point(slot)
                        VStack(spacing:2) { Text("\(slot.id+1)").font(.system(size:11,weight:.bold)).frame(width:24,height:24).background(.white,in:Circle()).foregroundStyle(Theme.green); Text(slot.id==0 ? "门将" : (routine.effectiveTaker(slots:store.editing.tactic.slots)==slot.playerID && !kind.defending ? "主罚" : routine.effectiveTasks(slots:store.editing.tactic.slots,kind:kind)[slot.id] ?? "待安排")).font(.system(size:8)).foregroundStyle(.white) }.position(x:p.x*geometry.size.width,y:p.y*geometry.size.height)
                    }
                }
            }
            Text("职责示意 · 不代表引擎实际站位").font(.system(size:10)).foregroundStyle(Theme.muted).padding(10).frame(maxWidth:.infinity).background(.white)
        }.clipShape(RoundedRectangle(cornerRadius:14))
    }
    private func point(_ slot:Slot) -> Point {
        if slot.id==0 {return Point(0.5,kind.defending ? 0.12 : 0.9)}
        if !kind.defending && slot.playerID==routine.effectiveTaker(slots:store.editing.tactic.slots) {return Point(side == .left ? 0.08 : 0.92,0.08)}
        let task=routine.effectiveTasks(slots:store.editing.tactic.slots,kind:kind)[slot.id] ?? "待安排"
        let base:Point
        if task.contains("近点") {base=Point(0.28,0.23)}
        else if task.contains("远点") {base=Point(0.72,0.23)}
        else if task.contains("中路") || task=="盯人" {base=Point(0.5,0.3)}
        else if task.contains("禁区外") {base=Point(0.5,0.47)}
        else if task.contains("短传") {base=Point(0.18,0.35)}
        else if task.contains("留前") {base=Point(0.5,0.78)}
        else {base=Point(0.5,kind.defending ? 0.28 : 0.7)}
        let peers=store.editing.tactic.slots.filter{$0.id != 0 && (routine.tasks[$0.id] ?? kind.tasks[0])==task}
        let index=peers.firstIndex(where:{$0.id==slot.id}) ?? 0
        let offset=(Double(index)-Double(peers.count-1)/2)*0.12
        return Point(min(0.9,max(0.1,base.x+offset)),base.y)
    }
}

struct ConditionsView:View {
    @EnvironmentObject var store:LabStore
    @State private var playerID:UUID?
    private var playerIndex:Int { store.editing.players.firstIndex(where:{$0.id==playerID}) ?? 0 }
    private var background:PlayerBackground { store.editing.players[playerIndex].background ?? PlayerBackground() }
    private func editBackground(_ edit:(inout PlayerBackground)->Void) {
        store.change { w in var value=w.players[playerIndex].background ?? PlayerBackground();edit(&value);w.players[playerIndex].background=value }
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                setupHeading("把战术与执行条件分开看","体能和累积疲劳不是同一项；战术理解、球员认同、情报和凝聚力也分别记录。")
                Card {
                    Toggle("自定义比赛情境",isOn:store.condition(\.custom)).font(.system(size:15,weight:.semibold))
                    if !store.editing.tactic.setup.conditions.custom {
                        Text("标准对照：体能 100%，比赛状态 100%，无累积疲劳，士气 20，团队凝聚力 80。执行力实验关闭。适合先隔离战术改动的影响。").font(.system(size:13)).foregroundStyle(Theme.muted)
                    } else {
                        HStack { Text("开赛状态").font(.system(size:11)); Button("体能不足") { store.editSetup { $0.conditions.condition=85;$0.conditions.sharpness=95 } }; Button("恢复标准") { store.editSetup { $0.conditions=MatchConditions();$0.conditions.custom=true } }; Spacer() }
                        HStack(alignment:.top,spacing:30) {
                            VStack(spacing:14) {
                                PercentField(title:"即时体能",value:store.condition(\.condition))
                                PercentField(title:"比赛状态",value:store.condition(\.sharpness))
                                HStack {Text("累积疲劳原值");TextField("0",value:Binding(get:{Int(store.editing.tactic.setup.conditions.fatigueRaw ?? 0)},set:{v in store.editSetup{$0.conditions.fatigueRaw=UInt16(clamping:v);$0.conditions.fatigue = .unknown}}),format:.number.grouping(.never))}
                                Text("0 为标准对照。原值范围 0–65535；未将轻度／重度标签换算成未经验证的数值。").font(.system(size:10)).foregroundStyle(Theme.muted)
                                Stepper("士气：\(store.editing.tactic.setup.conditions.morale) / 20",value:store.condition(\.morale),in:1...20)
                            }.frame(maxWidth:.infinity)
                            VStack(spacing:14) {
                                PercentField(title:"团队凝聚力 · 当前可验证范围 25–82",value:store.condition(\.cohesion),range:25...82)
                                Toggle("记录战术执行力实验条件",isOn:store.condition(\.executionEnabled))
                                if store.editing.tactic.setup.conditions.executionEnabled {
                                    PercentField(title:"战术理解／磨合",value:store.condition(\.understanding))
                                    PercentField(title:"球员认同",value:store.condition(\.buyIn))
                                    PercentField(title:"对手情报",value:store.condition(\.oppositionKnowledge))
                                }
                            }.frame(maxWidth:.infinity)
                        }.font(.system(size:12))
                        Text("体能、比赛状态、累积疲劳、士气与凝聚力传入原版引擎。战术执行力字段仍待映射；开启后会阻止运行，避免把未生效设置计入实验。").font(.system(size:11)).foregroundStyle(Theme.muted)
                    }
                }
                Card {
                    HStack { Label("性格与关系背景",systemImage:"person.2").font(.system(size:16,weight:.semibold)); Spacer(); Picker("球员",selection:Binding(get:{store.editing.players[playerIndex].id},set:{playerID=$0})) { ForEach(store.editing.players) { Text($0.name).tag($0.id) } }.frame(width:260) }
                    TextField("性格描述，例如：职业态度积极；未知可留空",text:Binding(get:{background.personality},set:{v in editBackground{$0.personality=v}}))
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:14) {
                        ForEach(PlayerBackground.traitNames,id:\.self) { trait in
                            Picker(trait,selection:Binding(get:{background.traits[trait] ?? 0},set:{v in editBackground{if v==0 {$0.traits.removeValue(forKey:trait)}else{$0.traits[trait]=v}}})) { Text("未知").tag(0);ForEach(1...20,id:\.self){Text("\($0)").tag($0)} }
                        }
                    }
                    TextField("关系备注：与谁配合默契、存在矛盾、指导关系及观察依据",text:Binding(get:{background.relationshipNotes},set:{v in editBackground{$0.relationshipNotes=v}}),axis:.vertical).lineLimit(3...5)
                    Text("已填写的七项性格数值传入原版引擎；未填写按控制值 10。文字描述与关系备注仅作记录，不产生额外搭档加成。").font(.system(size:11)).foregroundStyle(Theme.muted)
                }
                setupNote
            }.padding(22)
        }
    }
}

struct ChoiceField:View {
    let title:String;let options:[String];@Binding var value:String
    var body:some View { VStack(alignment:.leading,spacing:6) { Text(title).font(.system(size:11)).foregroundStyle(Theme.muted);Picker(title,selection:$value){ForEach(options,id:\.self){Text($0).tag($0)}}.labelsHidden() } }
}
struct PercentField:View {
    let title:String;@Binding var value:Int
    var range:ClosedRange<Double> = 0...100
    var body:some View { VStack { HStack {Text(title);Spacer();Text("\(value) / 100").monospacedDigit()};Slider(value:Binding(get:{Double(value)},set:{value=Int($0)}),in:range,step:1) } }
}
func setupHeading(_ title:String,_ subtitle:String)->some View {
    VStack(alignment:.leading,spacing:7) {Text(title).font(.system(size:20,weight:.semibold));Text(subtitle).font(.system(size:12)).foregroundStyle(Theme.muted)}
}
var setupNote:some View { Text("测试前保存双方配置快照，并校验引擎中的实际输入。未完成映射的实验条件会在开始前提示。").font(.system(size:11)).foregroundStyle(Theme.muted) }
