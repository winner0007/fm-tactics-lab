import SwiftUI
import TacticsCore

struct TacticSelectionControl:View {
    @Binding var management:TeamManagement
    var inherited:TacticSelection? = nil
    var body:some View {
        VStack(alignment:.leading,spacing:5) {
        HStack(spacing:10) {
            Picker("战术",selection:Binding(get:{management.tacticLocked ? .fixed:management.selection},set:{management.selection=$0;if $0 == .random,management.tacticSeed==nil {management.tacticSeed=UInt32.random(in:0...UInt32.max)}})) {
                if let inherited {Text("统一设置 · "+inherited.rawValue).tag(nil as TacticSelection?)}
                else {Text("指定战术").tag(nil as TacticSelection?)}
                ForEach(TacticSelection.allCases){Text($0.rawValue).tag(Optional($0))}
            }.frame(width:270).disabled(management.tacticLocked)
            if management.tacticLocked {Label("战术已锁定",systemImage:"lock.fill").font(.caption)}
            else if (management.selection ?? inherited)==TacticSelection.random {
                Text("种子 "+(management.tacticSeed.map(String.init) ?? (inherited==nil ? "42":"按球队 ID 固定"))).font(.caption).monospacedDigit()
                Button("重新抽取"){management.tacticSeed=UInt32.random(in:0...UInt32.max)}
            }
        }
        if !management.tacticLocked,(management.selection ?? inherited) == .originalAI {
            Text(management.coach?.parameters == nil ? "使用原版测试教练参数":"教练："+management.coach!.name).font(.caption).foregroundStyle(Theme.muted)
        }
        }
    }
}
struct ExperimentTacticsConfiguration:View {
    @EnvironmentObject var store:LabStore
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("双方战术配置").font(.headline);Spacer()
                Menu("统一设置") {ForEach(TacticSelection.allCases){mode in Button(mode.rawValue){store.setExperimentTactics(mode)}}}
                Button("复制主队战术给双方"){store.copyTacticsToExperiment()}
            }
            ForEach(0..<2,id:\.self){side in
                let team=side==0 ? store.workspace:store.workspace.opponent!.workspace
                HStack {
                    Text((side==0 ? "主队 · ":"对手 · ")+team.tactic.name).lineLimit(1).frame(width:190,alignment:.leading)
                    TacticSelectionControl(management:Binding(get:{side==0 ? store.workspace.management:store.workspace.opponent!.workspace.management},set:{store.setExperimentManagement($0,side:side)}))
                    Spacer();Button("编辑指定战术"){store.editingSide=side;store.page="战术工作台"}
                }
            }
            Text("指定战术使用工作台的三个方案与临场规则。随机战术按保存的种子抽取；AI 按本次对手生成赛前方案。同一批比赛固定生成结果，续跑不重新抽取。").font(.caption).foregroundStyle(Theme.muted)
        }.disabled(store.runningOriginal || store.leagueRunning)
    }
}
extension LabStore {
    func setExperimentManagement(_ management:TeamManagement,side:Int) {
        guard !runningOriginal,!leagueRunning else{return}
        let oldSide=editingSide,oldTeam=leagueEditingTeam;leagueEditingTeam=nil;editingSide=side
        change{$0.management=management};editingSide=oldSide;leagueEditingTeam=oldTeam
    }
    func setExperimentTactics(_ mode:TacticSelection) {
        for side in 0...1 {
            var management=side==0 ? workspace.management:workspace.opponent!.workspace.management
            if management.tacticLocked {continue};management.selection=mode
            if mode == .random {management.tacticSeed=UInt32.random(in:0...UInt32.max)}
            setExperimentManagement(management,side:side)
        }
    }
    func copyTacticsToExperiment() {
        guard !runningOriginal,!leagueRunning,let other=workspace.opponent else{return}
        do {
            let target=try other.workspace.copyingTactics(from:workspace)
            let side=editingSide,team=leagueEditingTeam;leagueEditingTeam=nil;editingSide=1;change{$0=target};editingSide=side;leagueEditingTeam=team
        }catch{self.error=error.localizedDescription}
    }
    func copyTacticsToLeague() {
        guard !leagueRunning else{return}
        do {
            var next=leagueSetup
            for i in next.teams.indices where !next.teams[i].plan.management.tacticLocked {next.teams[i].plan=try next.teams[i].plan.copyingTactics(from:workspace)}
            leagueSetup=next;saveLeagueSetup();message="已将普通对战主队战术应用到未锁定球队；阵容分别保留"
        }catch{self.error=error.localizedDescription}
    }
}
