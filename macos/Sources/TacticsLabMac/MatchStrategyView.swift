import SwiftUI
import TacticsCore

struct StrategyPlanTabs:View {
    @EnvironmentObject var store:LabStore
    var body:some View {
        HStack(spacing:10) {
            Text("战术方案").font(.system(size:11)).foregroundStyle(Theme.muted)
            ForEach(0..<3,id:\.self){i in
                let selected=(store.editing.matchStrategy?.editingSlot ?? 0)==i
                Button {store.change{$0.selectStrategyPlan(i)}} label:{
                    HStack(spacing:5){Text("\(i+1)").bold();Text(store.editing.matchStrategy?.planNames[i] ?? ["常用战术","加强进攻","稳守领先"][i]).lineLimit(1);if store.editing.matchStrategy?.kickoffSlot==i {Image(systemName:"flag.fill").font(.system(size:9))}}
                        .font(.system(size:12)).padding(.horizontal,12).padding(.vertical,9).foregroundStyle(selected ? Color.white:Theme.ink).background(selected ? Theme.green:Color.white,in:RoundedRectangle(cornerRadius:7))
                }.buttonStyle(.plain).accessibilityLabel("编辑战术方案 \(i+1)")
            }
            Spacer()
            Button(store.editing.matchStrategy?.enabled==true ? "临场策略 · 已开启":"设置临场策略") {store.change{$0.createStrategy()};store.workbenchStep="临场策略"}
        }.padding(.horizontal,22).padding(.top,10)
    }
}

struct MatchStrategyView:View {
    @EnvironmentObject var store:LabStore
    private var strategy:MatchStrategy {store.editing.matchStrategy ?? MatchStrategy(tactic:store.editing.tactic)}
    private func field<T>(_ path:WritableKeyPath<MatchStrategy,T>)->Binding<T> {Binding(get:{strategy[keyPath:path]},set:{v in store.change{$0.createStrategy();$0.matchStrategy![keyPath:path]=v}})}
    private func rule<T>(_ id:UUID,_ path:WritableKeyPath<StrategyRule,T>,_ fallback:T)->Binding<T> {
        Binding(get:{strategy.rules.first{$0.id==id}?[keyPath:path] ?? fallback},set:{v in store.change{w in w.createStrategy();if let i=w.matchStrategy!.rules.firstIndex(where:{$0.id==id}){w.matchStrategy!.rules[i][keyPath:path]=v}}})
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Card {
                    Toggle("根据比赛情况自动切换战术",isOn:field(\.enabled)).font(.system(size:17,weight:.semibold))
                    Text("在上方三套方案中分别设置阵型、角色、心态与指令。三套方案共用首发、候补、定位球和开赛状态；切换不会重置比赛或恢复体力。").font(.system(size:12)).foregroundStyle(Theme.muted)
                    HStack {
                        Picker("开场方案",selection:field(\.kickoffSlot)){ForEach(0..<3,id:\.self){i in Text("\(i+1) · "+strategy.planNames[i]).tag(i)}}.frame(maxWidth:380)
                        Stepper("两次切换至少间隔 \(strategy.cooldownMinutes) 分钟",value:field(\.cooldownMinutes),in:1...30).frame(maxWidth:330)
                    }
                    Toggle("没有规则符合时，回到开场方案",isOn:field(\.returnToKickoff))
                    Text("按列表从上到下匹配，先符合的规则生效。间隔按实际比赛经过时间计算；取消勾选回到开场方案时，会保持最近一次战术。").font(.system(size:11)).foregroundStyle(Theme.muted)
                }
                Card {
                    Text("三套战术").font(.system(size:16,weight:.semibold))
                    ForEach(0..<3,id:\.self){i in
                        HStack {
                            Text("\(i+1)").bold().frame(width:24)
                            TextField("方案名称",text:Binding(get:{strategy.planNames[i]},set:{v in store.change{$0.createStrategy();$0.matchStrategy!.planNames[i]=v}})).frame(width:190)
                            let plan=store.editing.strategyPlans.count==3 ? store.editing.strategyPlans[i]:store.editing.tactic
                            Text(plan.formation+" / "+plan.defensiveFormation).font(.system(size:12)).foregroundStyle(Theme.muted)
                            Spacer()
                            Button("编辑阵型与指令"){store.change{$0.selectStrategyPlan(i)};store.workbenchStep="阵型与首发"}
                        }
                    }
                }
                HStack {Text("切换规则 · 越靠上越优先").font(.system(size:16,weight:.semibold));Spacer();Button("添加规则"){store.change{$0.createStrategy();$0.matchStrategy!.rules.append(StrategyRule())}}.disabled(strategy.rules.count>=12)}
                ForEach(Array(strategy.rules.enumerated()),id:\.element.id){index,r in
                    Card {
                        HStack {
                            Toggle("规则 \(index+1)",isOn:rule(r.id,\.enabled,true)).font(.system(size:13,weight:.semibold))
                            Spacer()
                            Button {move(index,-1)} label:{Image(systemName:"arrow.up")}.disabled(index==0).help("提高优先级")
                            Button {move(index,1)} label:{Image(systemName:"arrow.down")}.disabled(index==strategy.rules.count-1).help("降低优先级")
                            Button("删除"){store.change{$0.matchStrategy?.rules.removeAll{$0.id==r.id}}}
                        }
                        HStack {
                            Text("从");TextField("60",value:rule(r.id,\.fromMinute,60),format:.number.grouping(.never)).frame(width:48)
                            Text("到");TextField("120",value:rule(r.id,\.throughMinute,120),format:.number.grouping(.never)).frame(width:48);Text("分钟")
                            Picker("比分",selection:rule(r.id,\.condition,.losing)){ForEach(ScoreCondition.allCases,id:\.self){Text($0.rawValue).tag($0)}}.frame(width:160)
                            if r.condition.usesMargin {TextField("3",value:rule(r.id,\.margin,3),format:.number).frame(width:40);Text("球")}
                            Spacer()
                            Picker("切换至",selection:rule(r.id,\.target,1)){ForEach(0..<3,id:\.self){i in Text("\(i+1) · "+strategy.planNames[i]).tag(i)}}.frame(width:240)
                        }.font(.system(size:12)).textFieldStyle(.roundedBorder)
                    }
                }
                Text("规则使用本队视角的领先／落后。双方均可设置，普通对战和联赛使用同一流程；每次切换会在报告中记录时间、比分和执行后的战术。").font(.system(size:12)).foregroundStyle(Theme.muted)
            }.padding(22)
        }
    }
    private func move(_ index:Int,_ delta:Int) {store.change{$0.matchStrategy?.rules.swapAt(index,index+delta)}}
}
