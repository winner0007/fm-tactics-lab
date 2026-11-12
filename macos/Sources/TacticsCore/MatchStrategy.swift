import Foundation

public enum ScoreCondition:String,Codable,CaseIterable {
    case any="任意比分",losing="落后",drawing="平局",winning="领先",leadingBy="领先至少",trailingBy="落后至少"
    public func matches(_ difference:Int,margin:Int)->Bool {
        switch self {case .any:return true;case .losing:return difference<0;case .drawing:return difference==0;case .winning:return difference>0;case .leadingBy:return difference>=margin;case .trailingBy:return difference <= -margin}
    }
    public var usesMargin:Bool {self == .leadingBy || self == .trailingBy}
    public var code:Int {Self.allCases.firstIndex(of:self)!}
}

public struct StrategyRule:Codable,Equatable,Identifiable {
    public var id=UUID()
    public var enabled=true
    public var fromMinute=60
    public var throughMinute=120
    public var condition:ScoreCondition = .losing
    public var margin=3
    public var target=1
    public init() {}
    public var summary:String {"\(fromMinute)–\(throughMinute) 分钟 · "+condition.rawValue+(condition.usesMargin ? " \(margin) 球":"")}
}

/// The current editor tactic occupies editingSlot. The other two snapshots are
/// retained here; lineup, set pieces and initial conditions are shared by all three.
public struct MatchStrategy:Codable,Equatable {
    public var enabled=false
    public var editingSlot=0
    public var kickoffSlot=0
    public var cooldownMinutes=10
    public var returnToKickoff=true
    public var planNames=["常用战术","加强进攻","稳守领先"]
    public var plans:[Tactic]
    public var rules:[StrategyRule]
    public init(tactic:Tactic) {
        var attack=tactic,defend=tactic
        attack.name="加强进攻";var a=attack.setup;a.nativeMentality=6;attack.configuration=a
        defend.name="稳守领先";var d=defend.setup;d.nativeMentality=2;defend.configuration=d
        plans=[tactic,attack,defend]
        var lead=StrategyRule();lead.condition = .leadingBy;lead.target=2
        rules=[StrategyRule(),lead]
    }
    public func validate()throws {
        guard plans.count==3,planNames.count==3,planNames.allSatisfy({!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.count<=80}),(0..<3).contains(editingSlot),(0..<3).contains(kickoffSlot),
              (1...30).contains(cooldownMinutes),rules.count<=12,Set(rules.map(\.id)).count==rules.count,
              rules.allSatisfy({(0...120).contains($0.fromMinute) && ($0.fromMinute...120).contains($0.throughMinute) && (1...10).contains($0.margin) && (0..<3).contains($0.target)}) else {throw LabError("临场策略需有三套方案；检查时间、比分条件、切换间隔和目标方案。")}
    }
}

extension Workspace {
    public var strategyPlans:[Tactic] {
        guard let strategy=matchStrategy,strategy.plans.count==3,strategy.plans.indices.contains(strategy.editingSlot) else{return [tactic]}
        var plans=strategy.plans;plans[strategy.editingSlot]=tactic
        for i in plans.indices {
            if strategy.planNames.indices.contains(i) {plans[i].name=strategy.planNames[i]}
            if plans[i].slots.count==tactic.slots.count {for j in tactic.slots.indices {plans[i].slots[j].playerID=tactic.slots[j].playerID}}
            var setup=plans[i].setup
            setup.conditions=tactic.setup.conditions;setup.gameSetPieces=tactic.setup.gameSetPieces;setup.setPieces=tactic.setup.setPieces
            plans[i].configuration=setup
        }
        return plans
    }
    public mutating func createStrategy() {if matchStrategy==nil {matchStrategy=MatchStrategy(tactic:tactic)}}
    public mutating func selectStrategyPlan(_ index:Int) {
        guard (0..<3).contains(index) else{return}
        createStrategy();let plans=strategyPlans
        let teamName=tactic.name
        matchStrategy!.plans=plans;matchStrategy!.editingSlot=index;tactic=plans[index];tactic.name=teamName
    }
    public var startingTactic:Tactic {
        guard let s=matchStrategy,s.enabled,strategyPlans.indices.contains(s.kickoffSlot) else{return tactic}
        var plan=strategyPlans[s.kickoffSlot];plan.name=tactic.name;return plan
    }
    public var lockedStrategy:MatchStrategy? {
        guard var s=matchStrategy else{return nil}
        s.plans=strategyPlans.map(\.lockedContent);s.editingSlot=0
        return s
    }
}

public struct NativeTacticInput:Codable,Equatable {
    public let name:String
    public let mentality:Int
    public let formation:String
    public let defendingFormation:String
    public let instructions:[NativeInstructionInput]
    public var phases:[[NativeCellInput]]
    public let extraTeamBits:String?
    public init(_ team:NativeTeamInput) {
        name=team.name;mentality=team.mentality;formation=team.formation;defendingFormation=team.defendingFormation
        instructions=team.instructions;phases=team.phases;extraTeamBits=team.extraTeamBits
    }
}
public struct NativeStrategyRule:Codable,Equatable {
    public let id:String
    public let fromMinute:Int
    public let throughMinute:Int
    public let condition:Int
    public let margin:Int
    public let target:Int
    public let label:String
    public init(_ rule:StrategyRule) {
        id=rule.id.uuidString;fromMinute=rule.fromMinute;throughMinute=rule.throughMinute
        condition=rule.condition.code;margin=rule.margin;target=rule.target;label=rule.summary
    }
}
public struct NativeMatchStrategy:Codable,Equatable {
    public let kickoffSlot:Int
    public let cooldownMinutes:Int
    public let returnToKickoff:Bool
    public var plans:[NativeTacticInput]
    public let rules:[NativeStrategyRule]
    public init(workspace:Workspace,opponent:Workspace)throws {
        let strategy=workspace.matchStrategy!;try strategy.validate()
        kickoffSlot=strategy.kickoffSlot;cooldownMinutes=strategy.cooldownMinutes;returnToKickoff=strategy.returnToKickoff
        plans=try workspace.strategyPlans.map {NativeTacticInput(try NativeTeamInput(players:workspace.players,tactic:$0,opponent:opponent))}
        rules=strategy.rules.filter(\.enabled).map(NativeStrategyRule.init)
    }
    public func target(minute:Int,difference:Int)->(Int,String)? {
        for rule in rules where minute>=rule.fromMinute && minute<=rule.throughMinute {
            if ScoreCondition.allCases[rule.condition].matches(difference,margin:rule.margin){return(rule.target,rule.id)}
        }
        return returnToKickoff ? (kickoffSlot,"fallback"):nil
    }
}
