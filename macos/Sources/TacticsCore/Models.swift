import Foundation

public struct LabError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum Phase: String, Codable, CaseIterable, Identifiable {
    case possession = "有球阶段", defending = "无球阶段"
    public var id: String { rawValue }
}

public struct Point: Codable, Equatable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

public enum Assignment: String, Codable, CaseIterable, Identifiable {
    case goalkeeper = "守门", cover = "保护", connect = "串联", width = "拉开", penetrate = "前插"
    public var id: String { rawValue }
}

public enum Attribute: String, CaseIterable, Identifiable {
    case pace = "速度", stamina = "耐力", passing = "传球", decisions = "决断", tackling = "抢断", finishing = "射门"
    public var id: String { rawValue }
    public var key: String {
        switch self {
        case .pace: return "pace"
        case .stamina: return "stamina"
        case .passing: return "passing"
        case .decisions: return "decisions"
        case .tackling: return "tackling"
        case .finishing: return "finishing"
        }
    }
}

public struct Player: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var position: String
    public var attributes: [String: Int]
    public var background: PlayerBackground? = nil
    public var abilityPreset: AbilityTier? = nil
    public var preferredFoot: String? = nil
    public var nativeAttributes:[Int]? = nil
    public var nativeProfile:[String:UInt32]? = nil
    public var sourceIdentity:String? = nil
    public init(name: String, position: String, attributes: [String: Int]) {
        id = UUID(); self.name = name; self.position = position; self.attributes = attributes
    }
    public func value(_ attribute: Attribute) -> Int { attributes[attribute.key] ?? 10 }
}

public struct Slot: Codable, Equatable, Identifiable {
    public var id: Int
    public var playerID: UUID
    public var possession: Point
    public var defending: Point
    public var assignment: Assignment
    public var defensiveAssignment: Assignment
    public var possessionRole:String? = nil
    public var defendingRole:String? = nil
    public var possessionPosition:String? = nil
    public var defendingPosition:String? = nil
    public func point(_ phase: Phase) -> Point { phase == .possession ? possession : defending }
    public func task(_ phase: Phase) -> Assignment { phase == .possession ? assignment : defensiveAssignment }
}

public enum Formation: String, CaseIterable, Identifiable {
    case fourThreeThree = "4-3-3", fourTwoThreeOne = "4-2-3-1", fourFourTwo = "4-4-2", diamond = "4-4-2 菱形", fourOneFourOne = "4-1-4-1", fourThreeOneTwo = "4-3-1-2", fourTwoFour = "4-2-4", threeFourThree = "3-4-3", threeFourTwoOne = "3-4-2-1", threeFiveTwo = "3-5-2", fiveTwoThree = "5-2-3", fiveFourOne = "5-4-1"
    public var id:String {rawValue}
    // The original project's PRESETS, in its goalkeeper/right-to-left slot order.
    public var positions:[String] {
        switch self {
        case .fourThreeThree:return ["GK","DR","DCR","DCL","DL","DMC","MCR","MCL","AMR","AML","ST"]
        case .fourTwoThreeOne:return ["GK","DR","DCR","DCL","DL","DMR","DML","AMR","AMC","AML","ST"]
        case .fourFourTwo:return ["GK","DR","DCR","DCL","DL","MR","MCR","MCL","ML","STR","STL"]
        case .diamond:return ["GK","DR","DCR","DCL","DL","DMC","MCR","MCL","AMC","STR","STL"]
        case .fourOneFourOne:return ["GK","DR","DCR","DCL","DL","DMC","MR","MCR","MCL","ML","ST"]
        case .fourThreeOneTwo:return ["GK","DR","DCR","DCL","DL","MCR","MC","MCL","AMC","STR","STL"]
        case .fourTwoFour:return ["GK","DR","DCR","DCL","DL","MCR","MCL","AMR","AML","STR","STL"]
        case .threeFourThree:return ["GK","DCR","DC","DCL","MR","MCR","MCL","ML","AMR","AML","ST"]
        case .threeFourTwoOne:return ["GK","DCR","DC","DCL","WBR","MCR","MCL","WBL","AMCR","AMCL","ST"]
        case .threeFiveTwo:return ["GK","DCR","DC","DCL","WBR","MCR","MC","MCL","WBL","STR","STL"]
        case .fiveTwoThree:return ["GK","DCR","DC","DCL","WBR","WBL","MCR","MCL","AMR","AML","ST"]
        case .fiveFourOne:return ["GK","DR","DCR","DC","DCL","DL","MR","MCR","MCL","ML","ST"]
        }
    }
    public var points:[Point] {positions.map{NativeCatalog.position($0).point}}
}

