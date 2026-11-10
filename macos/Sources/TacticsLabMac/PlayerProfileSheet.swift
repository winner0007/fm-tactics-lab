import SwiftUI
import TacticsCore

struct PlayerProfileSelection:Identifiable {let id:UUID}
struct PlayerProfileSheet:View {
    @EnvironmentObject var store:LabStore
    @Environment(\.dismiss) var dismiss
    let id:UUID
    private var player:Player? {store.editing.players.first{$0.id==id}}
    private func value(_ key:String)->Binding<UInt32> {
        Binding(get:{player?.nativeProfile?[key] ?? NativeProfile.defaults[key] ?? 10},set:{v in
            store.change {w in guard let i=w.players.firstIndex(where:{$0.id==id}) else{return};if w.players[i].nativeProfile==nil{w.players[i].nativeProfile=[:]};w.players[i].nativeProfile?[key]=v}
        })
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {Text(player?.name ?? "球员资料").font(.title2.bold());Spacer();Button("完成"){dismiss()}.keyboardShortcut(.defaultAction)}
            Text("这些资料随比赛配置写入原版引擎。CA 与属性独立设置，不会反向推算或改写属性。").font(.callout).foregroundStyle(Theme.muted)
            Grid(alignment:.leading,horizontalSpacing:24,verticalSpacing:12) {
                ForEach([("0","身高 cm"),("19","体重 kg"),("1","年龄"),("11","当前能力 CA"),("12","国内声望"),("13","当前声望"),("14","世界声望")],id:\.0){key,label in
                    GridRow {Text(label);Stepper(value:value(key),in:NativeProfile.range(Int(key)!)!){TextField(label,value:value(key),format:.number.grouping(.never)).frame(width:95)};Text("\(NativeProfile.range(Int(key)!)!.lowerBound)–\(NativeProfile.range(Int(key)!)!.upperBound)").foregroundStyle(Theme.muted)}
                }
            }
            Divider();Text("性格 · 1–20").font(.headline)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                ForEach(PlayerBackground.traitNames,id:\.self){trait in
                    Stepper(value:Binding(get:{player?.background?.traits[trait] ?? Int(player?.nativeProfile?[String((PlayerBackground.traitNames.firstIndex(of:trait) ?? 0)+2)] ?? 10)},set:{v in store.change{w in guard let i=w.players.firstIndex(where:{$0.id==id}) else{return};if w.players[i].background==nil{w.players[i].background=PlayerBackground()};w.players[i].background?.traits[trait]=v}}),in:1...20) {Text(trait+"：\(player?.background?.traits[trait] ?? Int(player?.nativeProfile?[String((PlayerBackground.traitNames.firstIndex(of:trait) ?? 0)+2)] ?? 10))")}
                }
            }
            Text("稳定性、大赛发挥、伤病倾向等在名单的“隐藏”页签编辑。习惯动作保留存档原值，目前没有可核对的中文编辑目录。").font(.caption).foregroundStyle(Theme.muted)
            if let source=player?.sourceIdentity {Text(source).font(.caption).foregroundStyle(Theme.muted)}
        }.padding(26).frame(width:650)
    }
}
