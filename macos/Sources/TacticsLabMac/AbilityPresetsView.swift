import SwiftUI
import TacticsCore

struct AbilityPresetsView:View {
    @EnvironmentObject var store:LabStore
    @State private var scopeName="全队"
    @State private var position="DC"
    @State private var playerID:UUID?
    @State private var tier:AbilityTier = .professional
    private var activePosition:String { store.workspace.positionChoices.contains(position) ? position : store.workspace.positionChoices.first ?? "" }
    private var activePlayer:UUID { store.workspace.players.first(where:{$0.id==playerID})?.id ?? store.workspace.players[0].id }
    private var scope:AbilityScope {
        if scopeName=="按位置" { return .position(activePosition) }
        if scopeName=="个人" { return .individual(activePlayer) }
        return .team
    }
    var body:some View {
        let count=store.workspace.players.filter { scope.contains($0) }.count
        Card {
            HStack {
                Label("快速设置能力",systemImage:"slider.horizontal.3").font(.system(size:15,weight:.semibold))
                Spacer()
                Picker("作用范围",selection:$scopeName) { ForEach(["全队","按位置","个人"],id:\.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(width:260)
            }
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
                    Picker("球员位置",selection:Binding(get:{activePosition},set:{position=$0})) { ForEach(store.workspace.positionChoices,id:\.self) { Text($0).tag($0) } }.frame(width:230)
                } else if scopeName=="个人" {
                    Picker("球员",selection:Binding(get:{activePlayer},set:{playerID=$0})) { ForEach(store.workspace.players) { Text($0.name).tag($0.id) } }.frame(width:230)
                }
                Text(tier.detail).font(.system(size:11)).foregroundStyle(Theme.muted)
                Spacer()
                Button("应用到 \(count) 人") { store.applyAbility(tier,scope:scope) }.buttonStyle(.borderedProminent).disabled(count==0)
            }
            Text("实验属性预设，不等同于游戏 CA 或声望。按位置依据球员资料；全队包含替补。所有批量设置都可用 ⌘Z 撤销。").font(.system(size:10)).foregroundStyle(Theme.muted)
        }
    }
}
