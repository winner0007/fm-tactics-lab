import Foundation

public enum TacticSelection:String,Codable,CaseIterable,Identifiable {
    case fixed="指定战术",random="随机战术",originalAI="原版 AI 制定"
    public var id:String {rawValue}
}
public struct NativeCoachRequest:Codable,Equatable {
    public var name:String
    public var source:String
    public var parameters:[Int]?
    public var formationCodes:[Int]?
    public init(_ coach:CoachProfile?) {
        name=coach?.name ?? "原版测试教练"
        parameters=coach?.parameters;formationCodes=coach?.formationCodes
        source=parameters==nil ? "原版测试载体的教练参数；姓名仅作标签":coach!.source
    }
}
public struct GeneratedTeamTactic:Codable,Equatable {
    public let side:Int
    public let order:[Int]
    public let fields:FMFTacticFields
    public let coachProfile:String
}
public struct TacticGenerationReceipt:Codable,Equatable {
    public let event:String
    public let accepted:Bool
    public let teams:[GeneratedTeamTactic]
    public let seed:UInt32
    public let configurationSHA256:String
    public let tick:Int
    public func resolve(_ input:NativeScenario)throws->NativeScenario {
        guard accepted,event=="native_tactics_generated",tick==0,configurationSHA256==input.sha256,teams.map(\.side)==[0,1] else {throw LabError("AI 战术生成回执与输入不一致。")}
        var result=input
        for side in 0...1 {
            let row=teams[side],original=input.teams[side]
            guard Set(row.order)==Set(original.players.indices),row.order.count==original.players.count,row.coachProfile.count==104,row.coachProfile.allSatisfy(\.isHexDigit) else {throw LabError("AI 首发中出现未提供的球员。")}
            if original.generation==nil {
                guard row.order==Array(original.players.indices),row.fields == (try FMFTacticFields.expected(original)) else {throw LabError("AI 生成过程改变了指定战术。")}
                continue
            }
            if let expected=original.generation?.parameters {
                guard row.coachProfile==expected.map({String(format:"%02x",$0)}).joined() else {throw LabError("AI 教练参数回读不一致。")}
            }
            result.teams[side]=try row.fields.applying(to:original,order:row.order)
        }
        // Target indices and taker lists follow identities when AI reorders a roster.
        for side in 0...1 {
            let opponentOrder=teams[1-side].order
            func remap(_ cells:[[NativeCellInput]])->[[NativeCellInput]] {cells.map{$0.map{c in var v=c;if v.targetPlayer != 255 {v.targetPlayer=UInt32(opponentOrder.firstIndex(of:Int(v.targetPlayer))!)};return v}}}
            result.teams[side].phases=remap(result.teams[side].phases)
            if var strategy=result.teams[side].strategy {
                for i in strategy.plans.indices {strategy.plans[i].phases=remap(strategy.plans[i].phases)}
                result.teams[side].strategy=strategy
            }
        }
        return try result.validated()
    }
}
extension FMFTacticFields {
    func applying(to original:NativeTeamInput,order:[Int])throws->NativeTeamInput {
        guard (1...7).contains(mentality),mapping.count==11,Set(mapping)==Set(0..<11),phases.count==2,phases.allSatisfy({$0.count==11}) else {throw LabError("AI 双阶段战术不完整。")}
        var team=original,bits=try Self.bytes(teamBits)
        team.preparationSource="原版 AI · "+(original.generation?.name ?? "")+" · "+(original.generation?.source ?? "")
        team.mentality=mentality;team.generation=nil;team.strategy=nil
        team.players=order.map{original.players[$0]}
        team.setPieces.priorities=original.setPieces.priorities.mapValues{$0.map{order.firstIndex(of:$0)!}}
        team.instructions=try NativeCatalog.teamInstructions.map {g in
            let selected=g.options.filter{$0.bit>0 && bits[$0.bit/8] & (1<<($0.bit%8)) != 0}
            guard selected.count<=1 else {throw LabError("AI 返回了互斥球队指令。")}
            return NativeInstructionInput(group:g.id,value:(selected.first ?? g.defaultOption).id)
        }
        for o in NativeCatalog.teamInstructions.flatMap(\.options) where o.bit>0 {bits[o.bit/8] &= ~(1<<(o.bit%8))}
        team.extraTeamBits=bits.allSatisfy{$0==0} ? nil:bits.map{String(format:"%02x",$0)}.joined()
        let known=NativeCatalog.playerInstructions.flatMap(\.options).filter{$0.id>0}.map(\.id)
        team.phases=try (0..<2).map {phase in try (0..<11).map{i in
            let c=phases[phase][phase==0 ? i:mapping[i]]
            guard let flags=UInt64(c.flags),flags & ~known.reduce(UInt64(0),{$0 | (1<<$1)})==0 else {throw LabError("AI 返回未知球员指令。")}
            return NativeCellInput(position:c.position,role:c.role,instructions:known.filter{flags & (1<<$0) != 0},targetPlayer:c.targetPlayer,targetPosition:c.targetPosition)
        }}
        func formation(_ cells:[NativeCellInput])->String {
            let positions=cells.compactMap{c in NativeCatalog.positions.first{$0.mask==c.position}?.id}
            return Formation.allCases.first{Set($0.positions)==Set(positions)}?.rawValue ?? "AI 自定义"
        }
        team.formation=formation(team.phases[0]);team.defendingFormation=formation(team.phases[1])
        return team
    }
}
public struct PreparedTactics:Codable,Equatable {
    public let requested:NativeScenario
    public let receipt:TacticGenerationReceipt
    public let engineSHA256:String
    public var resolved:NativeScenario {get throws{try receipt.resolve(requested)}}
    public init(requested:NativeScenario,receipt:TacticGenerationReceipt,engineSHA256:String) {self.requested=requested;self.receipt=receipt;self.engineSHA256=engineSHA256}
}

