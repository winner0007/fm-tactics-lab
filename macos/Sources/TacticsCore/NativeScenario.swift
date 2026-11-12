import Foundation
import CryptoKit

public struct NativeScenario:Codable,Equatable {
    public var schemaVersion=1
    public var teams:[NativeTeamInput]
    public var data:Data {let e=JSONEncoder();e.outputFormatting=[.sortedKeys];return try! e.encode(self)}
    public var sha256:String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    public init(workspace:Workspace) throws {
        let w=try workspace.validated().selectedTactics()
        let other=w.opponent!.workspace.selectedTactics()
        var own=try NativeTeamInput(players:w.players,tactic:w.startingTactic,opponent:other)
        var away=try NativeTeamInput(players:other.players,tactic:other.startingTactic,opponent:w)
        if w.tacticSelection == .fixed && w.matchStrategy?.enabled==true {own.strategy=try NativeMatchStrategy(workspace:w,opponent:other)}
        if other.tacticSelection == .fixed && other.matchStrategy?.enabled==true {away.strategy=try NativeMatchStrategy(workspace:other,opponent:w)}
        if w.tacticSelection == .originalAI {own.generation=NativeCoachRequest(w.management.coach)}
        if other.tacticSelection == .originalAI {away.generation=NativeCoachRequest(other.management.coach)}
        if w.tacticSelection == .random {own.preparationSource="随机战术 · 种子 \(w.management.tacticSeed ?? 42)"}
        if other.tacticSelection == .random {away.preparationSource="随机战术 · 种子 \(other.management.tacticSeed ?? 42)"}
        teams=[own,away]
        if own.strategy != nil || away.strategy != nil {schemaVersion=2}
        _ = try validated()
    }
    public func validated()throws->Self {
        guard (1...2).contains(schemaVersion),teams.count==2,(schemaVersion==2)==teams.contains(where:{$0.strategy != nil}) else {throw LabError("比赛配置必须包含两支球队，并声明正确的临场策略格式。")}
        for (side,t) in teams.enumerated() {
            if let coach=t.generation {
                guard t.strategy==nil,!coach.name.isEmpty,coach.name.count<=80 else{throw LabError("AI 战术不能同时使用手动临场方案。")}
                if let profile=coach.parameters {guard profile.count==52,profile.allSatisfy({(0...100).contains($0)}),let codes=coach.formationCodes,codes.count==8,codes.allSatisfy({(0...64).contains($0)}) else{throw LabError("AI 教练参数不完整。")}}
            }
            if let strategy=t.strategy {
                guard strategy.plans.count==3,(0..<3).contains(strategy.kickoffSlot),(1...30).contains(strategy.cooldownMinutes),strategy.rules.count<=12,
                      Set(strategy.rules.map(\.id)).count==strategy.rules.count,
                      strategy.rules.allSatisfy({UUID(uuidString:$0.id) != nil && (0...120).contains($0.fromMinute) && ($0.fromMinute...120).contains($0.throughMinute) && (0..<ScoreCondition.allCases.count).contains($0.condition) && (1...10).contains($0.margin) && (0..<3).contains($0.target)}) else {throw LabError("原版临场策略配置无效。")}
                for plan in strategy.plans {
                    var pair=teams.map {team -> NativeTeamInput in var v=team;v.strategy=nil;return v}
                    pair[side]=t.withTactic(plan)
                    _ = try NativeScenario(teams:pair).validated()
                }
                let kickoff=t.withTactic(strategy.plans[strategy.kickoffSlot])
                guard t.phases==kickoff.phases,t.mentality==kickoff.mentality,t.instructions==kickoff.instructions,t.extraTeamBits==kickoff.extraTeamBits else {throw LabError("开场战术与策略方案不一致。")}
            }
            guard !t.name.isEmpty,(1...7).contains(t.mentality),(11...20).contains(t.players.count),Set(t.players.map(\.id)).count==t.players.count,t.phases.count==2,t.phases.allSatisfy({$0.count==11}),Set(t.instructions.map(\.group))==Set(NativeCatalog.teamInstructions.map(\.id)),t.instructions.count==NativeCatalog.teamInstructions.count else {throw LabError("比赛配置的阵容或球队指令不完整。")}
            for p in t.players {
                guard UUID(uuidString:p.id) != nil,!p.name.isEmpty,p.name.count<=80,p.attributes.count==69,p.attributes.enumerated().allSatisfy({$0.offset<15 ? (0...20).contains($0.element):(1...100).contains($0.element)}),Set(p.profile.keys)==Set((0...22).map(String.init)) else {throw LabError("比赛配置的球员属性无效。")}
                try NativeProfile.validate(p.profile)
            }
            try FMFTacticFields.validateExtras(t.extraTeamBits)
            for ins in t.instructions {guard NativeCatalog.teamInstructions.first(where:{$0.id==ins.group})?.options.contains(where:{$0.id==ins.value})==true else {throw LabError("比赛配置的球队指令无效。")}}
            for (phase,cells) in t.phases.enumerated() {
                for c in cells {guard let flags=UInt64(c.role),FMFTacticFields.duties.contains(flags & ~FMFTacticFields.roleMask) else {throw LabError("未知角色职责。")}}
                let positions=cells.compactMap{c in NativeCatalog.positions.first{$0.mask==c.position}?.id}
                guard positions.count==11,Set(positions).count==11,positions.first=="GK" else {throw LabError("比赛配置位置重复或缺失。")}
                for (i,c) in cells.enumerated() {
                    guard let role=NativeCatalog.allowedRoles(positions:positions,position:positions[i],phase:phase==0 ? .possession:.defending).first(where:{String($0.flags)==String((UInt64(c.role) ?? 0) & FMFTacticFields.roleMask)}),Set(c.instructions).count==c.instructions.count,c.instructions.allSatisfy({$0>0 && NativeCatalog.policy(position:positions[i],role:role,option:$0)==0}) else {throw LabError("比赛配置的角色或个人指令无效。")}
                    let man=c.instructions.contains(34),zone=c.instructions.contains(35)
                    guard (man ? c.targetPlayer<teams[1-side].players.count:c.targetPlayer==255),(zone ? NativeCatalog.positions.contains(where:{$0.mask==c.targetPosition}):c.targetPosition==0) else {throw LabError("指定盯防目标无效。")}
                }
            }
            guard t.setPieces.routines.count==10,t.setPieces.throwStyles.count==3,t.setPieces.throwStyles.allSatisfy({(0...1).contains($0)}) else {throw LabError("定位球配置不完整。")}
            for kind in GameSetPieceKind.allCases {guard (1...3).contains(t.setPieces.routines[kind.id].count) else {throw LabError("定位球套路数量无效。")};for r in t.setPieces.routines[kind.id] {try r.validate(kind)}}
            for (key,list) in t.setPieces.priorities {guard let id=Int(key),(0..<20).contains(id),Set(list).count==list.count,list.allSatisfy({t.players.indices.contains($0)}) else {throw LabError("定位球候选名单无效。")}}
        }
        return self
    }
    private init(teams:[NativeTeamInput]) {self.teams=teams}
}
public struct NativeInstructionInput:Codable,Equatable {public let group:Int;public let value:UInt32}
public struct NativeCellInput:Codable,Equatable {
    public let position:UInt32
    public let role:String
    public let instructions:[UInt32]
    public var targetPlayer:UInt32=255
    public var targetPosition:UInt32=0
}
public struct NativePlayerInput:Codable,Equatable {
    public let id:String
    public let name:String
    public let attributes:[Int]
    public let profile:[String:UInt32]
    public let abilityTier:String
    public var attributeMean:Double {
        let keeper=attributes[0]>=15
        let indices=NativeTeamInput.attributes.filter {key,_ in
            !["dirtiness","injury_proneness","versatility","consistency","important_matches","eccentricity","punching"].contains(key) && (keeper || !["handling","aerial_reach","command_of_area","communication","kicking","throwing","one_on_ones","reflexes","rushing_out"].contains(key))
        }.map(\.value)
        return Double(indices.reduce(0){$0+attributes[$1]})/Double(indices.count)/5
    }
}
public struct NativeTeamInput:Codable,Equatable {
    public var preparationSource:String? = nil
    public var generation:NativeCoachRequest? = nil
    public var extraTeamBits:String? = nil
    public var strategy:NativeMatchStrategy? = nil
    public var name:String
    public var mentality:Int
    public var formation:String
    public var defendingFormation:String
    public var instructions:[NativeInstructionInput]
    public var players:[NativePlayerInput]
    public var phases:[[NativeCellInput]]
    public var setPieces:NativeSetPieceInput
    public let notes:[String]
    public func withTactic(_ plan:NativeTacticInput)->Self {
        var copy=self;copy.strategy=nil;copy.name=plan.name;copy.mentality=plan.mentality
        copy.formation=plan.formation;copy.defendingFormation=plan.defendingFormation
        copy.instructions=plan.instructions;copy.phases=plan.phases;copy.extraTeamBits=plan.extraTeamBits
        return copy
    }
    public init(players roster:[Player],tactic input:Tactic,opponent:Workspace) throws {
        var tactic=input;tactic.normalizePositions()
        let teamName=tactic.name
        if tactic.setup.hasLegacyInstructions {throw LabError("\(teamName)：旧版球队／个人指令仍是草稿。请在球队指令页查看并清除旧稿，使用原版指令重新设置后运行。")}
        extraTeamBits=tactic.setup.nativeExtraTeamBits
        name=teamName;mentality=tactic.gameMentality;formation=tactic.formation;defendingFormation=tactic.defensiveFormation
        instructions=NativeCatalog.teamInstructions.map{g in NativeInstructionInput(group:g.id,value:tactic.teamOption(g).id)}
        let bits=Set(instructions.compactMap{v in NativeCatalog.teamInstructions.first{$0.id==v.group}?.options.first{$0.id==v.value}?.bit})
        for (a,b) in [(25,28),(25,29),(25,30),(26,28),(26,29),(27,28),(27,30)] where bits.contains(a)&&bits.contains(b) {throw LabError("\(teamName)：外侧套上与肋部套上存在冲突，请调整球队指令。")}
        phases=try Phase.allCases.map {phase in
            try tactic.slots.map {slot in
                let position=slot.position(phase),role=tactic.role(slot.id,phase)
                let key=TacticalConfiguration.playerKey(slot.id,phase)
                let values=tactic.setup.nativePlayers?[key] ?? [:]
                var choices:[UInt32]=[]
                var targetPlayer:UInt32=255,targetPosition:UInt32=0
                for g in NativeCatalog.playerInstructions where g.phase==phase {
                    let v=values[g.id] ?? 0
                    if v>0 {
                        guard NativeCatalog.policy(position:position.id,role:role,option:v)==0 else {throw LabError("\(teamName)：\(role.label)不能使用所选个人指令。")}
                        if g.id==14 {
                            let target=tactic.setup.markTargets?[key]
                            if v==34 {
                                let other=Self.matchPlayers(opponent.players,tactic:opponent.tactic)
                                guard let id=target?.playerID,let index=other.firstIndex(where:{$0.id==id}) else {throw LabError("\(teamName)：请为指定盯人选择对方比赛名单中的球员。")}
                                targetPlayer=UInt32(index)
                            } else if v==35 {
                                guard let id=target?.position,let pos=NativeCatalog.positions.first(where:{$0.id==id}) else {throw LabError("\(teamName)：请选择指定盯防的位置。")}
                                targetPosition=pos.mask
                            }
                        }
                        choices.append(v)
                    }
                }
                return NativeCellInput(position:position.mask,role:String(role.flags | (UInt64(tactic.setup.nativeDuties?[key] ?? "0") ?? 0)),instructions:choices,targetPlayer:targetPlayer,targetPosition:targetPosition)
            }
        }
        let squad=Self.matchPlayers(roster,tactic:tactic)
        guard squad.count>=11 else {throw LabError("首发名单不完整。")}
        let conditions=tactic.setup.conditions
        if conditions.custom && conditions.executionEnabled {throw LabError("战术理解、认同与情报尚未完成 Mac 引擎映射，请先关闭执行力实验。")}
        if conditions.custom && ![.fresh,.unknown].contains(conditions.fatigue) && conditions.fatigueRaw==nil {throw LabError("旧版疲劳标签没有对应的游戏原值，请在状态页填写累积疲劳原值。")}
        if conditions.custom && !(25...82).contains(conditions.cohesion) {throw LabError("当前原版测试载体可验证的双方凝聚力范围为 25–82；请在状态页调整，标准值为 80。")}
        players=squad.map {p in
            var attrs=p.nativeAttributes ?? (Array(repeating:1,count:15)+Array(repeating:50,count:54))
            if p.nativeAttributes==nil {for key in p.positionKeys {if let index=Self.positionAttribute[key] {attrs[index]=20}}}
            for (key,index) in Self.attributes {if let value=p.attributes[key],p.nativeAttributes==nil || value != max(1,Int((Double(attrs[index])/5).rounded())) {attrs[index]=value*5}}
            if p.nativeAttributes==nil {
                attrs[39]=p.preferredFoot=="左脚" || p.preferredFoot=="双脚" ? 100:50
                attrs[40]=p.preferredFoot=="左脚" ? 50:100
            }
            for i in 15..<69 where attrs[i]==0 {attrs[i]=50}
            var profile:[String:UInt32]=["0":180,"1":25,"9":0,"10":0,"11":100,"12":5000,"13":5000,"14":5000,"15":UInt32(conditions.custom ? conditions.condition*100:10000),"16":UInt32(conditions.custom ? conditions.sharpness*100:10000),"17":UInt32(conditions.custom ? conditions.sharpness*100:10000),"18":0,"19":75,"20":UInt32(conditions.custom ? conditions.cohesion:80),"21":100,"22":UInt32(conditions.custom ? conditions.morale:20)]
            profile["18"]=conditions.custom ? UInt32(conditions.fatigueRaw ?? 0):0
            for (key,value) in p.nativeProfile ?? [:] {if let field=Int(key),field<=14 || field==19 {profile[key]=value}}
            for (i,trait) in PlayerBackground.traitNames.enumerated() {profile[String(i+2)]=UInt32(p.background?.traits[trait] ?? Int(profile[String(i+2)] ?? 10))}
            return NativePlayerInput(id:p.id.uuidString,name:p.name,attributes:attrs,profile:profile,abilityTier:p.abilityPreset?.rawValue ?? "自定义")
        }
        if !tactic.setup.setPieces.isEmpty && tactic.setup.gameSetPieces==nil {throw LabError("\(teamName)：旧版定位球草图需要核对。请在定位球页采用原版套路设置后运行；旧草图仍保留在方案文件内。")}
        let gameSetPieces=tactic.setup.gameSetPieces ?? GameSetPieces()
        try gameSetPieces.validate(ids:Set(roster.map(\.id)))
        setPieces=NativeSetPieceInput(gameSetPieces,players:players)
        notes=["导入球员保留原始属性与已映射资料；未提供／未解析的属性采用 10。自定义球员熟悉位置为 20，其余为 1。","未提供资料的控制值：年龄 25、身高 180 cm、体重 75 kg、CA 100、声望 5000；无额外习惯动作。能力档次按具体属性分布设置，不等同于 CA。","双方由手动战术控制，首发 11 人及最多 9 名候补；不启用 AI 自动改阵。","战术理解、球员认同与关系备注未写入引擎；未赋予额外默契加成。"]
    }
    public static func matchPlayers(_ roster:[Player],tactic:Tactic)->[Player] {
        let selected=tactic.slots.compactMap{s in roster.first{$0.id==s.playerID}},ids=Set(tactic.slots.map(\.playerID))
        return selected+roster.filter{!ids.contains($0.id)}.prefix(9)
    }
    static let positionAttribute:[String:Int] = ["GK":0,"DL":2,"DC":3,"DCL":3,"DCR":3,"DR":4,"DM":5,"DMC":5,"DML":5,"DMR":5,"ML":6,"MC":7,"MCL":7,"MCR":7,"MR":8,"AML":9,"AMC":10,"AMCL":10,"AMCR":10,"AMR":11,"ST":12,"STL":12,"STR":12,"WBL":13,"WBR":14]
    static let attributes:[String:Int] = ["crossing":15,"dribbling":16,"finishing":17,"heading":18,"long_shots":19,"marking":20,"off_the_ball":21,"passing":22,"penalty_taking":23,"tackling":24,"vision":25,"handling":26,"aerial_reach":27,"command_of_area":28,"communication":29,"kicking":30,"throwing":31,"anticipation":32,"decisions":33,"one_on_ones":34,"positioning":35,"reflexes":36,"first_touch":37,"technique":38,"flair":41,"corners":42,"teamwork":43,"work_rate":44,"long_throws":45,"eccentricity":46,"rushing_out":47,"punching":48,"acceleration":49,"free_kick_taking":50,"strength":51,"stamina":52,"pace":53,"jumping_reach":54,"leadership":55,"dirtiness":56,"balance":57,"bravery":58,"consistency":59,"aggression":60,"agility":61,"important_matches":62,"injury_proneness":63,"versatility":64,"natural_fitness":65,"determination":66,"composure":67,"concentration":68]
}
extension Tactic {
    public func teamOption(_ group:NativeInstruction) -> NativeOption {
        if let id=setup.nativeTeam?[group.id],let option=group.options.first(where:{$0.id==id}) {return option}
        let legacy:[Int:Int]=[1:passing,4:width,9:defensiveLine,10:pressing,21:tempo]
        if let index=legacy[group.id],group.options.count==5 {return group.options[min(4,max(0,index-1))]}
        return group.defaultOption
    }
}
