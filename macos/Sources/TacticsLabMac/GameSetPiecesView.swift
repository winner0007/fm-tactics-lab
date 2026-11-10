import SwiftUI
import TacticsCore

struct SetPiecesView:View {
    @EnvironmentObject var store:LabStore
    @State private var kind:GameSetPieceKind = .attackCorner
    @State private var variant=0
    @State private var tab="套路与球员任务"
    @State private var listID=2
    @State private var legacy=false
    private var setup:GameSetPieces {store.editing.tactic.setup.gameSetPieces ?? GameSetPieces()}
    private var variants:[GameSetPieceRoutine] {setup.routines[String(kind.id)]!}
    private var index:Int {min(variant,variants.count-1)}
    private var routine:GameSetPieceRoutine {variants[index]}
    private func edit(_ change:(inout GameSetPieces)->Void) {store.editSetup {c in var s=c.gameSetPieces ?? GameSetPieces();change(&s);c.gameSetPieces=s}}
    private func editRoutine(_ change:(inout GameSetPieceRoutine)->Void) {edit {s in var r=s.routines[String(kind.id)]![index];change(&r);s.routines[String(kind.id)]![index]=r}}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                setupHeading("定位球","按原项目的比赛情形、套路、角色任务与候选顺序设置；由 FM 原版引擎分配场上球员。")
                if !store.editing.tactic.setup.setPieces.isEmpty && store.editing.tactic.setup.gameSetPieces==nil {
                    Card {Text("旧版草图已保留。请核对下面的原版设置；采用后，比赛使用这里的套路。").font(.system(size:12));HStack {Button("查看旧草图"){legacy=true};Button("采用原版套路设置"){edit{_ in}}}}
                }
                Picker("定位球页面",selection:$tab){ForEach(["套路与球员任务","角色球员顺序","界外球策略","主罚人与队长"],id:\.self){Text($0).tag($0)}}.pickerStyle(.segmented)
                if tab=="套路与球员任务" {routines}
                else if tab=="界外球策略" {throwsCard}
                else {priorities}
            }.padding(22)
        }.onChange(of:kind){_,_ in variant=0}.onChange(of:store.editingSide){_,_ in variant=0}.onChange(of:tab){_,v in listID=v=="角色球员顺序" ? 16:2}
            .sheet(isPresented:$legacy){LegacySetPiecesView().frame(minWidth:950,minHeight:650).toolbar{Button("关闭"){legacy=false}}}
    }
    private var routines:some View {
        VStack(spacing:16) {
            Card {
                HStack {
                    Picker("比赛情形",selection:$kind){ForEach(GameSetPieceKind.allCases){Text($0.label).tag($0)}}.frame(width:270)
                    Picker("当前套路",selection:Binding(get:{index},set:{variant=$0})){ForEach(Array(variants.enumerated()),id:\.element.id){i,r in Text(r.name).tag(i)}}.frame(width:270)
                    Spacer()
                    Button("复制套路"){let newIndex=variants.count;edit {s in var r=routine;r.id=UUID();r.name+=" 副本";s.routines[String(kind.id)]!.append(r)};variant=newIndex}.disabled(variants.count>=3)
                    Button("删除"){edit{$0.routines[String(kind.id)]!.remove(at:index)};variant=0}.disabled(variants.count<=1)
                }
                HStack {
                    TextField("套路名称",text:Binding(get:{routine.name},set:{v in editRoutine{$0.name=String(v.prefix(64))}})).frame(maxWidth:260)
                    Picker("使用频率",selection:Binding(get:{routine.frequency},set:{v in editRoutine{$0.frequency=v}})){Text("较少 · 权重 2").tag(0);Text("正常 · 权重 5").tag(1);Text("较多 · 权重 8").tag(2)}
                    if !kind.strategyLabels.isEmpty {Picker(kind == .attackCorner ? "发球目标":"策略",selection:Binding(get:{routine.strategy},set:{v in editRoutine{$0.strategy=v}})){ForEach(kind.strategyLabels.indices,id:\.self){Text(kind.strategyLabels[$0]).tag($0)}}}
                    if kind.hasSwing {Picker("旋转方向",selection:Binding(get:{routine.swing},set:{v in editRoutine{$0.swing=v}})){Text("内弧球").tag(0);Text("外弧球").tag(1)}}
                }
                let count=routine.groups.reduce(0,{$0+$1.count})
                Text("\(count) / \(kind.taskCount) 项任务。每种情形最多 3 套；频率是抽取权重。调整角色人数时，先移除任务，再加入目标组。").font(.system(size:11)).foregroundStyle(count==kind.taskCount ? Theme.muted:Theme.amber)
            }
            ForEach(Array(routine.priority.enumerated()),id:\.element) {rank,group in
                taskGroup(group,rank:rank)
            }
        }
    }
    private func taskGroup(_ group:Int,rank:Int)->some View {
        Card {
            HStack {Text("\(rank+1). "+GameSetPieces.categories[group]).font(.system(size:16,weight:.semibold));Text("\(routine.groups[group].count) 人").foregroundStyle(Theme.muted);Spacer();Button("↑"){editRoutine{$0.priority.swapAt(rank,rank-1)}}.disabled(rank==0);Button("↓"){editRoutine{$0.priority.swapAt(rank,rank+1)}}.disabled(rank==routine.priority.count-1)}
            ForEach(routine.groups[group].indices,id:\.self) {i in
                HStack {
                    Text("\(i+1)").monospacedDigit().frame(width:25)
                    Picker("主要任务",selection:Binding(get:{routine.groups[group][i]},set:{v in editRoutine{$0.groups[group][i]=v}})) {ForEach(GameSetPieces.allowed[group],id:\.self){Text((group<4 ? GameSetPieces.defendTasks:GameSetPieces.attackTasks)[$0]).tag($0)}}
                    Picker("备用任务",selection:Binding(get:{routine.backups[group][i]},set:{v in editRoutine{$0.backups[group][i]=v}})) {Text("无备用任务").tag(0);ForEach(1..<16,id:\.self){Text((group<4 ? GameSetPieces.defendTasks:GameSetPieces.attackTasks)[$0]).tag($0)}}
                    Button("↑"){editRoutine{$0.groups[group].swapAt(i,i-1);$0.backups[group].swapAt(i,i-1)}}.disabled(i==0)
                    Button("↓"){editRoutine{$0.groups[group].swapAt(i,i+1);$0.backups[group].swapAt(i,i+1)}}.disabled(i==routine.groups[group].count-1)
                    Button("移除"){editRoutine{$0.groups[group].remove(at:i);$0.backups[group].remove(at:i)}}
                }.font(.system(size:12))
            }
            Menu("添加任务") {ForEach(GameSetPieces.allowed[group],id:\.self){task in Button((group<4 ? GameSetPieces.defendTasks:GameSetPieces.attackTasks)[task]){editRoutine{$0.groups[group].append(task);$0.backups[group].append(0)}}}}.frame(width:160).disabled(routine.groups.reduce(0,{$0+$1.count})>=kind.taskCount)
        }
    }
    private var throwsCard:some View {
        Card {
            Text("按场地区域设置界外球").font(.system(size:17,weight:.semibold))
            ForEach(0..<3,id:\.self){i in Picker(["后场","中场","前场"][i],selection:Binding(get:{setup.throwStyles[i]},set:{v in edit{$0.throwStyles[i]=v}})){Text(i==2 ? "短距离界外球":"保持球权").tag(0);Text(i==2 ? "长距离界外球":"沿边线推进").tag(1)}.frame(maxWidth:500)}
            Text("前场接应任务在进攻界外球套路中设置。实际掷球由主罚能力、场上空间与比赛状态决定。").font(.system(size:12)).foregroundStyle(Theme.muted)
        }
    }
    private var priorities:some View {
        let ids=setup.priorities[String(listID)] ?? []
        return Card {
            Picker("候选名单",selection:$listID){ForEach(tab=="角色球员顺序" ? Array(12..<20):Array(0..<12),id:\.self){Text(GameSetPieces.listNames[$0]).tag($0)}}.frame(width:360)
            Text("空名单由原版引擎按能力选择；已承担前序任务、未上场或正在主罚的球员，会由引擎跳过。只有比赛名单内的候选人传入测试。").font(.system(size:12)).foregroundStyle(Theme.muted)
            ForEach(Array(ids.enumerated()),id:\.element){i,id in
                HStack {Text("\(i+1)").frame(width:25);Text(store.editing.players.first{$0.id==id}?.name ?? "未找到球员");Spacer();Button("↑"){edit{$0.priorities[String(listID)]!.swapAt(i,i-1)}}.disabled(i==0);Button("↓"){edit{$0.priorities[String(listID)]!.swapAt(i,i+1)}}.disabled(i==ids.count-1);Button("移除"){edit{$0.priorities[String(listID)]!.remove(at:i)}}}.font(.system(size:12))
            }
            HStack {
                Menu("添加球员") {ForEach(store.editing.players.filter{!ids.contains($0.id)}){p in Button(p.name){edit{$0.priorities[String(listID),default:[]].append(p.id)}}}}.frame(width:180)
                Button("恢复自动分配"){edit{$0.priorities[String(listID)]=[]}}
            }
        }
    }
}