public struct Tactic: Codable, Equatable {
    public var name: String
    public var formation: String
    public var defensiveFormation: String
    public var slots: [Slot]
    public var mentality: Int
    public var tempo: Int
    public var pressing: Int
    public var defensiveLine: Int
    public var width: Int
    public var passing: Int
    public var notes: String
    public var configuration: TacticalConfiguration? = nil
    public mutating func apply(_ formation: Formation, phase: Phase) {
        for i in slots.indices {
            let p=formation.positions[i]
            if phase == .possession { slots[i].possession=formation.points[i];slots[i].possessionPosition=p }
            else { slots[i].defending=formation.points[i];slots[i].defendingPosition=p }
        }
        normalizeRoles(phase)
        if phase == .possession { self.formation = formation.rawValue }
        else { defensiveFormation = formation.rawValue }
    }
}

public struct Workspace: Codable, Equatable {
    public var schema = "tactics-lab-mac/5"
    public var opponent:OpponentPlan? = nil
    public var teamManagement:TeamManagement? = nil
    public var matchStrategy:MatchStrategy? = nil
    public var players: [Player]
    public var tactic: Tactic
    public var baseline: Tactic?
    public var baselinePlayers: [Player]? = nil
    public var baselineRosterSource: String? = nil
    public var rosterSource: String

    public static func example(includeOpponent:Bool=true) -> Workspace {
        let positions = Formation.fourThreeThree.positions
        let names = positions.enumerated().map{NativeCatalog.position($0.element).label+String(format:" %02d",$0.offset+1)}
        let players = (0..<11).map { i in
            Player(name: names[i], position: positions[i], attributes: Dictionary(uniqueKeysWithValues: Attribute.allCases.enumerated().map { j, a in (a.key, 10 + (i * 3 + j * 2) % 7) }))
        }
        let points = Formation.fourThreeThree.points
        let slots = (0..<11).map { i in
            Slot(id: i, playerID: players[i].id, possession: points[i], defending: Formation.fourFourTwo.points[i], assignment: i == 0 ? .goalkeeper : (i < 6 ? .cover : (i == 9 ? .penetrate : .connect)), defensiveAssignment: i == 0 ? .goalkeeper : .cover)
        }
        var result=Workspace(players: players, tactic: Tactic(name: "我的 4-3-3 方案", formation: "4-3-3", defensiveFormation: "4-4-2", slots: slots, mentality: 3, tempo: 3, pressing: 3, defensiveLine: 3, width: 3, passing: 3, notes: ""), rosterSource: "内置示例球员 · 可编辑或导入 CSV")
        result.tactic.normalizePositions()
        if includeOpponent {result.opponent=OpponentPlan.example()}
        return result
    }

