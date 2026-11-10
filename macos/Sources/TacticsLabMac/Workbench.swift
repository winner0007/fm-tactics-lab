import SwiftUI
import TacticsCore

struct WorkbenchView: View {
    @EnvironmentObject var store: LabStore
    var body: some View {
        VStack(spacing:0) {
            Picker("配置步骤",selection:$store.workbenchStep) {
                ForEach(["阵型与首发","球队指令","球员指令","定位球","状态与磨合"],id:\.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal,22).padding(.top,16)
            if store.workbenchStep == "阵型与首发" { formationBody }
            else if store.workbenchStep == "球队指令" { TeamInstructionsView() }
            else if store.workbenchStep == "球员指令" { PlayerInstructionsView() }
            else if store.workbenchStep == "定位球" { SetPiecesView() }
            else { ConditionsView() }
        }
    }
    private var formationBody:some View {
        HStack(alignment:.top,spacing:18) {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    HStack {
                        VStack(alignment:.leading,spacing:6) {
                            TextField("方案名称",text:store.field(\.name)).font(.system(size:19,weight:.semibold)).textFieldStyle(.plain)
                            Text(store.workspace.rosterSource).font(.system(size:11)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Chip(text:"11 人 / 双阶段")
                    }
                    HStack(alignment:.top,spacing:14) {
                        PitchPanel(phase:.possession)
                        PitchPanel(phase:.defending)
                    }
                    HStack(spacing:6) { Image(systemName:"hand.draw"); Text("拖到空位调整站位 · 拖到球员上交换首发 · 两阶段同步") }.font(.system(size:11)).foregroundStyle(Theme.muted)
                    Card {
                        HStack { Label("战术体检",systemImage:"waveform.path.ecg").font(.system(size:14,weight:.semibold)); Spacer(); Chip(text:"规则分析 · 未经比赛验证",color:Theme.amber) }
                        ForEach(Analysis.inspect(store.workspace)) { insight in
                            HStack(alignment:.top,spacing:10) {
                                Image(systemName:insight.concern ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle(insight.concern ? Theme.amber : Theme.green).padding(.top,2)
                                VStack(alignment:.leading,spacing:5) { Text(insight.title).font(.system(size:12,weight:.semibold)); Text(insight.detail).font(.system(size:11)).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true) }
                            }
                        }
                    }
                    baselineCard
                }.padding(22)
            }
            ScrollView { InspectorView().padding(.trailing,22).padding(.vertical,22) }.frame(width:295)
        }
    }
    private var baselineCard: some View {
        Card {
            HStack {
                Label("对照方案",systemImage:"square.stack.3d.up").font(.system(size:14,weight:.semibold))
                Spacer()
                Button(store.workspace.baseline == nil ? "设为对照" : "更新对照") { store.change { $0.captureBaseline() } }
                if store.workspace.baseline != nil { Button("恢复对照") { store.change { $0.restoreBaseline() } } }
            }
            if let baseline = store.workspace.baseline {
                Text(baseline.name).font(.system(size:12,weight:.medium))
                if store.workspace.differences().isEmpty { Text("当前方案与对照相同。调整一个指令后，在这里查看差异。").font(.system(size:11)).foregroundStyle(Theme.muted) }
                ForEach(store.workspace.differences(),id:\.self) { Text("• " + $0).font(.system(size:11)) }
            } else { Text("先保存当前战术作为对照，再调整逼抢、防线或站位。").font(.system(size:11)).foregroundStyle(Theme.muted) }
        }
    }
}

struct PitchPanel: View {
    @EnvironmentObject var store: LabStore
    let phase: Phase
    var formation: String { phase == .possession ? store.workspace.tactic.formation : store.workspace.tactic.defensiveFormation }
    var body: some View {
        VStack(spacing:0) {
            HStack { Circle().fill(phase == .possession ? Theme.green : Theme.amber).frame(width:6,height:6); Text(phase.rawValue).font(.system(size:12,weight:.semibold)); Spacer(); Text("进攻 ↑").font(.system(size:10)).foregroundStyle(Theme.muted) }.padding(13)
            PitchView(phase:phase).aspectRatio(0.73,contentMode:.fit)
            HStack {
                Text(formation).font(.system(size:14,weight:.semibold,design:.rounded))
                Spacer()
                Menu { ForEach(Formation.allCases) { f in Button(f.rawValue) { store.change { $0.tactic.apply(f,phase:phase) } } } } label: { Label("套用阵型",systemImage:"chevron.down").font(.system(size:10)) }.menuStyle(.borderlessButton).fixedSize()
            }.padding(13)
        }.background(.white,in:RoundedRectangle(cornerRadius:14)).clipShape(RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(Theme.ink.opacity(0.08)))
    }
}

struct PitchView: View {
    @EnvironmentObject var store: LabStore
    let phase: Phase
    @State private var dragged: Int?
    @State private var live: Point?
    var body: some View {
        GeometryReader { geometry in
            let target=dragged.flatMap { id in live.flatMap { store.workspace.tactic.overlapTarget(slotID:id,phase:phase,point:$0,width:geometry.size.width,height:geometry.size.height) } }
            ZStack {
                PitchLines()
                ForEach(store.workspace.tactic.slots) { slot in
                    let point = dragged == slot.id ? (live ?? slot.point(phase)) : slot.point(phase)
                    VStack(spacing:3) {
                        Text(String(slot.id+1)).font(.system(size:13,weight:.bold,design:.rounded)).frame(width:29,height:29)
                            .foregroundStyle(store.selectedSlot == slot.id ? Theme.ink : Theme.green)
                            .background(store.selectedSlot == slot.id ? Color(red:0.88,green:0.94,blue:0.58) : .white,in:Circle())
                            .overlay(Circle().stroke(target==slot.id ? Color.yellow : .white.opacity(0.3),lineWidth:target==slot.id ? 4 : 3)).shadow(color:.black.opacity(0.15),radius:4,y:2)
                        Text(store.player(slot).name).font(.system(size:9,weight:.medium)).lineLimit(1).frame(width:80).foregroundStyle(.white)
                        Text(target==slot.id ? "松手换位" : slot.task(phase).rawValue).font(.system(size:8)).foregroundStyle(target==slot.id ? .yellow : .white.opacity(0.65))
                    }.position(x:point.x*geometry.size.width,y:point.y*geometry.size.height)
                        .onTapGesture { store.selectedSlot=slot.id; store.phase=phase }
                        .gesture(DragGesture(minimumDistance:3,coordinateSpace:.named("pitch-\(phase.rawValue)"))
                            .onChanged { value in
                                store.selectedSlot=slot.id; store.phase=phase; dragged=slot.id
                                live=Point(min(0.95,max(0.05,slot.point(phase).x+value.translation.width/geometry.size.width)),min(0.95,max(0.05,slot.point(phase).y+value.translation.height/geometry.size.height)))
                            }
                            .onEnded { value in
                                let p=Point(slot.point(phase).x+value.translation.width/geometry.size.width,slot.point(phase).y+value.translation.height/geometry.size.height)
                                store.move(slot.id,phase:phase,point:p,width:geometry.size.width,height:geometry.size.height); dragged=nil; live=nil
                            })
                        .zIndex(dragged==slot.id ? 1 : 0)
                        .accessibilityLabel("\(phase.rawValue)，\(store.player(slot).name)，\(slot.task(phase).rawValue)")
                }
            }.coordinateSpace(name:"pitch-\(phase.rawValue)")
        }
    }
}

struct PitchLines: View {
    var body: some View {
        Canvas { context,size in
            context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Color(red:0.13,green:0.34,blue:0.27)))
            for i in stride(from:0,to:10,by:2) { context.fill(Path(CGRect(x:0,y:Double(i)*size.height/10,width:size.width,height:size.height/10)),with:.color(.white.opacity(0.025))) }
            var p=Path()
            let w=size.width,h=size.height
            p.addRect(CGRect(x:12,y:12,width:w-24,height:h-24))
            p.move(to:CGPoint(x:12,y:h/2)); p.addLine(to:CGPoint(x:w-12,y:h/2))
            p.addEllipse(in:CGRect(x:w/2-w*0.17,y:h/2-w*0.17,width:w*0.34,height:w*0.34))
            for y in [12.0,h-12-h*0.17] { p.addRect(CGRect(x:w*0.24,y:y,width:w*0.52,height:h*0.17)) }
            for y in [12.0,h-12-h*0.07] { p.addRect(CGRect(x:w*0.36,y:y,width:w*0.28,height:h*0.07)) }
            context.stroke(p,with:.color(.white.opacity(0.23)),lineWidth:1)
            context.fill(Path(ellipseIn:CGRect(x:w/2-2,y:h/2-2,width:4,height:4)),with:.color(.white.opacity(0.3)))
        }
    }
}

