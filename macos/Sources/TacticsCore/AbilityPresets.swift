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
    public var detail: String { "每人、每项属性分别在 \(rangeLabel) 内抽取；再次应用会重新生成" }
    public var menuTitle: String { rawValue + " · " + rangeLabel }

}

public enum AbilityScope: Equatable {
    case team, position(String), individual(UUID)
    public func contains(_ player: Player) -> Bool {
        switch self {
        case .team: return true
        case .individual(let id): return player.id == id
        case .position(let position): return player.positionKeys.contains(position)
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
            for attribute in PlayerAttribute.all { players[i].attributes[attribute.id] = Int.random(in:tier.range,using:&random) }
            players[i].abilityPreset = tier
            count += 1
        }
        return count
    }
}
