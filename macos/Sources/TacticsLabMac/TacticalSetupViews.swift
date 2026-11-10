import SwiftUI
import TacticsCore

struct TeamInstructionsView:View {
    @EnvironmentObject var store:LabStore
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                setupHeading("按比赛阶段组织球队指令","先确定整体思路，再配置有球、转换和无球阶段。设置随方案保存。")
                Card { InstructionSlider(title:"整体比赛心态",low:"谨慎",high:"积极",value:store.field(\.mentality)).frame(maxWidth:450) }
                HStack(alignment:.top,spacing:16) {
                    ForEach(["有球","转换","无球"],id:\.self) { section in
                        Card {
                            Text(section+"阶段").font(.system(size:17,weight:.semibold))
                            if section=="有球" {
                                InstructionSlider(title:"节奏",low:"耐心",high:"快速",value:store.field(\.tempo))
                                InstructionSlider(title:"宽度",low:"收窄",high:"拉开",value:store.field(\.width))
                                InstructionSlider(title:"传球距离",low:"短传",high:"直接",value:store.field(\.passing))
                            }
                            if section=="无球" {
                                InstructionSlider(title:"逼抢强度",low:"较少",high:"强烈",value:store.field(\.pressing))
                                InstructionSlider(title:"防线高度",low:"回收",high:"前压",value:store.field(\.defensiveLine))
                            }
                            ForEach(InstructionDefinition.team.filter{$0.section==section}) { definition in
                                ChoiceField(title:definition.title,options:definition.options,value:Binding(get:{store.workspace.tactic.setup.team[definition.id] ?? definition.defaultValue},set:{v in store.editSetup{$0.team[definition.id]=v}}))
                            }
                        }.frame(maxWidth:.infinity)
                    }
                }
                setupNote
            }.padding(22)
        }
    }
}

struct PlayerInstructionsView:View {
    @EnvironmentObject var store:LabStore
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                setupHeading("每个位置，各司其职","个人指令按位置和阶段保存。换位时，球员接替目标位置的职责与指令。")
                HStack {
                    Picker("位置",selection:$store.selectedSlot) { ForEach(store.workspace.tactic.slots) { slot in Text("\(slot.id+1) · \(store.player(slot).name)").tag(slot.id) } }.frame(width:300)
                    Picker("阶段",selection:$store.phase) { ForEach(Phase.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(width:280)
                    Spacer()
                }
                HStack(alignment:.top,spacing:20) {
                    PitchPanel(phase:store.phase).frame(width:310)
                    Card {
                        let slot=store.workspace.tactic.slots[store.selectedSlot]
                        Text(store.player(slot).name).font(.system(size:20,weight:.semibold))
                        Picker("战术任务",selection:Binding(get:{slot.task(store.phase)},set:{v in store.change { w in if store.phase == .possession {w.tactic.slots[store.selectedSlot].assignment=v} else {w.tactic.slots[store.selectedSlot].defensiveAssignment=v} }})) { ForEach(Assignment.allCases) { Text($0.rawValue).tag($0) } }
                        ForEach(InstructionDefinition.player.filter{$0.section == (store.phase == .possession ? "有球" : "无球")}) { definition in
                            let key=TacticalConfiguration.playerKey(store.selectedSlot,store.phase)
                            ChoiceField(title:definition.title,options:definition.options,value:Binding(get:{store.workspace.tactic.setup.players[key]?[definition.id] ?? definition.defaultValue},set:{v in store.editSetup{$0.players[key,default:[:]][definition.id]=v}}))
                        }
                    }
                }
                setupNote
            }.padding(22)
        }
    }
}

struct SetPieceMap:View {
    @EnvironmentObject var store:LabStore
    let kind:SetPieceKind; let side:SetPieceSide; let routine:SetPieceRoutine
    var body:some View {
        VStack(spacing:0) {
            GeometryReader { geometry in
                ZStack {
                    PitchLines()
                    ForEach(store.workspace.tactic.slots) { slot in
                        let p=point(slot)
                        VStack(spacing:2) { Text("\(slot.id+1)").font(.system(size:11,weight:.bold)).frame(width:24,height:24).background(.white,in:Circle()).foregroundStyle(Theme.green); Text(slot.id==0 ? "门将" : (routine.effectiveTaker(slots:store.workspace.tactic.slots)==slot.playerID && !kind.defending ? "主罚" : routine.effectiveTasks(slots:store.workspace.tactic.slots,kind:kind)[slot.id] ?? "待安排")).font(.system(size:8)).foregroundStyle(.white) }.position(x:p.x*geometry.size.width,y:p.y*geometry.size.height)
                    }
                }
            }
            Text("职责示意 · 不代表引擎实际站位").font(.system(size:10)).foregroundStyle(Theme.muted).padding(10).frame(maxWidth:.infinity).background(.white)
        }.clipShape(RoundedRectangle(cornerRadius:14))
    }
    private func point(_ slot:Slot) -> Point {
        if slot.id==0 {return Point(0.5,kind.defending ? 0.12 : 0.9)}
        if !kind.defending && slot.playerID==routine.effectiveTaker(slots:store.workspace.tactic.slots) {return Point(side == .left ? 0.08 : 0.92,0.08)}
        let task=routine.effectiveTasks(slots:store.workspace.tactic.slots,kind:kind)[slot.id] ?? "待安排"
        let base:Point
        if task.contains("近点") {base=Point(0.28,0.23)}
        else if task.contains("远点") {base=Point(0.72,0.23)}
        else if task.contains("中路") || task=="盯人" {base=Point(0.5,0.3)}
        else if task.contains("禁区外") {base=Point(0.5,0.47)}
        else if task.contains("短传") {base=Point(0.18,0.35)}
        else if task.contains("留前") {base=Point(0.5,0.78)}
        else {base=Point(0.5,kind.defending ? 0.28 : 0.7)}
        let peers=store.workspace.tactic.slots.filter{$0.id != 0 && (routine.tasks[$0.id] ?? kind.tasks[0])==task}
        let index=peers.firstIndex(where:{$0.id==slot.id}) ?? 0
        let offset=(Double(index)-Double(peers.count-1)/2)*0.12
        return Point(min(0.9,max(0.1,base.x+offset)),base.y)
    }
}