struct InspectorView: View {
    @EnvironmentObject var store: LabStore
    var slot: Slot { store.workspace.tactic.slots[store.selectedSlot] }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Card {
                HStack { Text("位置 \(slot.id+1)").font(.system(size:13,weight:.semibold)); Spacer(); Chip(text:store.phase.rawValue) }
                Picker("首发",selection:Binding(get:{slot.playerID},set:{store.assign($0,slot:store.selectedSlot)})) { ForEach(store.workspace.players) { player in Text(player.name).tag(player.id) } }.labelsHidden()
                Picker("战术任务",selection:Binding(get:{slot.task(store.phase)},set:{ value in store.change { w in if store.phase == .possession { w.tactic.slots[store.selectedSlot].assignment=value } else { w.tactic.slots[store.selectedSlot].defensiveAssignment=value } } })) { ForEach(Assignment.allCases) { task in Text(task.rawValue).tag(task) } }
                Text("任务用于战术草图与结构检查，尚未映射为 FM 游戏角色。").font(.system(size:10)).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
            }
            Card {
                Label("球队指令",systemImage:"slider.horizontal.3").font(.system(size:14,weight:.semibold))
                InstructionSlider(title:"比赛心态",low:"谨慎",high:"积极",value:store.field(\.mentality))
                InstructionSlider(title:"比赛节奏",low:"耐心",high:"快速",value:store.field(\.tempo))
                InstructionSlider(title:"逼抢强度",low:"较少",high:"强烈",value:store.field(\.pressing))
                InstructionSlider(title:"防线高度",low:"回收",high:"前压",value:store.field(\.defensiveLine))
                InstructionSlider(title:"进攻宽度",low:"收窄",high:"拉开",value:store.field(\.width))
                InstructionSlider(title:"传球距离",low:"短传",high:"直接",value:store.field(\.passing))
            }
            Card {
                Label("实验笔记",systemImage:"square.and.pencil").font(.system(size:13,weight:.semibold))
                TextEditor(text:store.field(\.notes)).font(.system(size:12)).frame(height:85).scrollContentBackground(.hidden)
                Text("记下问题、对手特点和准备改变的一个变量。").font(.system(size:10)).foregroundStyle(Theme.muted)
            }
        }
    }
}

struct InstructionSlider: View {
    var title: String; var low: String; var high: String
    @Binding var value: Int
    var body: some View {
        VStack(spacing:4) {
            HStack { Text(title).font(.system(size:11,weight:.medium)); Spacer(); Text("\(value) / 5").font(.system(size:10,design:.monospaced)).foregroundStyle(Theme.muted) }
            Slider(value:Binding(get:{Double(value)},set:{value=Int($0)}),in:1...5,step:1).controlSize(.small)
            HStack { Text(low); Spacer(); Text(high) }.font(.system(size:9)).foregroundStyle(Theme.muted)
        }
    }
}
