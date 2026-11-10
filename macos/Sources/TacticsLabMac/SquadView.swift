import SwiftUI
import TacticsCore

struct SquadView: View {
    @EnvironmentObject var store:LabStore
    @State private var group="基础"
    @State private var filter="全部"
    private var fields:[PlayerAttribute] { PlayerAttribute.fields(group) }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack {
                    Text("首发与候补 · \(store.workspace.players.count) 人").font(.system(size:20,weight:.semibold))
                    Spacer()
                    Button("添加候补球员") { store.change { w in var rng=SystemRandomNumberGenerator(); w.addCandidate(using:&rng) } }.disabled(store.workspace.players.count>=100)
                    Button("CSV 模板") { store.export(Data(CSV.playerTemplate().utf8),name:"球员导入模板.csv",type:.commaSeparatedText) }
                }
                AbilityPresetsView()
                HStack {
                    Picker("属性",selection:$group) { ForEach(PlayerAttribute.groups,id:\.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(width:480)
                    Spacer()
                    Picker("名单",selection:$filter) { ForEach(["全部","首发","候补"],id:\.self) { Text($0).tag($0) } }.frame(width:150)
                }
                Text("点击名单安排首发；已有首发自动互换。属性为 1–20，— 表示未录入。候补可随时替换首发；比赛报名和换人规则待原版引擎接入后校验。").font(.system(size:12)).foregroundStyle(Theme.muted)
                ScrollView(.horizontal) {
                    VStack(spacing:0) {
                        HStack(spacing:12) {
                            Text("球员").frame(width:132,alignment:.leading)
                            Text("位置").frame(width:85)
                            Text("名单 / 换人").frame(width:105)
                            Text("惯用脚").frame(width:75)
                            ForEach(fields) { a in Text(a.title).frame(width:68) }
                            Text("上次生成档次").frame(width:100)
                        }.font(.system(size:11,weight:.semibold)).foregroundStyle(Theme.muted).padding(14).background(Theme.green.opacity(0.06))
                        ForEach(store.workspace.players.indices,id:\.self) { index in
                            let starter=store.workspace.tactic.slots.contains { $0.playerID==store.workspace.players[index].id }
                            if filter=="全部" || (filter=="首发" ? starter : !starter) {
                                row(index);Divider().opacity(0.4)
                            }
                        }
                    }.background(.white,in:RoundedRectangle(cornerRadius:12))
                }
                Text(store.workspace.rosterSource).font(.system(size:11)).foregroundStyle(Theme.muted)
            }.padding(24)
        }
    }
    private func row(_ index:Int) -> some View {
        let player=store.workspace.players[index]
        let slot=store.workspace.tactic.slots.first { $0.playerID==player.id }
        return HStack(spacing:12) {
            TextField("姓名",text:Binding(get:{store.workspace.players[index].name},set:{v in store.change{$0.players[index].name=v}})).frame(width:132)
            TextField("位置",text:Binding(get:{store.workspace.players[index].position},set:{v in store.change{$0.players[index].position=v}})).frame(width:85)
            Menu(slot.map { "首发 · \($0.id+1)" } ?? "候补") {
                ForEach(store.workspace.tactic.slots) { target in
                    Button("\(target.id+1) · 替换 \(store.player(target).name)") { store.assign(player.id,slot:target.id) }
                }
            }.frame(width:105)
            Picker("惯用脚",selection:Binding(get:{player.preferredFoot ?? "未知"},set:{v in store.change{$0.players[index].preferredFoot = v=="未知" ? nil : v}})) {
                ForEach(["未知","左脚","右脚","双脚"],id:\.self) { Text($0).tag($0) }
            }.labelsHidden().frame(width:75)
            ForEach(fields) { a in
                Menu(player.attributes[a.id].map(String.init) ?? "—") {
                    if !Attribute.allCases.contains(where:{$0.key==a.id}) { Button("未知") { store.change{$0.players[index].attributes[a.id]=nil;$0.players[index].abilityPreset=nil} } }
                    ForEach(1...20,id:\.self) { v in Button(String(v)) { store.change{$0.players[index].attributes[a.id]=v;$0.players[index].abilityPreset=nil} } }
                }.monospacedDigit().frame(width:68)
            }
            Menu(player.abilityPreset?.rawValue ?? "自定义") {
                ForEach(AbilityTier.allCases) { tier in Button(tier.menuTitle) { store.applyAbility(tier,scope:.individual(player.id)) } }
            }.frame(width:100)
        }.font(.system(size:12)).padding(14)
    }
}
