import Foundation
import CryptoKit

public enum TacticGrouping: String, CaseIterable, Identifiable {
    case exact = "完整战术", shape = "双阶段阵型"
    public var id:String {rawValue}
}
public enum MatchVenue: String, CaseIterable, Identifiable {
    case all = "全部主客场", home = "主场", away = "客场"
    public var id:String {rawValue}
}

extension NativeTeamInput {
    private func sameTactic(as other:Self,grouping:TacticGrouping)->Bool {
        guard strategy==other.strategy else{return false}
        if grouping == .shape {return phases.map{$0.map(\.position)}==other.phases.map{$0.map(\.position)}}
        return mentality==other.mentality && extraTeamBits==other.extraTeamBits && instructions==other.instructions && phases==other.phases && setPieces==other.setPieces
    }
    /// Identity-free execution data. Dictionary keys are strings so sortedKeys
    /// produces a stable digest; arrays preserve native slot/priority order.
    public func tacticKey(_ grouping:TacticGrouping = .exact)->String {
        let cells=phases.map {phase in phase.map {cell -> [String:Any] in
            if grouping == .shape {return ["position":cell.position]}
            return ["position":cell.position,"role":cell.role,"instructions":cell.instructions.sorted(),"targetPlayer":cell.targetPlayer,"targetPosition":cell.targetPosition]
        }}
        var value:[String:Any]=["phases":cells]
        if let strategy {
            value["strategy"]=["kickoff":strategy.kickoffSlot,"cooldown":strategy.cooldownMinutes,"return":strategy.returnToKickoff,
                "plans":strategy.plans.map{withTactic($0).tacticKey(grouping)},
                "rules":strategy.rules.map{["from":$0.fromMinute,"through":$0.throughMinute,"condition":$0.condition,"margin":$0.margin,"target":$0.target]}]
        }
        if grouping == .exact {
            value["mentality"]=mentality
            value["extraTeamBits"]=extraTeamBits ?? String(repeating:"0",count:32)
            value["instructions"]=instructions.sorted{$0.group<$1.group}.map{["group":$0.group,"value":Int($0.value)]}
            value["setPieces"]=["routines":setPieces.routines.map{$0.map{r -> [String:Any] in
                ["frequency":r.frequency,"strategy":r.strategy,"swing":r.swing,"groups":r.groups,"backups":r.backups,"priority":r.priority]
            }},"priorities":setPieces.priorities,"throwStyles":setPieces.throwStyles]
        }
        let data=try! JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
        return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
    }
    public var shapeLabel:String {
        if let strategy {return "动态策略 · "+strategy.plans.map(\.formation).joined(separator:" → ")}
        func label(_ phase:Int,_ name:String)->String {
            if name != "自定义" {return name}
            return phases[phase].map{c in NativeCatalog.positions.first{$0.mask==c.position}?.id ?? "?"}.joined(separator:"·")
        }
        return label(0,formation)+" / "+label(1,defendingFormation)
    }
    public var startingAbility:Double {Double(players.prefix(11).reduce(UInt32(0)){$0+($1.profile["11"] ?? 0)})/Double(max(1,min(11,players.count)))}

    fileprivate func cachedKey(_ grouping:TacticGrouping,id:UUID,cache:inout [UUID:(Self,String)])->String {
        if let previous=cache[id],sameTactic(as:previous.0,grouping:grouping) {return previous.1}
        let key=tacticKey(grouping);cache[id]=(self,key);return key
    }
}

public struct TacticPerformance:Identifiable {
    public let id:String
    public let ownKey:String
    public let opponentKey:String
    public let opponentShape:String
    public var games=0,wins=0,draws=0,losses=0,goalsFor=0,goalsAgainst=0,homeGames=0,awayGames=0
    public var opponents:Set<String>=[]
    public var ownAbilityTotal=0.0,opponentAbilityTotal=0.0,opponentAbilityMin=Double.infinity,opponentAbilityMax = -Double.infinity
    public var xgFor=0.0,xgAgainst=0.0,xgGames=0
    public var reports:[OriginalMatchReport]=[]
    public var focusSides:[UInt32:Int]=[:]
    public var impact:TacticalImpact {TacticalImpact(reports,focusSides:focusSides)}
    public var winRate:Double {Double(wins)/Double(max(1,games))}
    public var pointsPerGame:Double {Double(wins*3+draws)/Double(max(1,games))}
    public var ownAbility:Double {ownAbilityTotal/Double(max(1,games))}
    public var opponentAbility:Double {opponentAbilityTotal/Double(max(1,games))}
    public var xgDifference:Double? {xgGames>0 ? (xgFor-xgAgainst)/Double(xgGames):nil}

    /// Every row is derived from committed original-engine reports, never the
    /// current editor. Own tactics always stay separate, even in shape mode.
    public static func aggregate(run:LeagueRun,teamID:UUID,season:Int?=nil,grouping:TacticGrouping = .exact,venue:MatchVenue = .all)->[Self] {
        var values:[String:Self]=[:]
        var ownCache:[UUID:(NativeTeamInput,String)]=[:],opponentCache:[UUID:(NativeTeamInput,String)]=[:]
        for result in run.results where season == nil || result.season==season {
            let side:Int
            if result.fixture.home==teamID {side=0} else if result.fixture.away==teamID {side=1} else {continue}
            if (venue == .home && side != 0) || (venue == .away && side != 1) {continue}
            guard let config=result.report.configuration,config.teams.count==2 else {continue}
            let own=config.teams[side],other=config.teams[1-side]
            let opponentID=side==0 ? result.fixture.away:result.fixture.home
            let ownKey=own.cachedKey(.exact,id:teamID,cache:&ownCache),otherKey=other.cachedKey(grouping,id:opponentID,cache:&opponentCache),key=ownKey+":"+otherKey
            var row=values[key] ?? Self(id:key,ownKey:ownKey,opponentKey:otherKey,opponentShape:other.shapeLabel)
            let gf=result.report.score[side],ga=result.report.score[1-side]
            row.games+=1;row.goalsFor+=gf;row.goalsAgainst+=ga
            row.reports.append(result.report);row.focusSides[result.report.seed]=side
            if gf>ga {row.wins+=1} else if gf==ga {row.draws+=1} else {row.losses+=1}
            if side==0 {row.homeGames+=1} else {row.awayGames+=1}
            row.opponents.insert(other.name)
            row.ownAbilityTotal+=own.startingAbility;row.opponentAbilityTotal+=other.startingAbility
            row.opponentAbilityMin=min(row.opponentAbilityMin,other.startingAbility);row.opponentAbilityMax=max(row.opponentAbilityMax,other.startingAbility)
            if let a=result.report.teams.first(where:{$0.side==side})?.statistics["xg"],let b=result.report.teams.first(where:{$0.side==1-side})?.statistics["xg"] {
                row.xgFor+=a;row.xgAgainst+=b;row.xgGames+=1
            }
            values[key]=row
        }
        return values.values.sorted {a,b in a.games != b.games ? a.games>b.games:a.id<b.id}
    }
}
