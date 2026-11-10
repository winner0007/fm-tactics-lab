import SwiftUI
import TacticsCore

struct LegacySetPiecesView:View {
    @EnvironmentObject var store:LabStore
    @State private var kind:SetPieceKind = .attackingCorner
    @State private var side:SetPieceSide = .left
    private var routine:SetPieceRoutine {store.editing.tactic.setup.routine(kind,side)}
    private func edit(_ change:(inout SetPieceRoutine)->Void) {
        store.editSetup { setup in var r=setup.routine(kind,side);change(&r);setup.setPieces[TacticalConfiguration.key(kind,side)]=r }
    }
    private func editPeople(_ change:(inout SetPiecePersonnel)->Void) {
        edit { r in var p=r.personnel ?? .initial(kind);change(&p);r.personnel=p }
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                setupHeading("定位球：套路、主罚与人员分工","先定进攻或防守方式，再安排主罚顺序、职责优先级和球员排名。首发变化后，自动从名单中递补。")
                HStack {
                    Picker("类型",selection:$kind) {ForEach(SetPieceKind.allCases){Text($0.rawValue).tag($0)}}.frame(width:230)
                    if kind != .penalty {
                        Picker("侧别",selection:$side) {ForEach(SetPieceSide.allCases){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented).frame(width:160)
                        Button("复制到另一侧") { store.editSetup{$0.setPieces[TacticalConfiguration.key(kind,side == .left ? .right : .left)]=routine} }
                    }
                    Spacer()
                }
                HStack(alignment:.top,spacing:18) {
                    VStack(spacing:16) {
                        Card {
                            ChoiceField(title:kind.defending ? "防守方式" : "开球方式",options:kind.deliveries,value:Binding(get:{routine.delivery},set:{v in edit{$0.delivery=v}}))
                            if [.attackingCorner,.attackingFreeKick].contains(kind) {
                                ChoiceField(title:"旋转方向",options:["混合","内旋","外旋"],value:Binding(get:{routine.swing ?? "混合"},set:{v in edit{$0.swing=v}}))
                                Text("内旋：左侧右脚／右侧左脚；外旋相反。请结合惯用脚安排主罚名单。").font(.system(size:11)).foregroundStyle(Theme.muted)
                            }
                            if kind == .attackingThrow {
                                ForEach(["后场","中场","前场"],id:\.self) { zone in
                                    ChoiceField(title:zone,options:zone == "前场" ? ["传入禁区","长距离掷入"] : ["保留球权","沿边线推进"],value:Binding(get:{routine.throwZones?[zone] ?? (zone == "前场" ? "传入禁区" : "保留球权")},set:{v in edit { if $0.throwZones==nil {$0.throwZones=[:]};$0.throwZones?[zone]=v }}))
                                }
                            }
                            if kind == .penalty {Toggle("罚失后更换主罚人",isOn:Binding(get:{routine.changeAfterMiss ?? false},set:{v in edit{$0.changeAfterMiss=v}}))}
                            TextField("套路备注",text:Binding(get:{routine.notes},set:{v in edit{$0.notes=v}}),axis:.vertical).lineLimit(2...4)
                        }
                        if kind != .penalty {SetPieceMap(kind:kind,side:side,routine:routine).frame(height:365)}
                    }.frame(width:310)
                    VStack(spacing:16) {
                        Card {
                            HStack {
                                Text("人员顺序").font(.system(size:16,weight:.semibold));Spacer()
                                Button("按已知属性建议") {editPeople{$0.suggest(players:store.editing.players,kind:kind)}}
                            }
                            Text("建议按相关属性等权排序，仅是编辑辅助，不等同于 FM 评分。缺少所需属性的球员不自动推荐，可手动加入；排序可上下调整。").font(.system(size:11)).foregroundStyle(Theme.muted)
                            if routine.personnel == nil {
                                Text("现有方案保留原来的位置分工。启用人员顺序后，按当前首发自动分配。").font(.system(size:12))
                                Button("启用人员顺序") { editPeople { p in p.takers=[routine.primaryTaker,routine.backupTaker].compactMap{$0} } }
                            }
                            if !kind.defending {
                                ranking("主罚名单",ids:routine.personnel?.takers ?? [routine.primaryTaker,routine.backupTaker].compactMap{$0}) { ids in editPeople{$0.takers=ids} }
                                let active=routine.effectiveTaker(slots:store.editing.tactic.slots)
                                Text("本场主罚：\(store.editing.players.first{$0.id==active}?.name ?? "待安排")").font(.system(size:12,weight:.medium)).foregroundStyle(active==nil ? Theme.amber : Theme.green)
                            }
                        }
                        if kind != .penalty { allocation }
                    }.frame(maxWidth:.infinity)
                }
                if kind != .penalty,let personnel=routine.personnel {
                    ForEach(personnel.priority.indices,id:\.self) { index in
                        let group=personnel.priority[index]
                        Card {
                            HStack {
                                Text("\(index+1). \(group.rawValue)").font(.system(size:15,weight:.semibold));Spacer()
                                Button("提高优先级") {editPeople{$0.priority.swapAt(index,index-1)}}.disabled(index==0)
                            }
                            ranking("球员排名",ids:personnel.rankings[group.rawValue] ?? []) { ids in editPeople{$0.rankings[group.rawValue]=ids} }
                            let tasks=personnel.duties[group.rawValue] ?? []
                            HStack {
                                Text("依顺序分配职责").font(.system(size:12))
                                ForEach(tasks.indices,id:\.self) { i in
                                    Picker("\(i+1)",selection:Binding(get:{tasks[i]},set:{v in editPeople{$0.duties[group.rawValue]?[i]=v}})) {ForEach(kind.tasks,id:\.self){Text($0).tag($0)}}.frame(maxWidth:180)
                                }
                            }
                        }
                    }
                }
                setupNote
            }.padding(22)
        }
    }
    private var allocation:some View {
        let tasks=routine.effectiveTasks(slots:store.editing.tactic.slots,kind:kind)
        let taker=routine.effectiveTaker(slots:store.editing.tactic.slots)
        return Card {
            Text("当前首发的职责").font(.system(size:16,weight:.semibold))
            ForEach(store.editing.tactic.slots.filter{$0.id != 0}) { slot in
                HStack {
                    Text(store.player(slot).name).frame(maxWidth:.infinity,alignment:.leading)
                    if !kind.defending && slot.playerID==taker {Chip(text:"主罚")}
                    else if routine.personnel != nil {Text(tasks[slot.id] ?? "待安排").foregroundStyle(tasks[slot.id]==nil ? Theme.amber : Theme.green)}
                    else {Picker("职责",selection:Binding(get:{routine.tasks[slot.id] ?? kind.tasks[0]},set:{v in edit{$0.tasks[slot.id]=v}})){ForEach(kind.tasks,id:\.self){Text($0).tag($0)}}.labelsHidden().frame(width:140)}
                }.font(.system(size:12)).padding(.vertical,3)
            }
        }
    }
    private func ranking(_ title:String,ids:[UUID],set:@escaping([UUID])->Void) -> some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text(title).font(.system(size:12,weight:.semibold));Spacer()
                Menu("添加球员") {
                    ForEach(store.editing.players.filter{!ids.contains($0.id)}) { player in Button(player.name){set(ids+[player.id])} }
                }.frame(width:110).disabled(ids.count==store.editing.players.count)
            }
            ForEach(Array(ids.enumerated()),id:\.element) { index,id in
                let player=store.editing.players.first{$0.id==id}
                HStack {
                    Text("\(index+1)").monospacedDigit().foregroundStyle(Theme.muted).frame(width:20)
                    Text(player?.name ?? "未知球员")
                    Text(player?.preferredFoot ?? "惯用脚未知").foregroundStyle(Theme.muted)
                    if !store.editing.tactic.slots.contains(where:{$0.playerID==id}) {Text("候补").foregroundStyle(Theme.muted)}
                    Spacer()
                    Button {var list=ids;list.swapAt(index,index-1);set(list)} label:{Image(systemName:"arrow.up")}.disabled(index==0).help("上移")
                    Button {var list=ids;list.swapAt(index,index+1);set(list)} label:{Image(systemName:"arrow.down")}.disabled(index==ids.count-1).help("下移")
                    Button {set(ids.filter{$0 != id})} label:{Image(systemName:"minus")}.help("移出名单")
                }.font(.system(size:11))
            }
            if ids.isEmpty {Text("尚无人员。添加球员，或补充属性后生成建议。").font(.system(size:11)).foregroundStyle(Theme.muted)}
        }
    }
}
