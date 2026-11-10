import Foundation

public enum CSV {
    public static func parse(_ source: String) throws -> [[String]] {
        let input = source.replacingOccurrences(of: "\u{feff}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closed = false
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i+1 < chars.count && chars[i+1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == "," || c == "\n" {
                row.append(field); field = ""; closed = false
                if c == "\n" { if row.contains(where: { !$0.isEmpty }) { rows.append(row) }; row = [] }
            } else if c == "\"" {
                guard field.isEmpty && !closed else { throw LabError("CSV 引号格式无效。") }
                quoted = true
            } else {
                guard !closed else { throw LabError("CSV 结束引号后存在多余字符。") }
                field.append(c)
            }
            i += 1
        }
        guard !quoted else { throw LabError("CSV 存在未闭合的引号。") }
        if !field.isEmpty || !row.isEmpty || closed { row.append(field); rows.append(row) }
        guard let header = rows.first, !header.isEmpty, Set(header).count == header.count else { throw LabError("CSV 表头为空或包含重复列。") }
        guard rows.allSatisfy({ $0.count == header.count }) else { throw LabError("CSV 各行的列数不一致。") }
        return rows
    }

    public static func records(_ source: String) throws -> [[String: String]] {
        let rows = try parse(source)
        return rows.dropFirst().map { Dictionary(uniqueKeysWithValues: zip(rows[0], $0)) }
    }

    public static func players(_ source: String) throws -> [Player] {
        let rows = try records(source)
        guard (11...100).contains(rows.count) else { throw LabError("球员 CSV 需要 11–100 行球员。") }
        return try rows.enumerated().map { index, row in
            let name = (row["name"] ?? row["姓名"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let position = row["position"] ?? row["位置"] ?? ""
            guard !name.isEmpty && name.count <= 80 && !position.isEmpty else { throw LabError("第 \(index+2) 行缺少姓名或位置。") }
            var attributes: [String: Int] = [:]
            for a in Attribute.allCases {
                guard let value = Int(row[a.key] ?? row[a.rawValue] ?? ""), (1...20).contains(value) else { throw LabError("第 \(index+2) 行的\(a.rawValue)必须是 1–20 的整数。") }
                attributes[a.key] = value
            }
            for a in PlayerAttribute.all where attributes[a.id] == nil {
                if let raw = row[a.id] ?? row[a.title], !raw.isEmpty {
                    guard let value=Int(raw), (1...20).contains(value) else { throw LabError("第 \(index+2) 行的\(a.title)需为 1–20 或留空。") }
                    attributes[a.id]=value
                }
            }
            var player=Player(name:name,position:position,attributes:attributes)
            if let foot=row["preferred_foot"], !foot.isEmpty {
                guard ["左脚","右脚","双脚"].contains(foot) else { throw LabError("惯用脚请填写左脚、右脚、双脚或留空。") }
                player.preferredFoot=foot
            }
            return player
        }
    }

    public static func encode(_ rows: [[String]]) -> String {
        "\u{feff}" + rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    public static func playerTemplate() -> String {
        encode([["name","position","preferred_foot"] + PlayerAttribute.all.map(\.id)] + Workspace.example().players.map { player in [player.name,player.position,player.preferredFoot ?? ""] + PlayerAttribute.all.map { player.attributes[$0.id].map(String.init) ?? "" } })
    }
}