struct ConditionsView:View {
    @EnvironmentObject var store:LabStore
    @State private var playerID:UUID?
    private var playerIndex:Int { store.workspace.players.firstIndex(where:{$0.id==playerID}) ?? 0 }
    private var background:PlayerBackground { store.workspace.players[playerIndex].background ?? PlayerBackground() }
    private func editBackground(_ edit:(inout PlayerBackground)->Void) {
        store.change { w in var value=w.players[playerIndex].background ?? PlayerBackground();edit(&value);w.players[playerIndex].background=value }
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                setupHeading("把战术与执行条件分开看","体能和累积疲劳不是同一项；战术理解、球员认同、情报和凝聚力也分别记录。")
                Card {
                    Toggle("自定义比赛情境",isOn:store.condition(\.custom)).font(.system(size:15,weight:.semibold))
                    if !store.workspace.tactic.setup.conditions.custom {
                        Text("标准对照：体能 100%，比赛状态 100%，无累积疲劳，士气 20，团队凝聚力 80。执行力实验关闭。适合先隔离战术改动的影响。").font(.system(size:13)).foregroundStyle(Theme.muted)
                    } else {
                        HStack { Text("情境示例").font(.system(size:11)); Button("赛程密集") { store.editSetup { $0.conditions.condition=85;$0.conditions.sharpness=95;$0.conditions.fatigue = .tired } }; Button("新战术磨合") { store.editSetup { $0.conditions.executionEnabled=true;$0.conditions.understanding=35;$0.conditions.buyIn=60;$0.conditions.cohesion=50 } }; Spacer() }
                        HStack(alignment:.top,spacing:30) {
                            VStack(spacing:14) {
                                PercentField(title:"即时体能",value:store.condition(\.condition))
                                PercentField(title:"比赛状态",value:store.condition(\.sharpness))
                                Picker("累积疲劳",selection:store.condition(\.fatigue)) { ForEach(FatigueLevel.allCases) { Text($0.rawValue).tag($0) } }
                                Stepper("士气：\(store.workspace.tactic.setup.conditions.morale) / 20",value:store.condition(\.morale),in:1...20)
                            }.frame(maxWidth:.infinity)
                            VStack(spacing:14) {
                                PercentField(title:"团队凝聚力",value:store.condition(\.cohesion))
                                Toggle("记录战术执行力实验条件",isOn:store.condition(\.executionEnabled))
                                if store.workspace.tactic.setup.conditions.executionEnabled {
                                    PercentField(title:"战术理解／磨合",value:store.condition(\.understanding))
                                    PercentField(title:"球员认同",value:store.condition(\.buyIn))
                                    PercentField(title:"对手情报",value:store.condition(\.oppositionKnowledge))
                                }
                            }.frame(maxWidth:.infinity)
                        }.font(.system(size:12))
                        Text("均为手动实验输入。疲劳标签尚未映射游戏原始数值；不会据此生成比赛结果或统一的执行力评分。").font(.system(size:11)).foregroundStyle(Theme.muted)
                    }
                }
                Card {
                    HStack { Label("性格与关系背景",systemImage:"person.2").font(.system(size:16,weight:.semibold)); Spacer(); Picker("球员",selection:Binding(get:{store.workspace.players[playerIndex].id},set:{playerID=$0})) { ForEach(store.workspace.players) { Text($0.name).tag($0.id) } }.frame(width:260) }
                    TextField("性格描述，例如：职业态度积极；未知可留空",text:Binding(get:{background.personality},set:{v in editBackground{$0.personality=v}}))
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:14) {
                        ForEach(PlayerBackground.traitNames,id:\.self) { trait in
                            Picker(trait,selection:Binding(get:{background.traits[trait] ?? 0},set:{v in editBackground{if v==0 {$0.traits.removeValue(forKey:trait)}else{$0.traits[trait]=v}}})) { Text("未知").tag(0);ForEach(1...20,id:\.self){Text("\($0)").tag($0)} }
                        }
                    }
                    TextField("关系备注：与谁配合默契、存在矛盾、指导关系及观察依据",text:Binding(get:{background.relationshipNotes},set:{v in editBackground{$0.relationshipNotes=v}}),axis:.vertical).lineLimit(3...5)
                    Text("性格分项与关系来自你的记录，未读取隐藏属性；未知保持未知。当前仅作背景，不产生搭档加成或能力扣分。").font(.system(size:11)).foregroundStyle(Theme.muted)
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
    var body:some View { VStack { HStack {Text(title);Spacer();Text("\(value) / 100").monospacedDigit()};Slider(value:Binding(get:{Double(value)},set:{value=Int($0)}),in:0...100,step:1) } }
}
func setupHeading(_ title:String,_ subtitle:String)->some View {
    VStack(alignment:.leading,spacing:7) {Text(title).font(.system(size:20,weight:.semibold));Text(subtitle).font(.system(size:12)).foregroundStyle(Theme.muted)}
}
var setupNote:some View { Text("这些配置用于方案规划与对照保存。自定义配置写入原版引擎与 FMF 回写仍在适配，当前内置基线模拟不会使用这里的改动。").font(.system(size:11)).foregroundStyle(Theme.muted) }
