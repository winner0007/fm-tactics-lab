import Foundation

public struct InstructionDefinition: Identifiable {
    public let id: String
    public let title: String
    public let section: String
    public let options: [String]
    public var defaultValue: String { options[0] }
    public static let team: [InstructionDefinition] = [
        .init(id:"buildUp",title:"后场组织",section:"有球",options:["均衡","从后场组织","直接向前"]),
        .init(id:"focus",title:"进攻侧重",section:"有球",options:["均衡","左路","右路","中路","两翼"]),
        .init(id:"crosses",title:"传中方式",section:"有球",options:["混合传中","低平球","高球","快速传中"]),
        .init(id:"finalThird",title:"最后三区",section:"有球",options:["均衡","耐心组织入禁区","增加射门","争取定位球"]),
        .init(id:"overlap",title:"边路套上",section:"有球",options:["按角色执行","左侧套上","右侧套上","两侧套上","内线接应"]),
        .init(id:"freedom",title:"创造自由",section:"有球",options:["均衡","更有纪律","更多自由"]),
        .init(id:"loss",title:"丢失球权",section:"转换",options:["按局势应对","立即反抢","回撤重组"]),
        .init(id:"recovery",title:"夺回球权",section:"转换",options:["按局势应对","快速反击","控制球权"]),
        .init(id:"keeperTempo",title:"门将出球时机",section:"转换",options:["均衡","快速发球","放慢节奏"]),
        .init(id:"keeperTarget",title:"门将出球目标",section:"转换",options:["混合","中后卫","边后卫","组织核心","锋线"]),
        .init(id:"block",title:"压迫起点",section:"无球",options:["中位防守","高位压迫","低位防守"]),
        .init(id:"trap",title:"逼抢方向",section:"无球",options:["均衡","迫向边路","迫向中路"]),
        .init(id:"tackle",title:"抢断方式",section:"无球",options:["标准","谨慎出脚","更强硬"]),
        .init(id:"marking",title:"盯防",section:"无球",options:["标准","更紧密"]),
        .init(id:"keeperPress",title:"阻止门将短传",section:"无球",options:["按局势应对","积极阻止"])
    ]
    public static let player: [InstructionDefinition] = [
        .init(id:"risk",title:"传球风险",section:"有球",options:["遵循球队","更冒险","更稳妥"]),
        .init(id:"dribble",title:"盘带",section:"有球",options:["遵循角色","更多盘带","减少盘带"]),
        .init(id:"shoot",title:"射门",section:"有球",options:["遵循角色","更多射门","减少射门"]),
        .init(id:"movement",title:"跑动",section:"有球",options:["遵循角色","更多前插","保持位置","自由跑位"]),
        .init(id:"press",title:"个人逼抢",section:"无球",options:["遵循球队","更积极","更谨慎"]),
        .init(id:"mark",title:"个人盯人",section:"无球",options:["遵循球队","更紧密"]),
        .init(id:"tackle",title:"个人抢断",section:"无球",options:["遵循球队","谨慎出脚","更强硬"])
    ]
}

public enum SetPieceKind: String, Codable, CaseIterable, Identifiable {
    case attackingCorner="进攻角球", defendingCorner="防守角球", attackingFreeKick="进攻任意球", defendingFreeKick="防守任意球", attackingThrow="进攻界外球", defendingThrow="防守界外球", penalty="点球"
    public var id:String { rawValue }
    public var defending:Bool { [.defendingCorner,.defendingFreeKick,.defendingThrow].contains(self) }
    public var deliveries:[String] {
        switch self {
        case .attackingCorner: return ["近点","远点","中路","短角球"]
        case .attackingFreeKick: return ["直接射门","传向近点","传向远点","短传配合"]
        case .attackingThrow: return ["短传","长距离掷入","快速开出"]
        case .penalty: return ["按主罚顺序"]
        default: return ["混合防守","区域防守","人盯人"]
        }
    }
    public var tasks:[String] {
        if defending { return ["区域保护","盯人","保护近点","保护远点","封堵禁区外","留前反击"] }
        return ["留守防反","冲击近点","冲击远点","冲击中路","禁区外接应","短传接应"]
    }
}
public enum SetPieceSide:String,Codable,CaseIterable,Identifiable { case left="左侧",right="右侧"; public var id:String { rawValue } }

