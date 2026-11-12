import Foundation

public struct OriginalGoal:Codable,Equatable,Identifiable {
    public let side:Int
    public let nativeID:UInt32
    public let assistID:UInt32?
    public let tick:Int
    /// Native final-result category: ordinary / own goal / penalty.
    public let type:Int
    public let minute:Int
    public let added:Int
    public var id:String {"\(tick):\(side):\(nativeID)"}
    public var timeLabel:String {"\(minute)"+(added>0 ? "+\(added)":"")+"′"}
    public var method:String {Self.methods.indices.contains(type) ? Self.methods[type]:"未分类"}
    public static let methods=["非点球进球","乌龙球","点球"]
    public var timeBand:Int {min(5,max(0,(max(1,minute)-1)/15))}
}

public struct OriginalStrategySwitch:Codable,Equatable,Identifiable {
    public let side:Int
    public let from:Int
    public let to:Int
    public let ruleID:String
    public let tick:Int
    public let clock:Int
    public let elapsedClock:Int
    public let score:[Int]
    public let xg:[Double]
    public let readbackVerified:Bool
    public var statistics:[[String:Double]]? = nil
    public var id:String {"\(tick):\(side)"}
    public var timeLabel:String {String(format:"%d:%02d",clock/240,(clock%240)/4)}
}

extension OriginalMatchReport {
    public func playerName(_ id:UInt32)->String {roster?.first{$0.nativeID==id}?.name ?? "球员 #\(id)"}
    public func validateAnalysis()throws {
        let dynamic=configuration?.teams.contains{$0.strategy != nil}==true
        guard analysisVersion != nil else {
            guard goals==nil,strategyEvents==nil,!dynamic else {throw LabError("比赛明细缺少格式版本或临场切换记录。")};return
        }
        guard [1,2].contains(analysisVersion),let goals,let switches=strategyEvents,Set(goals.map(\.id)).count==goals.count,
              goals.count==score.reduce(0,+) else {throw LabError("终场进球明细不完整。")}
        for side in 0...1 {
            guard goals.filter({$0.side==side}).count==score[side] else {throw LabError("终场进球明细与比分不一致。")}
            for player in players.filter({$0.side==side}) {
                guard player.statistics["goals"]==Double(goals.filter{$0.side==side && $0.nativeID==player.nativeID && $0.type != 1}.count),
                      player.statistics["assists"]==Double(goals.filter{$0.side==side && $0.assistID==player.nativeID}.count) else {throw LabError("进球、助攻明细与球员合计不一致。")}
            }
        }
        for goal in goals {
            guard (0...1).contains(goal.side),(0...2).contains(goal.type),(0...120).contains(goal.minute),(0...30).contains(goal.added),
                  (0...finalTick).contains(goal.tick),players.contains(where:{$0.side==(goal.type==1 ? 1-goal.side:goal.side) && $0.nativeID==goal.nativeID}),
                  goal.assistID.map({id in goal.type != 1 && id != goal.nativeID && players.contains{$0.side==goal.side && $0.nativeID==id}}) ?? true else {throw LabError("进球时间、类型或球员身份无效。")}
        }
        var active=configuration?.teams.map{$0.strategy?.kickoffSlot ?? 0} ?? [0,0],last=[-100000,-100000],tick=0
        for event in switches {
            guard (0...1).contains(event.side),let strategy=configuration?.teams[event.side].strategy,
                  event.tick>=tick,event.tick<finalTick,event.clock>=0,event.clock<=finalClock,event.elapsedClock>=event.clock,event.elapsedClock<=(timeline.last?.elapsedClock ?? 0),
                  event.score.count==2,event.score.allSatisfy({(0...100).contains($0)}),event.xg.count==2,event.xg.allSatisfy({$0.isFinite && (0...100).contains($0)}),event.readbackVerified,
                  event.from==active[event.side],event.to != event.from,event.elapsedClock-last[event.side]>=strategy.cooldownMinutes*240,
                  let target=strategy.target(minute:event.clock/240,difference:event.score[event.side]-event.score[1-event.side]),target.0==event.to,target.1==event.ruleID else {throw LabError("临场切换记录与策略条件不一致。")}
            active[event.side]=event.to;last[event.side]=event.elapsedClock;tick=event.tick
        }
        if analysisVersion==2 {
            let keys=Self.segmentCounters
            var previous=[[String:Double](),[String:Double]()]
            let snapshots=switches.map(\.statistics)+[Optional((0...1).map{side in teams.first{$0.side==side}?.statistics ?? [:]})]
            for snapshot in snapshots {
                guard let snapshot,snapshot.count==2 else{throw LabError("临场统计快照缺失。")}
                for side in 0...1 {
                    for key in keys {
                        guard let value=snapshot[side][key],value.isFinite,value>=0,value.rounded()==value,value>=(previous[side][key] ?? 0) else{throw LabError("临场统计快照无效：\(key)。")}
                    }
                    try validateStatRelations(snapshot[side],row:side+1)
                }
                previous=snapshot
            }
        }
    }
    public static let segmentCounters=["shots","shots_on_target","passes","completed_passes","crosses","completed_crosses","possession_ticks"]
}