    public func validated(includeOpponent:Bool=true) throws -> Workspace {
        try matchStrategy?.validate()
        if let coach=management.coach {
            if let parameters=coach.parameters {
                guard parameters.count==52,parameters.allSatisfy({(0...100).contains($0)}),let codes=coach.formationCodes,codes.count==8,codes.allSatisfy({(0...64).contains($0)}) else {throw LabError("教练参数或阵型偏好不完整。")}
            } else if coach.formationCodes != nil {throw LabError("缺少与阵型偏好对应的教练参数。")}
            guard !coach.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,coach.name.count<=80,!coach.id.isEmpty,
                  coach.styleID == nil || (0...9).contains(coach.styleID!) else {throw LabError("主教练姓名或战术偏好无效。")}
        }
        guard ["tactics-lab-mac/1","tactics-lab-mac/2","tactics-lab-mac/3","tactics-lab-mac/4","tactics-lab-mac/5"].contains(schema) else { throw LabError("这是其他格式的方案。当前只支持 Mac 版方案 JSON。") }
        guard (11...100).contains(players.count), Set(players.map(\.id)).count == players.count else { throw LabError("名单需要 11–100 名球员，且标识不能重复。") }
        if let baselinePlayers {
            guard baseline != nil, baselinePlayers.count == players.count,
                  Set(baselinePlayers.map(\.id)) == Set(players.map(\.id)) else { throw LabError("对照方案的球员快照不完整。") }
        }
        for player in players + (baselinePlayers ?? []) {
            try NativeProfile.validate(player.nativeProfile ?? [:])
            if let raw=player.nativeAttributes {guard raw.count==69,raw.enumerated().allSatisfy({(0..<15).contains($0.offset) ? (0...20).contains($0.element):(0...100).contains($0.element)}) else {throw LabError("球员原始属性不完整。")}}
            guard !player.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, player.name.count <= 80,
                  Attribute.allCases.allSatisfy({ (1...20).contains(player.attributes[$0.key] ?? 0) }) else { throw LabError("球员姓名或属性无效，六项属性均需为 1–20。") }
            guard player.attributes.values.allSatisfy({ (1...20).contains($0) }), player.preferredFoot == nil || ["左脚","右脚","双脚"].contains(player.preferredFoot!) else { throw LabError("球员属性或惯用脚无效。") }
            if let background=player.background {
                guard background.traits.allSatisfy({ PlayerBackground.traitNames.contains($0.key) && (1...20).contains($0.value) }) else { throw LabError("性格属性需为 1–20，未知值应留空。") }
            }
        }
        for plan in strategyPlans + [baseline].compactMap({ $0 }) {
            try plan.setup.validate(playerIDs:Set(players.map(\.id)))
            guard !plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  plan.slots.count == 11, plan.slots.map(\.id) == Array(0..<11),
                  Set(plan.slots.map(\.playerID)).count == 11,
                  plan.slots.allSatisfy({ slot in players.contains(where: { $0.id == slot.playerID }) }),
                  [plan.mentality,plan.tempo,plan.pressing,plan.defensiveLine,plan.width,plan.passing].allSatisfy({ (1...5).contains($0) }),
                  plan.slots.allSatisfy({ s in [s.possession,s.defending].allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0.05...0.95).contains($0.x) && (0.05...0.95).contains($0.y) }) }) else { throw LabError("战术配置无效：检查首发、站位和指令范围。") }
        }
        if let opponent { _ = try opponent.workspace.validated(includeOpponent:false) }
        var upgraded=self;upgraded.schema="tactics-lab-mac/5";upgraded.tactic.normalizePositions()
        if includeOpponent && upgraded.opponent==nil {upgraded.opponent=OpponentPlan.example()}
        return upgraded
    }

    public mutating func captureBaseline() {
        baseline = tactic; baselinePlayers = players; baselineRosterSource = rosterSource
    }
    public mutating func restoreBaseline() {
        guard let baseline else { return }
        tactic = baseline
        if let baselinePlayers { players = baselinePlayers }
        if let baselineRosterSource { rosterSource = baselineRosterSource }
    }

    public func differences() -> [String] {
        guard let b = baseline else { return [] }
        let t = tactic
        var rows: [String] = []
        for (name, old, new) in [("比赛心态",b.mentality,t.mentality),("节奏",b.tempo,t.tempo),("逼抢",b.pressing,t.pressing),("防线",b.defensiveLine,t.defensiveLine),("宽度",b.width,t.width),("传球距离",b.passing,t.passing)] where old != new { rows.append("\(name)：\(old) → \(new)") }
        let moved = t.slots.filter { slot in b.slots.first(where: { $0.id == slot.id }) != slot }.count
        if moved > 0 { rows.append("\(moved) 个位置的站位、任务或首发发生变化") }
        if t.setup.team != b.setup.team || t.setup.nativeTeam != b.setup.nativeTeam || t.gameMentality != b.gameMentality { rows.append("比赛心态或球队阶段指令发生变化") }
        if t.setup.players != b.setup.players || t.setup.nativePlayers != b.setup.nativePlayers || t.setup.markTargets != b.setup.markTargets { rows.append("个人指令发生变化") }
        if t.setup.setPieces != b.setup.setPieces || t.setup.gameSetPieces != b.setup.gameSetPieces { rows.append("定位球方案发生变化") }
        if t.setup.conditions != b.setup.conditions { rows.append("比赛状态与磨合条件发生变化") }
        if let baselinePlayers {
            let changed = players.filter { player in baselinePlayers.first(where: { $0.id == player.id }) != player }.count
            if changed > 0 { rows.append("\(changed) 名球员的属性或资料发生变化") }
        }
        return rows
    }
}

