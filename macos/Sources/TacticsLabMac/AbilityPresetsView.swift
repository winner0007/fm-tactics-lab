import SwiftUI
import TacticsCore

struct AbilityPresetsView:View {
    @EnvironmentObject var store:LabStore
    @State private var scopeName="全队"
    @State private var position="DC"
    @State private var playerID:UUID?
    @State private var tier:AbilityTier?
    private var activePosition:String { store.editing.positionChoices.contains(position) ? position : store.editing.positionChoices.first ?? "" }
    private var activePlayer:UUID { store.editing.players.first(where:{$0.id==playerID})?.id ?? store.editing.players[0].id }
    private var scope:AbilityScope {
        if scopeName=="按位置" { return .position(activePosition) }
        if scopeName=="个人" { return .individual(activePlayer) }
        return .team
    }
    var body:some View {
        let count=store.editing.players.filter { scope.contains($0) }.count
        Card {
            HStack {
                Label("按档次重设能力（可选）",systemImage:"slider.horizontal.3").font(.system(size:15,weight:.semibold))
                Spacer()
                Picker("作用范围",selection:$scopeName) { ForEach(["全队","按位置","个人"],id:\.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(width:260)
            }
            Text(store.editing.abilitySourceDescription+" · 每场测试保持相同能力").font(.system(size:12)).foregroundStyle(Theme.muted)
            HStack(spacing:8) {
                ForEach(AbilityTier.allCases) { option in
                    Button { tier=option } label: {
                        VStack(spacing:6) { Text(option.rawValue).font(.system(size:12,weight:.semibold)); Text(option.rangeLabel).font(.system(size:10,design:.monospaced)) }
                            .frame(maxWidth:.infinity).padding(.vertical,12).foregroundStyle(tier==option ? .white : Theme.green)
                            .background(tier==option ? Theme.green : Theme.green.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
                    }.buttonStyle(.plain)
                }
            }
            HStack {
                if scopeName=="按位置" {
                    Picker("球员位置",selection:Binding(get:{activePosition},set:{position=$0})) { ForEach(store.editing.positionChoices,id:\.self) { Text($0).tag($0) } }.frame(width:230)
                } else if scopeName=="个人" {
                    Picker("球员",selection:Binding(get:{activePlayer},set:{playerID=$0})) { ForEach(store.editing.players) { Text($0.name).tag($0.id) } }.frame(width:230)
                }
                Text(tier?.detail ?? "选择档次后，点击右侧按钮重设能力。").font(.system(size:11)).foregroundStyle(Theme.muted)
                Spacer()
                Button("重设选中 \(count) 人的能力") { if let tier {store.applyAbility(tier,scope:scope)} }.buttonStyle(.borderedProminent).disabled(count==0 || tier==nil)
            }
            Text("档次表示属性区间，不是游戏 CA 或声望；全队包含替补。⌘Z 撤销修改。").font(.system(size:10)).foregroundStyle(Theme.muted)
        }
    }
}