extension Workspace {
    public var tacticSelection:TacticSelection {management.tacticLocked ? .fixed:management.selection ?? .fixed}
    public func selectedTactics()->Workspace {
        guard tacticSelection == .random else{return self}
        var result=self
        // A saved seed draws one shape per team; all matches in the comparison
        // use that same shape. It never changes attributes or team membership.
        let seed=management.tacticSeed ?? 42
        let formation=Formation.allCases[Int(seed)%Formation.allCases.count]
        result.matchStrategy=nil
        result.tactic.apply(formation,phase:.possession);result.tactic.apply(formation,phase:.defending)
        var config=result.tactic.setup;config.nativeMentality=2+Int(seed/31)%5
        config.nativeTeam=[:];config.nativeExtraTeamBits=nil;config.nativePlayers=[:];config.nativeDuties=[:];config.markTargets=[:]
        // Vary independent controls; preserve set-piece routines and condition.
        for group in NativeCatalog.teamInstructions where ["传球方式","比赛节奏","进攻宽度"].contains(group.label) {
            config.nativeTeam?[group.id]=group.options[(Int(seed)/max(1,group.id+1))%group.options.count].id
        }
        result.tactic.configuration=config
        return result
    }
}

extension Workspace {
    public func copyingTactics(from source:Workspace)throws->Workspace {
        var next=self
        let players=tactic.slots.map(\.playerID)
        func copy(_ template:Tactic)->Tactic {
            var t=template
            for i in t.slots.indices {t.slots[i].playerID=players[i]}
            var config=t.setup
            config.conditions=tactic.setup.conditions
            // Takers and marking targets refer to people, not transferable slots.
            config.gameSetPieces?.priorities=[:];config.markTargets=[:]
            if var pi=config.nativePlayers {for key in pi.keys {pi[key]?[14]=nil};config.nativePlayers=pi}
            t.configuration=config;return t
        }
        next.tactic=copy(source.tactic)
        next.matchStrategy=source.matchStrategy
        if next.matchStrategy != nil {
            for i in next.matchStrategy!.plans.indices {next.matchStrategy!.plans[i]=copy(next.matchStrategy!.plans[i])}
        }
        next.management.selection = .fixed;next.management.tacticSource="统一指定 · "+source.tactic.name
        try checkReplacement(next);return try next.validated(includeOpponent:false)
    }
}