public struct Insight: Identifiable {
    public let title: String
    public let detail: String
    public let concern: Bool
    public var id: String { title }
}

public enum Analysis {
    public static func inspect(_ workspace: Workspace) -> [Insight] {
        let t = workspace.tactic
        let outfield = t.slots.filter { $0.id != 0 }.compactMap { slot in workspace.players.first { $0.id == slot.playerID } }
        func mean(_ a: Attribute) -> Double { outfield.reduce(0) { $0 + Double($1.value(a)) } / Double(max(1,outfield.count)) }
        var result: [Insight] = []
        let conditions=t.setup.conditions
        if conditions.custom && t.pressing >= 4 && (conditions.condition < 85 || [.tired,.exhausted].contains(conditions.fatigue)) {
            result.append(Insight(title:"疲劳状态下的高强度逼抢",detail:"实验条件中存在体能不足或累积疲劳。建议单独比较较低逼抢强度；此提示不计算胜率或能力折扣。",concern:true))
        }
        if conditions.custom && conditions.executionEnabled && conditions.understanding < 50 {
            result.append(Insight(title:"新战术仍需磨合",detail:"手动设置的战术理解低于 50。把相同战术在不同磨合水平下分组比较，避免与阵型优劣混为一谈。",concern:true))
        }
        if t.pressing >= 4 && mean(.stamina) < 13 {
            result.append(Insight(title: "高压迫的体能门槛", detail: String(format:"首发非门将平均耐力 %.1f，低于规则参考值 13。先降低一级逼抢，对比下半场表现。",mean(.stamina)), concern: true))
        }
        let defenders = t.slots.filter { $0.id != 0 && $0.defending.y >= 0.65 }.compactMap { slot in workspace.players.first { $0.id == slot.playerID } }
        if t.defensiveLine >= 4, let slow = defenders.min(by: { $0.value(.pace) < $1.value(.pace) }), slow.value(.pace) < 13 {
            result.append(Insight(title: "防线身后的空间", detail: "\(slow.name) 的速度为 \(slow.value(.pace))。高位防线遇到直塞时值得重点测试；试着回收一级防线。", concern: true))
        }
        if t.tempo >= 4 && (mean(.passing) < 13 || mean(.decisions) < 13) {
            result.append(Insight(title: "出球速度与处理能力", detail: String(format:"平均传球 %.1f、决断 %.1f。快节奏可能增加处理压力，可先对比标准节奏。",mean(.passing),mean(.decisions)), concern: true))
        }
        let anchors = t.slots.filter { $0.id != 0 && $0.possession.y >= 0.55 && $0.assignment == .cover }
        if anchors.count < 3 { result.append(Insight(title: "丢球后的保护人数", detail: "有球阶段仅 \(anchors.count) 人处于后场并承担保护任务。考虑保留一名后腰或一侧边后卫。", concern: true)) }
        let wide = t.slots.filter { $0.id != 0 && ($0.possession.x < 0.22 || $0.possession.x > 0.78) }
        if wide.count < 2 { result.append(Insight(title: "边路宽度不足", detail: "球场两侧合计只有 \(wide.count) 个站位。面对密集防守时，可让一侧球员拉开。", concern: true)) }
        for phase in Phase.allCases {
            let crowding = t.slots.enumerated().contains { i, a in t.slots.dropFirst(i+1).contains { b in let p=a.point(phase), q=b.point(phase); return hypot(p.x-q.x,p.y-q.y) < 0.09 } }
            if crowding { result.append(Insight(title: "\(phase.rawValue)站位重叠", detail: "部分球员之间的距离过近。拖开位置，检查是否争用同一条传球线路。", concern: true)) }
        }
        if result.isEmpty { result.append(Insight(title: "当前未触发结构提醒", detail: "已检查体能、高位防线、出球压力、保护人数和站位间距。这并不代表战术已通过比赛验证。", concern: false)) }
        return result
    }
}
