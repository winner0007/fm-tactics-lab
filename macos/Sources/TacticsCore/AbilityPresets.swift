import Foundation

public enum AbilityTier: String, Codable, CaseIterable, Identifiable {
    case random = "随机", amateur = "业余", semiProfessional = "半职业", professional = "职业", national = "享誉国内", continental = "洲际", international = "国际"
    public var id: String { rawValue }
    public var range: ClosedRange<Int> {
        switch self {
        case .random: return 1...20
        case .amateur: return 3...7
        case .semiProfessional: return 5...10
        case .professional: return 8...13
        case .national: return 11...16
        case .continental: return 13...18
        case .international: return 15...20
        }
    }
    public var rangeLabel: String { "\(range.lowerBound)–\(range.upperBound)" }
    public var detail: String { "相关属性在 \(rangeLabel) 内按位置抽取；隐藏属性与性格独立生成" }
    public var menuTitle: String { rawValue + " · " + rangeLabel }

}

public enum AbilityScope: Equatable {
    case team, position(String), individual(UUID)
    public func contains(_ player: Player) -> Bool {
        switch self {
        case .team: return true
        case .individual(let id): return player.id == id
        case .position(let position): return player.positionKeys.contains {key in
            key==position || (["DC","DM","MC","AMC","ST"].contains(position) && key.hasPrefix(position))
        }
        }
    }
}

extension Player {
    public var positionKeys: [String] {
        position.uppercased().components(separatedBy:CharacterSet(charactersIn:",;/|、，；").union(.whitespacesAndNewlines)).filter { !$0.isEmpty }
    }

}

extension Workspace {
    public var positionChoices: [String] { Array(Set(players.flatMap(\.positionKeys))).sorted() }
    @discardableResult public mutating func applyAbility<R: RandomNumberGenerator>(_ tier: AbilityTier, scope: AbilityScope, using random: inout R) -> Int {
        var count = 0
        for i in players.indices where scope.contains(players[i]) {
            let keeper=players[i].positionKeys.contains("GK")
            players[i].nativeAttributes=nil;players[i].nativeProfile=nil;players[i].sourceIdentity=nil
            let important=RandomPlayerProfile.strengths(players[i].positionKeys)
            for attribute in PlayerAttribute.all {
                let value:Int
                if attribute.group=="隐藏" || ["eccentricity","punching","aggression","flair","leadership"].contains(attribute.id) {
                    value=Int.random(in:1...20,using:&random)
                } else if attribute.group=="门将" && !keeper {
                    value=Int.random(in:1...min(5,tier.range.upperBound),using:&random)
                } else {
                    let a=Int.random(in:tier.range,using:&random),b=Int.random(in:tier.range,using:&random)
                    value=important.contains(attribute.id) ? max(a,b):min(a,b)
                }
                players[i].attributes[attribute.id]=value
            }
            var background=players[i].background ?? PlayerBackground()
            background.personality="随机实验性格"
            background.relationshipNotes=""
            for name in PlayerBackground.traitNames {background.traits[name]=Int.random(in:1...20,using:&random)}
            players[i].background=background
            players[i].preferredFoot=["左脚","右脚","右脚","右脚","双脚"].randomElement(using:&random)
            players[i].abilityPreset = tier
            count += 1
        }
        return count
    }
}

/// Synthetic distributions for controlled experiments, not official CA weights.
public enum RandomPlayerProfile {
    public static func strengths(_ positions:[String])->Set<String> {
        var result=Set<String>()
        for p in positions {
            let fields:[String]
            if p=="GK" {fields=["handling","reflexes","one_on_ones","aerial_reach","command_of_area","communication","positioning","concentration","agility"]}
            else if p.hasPrefix("DC") {fields=["marking","tackling","heading","jumping_reach","strength","positioning","anticipation","concentration","bravery"]}
            else if ["DR","DL","WBR","WBL"].contains(p) {fields=["pace","stamina","acceleration","crossing","tackling","work_rate","positioning"]}
            else if p.hasPrefix("DM") {fields=["tackling","positioning","anticipation","passing","decisions","teamwork","stamina"]}
            else if ["AML","AMR","ML","MR"].contains(p) {fields=["pace","acceleration","dribbling","crossing","off_the_ball","technique","agility"]}
            else if p.hasPrefix("AMC") {fields=["passing","vision","technique","first_touch","decisions","off_the_ball","dribbling"]}
            else if p.hasPrefix("ST") {fields=["finishing","off_the_ball","anticipation","composure","acceleration","heading","first_touch"]}
            else {fields=["passing","vision","decisions","first_touch","teamwork","stamina","technique"]}
            result.formUnion(fields)
        }
        return result
    }
}