public struct AnalysisBar:Identifiable {
    public let label:String
    public let side:Int
    public let count:Int
    public var id:String {"\(label):\(side)"}
}
public struct TacticalImpact {
    public let matches:[OriginalMatchReport]
    public let focusSides:[UInt32:Int]
    public init(_ matches:[OriginalMatchReport],focusSides:[UInt32:Int]=[:]) {self.matches=matches;self.focusSides=focusSides}
    public func nativeSide(_ side:Int,report:OriginalMatchReport)->Int {focusSides[report.seed]==1 ? 1-side:side}
    public func mean(_ key:String,side:Int)->Double? {
        let values=matches.compactMap{r in key=="goals" ? Double(r.score[nativeSide(side,report:r)]):r.teams.first{$0.side==nativeSide(side,report:r)}?.statistics[key]}
        return values.isEmpty ? nil:values.reduce(0,+)/Double(values.count)
    }
    public var detailed:[OriginalMatchReport] {matches.filter{$0.goals != nil}}
    public static let timeBands=["1–15","16–30","31–45+","46–60","61–75","76–90+"]
    public var goalDistribution:[AnalysisBar] {(0...5).flatMap{n in (0...1).map{side in AnalysisBar(label:n==5 ? "5+":"\(n)",side:side,count:matches.filter{min(5,$0.score[nativeSide(side,report:$0)])==n}.count)}}}
    public var timing:[AnalysisBar] {Self.timeBands.enumerated().flatMap{i,label in (0...1).map{side in AnalysisBar(label:label,side:side,count:detailed.reduce(0){total,r in total+(r.goals ?? []).filter{$0.side==nativeSide(side,report:r) && $0.timeBand==i}.count})}}}
    public var methods:[AnalysisBar] {OriginalGoal.methods.enumerated().flatMap{i,label in (0...1).map{side in AnalysisBar(label:label,side:side,count:detailed.reduce(0){total,r in total+(r.goals ?? []).filter{$0.side==nativeSide(side,report:r) && $0.type==i}.count})}}}
    public func ratio(_ numerator:String,_ denominator:String,side:Int)->Double? {
        let valid=matches.compactMap {r -> (Double,Double)? in
            let actual=nativeSide(side,report:r),stats=r.teams.first{$0.side==actual}?.statistics ?? [:]
            let scored=r.players.filter{$0.side==actual}.compactMap{$0.statistics["goals"]}
            let numeratorValue=numerator=="scoring_goals" ? (scored.isEmpty ? nil:scored.reduce(0,+)):(numerator=="goals" ? Double(r.score[actual]):stats[numerator])
            guard let n=numeratorValue,let d=stats[denominator] else{return nil}
            return(n,d)
        }
        let sum=valid.reduce(0){$0+$1.1};return sum>0 ? valid.reduce(0){$0+$1.0}/sum:nil
    }
    public func scoringRate(side:Int)->Double? {matches.isEmpty ? nil:Double(matches.filter{$0.score[nativeSide(side,report:$0)]>0}.count)/Double(matches.count)}
    public var scores:[(String,Int)] {Dictionary(grouping:matches,by:{"\($0.score[nativeSide(0,report:$0)]):\($0.score[nativeSide(1,report:$0)])"}).map{($0.key,$0.value.count)}.sorted{$0.1==$1.1 ? $0.0<$1.0:$0.1>$1.1}}
}

