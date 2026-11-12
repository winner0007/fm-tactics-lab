import Foundation

/// All match means use only reports containing that metric. Ratios pool counts,
/// never average match percentages. Missing measurements remain nil.
public enum TacticalMetric:String,CaseIterable,Identifiable {
    case possession,passes,completedPasses,passRate,crosses,completedCrosses,crossRate,shots,shotsOnTarget,goals,xg,conversion,scoringRate
    public var id:String {rawValue}
    public var title:String {
        switch self {
        case .possession:return "场均控球率"
        case .passes:return "场均传球"
        case .completedPasses:return "场均成功传球"
        case .passRate:return "传球成功率"
        case .crosses:return "场均传中"
        case .completedCrosses:return "场均成功传中"
        case .crossRate:return "传中成功率"
        case .shots:return "场均射门"
        case .shotsOnTarget:return "场均射正"
        case .goals:return "场均进球"
        case .xg:return "场均 xG"
        case .conversion:return "射门转化率"
        case .scoringRate:return "有进球场次占比"
        }
    }
    public var percent:Bool {[.possession,.passRate,.crossRate,.conversion,.scoringRate].contains(self)}
    public func value(_ impact:TacticalImpact,side:Int)->Double? {
        switch self {
        case .completedPasses:return impact.mean("completed_passes",side:side)
        case .completedCrosses:return impact.mean("completed_crosses",side:side)
        case .shotsOnTarget:return impact.mean("shots_on_target",side:side)
        case .passRate:return impact.ratio("completed_passes","passes",side:side).map{$0*100}
        case .crossRate:return impact.ratio("completed_crosses","crosses",side:side).map{$0*100}
        case .conversion:return impact.ratio("scoring_goals","shots",side:side).map{$0*100}
        case .scoringRate:return impact.scoringRate(side:side).map{$0*100}
        default:return impact.mean(rawValue,side:side)
        }
    }
    public func format(_ value:Double?)->String {value.map{String(format:percent ? "%.1f%%":"%.2f",$0)} ?? "—"}
}

public struct TacticMatchGroup:Identifiable {
    public let id:String
    public let name:String
    public let shape:String
    public var reports:[OriginalMatchReport]
    public var focusSides:[UInt32:Int]
    public var impact:TacticalImpact {TacticalImpact(reports,focusSides:focusSides)}
    public static func aggregate(_ reports:[OriginalMatchReport],focusSides:[UInt32:Int]=[:])->[Self] {
        var groups:[String:Self]=[:],order:[String]=[]
        for report in reports {
            let side=focusSides[report.seed] ?? 0,team=report.configuration?.teams[side]
            let key=team?.tacticKey() ?? "original_fixture"
            if groups[key]==nil {
                order.append(key);groups[key]=Self(id:key,name:team?.name ?? "原版基准战术",shape:team?.shapeLabel ?? "原版内置测试阵容",reports:[],focusSides:[:])
            }
            groups[key]!.reports.append(report);groups[key]!.focusSides[report.seed]=side
        }
        return order.compactMap{groups[$0]}
    }
}