public struct SetPieceRoutine:Codable,Equatable {
    public var delivery:String
    public var primaryTaker:UUID?
    public var backupTaker:UUID?
    public var tasks:[Int:String]
    public var notes:String
    public var swing:String? = nil
    public var personnel:SetPiecePersonnel? = nil
    public var changeAfterMiss:Bool? = nil
    public var throwZones:[String:String]? = nil
    public static func initial(_ kind:SetPieceKind) -> SetPieceRoutine {
        SetPieceRoutine(delivery:kind.deliveries[0],tasks:Dictionary(uniqueKeysWithValues:(1..<11).map { ($0,kind.tasks[$0 <= 3 ? 0 : (($0-3)%kind.tasks.count)]) }),notes:"")
    }
}

public enum FatigueLevel:String,Codable,CaseIterable,Identifiable {
    case unknown="未知",fresh="无累积疲劳",normal="一般",tired="疲劳",exhausted="非常疲劳"
    public var id:String { rawValue }
}
public struct MatchConditions:Codable,Equatable {
    public var custom = false
    public var condition = 100
    public var sharpness = 100
    public var fatigue:FatigueLevel = .fresh
    public var fatigueRaw:UInt16? = nil
    public var morale = 20
    public var cohesion = 80
    public var executionEnabled = false
    public var understanding = 80
    public var buyIn = 80
    public var oppositionKnowledge = 80
    public init() {}
}

public struct MarkTarget:Codable,Equatable {
    public var playerID:UUID? = nil
    public var position:String? = nil
    public init() {}
}

public struct PlayerBackground:Codable,Equatable {
    public var personality = ""
    public var relationshipNotes = ""
    public var traits:[String:Int] = [:]
    public init() {}
    public static let traitNames = ["职业素养","忠诚","体育精神","情绪控制","抗压","雄心","适应性"]
}

public struct TacticalConfiguration:Codable,Equatable {
    public var nativeExtraTeamBits:String? = nil
    public var nativeDuties:[String:String]? = nil
    public var nativeMentality:Int? = nil
    public var nativeTeam:[Int:UInt32]? = nil
    public var nativePlayers:[String:[Int:UInt32]]? = nil
    public var markTargets:[String:MarkTarget]? = nil
    public var gameSetPieces:GameSetPieces? = nil
    public var team:[String:String] = [:]
    public var players:[String:[String:String]] = [:]
    public var setPieces:[String:SetPieceRoutine] = [:]
    public var conditions = MatchConditions()
    public init() {}
    public func routine(_ kind:SetPieceKind,_ side:SetPieceSide) -> SetPieceRoutine { setPieces[Self.key(kind,side)] ?? .initial(kind) }
    public var legacyInstructionLines:[String] {
        let teamLines=InstructionDefinition.team.compactMap {d in team[d.id].flatMap{$0==d.defaultValue ? nil:d.title+"："+$0}}
        let playerLines=players.keys.sorted().flatMap {key in InstructionDefinition.player.compactMap {d in players[key]?[d.id].flatMap{$0==d.defaultValue ? nil:key+" · "+d.title+"："+$0}}}
        return teamLines+playerLines
    }
    public var hasLegacyInstructions:Bool {!legacyInstructionLines.isEmpty}
    public static func key(_ kind:SetPieceKind,_ side:SetPieceSide) -> String { kind.rawValue+":"+(kind == .penalty ? "统一" : side.rawValue) }
    public static func playerKey(_ slot:Int,_ phase:Phase) -> String { "\(slot):\(phase.rawValue)" }

