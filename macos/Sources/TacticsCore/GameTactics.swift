import Foundation

public struct OpponentPlan:Codable,Equatable {
    public var players:[Player]
    public var tactic:Tactic
    public var source:String
    public var baseline:Tactic?
    public var baselinePlayers:[Player]?
    public var baselineSource:String?
    public var teamManagement:TeamManagement? = nil
    public var matchStrategy:MatchStrategy? = nil
    public static func example() -> Self {
        var w=Workspace.example(includeOpponent:false)
        for i in w.players.indices {w.players[i].name="对手 "+w.players[i].name}
        var random=SystemRandomNumberGenerator()
        _=w.applyAbility(.professional,scope:.team,using:&random)
        w.tactic.name="对手 4-2-3-1";w.tactic.apply(.fourTwoThreeOne,phase:.possession);w.tactic.apply(.fourFourTwo,phase:.defending)
        return Self(players:w.players,tactic:w.tactic,source:"自定义对手 · 职业档次 8–13")
    }
    public var workspace:Workspace {Workspace(teamManagement:teamManagement,matchStrategy:matchStrategy,players:players,tactic:tactic,baseline:baseline,baselinePlayers:baselinePlayers,baselineRosterSource:baselineSource,rosterSource:source)}
    public init(_ w:Workspace) {players=w.players;tactic=w.tactic;source=w.rosterSource;baseline=w.baseline;baselinePlayers=w.baselinePlayers;baselineSource=w.baselineRosterSource;teamManagement=w.teamManagement;matchStrategy=w.matchStrategy}
    private init(players:[Player],tactic:Tactic,source:String) {self.players=players;self.tactic=tactic;self.source=source}
}

extension Slot {
    public func position(_ phase:Phase) -> NativePosition {
        let explicit=phase == .possession ? possessionPosition:defendingPosition
        return explicit.map{NativeCatalog.position($0)} ?? NativeCatalog.nearest(point(phase),goalkeeper:id==0)
    }
    public func roleID(_ phase:Phase) -> String? {phase == .possession ? possessionRole:defendingRole}
}
extension Tactic {
    public var gameMentality:Int {setup.nativeMentality ?? min(7,max(1,mentality+1))}
    public func role(_ slot:Int,_ phase:Phase) -> NativeRole {
        let positions=slots.map{$0.position(phase).id},p=slots[slot].position(phase).id
        let allowed=NativeCatalog.allowedRoles(positions:positions,position:p,phase:phase)
        return allowed.first{$0.id==slots[slot].roleID(phase)} ?? NativeCatalog.defaultRole(position:p,phase:phase,positions:positions)
    }
    public mutating func setRole(_ roleID:String,slot:Int,phase:Phase) {
        var cfg=setup;cfg.nativeDuties?[TacticalConfiguration.playerKey(slot,phase)]=nil;configuration=cfg
        if phase == .possession {slots[slot].possessionRole=roleID}else{slots[slot].defendingRole=roleID}
        normalizeRoles(phase)
    }
    public mutating func normalizeRoles(_ phase:Phase) {
        var config=setup
        for i in slots.indices {
            let r=role(i,phase),p=slots[i].position(phase).id
            if slots[i].roleID(phase) != r.id {config.nativeDuties?[TacticalConfiguration.playerKey(i,phase)]=nil}
            if phase == .possession {slots[i].possessionRole=r.id}else{slots[i].defendingRole=r.id}
            let key=TacticalConfiguration.playerKey(i,phase)
            let filtered=config.nativePlayers?[key]?.filter{_,v in v==0 || NativeCatalog.policy(position:p,role:r,option:v)==0}
            config.nativePlayers?[key]=filtered
        }
        configuration=config
    }
    /// Preserve older freeform boards by snapping each player to the nearest
    /// unoccupied native position. Never silently put two slots in one position.
    public mutating func normalizePositions() {
        for phase in Phase.allCases {
            var used=Set<String>()
            for i in slots.indices {
                let old=slots[i],point=old.point(phase)
                let candidates=NativeCatalog.positions.filter{($0.id=="GK") == (i==0) && !used.contains($0.id)}
                let pos=candidates.first{$0.id==old.position(phase).id} ?? candidates.min{hypot($0.point.x-point.x,$0.point.y-point.y)<hypot($1.point.x-point.x,$1.point.y-point.y)}!
                used.insert(pos.id)
                if phase == .possession {slots[i].possession=pos.point;slots[i].possessionPosition=pos.id}
                else {slots[i].defending=pos.point;slots[i].defendingPosition=pos.id}
            }
            normalizeRoles(phase)
        }
    }
    public mutating func setPosition(_ position:String,slot:Int,phase:Phase) {
        guard (slot==0)==(position=="GK"),NativeCatalog.positions.contains(where:{$0.id==position}) else{return}
        let old=slots[slot].position(phase)
        if let other=slots.firstIndex(where:{$0.id != slot && $0.position(phase).id==position}) {
            // Upstream desktopMove swaps entire cells in the edited phase.
            // Player identity and the other phase stay unchanged.
            if phase == .possession {
                slots[other].possession=old.point;slots[other].possessionPosition=old.id
                let r=slots[other].possessionRole;slots[other].possessionRole=slots[slot].possessionRole;slots[slot].possessionRole=r
                slots[slot].possession=NativeCatalog.position(position).point;slots[slot].possessionPosition=position
            } else {
                slots[other].defending=old.point;slots[other].defendingPosition=old.id
                let r=slots[other].defendingRole;slots[other].defendingRole=slots[slot].defendingRole;slots[slot].defendingRole=r
                slots[slot].defending=NativeCatalog.position(position).point;slots[slot].defendingPosition=position
            }
            var config=setup
            let a=TacticalConfiguration.playerKey(slot,phase),b=TacticalConfiguration.playerKey(other,phase)
            let duty=config.nativeDuties?[a],otherDuty=config.nativeDuties?[b];config.nativeDuties?[a]=otherDuty;config.nativeDuties?[b]=duty
            let pi=config.nativePlayers?[a],target=config.markTargets?[a],otherPI=config.nativePlayers?[b],otherTarget=config.markTargets?[b]
            config.nativePlayers?[a]=otherPI;config.nativePlayers?[b]=pi
            config.markTargets?[a]=otherTarget;config.markTargets?[b]=target
            configuration=config
            return
        }
        guard old.id != position else{return}
        let p=NativeCatalog.position(position)
        if phase == .possession {slots[slot].possession=p.point;slots[slot].possessionPosition=position;formation="自定义"}
        else {slots[slot].defending=p.point;slots[slot].defendingPosition=position;defensiveFormation="自定义"}
        normalizeRoles(phase)
    }
}
