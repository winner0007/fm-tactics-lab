import SwiftUI
import TacticsCore

struct WorkbenchView: View {
    @EnvironmentObject var store: LabStore
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text(store.editedLeagueTeam.map{"\($0.name) · 战术设置"} ?? "普通对战 · 战术设置").font(.system(size:13,weight:.semibold))
                Spacer()
                Button("按位置选首发") {store.autoLineup()}
                Button("球员属性 ↗") {store.page="球员与阵容"}
            }.padding(.horizontal,22).padding(.top,14)
            Picker("配置步骤",selection:$store.workbenchStep) {
                ForEach(["阵型与首发","球队指令","球员指令","定位球","状态与磨合"],id:\.self) {Text($0).tag($0)}
            }.pickerStyle(.segmented).padding(.horizontal,22).padding(.vertical,12)
            if store.workbenchStep == "阵型与首发" {formationBody}
            else if store.workbenchStep == "球队指令" {TeamInstructionsView()}
            else if store.workbenchStep == "球员指令" {PlayerInstructionsView()}
            else if store.workbenchStep == "定位球" {SetPiecesView()}
            else {ConditionsView()}
            if store.editedLeagueTeam == nil {SimulationBar()}
            else {HStack {Text("这支球队会使用当前阵容与战术参加联赛。").font(.system(size:12));Spacer();Button("返回联赛安排比赛"){store.leaveLeagueEditor()}}.padding(18).background(.white)}
        }
    }
    private var formationBody:some View {
        GeometryReader {geometry in
            HStack(alignment:.top,spacing:18) {
                ScrollView {
                    VStack(alignment:.leading,spacing:14) {
                        TextField(store.editedLeagueTeam == nil ? "球队与方案名称":"战术名称",text:store.field(\.name)).font(.system(size:19,weight:.semibold)).textFieldStyle(.plain)
                        Text("双阶段战术板 · 点击球员编辑位置与角色").font(.system(size:11)).foregroundStyle(Theme.muted)
                        HStack(alignment:.top,spacing:10) {PitchPanel(phase:.possession);PitchPanel(phase:.defending)}
                        Text("拖动后吸附到支持的位置；重叠时交换当前阶段站位。首发名单由两阶段共用。").font(.system(size:11)).foregroundStyle(Theme.muted)
                        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:4) {
                            ForEach(store.editing.tactic.slots) {slot in
                                Button {store.selectedSlot=slot.id;store.instructionTab="角色与球员指令"} label: {
                                    HStack {Text("\(slot.id+1)").monospacedDigit().frame(width:20);Text(store.player(slot).name).lineLimit(1);Spacer();Text(slot.position(store.phase).id).foregroundStyle(Theme.muted)}.font(.system(size:11)).padding(8).background(store.selectedSlot==slot.id ? Theme.green.opacity(0.13):Color.white,in:RoundedRectangle(cornerRadius:5))
                                }.buttonStyle(.plain)
                            }
                        }
                        baselineCard
                    }.padding(18)
                }.frame(width:max(450,(geometry.size.width-18)*0.54))
                ScrollView {GameInstructionPane().padding(.vertical,18).padding(.trailing,18)}
            }
        }
    }
    private var baselineCard: some View {
        Card {
            HStack {
                Label("对照方案",systemImage:"square.stack.3d.up").font(.system(size:14,weight:.semibold))
                Spacer()
                Button(store.editing.baseline == nil ? "设为对照" : "更新对照") { store.change { $0.captureBaseline() } }
                if store.editing.baseline != nil { Button("恢复对照") { store.change { $0.restoreBaseline() } } }
            }
            if let baseline = store.editing.baseline {
                Text(baseline.name).font(.system(size:12,weight:.medium))
                if store.editing.differences().isEmpty { Text("当前方案与对照相同。调整一个指令后，在这里查看差异。").font(.system(size:11)).foregroundStyle(Theme.muted) }
                ForEach(store.editing.differences(),id:\.self) { Text("• " + $0).font(.system(size:11)) }
            } else { Text("先保存当前战术作为对照，再调整逼抢、防线或站位。").font(.system(size:11)).foregroundStyle(Theme.muted) }
        }
    }
}

struct PitchPanel: View {
    @EnvironmentObject var store: LabStore
    let phase: Phase
    var formation: String { phase == .possession ? store.editing.tactic.formation : store.editing.tactic.defensiveFormation }
    var body: some View {
        VStack(spacing:0) {
            HStack { Circle().fill(phase == .possession ? Theme.green : Theme.amber).frame(width:6,height:6); Text(phase.rawValue).font(.system(size:12,weight:.semibold)); Spacer(); Text("进攻 ↑").font(.system(size:10)).foregroundStyle(Theme.muted) }.padding(13).contentShape(Rectangle()).onTapGesture{store.phase=phase}
            PitchView(phase:phase).aspectRatio(0.73,contentMode:.fit)
            HStack {
                Text(formation).font(.system(size:14,weight:.semibold,design:.rounded))
                Spacer()
                Menu { ForEach(Formation.allCases) { f in Button(f.rawValue) { store.change { $0.tactic.apply(f,phase:phase) } } } } label: { Label("套用阵型",systemImage:"chevron.down").font(.system(size:10)) }.menuStyle(.borderlessButton).fixedSize()
            }.padding(13)
        }.background(.white,in:RoundedRectangle(cornerRadius:14)).clipShape(RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(store.phase==phase ? Theme.green:Theme.ink.opacity(0.08),lineWidth:store.phase==phase ? 2:1))
    }
}

struct PitchView: View {
    @EnvironmentObject var store: LabStore
    let phase: Phase
    @State private var dragged: Int?
    @State private var live: Point?
    var body: some View {
        GeometryReader { geometry in
            let target=dragged.flatMap { id in live.flatMap { store.editing.tactic.overlapTarget(slotID:id,phase:phase,point:$0,width:geometry.size.width,height:geometry.size.height) } }
            ZStack {
                PitchLines()
                ForEach(store.editing.tactic.slots) { slot in
                    let point = dragged == slot.id ? (live ?? slot.point(phase)) : slot.point(phase)
                    VStack(spacing:3) {
                        Text(String(slot.id+1)).font(.system(size:13,weight:.bold,design:.rounded)).frame(width:29,height:29)
                            .foregroundStyle(store.selectedSlot == slot.id ? Theme.ink : Theme.green)
                            .background(store.selectedSlot == slot.id ? Color(red:0.88,green:0.94,blue:0.58) : .white,in:Circle())
                            .overlay(Circle().stroke(target==slot.id ? Color.yellow : .white.opacity(0.3),lineWidth:target==slot.id ? 4 : 3)).shadow(color:.black.opacity(0.15),radius:4,y:2)
                        Text(store.player(slot).name).font(.system(size:9,weight:.medium)).lineLimit(1).frame(width:80).foregroundStyle(.white)
                        Text(target==slot.id ? "松手换位" : slot.position(phase).id).font(.system(size:8)).foregroundStyle(target==slot.id ? .yellow : .white.opacity(0.65))
                    }.position(x:point.x*geometry.size.width,y:point.y*geometry.size.height)
                        .onTapGesture { store.selectedSlot=slot.id; store.phase=phase;store.instructionTab="角色与球员指令" }
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