    public func validate(playerIDs:Set<UUID>) throws {
        try FMFTacticFields.validateExtras(nativeExtraTeamBits)
        guard (nativeDuties ?? [:]).allSatisfy({FMFTacticFields.duties.contains(UInt64($0.value) ?? UInt64.max)}) else {throw LabError("未知角色职责任务位。") }
        try gameSetPieces?.validate(ids:playerIDs,complete:false)
        guard nativeMentality == nil || (1...7).contains(nativeMentality!) else {throw LabError("比赛心态无效。")}
        for (id,value) in nativeTeam ?? [:] {
            guard NativeCatalog.teamInstructions.contains(where:{$0.id==id && $0.options.contains(where:{$0.id==value})}) else {throw LabError("球队指令无效。")}
        }
        for (_,values) in nativePlayers ?? [:] {for (id,value) in values {
            guard NativeCatalog.playerInstructions.contains(where:{$0.id==id && $0.options.contains(where:{$0.id==value})}) else {throw LabError("个人指令无效。")}
        }}
        func validOptions(_ values:[String:String],_ definitions:[InstructionDefinition]) -> Bool {
            values.allSatisfy { key,value in definitions.contains { $0.id==key && $0.options.contains(value) } }
        }
        let playerKeys=Set((0..<11).flatMap { slot in Phase.allCases.map { Self.playerKey(slot,$0) } })
        guard Set((nativeDuties ?? [:]).keys).isSubset(of:playerKeys),Set((nativePlayers ?? [:]).keys).isSubset(of:playerKeys),Set((markTargets ?? [:]).keys).isSubset(of:playerKeys),(markTargets ?? [:]).values.allSatisfy({target in target.position == nil || NativeCatalog.positions.contains(where:{$0.id == target.position})}) else {throw LabError("个人指令位置无效。")}
        guard validOptions(team,InstructionDefinition.team), players.allSatisfy({ key,values in playerKeys.contains(key) && validOptions(values,InstructionDefinition.player.filter { key.hasSuffix($0.section=="有球" ? Phase.possession.rawValue : Phase.defending.rawValue) }) }) else { throw LabError("球队或球员指令含有不支持的选项。") }
        let keys=Set(SetPieceKind.allCases.flatMap { kind in SetPieceSide.allCases.map { Self.key(kind,$0) } })
        guard Set(setPieces.keys).isSubset(of:keys) else { throw LabError("定位球方案类型无效。") }
        for kind in SetPieceKind.allCases {
            for side in SetPieceSide.allCases {
                let routine=routine(kind,side)
                if let personnel=routine.personnel {try personnel.validate(ids:playerIDs,kind:kind)}
                guard routine.swing == nil || ["混合","内旋","外旋"].contains(routine.swing!) else {throw LabError("定位球旋转方向无效。")}
                if let zones=routine.throwZones {
                    guard zones.allSatisfy({ ["后场","中场","前场"].contains($0.key) && ["保留球权","沿边线推进","传入禁区","长距离掷入"].contains($0.value) }) else {throw LabError("界外球区域设置无效。")}
                }
                let takers=[routine.primaryTaker,routine.backupTaker].compactMap { $0 }
                guard kind.deliveries.contains(routine.delivery), Set(takers).count==takers.count, Set(takers).isSubset(of:playerIDs),
                      Set(routine.tasks.keys).isSubset(of:Set(1..<11)),routine.tasks.values.allSatisfy({kind.tasks.contains($0)}) else { throw LabError("定位球主罚人或任务无效。") }
            }
        }
        guard [conditions.condition,conditions.sharpness,conditions.cohesion,conditions.understanding,conditions.buyIn,conditions.oppositionKnowledge].allSatisfy({ (0...100).contains($0) }), (1...20).contains(conditions.morale) else { throw LabError("比赛状态超出允许范围。") }
    }
}

extension Tactic {
    public var setup:TacticalConfiguration { configuration ?? TacticalConfiguration() }
}
