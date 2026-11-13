import Foundation

/// Experiment controls travel with the team, including presets and run snapshots.
public struct TeamManagement: Codable, Equatable {
    public var selection:TacticSelection? = nil
    public var tacticSeed:UInt32? = nil
    public var coach: CoachProfile? = nil
    public var coachLocked = false
    public var tacticLocked = false
    public var tacticSource = "手动设置"
    public init() {}
    public func selectionDescription(inherited:TacticSelection = .fixed)->String {
        switch tacticLocked ? TacticSelection.fixed:selection ?? inherited {
        case .fixed:return "使用工作台方案"+(tacticLocked ? " · 已锁定":"")
        case .random:return "随机战术 · 按球队种子抽取，实验内固定复用"
        case .originalAI:return "原版 AI 赛前制定 · "+(coach?.parameters == nil ? "使用测试教练参数":coach!.name)
        }
    }
    public var workbenchSource:String {tacticSource.replacingOccurrences(of:"未读取存档 AI 战术",with:"未还原存档中的现成战术")}
}

public struct CoachProfile: Codable, Equatable, Identifiable {
    public var parameters:[Int]? = nil
    public var formationCodes:[Int]? = nil
    public var id: String
    public var name: String
    public var source: String
    public var styleID: Int?
    public var primaryFormation: Int?
    public var secondaryFormation: Int?
    public init(id: String = UUID().uuidString, name: String, source: String = "用户指定", styleID: Int? = nil, primaryFormation: Int? = nil, secondaryFormation: Int? = nil) {
        self.id=id;self.name=name;self.source=source;self.styleID=styleID;self.primaryFormation=primaryFormation;self.secondaryFormation=secondaryFormation
    }
    public static let styles = ["控制球权","高位逼抢","密集短传","纵向短传渗透","边路进攻","长传冲吊","流畅反击","直接反击","链式防守","摆大巴"]
    public var styleName: String {styleID.flatMap{Self.styles.indices.contains($0) ? Self.styles[$0]:nil} ?? "偏好未确认"}
}

extension Workspace {
    public var abilitySourceDescription:String {
        let generated=players.filter{$0.abilityPreset != nil}.count
        if generated>0 {return "自定义能力 · \(generated) / \(players.count) 人使用随机档次"}
        if players.contains(where:{$0.sourceIdentity != nil}) {return "使用导入的球员属性"+(rosterSource.contains("DAT 未设定值") ? " · 含 DAT 未设定值补全":"")}
        return "使用当前球员属性"
    }
    public var management: TeamManagement {
        get {teamManagement ?? TeamManagement()}
        set {teamManagement=newValue}
    }
    /// All replacement paths must check the destination's locks, not the incoming
    /// file's flags. Changing a flag alone is allowed; replacing and unlocking in
    /// one operation is not. Lineup and match conditions remain editable.
    public func checkReplacement(_ next: Workspace) throws {
        if management.coachLocked && management.coach != next.management.coach {
            throw LabError("主教练已锁定，请先解锁再更换。")
        }
        if management.tacticLocked && (lockedStrategy != next.lockedStrategy || (matchStrategy==nil && tactic.lockedContent != next.tactic.lockedContent)) {
            throw LabError("战术已锁定，请先解锁再修改阵型、角色、指令或定位球。")
        }
        if let other=opponent,let replacement=next.opponent {try other.workspace.checkReplacement(replacement.workspace)}
        if let other=opponent,next.opponent==nil,other.workspace.management.tacticLocked || other.workspace.management.coachLocked {throw LabError("对手配置已锁定，不能在导入时清除。")}
    }
    public func protectingLocks(in next: Workspace,allowLockChanges:Bool=false)throws->Workspace {
        try checkReplacement(next)
        var value=next
        if !allowLockChanges && (management.coachLocked || management.tacticLocked) {
            value.management.coachLocked=management.coachLocked;value.management.tacticLocked=management.tacticLocked
        }
        if let other=opponent,let replacement=value.opponent {value.opponent=OpponentPlan(try other.workspace.protectingLocks(in:replacement.workspace,allowLockChanges:allowLockChanges))}
        return value
    }
}

extension Tactic {
    /// Personnel may change, but the tactical instructions and set-piece routines
    /// must not. Names, notes, routine IDs and presentation coordinates are labels.
    public var lockedContent: Tactic {
        var copy=self
        copy.name="";copy.notes="";copy.formation="";copy.defensiveFormation=""
        for i in copy.slots.indices {
            copy.slots[i].playerID=UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
            copy.slots[i].possession=copy.slots[i].position(.possession).point
            copy.slots[i].defending=copy.slots[i].position(.defending).point
        }
        var config=copy.setup;config.conditions=MatchConditions()
        do {
            var pieces=config.gameSetPieces ?? GameSetPieces()
            pieces.priorities=[:]
            for key in pieces.routines.keys {
                for i in pieces.routines[key]!.indices {
                    pieces.routines[key]![i].id=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
                    pieces.routines[key]![i].name=""
                }
            }
            config.gameSetPieces=pieces
        }
        for key in config.setPieces.keys {
            config.setPieces[key]?.primaryTaker=nil;config.setPieces[key]?.backupTaker=nil;config.setPieces[key]?.notes=""
        }
        copy.configuration=config
        return copy
    }
}
