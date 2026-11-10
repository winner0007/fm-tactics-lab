import Foundation

public enum SetPieceGroup:String,CaseIterable,Codable,Identifiable {
    case aerial="争顶威胁",box="禁区威胁",recovery="留守防守",creator="创造者"
    public var id:String { rawValue }
    public var attributes:[String] {
        switch self {
        case .aerial: return ["jumping_reach","heading","strength"]
        case .box: return ["off_the_ball","anticipation","finishing"]
        case .recovery: return ["pace","positioning","tackling"]
        case .creator: return ["passing","vision","first_touch"]
        }
    }
}
public struct SetPiecePersonnel:Codable,Equatable {
    public var takers:[UUID] = []
    public var priority:[SetPieceGroup] = SetPieceGroup.allCases
    public var rankings:[String:[UUID]] = [:]
    public var duties:[String:[String]] = [:]
    public init() {}
    public static func initial(_ kind:SetPieceKind) -> Self {
        var p=Self()
        p.duties = kind.defending ? ["争顶威胁":["盯人","盯人","盯人"],"禁区威胁":["保护近点","保护远点","区域保护"],"留守防守":["区域保护","封堵禁区外"],"创造者":["留前反击","留前反击"]] : ["争顶威胁":["冲击近点","冲击远点"],"禁区威胁":["冲击中路","冲击中路","冲击远点"],"留守防守":["留守防反","留守防反"],"创造者":["禁区外接应","短传接应"]]
        return p
    }
    public mutating func suggest(players:[Player],kind:SetPieceKind) {
        // Transparent editor aid only. Not FM's private role suitability formula.
        func sorted(_ keys:[String]) -> [UUID] {
            players.filter { p in keys.allSatisfy { p.attributes[$0] != nil } }.sorted { a,b in
                func score(_ p:Player) -> Int { keys.allSatisfy{p.attributes[$0] != nil} ? keys.reduce(0){$0+(p.attributes[$1] ?? 0)} : -1 }
                if score(a)==score(b) {return a.id.uuidString<b.id.uuidString};return score(a)>score(b)
            }.map(\.id)
        }
        for group in SetPieceGroup.allCases { rankings[group.rawValue]=sorted(group.attributes) }
        let key = kind == .penalty ? "penalty_taking" : (kind == .attackingThrow ? "long_throws" : (kind == .attackingCorner ? "corners" : "free_kick_taking"))
        takers=sorted([key])
    }
    public func activeTaker(slots:[Slot]) -> UUID? { takers.first { id in slots.contains{$0.playerID==id} } }
    public func resolve(slots:[Slot],kind:SetPieceKind) -> [UUID:String] {
        let available=Set(slots.filter{$0.id != 0}.map(\.playerID))
        var used=Set<UUID>(),result:[UUID:String]=[:]
        if !kind.defending,let taker=activeTaker(slots:slots) {used.insert(taker)}
        for group in priority {
            var candidates=(rankings[group.rawValue] ?? []).filter{available.contains($0) && !used.contains($0)}
            for task in duties[group.rawValue] ?? [] where !candidates.isEmpty {
                let id=candidates.removeFirst();used.insert(id);result[id]=task
            }
        }
        return result
    }
    public func validate(ids:Set<UUID>,kind:SetPieceKind) throws {
        let lists=[takers]+Array(rankings.values)
        guard priority.count==4,Set(priority)==Set(SetPieceGroup.allCases),
              Set(rankings.keys).isSubset(of:Set(SetPieceGroup.allCases.map(\.rawValue))),
              Set(duties.keys).isSubset(of:Set(SetPieceGroup.allCases.map(\.rawValue))),
              lists.allSatisfy({Set($0).count==$0.count && Set($0).isSubset(of:ids)}),
              duties.values.flatMap({$0}).count<=10,
              duties.values.flatMap({$0}).allSatisfy({kind.tasks.contains($0)}) else {throw LabError("定位球人员顺序、职责优先级或分工无效。")}
    }
}

extension SetPieceRoutine {
    public func effectiveTaker(slots:[Slot]) -> UUID? {
        if let personnel {return personnel.activeTaker(slots:slots)}
        return [primaryTaker,backupTaker].compactMap{$0}.first { id in slots.contains{$0.playerID==id} }
    }
    public func effectiveTasks(slots:[Slot],kind:SetPieceKind) -> [Int:String] {
        guard let personnel else {return tasks}
        let resolved=personnel.resolve(slots:slots,kind:kind)
        return Dictionary(uniqueKeysWithValues:slots.compactMap { slot in resolved[slot.playerID].map{(slot.id,$0)} })
    }
}