public struct StrategyUsage:Identifiable {
    public let tacticKey:String
    public let slot:Int
    public let name:String
    public var matches=0,entries=0,goalsFor=0,goalsAgainst=0
    public var minutes=0.0,xgFor=0.0,xgAgainst=0.0
    public var measuredMinutes=0.0
    public var statistics:[String:Double]=[:],opponentStatistics:[String:Double]=[:]
    public var id:String {tacticKey+":\(slot)"}
    public func per90(_ key:String)->Double? {measuredMinutes>0 ? (statistics[key] ?? 0)*90/measuredMinutes:nil}
    public func ratio(_ part:String,_ total:String)->Double? {
        guard measuredMinutes>0,let d=statistics[total],d>0,let n=statistics[part] else{return nil};return n/d
    }
    public var possession:Double? {
        let own=statistics["possession_ticks"] ?? 0,other=opponentStatistics["possession_ticks"] ?? 0
        return own+other>0 ? own/(own+other):nil
    }
    public static func aggregate(_ reports:[OriginalMatchReport],side:Int,focusSides:[UInt32:Int]=[:])->[Self] {
        var groups:[String:[Self]]=[:],order:[String]=[]
        for report in reports {
            let side=focusSides[report.seed]==1 ? 1-side:side
            guard let team=report.configuration?.teams[side],let strategy=team.strategy,
                  let events=report.strategyEvents,let goals=report.goals,let end=report.timeline.last else{continue}
            let key=team.tacticKey()
            if groups[key]==nil {order.append(key);groups[key]=strategy.plans.enumerated().map{Self(tacticKey:key,slot:$0.offset,name:$0.element.name)}}
            var rows=groups[key]!
            var slot=strategy.kickoffSlot,startTick=0,startClock=0,xg=[0.0,0.0],used=Set<Int>()
            var previousStats=[[String:Double](),[String:Double]()]
            func segment(tick:Int,clock:Int,values:[Double],stats:[[String:Double]]?) {
                guard clock>startClock else{return};used.insert(slot);rows[slot].entries+=1
                rows[slot].minutes+=Double(clock-startClock)/240
                rows[slot].xgFor+=values[side]-xg[side];rows[slot].xgAgainst+=values[1-side]-xg[1-side]
                for goal in goals where goal.tick>=startTick && goal.tick<tick {if goal.side==side{rows[slot].goalsFor+=1}else{rows[slot].goalsAgainst+=1}}
                if report.analysisVersion==2,let stats,stats.count==2 {
                    rows[slot].measuredMinutes+=Double(clock-startClock)/240
                    for key in OriginalMatchReport.segmentCounters {
                        rows[slot].statistics[key,default:0]+=(stats[side][key] ?? 0)-(previousStats[side][key] ?? 0)
                        rows[slot].opponentStatistics[key,default:0]+=(stats[1-side][key] ?? 0)-(previousStats[1-side][key] ?? 0)
                    }
                    previousStats=stats
                }
            }
            for event in events where event.side==side {segment(tick:event.tick,clock:event.elapsedClock,values:event.xg,stats:event.statistics);slot=event.to;startTick=event.tick;startClock=event.elapsedClock;xg=event.xg}
            segment(tick:report.finalTick+1,clock:end.elapsedClock,values:end.xg,stats:(0...1).map{s in report.teams.first{$0.side==s}?.statistics ?? [:]})
            for slot in used {rows[slot].matches+=1}
            groups[key]=rows
        }
        return order.flatMap{groups[$0] ?? []}
    }
}
