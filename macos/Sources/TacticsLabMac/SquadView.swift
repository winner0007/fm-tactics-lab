import SwiftUI
import TacticsCore

struct SquadView: View {
    @EnvironmentObject var store:LabStore
    @State private var group="基础"
    @State private var filter="全部"
    @State private var profileID:UUID?
    private var fields:[PlayerAttribute] { PlayerAttribute.fields(group) }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack {
                    Text("首发与候补 · \(store.editing.players.count) 人").font(.system(size:20,weight:.semibold))
                    Spacer()
                    Button("添加候补球员") { store.change { w in var rng=SystemRandomNumberGenerator(); w.addCandidate(using:&rng) } }.disabled(store.editing.players.count>=100)
                    Button("CSV 模板") { store.export(Data(CSV.playerTemplate().utf8),name:"球员导入模板.csv",type:.commaSeparatedText) }
                }
                AbilityPresetsView()
                HStack {
                    Picker("属性",selection:$group) { ForEach(PlayerAttribute.groups,id:\.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(minWidth:580,maxWidth:680)
                    Spacer()
                    Picker("名单",selection:$filter) { ForEach(["全部","首发","候补"],id:\.self) { Text($0).tag($0) } }.frame(width:150)
                }
                Text("点击名单安排首发；已有首发自动互换。属性为 1–20，— 表示未录入。比赛使用 11 名首发及名单顺序中的前 9 名候补；点击资料可编辑身高、年龄、CA、声望和性格。").font(.system(size:12)).foregroundStyle(Theme.muted)
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
                        ForEach(store.editing.players) { player in
                            let starter=store.editing.tactic.slots.contains { $0.playerID==player.id }
                            if filter=="全部" || (filter=="首发" ? starter : !starter) {
                                row(player);Divider().opacity(0.4)
                            }
                        }
                    }.background(.white,in:RoundedRectangle(cornerRadius:12))
                }
                Text(store.editing.rosterSource).font(.system(size:11)).foregroundStyle(Theme.muted)
            }.padding(24)
        }.sheet(item:Binding(get:{profileID.map{PlayerProfileSelection(id:$0)}},set:{profileID=$0?.id})){item in PlayerProfileSheet(id:item.id)}
    }
    private func edit(_ id:UUID,_ action:(inout Player)->Void) {store.change{w in guard let i=w.players.firstIndex(where:{$0.id==id}) else{return};action(&w.players[i])}}
    private func row(_ player:Player) -> some View {
        let slot=store.editing.tactic.slots.first { $0.playerID==player.id }
        return HStack(spacing:12) {
            HStack(spacing:4){TextField("姓名",text:Binding(get:{store.editing.players.first{$0.id==player.id}?.name ?? player.name},set:{v in edit(player.id){$0.name=v}}));Button {profileID=player.id}label:{Image(systemName:"person.crop.rectangle")}.help("球员资料与性格")}.frame(width:132)
            TextField("位置",text:Binding(get:{store.editing.players.first{$0.id==player.id}?.position ?? player.position},set:{v in edit(player.id){$0.setPositionDescription(v)}})).frame(width:85)
            Menu(slot.map { "首发 · \($0.id+1)" } ?? "候补") {
                ForEach(store.editing.tactic.slots) { target in
                    Button("\(target.id+1) · 替换 \(store.player(target).name)") { store.assign(player.id,slot:target.id) }
                }
            }.frame(width:105)
            Picker("惯用脚",selection:Binding(get:{player.preferredFoot ?? "未知"},set:{v in edit(player.id){$0.setFoot(v=="未知" ? nil : v)}})) {
                ForEach(["未知","左脚","右脚","双脚"],id:\.self) { Text($0).tag($0) }
            }.labelsHidden().frame(width:75)
            ForEach(fields) { a in
                Menu(player.attributes[a.id].map(String.init) ?? "—") {
                    if !Attribute.allCases.contains(where:{$0.key==a.id}) { Button("未知") { edit(player.id){$0.setAttribute(a.id,nil)} } }
                    ForEach(1...20,id:\.self) { v in Button(String(v)) { edit(player.id){$0.setAttribute(a.id,v)} } }
                }.monospacedDigit().frame(width:68)
            }
            Menu(player.abilityPreset?.rawValue ?? "自定义") {
                ForEach(AbilityTier.allCases) { tier in Button(tier.menuTitle) { store.applyAbility(tier,scope:.individual(player.id)) } }
            }.frame(width:100)
        }.font(.system(size:12)).padding(14)
    }
}
