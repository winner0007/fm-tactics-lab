import Foundation

public struct MatchRecord: Codable, Equatable, Identifiable {
    public let variant: String
    public let seed: String
    public let opponent: String
    public let venue: String
    public let goalsFor: Int
    public let goalsAgainst: Int
    public let xgFor: Double?
    public let xgAgainst: Double?
    public var statistics: [String:Double]? = nil
    public var pairKey: String { [seed,opponent,venue].joined(separator: "\u{1f}") }
    public var id: String { variant + "\u{1f}" + pairKey }
    public var goalDifference: Double { Double(goalsFor-goalsAgainst) }
    public var points: Double { goalsFor > goalsAgainst ? 3 : (goalsFor == goalsAgainst ? 1 : 0) }
}

public struct Experiment: Codable, Equatable {
    public let source: String
    public let records: [MatchRecord]
    public let excluded: Int
    public let hasContext: Bool
    public var playerRecords: [PlayerMatchRecord]? = nil
    public var variants: [String] { Array(Set(records.map(\.variant))).sorted() }

    public static func load(_ csv: String, source: String) throws -> Experiment {
        let rows = try CSV.records(csv)
        guard !rows.isEmpty && rows.count <= 20000 else { throw LabError("实验 CSV 需要 1–20000 行数据。") }
        var records: [MatchRecord] = [], excluded = 0, seen = Set<String>()
        for (i,row) in rows.enumerated() {
            let status = row["status"] ?? "complete"
            if ["failed","error","cancelled","incomplete"].contains(status) { excluded += 1; continue }
            guard ["complete","completed","success"].contains(status) else { throw LabError("第 \(i+2) 行 status 未识别：\(status)。") }
            let variant = (row["variant"] ?? row["方案"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let seed = row["seed"] ?? row["种子"] ?? ""
            guard !variant.isEmpty, !variant.contains("\u{1f}"), let numericSeed = UInt32(seed),
                  let gf = Int(row["goals_for"] ?? row["主队进球"] ?? ""), let ga = Int(row["goals_against"] ?? row["客队进球"] ?? ""),
                  (0...100).contains(gf), (0...100).contains(ga) else { throw LabError("第 \(i+2) 行的方案、种子或比分无效。") }
            func optionalXG(_ key: String) throws -> Double? {
                guard let s = row[key], !s.isEmpty else { return nil }
                guard let n = Double(s), n.isFinite, (0...100).contains(n) else { throw LabError("第 \(i+2) 行的 \(key) 无效。") }
                return n
            }
            let opponent = row["opponent"] ?? "未记录对手"
            let venue = row["venue"] ?? "home"
            guard !opponent.contains("\u{1f}"), ["home","away"].contains(venue) else { throw LabError("第 \(i+2) 行的对手或主客场无效。") }
            var record = MatchRecord(variant: variant, seed: String(numericSeed), opponent: opponent, venue: venue, goalsFor: gf, goalsAgainst: ga, xgFor: try optionalXG("xg_for"), xgAgainst: try optionalXG("xg_against"))
            var stats:[String:Double]=[:]
            for side in ["for","against"] {
                var sideStats:[String:Double]=[:]
                for metric in StatMetric.team where !["goals","xg"].contains(metric.id) {
                    let value=try metric.parse(row[metric.id+"_"+side],row:i+2)
                    stats[metric.id+"_"+side]=value;sideStats[metric.id]=value
                }
                try validateStatRelations(sideStats,row:i+2)
            }
            if let a=stats["possession_for"],let b=stats["possession_against"],abs(a+b-100)>1 {throw LabError("第 \(i+2) 行双方控球率应相加约为 100；请使用百分数，而非 0–1 比例。")}
            record.statistics=stats.isEmpty ? nil : stats
            guard seen.insert(record.id).inserted else { throw LabError("第 \(i+2) 行重复了同方案、种子、对手和主客场的结果。请按独立批次导入。") }
            records.append(record)
        }
        guard !records.isEmpty else { throw LabError("没有可分析的完整比赛。") }
        return Experiment(source: source, records: records, excluded: excluded, hasContext: rows[0]["opponent"] != nil && rows[0]["venue"] != nil)
    }

    public func summary(_ variant: String) -> MatchSummary {
        let rows = records.filter { $0.variant == variant }
        let n = Double(max(1, rows.count))
        return MatchSummary(count: rows.count, winRate: Double(rows.filter { $0.goalsFor > $0.goalsAgainst }.count)/n,
                            goalsFor: rows.reduce(0) { $0+Double($1.goalsFor) }/n, goalsAgainst: rows.reduce(0) { $0+Double($1.goalsAgainst) }/n,
                            points: rows.reduce(0) { $0+$1.points }/n)
    }

    public func compare(baseline: String, candidate: String) -> PairedComparison {
        guard baseline != candidate else { return PairedComparison(differences: [], unpaired: 0) }
        let a = records.filter { $0.variant == baseline }, b = records.filter { $0.variant == candidate }
        let map = Dictionary(uniqueKeysWithValues: a.map { ($0.pairKey,$0) })
        let differences = b.compactMap { record -> Double? in
            guard let base = map[record.pairKey] else { return nil }
            return record.goalDifference-base.goalDifference
        }
        return PairedComparison(differences: differences, unpaired: a.count+b.count-2*differences.count)
    }
}

public struct MatchSummary {
    public let count: Int
    public let winRate: Double
    public let goalsFor: Double
    public let goalsAgainst: Double
    public let points: Double
}

public struct PairedComparison {
    public let differences: [Double]
    public let unpaired: Int
    public var mean: Double { differences.reduce(0,+)/Double(max(1,differences.count)) }
    // Seeded paired percentile bootstrap. An exploratory interval, not a game-win probability.
    public func interval() -> ClosedRange<Double>? {
        guard differences.count >= 20 else { return nil }
        var rng: UInt64 = 24601
        var samples: [Double] = []
        // Cap work for large CSV files while retaining all pairs in each resample.
        for _ in 0..<1000 {
            var sum = 0.0
            for _ in differences {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                sum += differences[Int((rng >> 32) % UInt64(differences.count))]
            }
            samples.append(sum/Double(differences.count))
        }
        samples.sort()
        return samples[24]...samples[974]
    }
}
