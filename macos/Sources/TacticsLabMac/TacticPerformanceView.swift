import SwiftUI
import Charts
import TacticsCore

struct TacticPerformanceView:View {
    let run:LeagueRun
    let season:Int
    @State private var selected:UUID?
    @State private var grouping:TacticGrouping = .exact
    @State private var venue:MatchVenue = .all
    @State private var allSeasons=false
    private var teamID:UUID? {selected ?? run.setup.teams.first?.id}
    private var rows:[TacticPerformance] {teamID.map{TacticPerformance.aggregate(run:run,teamID:$0,season:allSeasons ? nil:season,grouping:grouping,venue:venue)} ?? []}
    var body:some View {
        let data=rows
        Card {
            Text("面对不同战术的表现").font(.system(size:17,weight:.semibold))
            filters
            Text("完整战术按实际开赛的阵型、角色、指令、盯防和定位球分组。己方战术不同会另列；球队名称和球员能力不会决定分组。").font(.system(size:11)).foregroundStyle(Theme.muted)
            if data.isEmpty {Text("这支球队尚无符合筛选条件的完赛记录。").foregroundStyle(Theme.muted)}
            else {
                Chart(data) {row in
                    BarMark(x:.value("场均积分",row.pointsPerGame),y:.value("对手战术",row.opponentShape+" · "+row.opponentKey.prefix(6)+" / 己 "+row.ownKey.prefix(6))).foregroundStyle(Theme.green)
                }.chartXScale(domain:0...3).frame(height:CGFloat(max(160,data.count*35)))
                Text("场均积分统一按胜 3、平 1、负 0 比较。").font(.system(size:10)).foregroundStyle(Theme.muted)
                resultTable(data)
                Text("这是已完成比赛的分组结果，不代表战术克制结论。先比较样本数、主客场与对手强度；需要更稳定的比较时，增加重复赛季。CA 为开赛首发平均当前能力，范围 0–200。").font(.system(size:11)).foregroundStyle(Theme.muted)
            }
        }.onChange(of:run.id){_,_ in selected=nil}
    }
    private var filters:some View {
            HStack {
                Picker("分析球队",selection:Binding(get:{teamID},set:{selected=$0})) {ForEach(run.setup.teams){Text($0.name).tag(Optional($0.id))}}.frame(width:260)
                Picker("分组",selection:$grouping){ForEach(TacticGrouping.allCases){Text($0.rawValue).tag($0)}}.frame(width:170)
                Picker("场地",selection:$venue){ForEach(MatchVenue.allCases){Text($0.rawValue).tag($0)}}.frame(width:160)
                Toggle("合并重复赛季",isOn:$allSeasons).toggleStyle(.checkbox)
            }
    }
    private func resultTable(_ rows:[TacticPerformance])->some View {
                ScrollView(.horizontal) {
                    VStack(alignment:.leading,spacing:10) {
                        HStack {Text("对手有球 / 无球阵型 · 战术编号").frame(width:275,alignment:.leading);ForEach(["场次（主/客）","胜/平/负","胜率","场均进/失球","场均 xG/失 xG","首发 CA 己/敌"],id:\.self){Text($0).frame(width:105)}}.font(.system(size:11)).foregroundStyle(Theme.muted)
                        ForEach(rows) {r in
                            TacticPerformanceRow(row:r)
                        }
                    }
                }
    }

}

private struct TacticPerformanceRow:View {
    let row:TacticPerformance
    private var r:TacticPerformance {row}
    private var caption:String {"对手："+r.opponents.sorted().joined(separator:"、")+String(format:" · 对手 CA 范围 %.1f–%.1f",r.opponentAbilityMin,r.opponentAbilityMax)+" · 己方战术 "+r.ownKey.prefix(8)}
    var body:some View {
                            VStack(alignment:.leading,spacing:5) {
                                HStack {
                                    Text(r.opponentShape+" · "+r.opponentKey.prefix(8)).frame(width:275,alignment:.leading)
                                    Text("\(r.games)（\(r.homeGames)/\(r.awayGames)）").frame(width:105)
                                    Text("\(r.wins)/\(r.draws)/\(r.losses)").frame(width:105)
                                    Text(String(format:"%.1f%%",r.winRate*100)).frame(width:105)
                                    Text(String(format:"%.2f / %.2f",Double(r.goalsFor)/Double(r.games),Double(r.goalsAgainst)/Double(r.games))).frame(width:105)
                                    Text(r.xgGames>0 ? String(format:"%.2f / %.2f",r.xgFor/Double(r.xgGames),r.xgAgainst/Double(r.xgGames)):"—").frame(width:105)
                                    Text(String(format:"%.1f / %.1f",r.ownAbility,r.opponentAbility)).frame(width:105)
                                }.font(.system(size:11)).monospacedDigit()
                                Text(caption).font(.system(size:10)).foregroundStyle(Theme.muted)
                                Divider()
                            }
    }
}
