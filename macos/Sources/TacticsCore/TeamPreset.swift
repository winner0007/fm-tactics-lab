import Foundation

/// A reusable, independent team snapshot, not an FM tactic or editor database.
public struct TeamPreset: Codable, Equatable, Identifiable {
    public var schema = "tactics-lab-mac/team-preset/1"
    public var id = UUID()
    public var name: String
    public var savedAt = Date()
    public var plan: Workspace

    public init(name: String, plan: Workspace) throws {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var team = plan
        team.opponent = nil
        team.baseline = nil; team.baselinePlayers = nil; team.baselineRosterSource = nil
        self.plan = try team.validated(includeOpponent: false)
        _ = try validated()
    }

    public func validated() throws -> Self {
        guard schema == "tactics-lab-mac/team-preset/1",
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80,
              savedAt.timeIntervalSince1970.isFinite,
              plan.opponent == nil, plan.baseline == nil, plan.baselinePlayers == nil,
              plan.baselineRosterSource == nil else { throw LabError("阵容方案格式无效；名称需为 1–80 个字，文件只能包含一支球队。") }
        var result = self
        result.plan = try plan.validated(includeOpponent: false)
        return result
    }

    public var data: Data {
        get throws {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(validated())
        }
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 10_000_000 else { throw LabError("阵容方案超过 10 MB。") }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
}
