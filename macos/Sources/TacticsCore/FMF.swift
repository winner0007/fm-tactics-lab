import Foundation

public struct FMFCell: Codable, Equatable {
    public let position: UInt32
    public let role: String
    public let flags: String
    public let targetPlayer: UInt32
    public let targetPosition: UInt32
}
public struct FMFTacticFields: Codable, Equatable {
    public static let roleMask: UInt64 = 0xfffffffbf91fffff
    public static let duties: Set<UInt64> = [0,2097152,4194304,8388608,33554432,67108864,17179869184]
    public let mentality: Int
    public let teamBits: String
    public let mapping: [Int]
    public let phases: [[FMFCell]]

    public static func bytes(_ hex: String) throws -> [UInt8] {
        let chars = Array(hex)
        guard chars.count == 32 else { throw LabError("战术球队指令长度无效。") }
        return try stride(from: 0, to: 32, by: 2).map { i in
            guard let byte = UInt8(String(chars[i...i+1]), radix: 16) else { throw LabError("战术球队指令编码无效。") }; return byte
        }
    }
    public static func validateExtras(_ value: String?) throws {
        guard let value else { return }
        let bits = try bytes(value)
        guard NativeCatalog.teamInstructions.flatMap(\.options).allSatisfy({$0.bit == 0 || bits[$0.bit/8] & (1 << ($0.bit%8)) == 0}) else { throw LabError("附加战术位与已命名球队指令冲突。") }
    }
    public static func expected(_ input: NativeTeamInput) throws -> Self {
        var bits = try bytes(input.extraTeamBits ?? String(repeating: "0", count: 32))
        for ins in input.instructions {
            let bit = NativeCatalog.teamInstructions.first{$0.id==ins.group}!.options.first{$0.id==ins.value}!.bit
            if bit > 0 { bits[bit/8] |= 1 << (bit%8) }
        }
        return Self(mentality: input.mentality, teamBits: bits.map{String(format:"%02x",$0)}.joined(), mapping: Array(0..<11), phases: input.phases.map{$0.map{c in FMFCell(position:c.position,role:c.role,flags:String(c.instructions.reduce(UInt64(0)){$0 | (1 << $1)}),targetPlayer:c.targetPlayer,targetPosition:c.targetPosition)}})
    }

    public func applying(to original: Workspace, name: String, opponent: Workspace) throws -> Workspace {
        guard (1...7).contains(mentality), mapping.count == 11, phases.count == 2, phases.allSatisfy({$0.count==11}) else { throw LabError("FMF 战术的双阶段数据不完整。") }
        let order = mapping.enumerated().map{$0.element == 255 ? $0.offset : $0.element}
        guard Set(order) == Set(0..<11) else { throw LabError("FMF 有球／无球对应关系无效。") }
        var result = original, setup = original.tactic.setup
        var bits = try Self.bytes(teamBits)
        setup.nativeMentality = mentality; setup.nativeTeam = [:]; setup.nativePlayers = [:]; setup.nativeDuties = [:]; setup.markTargets = [:]
        setup.team = [:]; setup.players = [:]
        for group in NativeCatalog.teamInstructions {
            let options = group.options.filter{$0.bit > 0 && bits[$0.bit/8] & (1 << ($0.bit%8)) != 0}
            guard options.count <= 1 else { throw LabError("FMF 含互斥的球队指令，无法无损导入。") }
            setup.nativeTeam?[group.id] = (options.first ?? group.defaultOption).id
        }
        for option in NativeCatalog.teamInstructions.flatMap(\.options) where option.bit > 0 { bits[option.bit/8] &= ~(1 << (option.bit%8)) }
        setup.nativeExtraTeamBits = bits.allSatisfy{$0==0} ? nil : bits.map{String(format:"%02x",$0)}.joined()
        let knownPI = NativeCatalog.playerInstructions.flatMap(\.options).reduce(UInt64(0)){$1.id==0 ? $0 : $0 | (1 << $1.id)}
        let opponents = NativeTeamInput.matchPlayers(opponent.players, tactic: opponent.tactic)
        for (phaseIndex,phase) in Phase.allCases.enumerated() {
            for i in 0..<11 {
                let cell = phases[phaseIndex][phaseIndex==0 ? i : order[i]]
                guard let position = NativeCatalog.positions.first(where:{$0.mask==cell.position}),
                      let flags = UInt64(cell.role), Self.duties.contains(flags & ~Self.roleMask),
                      let role = NativeCatalog.roles.first(where:{$0.phase==phase && $0.flags==(flags & Self.roleMask)}),
                      let pi = UInt64(cell.flags), pi & ~knownPI == 0 else { throw LabError("FMF 含尚未映射的位置、角色或个人指令，未修改当前战术。") }
                let key = TacticalConfiguration.playerKey(i,phase)
                setup.nativeDuties?[key] = String(flags & ~Self.roleMask)
                var choices: [Int:UInt32] = [:]
                for group in NativeCatalog.playerInstructions {
                    let values = group.options.filter{$0.id > 0 && pi & (1 << $0.id) != 0}
                    guard values.count <= 1, values.isEmpty || group.phase==phase else { throw LabError("FMF 含冲突或阶段不匹配的个人指令。") }
                    if let option=values.first { choices[group.id]=option.id }
                }
                setup.nativePlayers?[key] = choices
                var target = MarkTarget()
                if choices[14]==34 {
                    guard Int(cell.targetPlayer)<opponents.count else { throw LabError("FMF 指定盯人的目标不在当前对手名单中，请先配置对手。") }
                    target.playerID = opponents[Int(cell.targetPlayer)].id
                } else if choices[14]==35 {
                    guard let position=NativeCatalog.positions.first(where:{$0.mask==cell.targetPosition}) else {throw LabError("FMF 指定盯防位置无效。")};target.position=position.id
                }
                setup.markTargets?[key]=target
                if phase == .possession {result.tactic.slots[i].possession=position.point;result.tactic.slots[i].possessionPosition=position.id;result.tactic.slots[i].possessionRole=role.id}
                else {result.tactic.slots[i].defending=position.point;result.tactic.slots[i].defendingPosition=position.id;result.tactic.slots[i].defendingRole=role.id}
            }
            let positions=result.tactic.slots.map{$0.position(phase).id}
            guard Set(positions).count==11,positions.first=="GK" else {throw LabError("FMF 阵型缺少门将或位置重叠。")}
            for slot in result.tactic.slots {
                guard NativeCatalog.allowedRoles(positions:positions,position:slot.position(phase).id,phase:phase).contains(where:{$0.id==slot.roleID(phase)}) else {throw LabError("FMF 角色不适用于当前阵型，无法无损导入。")}
                for option in setup.nativePlayers?[TacticalConfiguration.playerKey(slot.id,phase)]?.values ?? Dictionary<Int,UInt32>().values {
                    guard NativeCatalog.policy(position:slot.position(phase).id,role:result.tactic.role(slot.id,phase),option:option)==0 else {throw LabError("FMF 包含当前角色不支持的个人指令，无法无损导入。")}
                }
            }
            let formation=Formation.allCases.first{$0.positions==positions}?.rawValue ?? "自定义"
            if phase == .possession {result.tactic.formation=formation} else {result.tactic.defensiveFormation=formation}
        }
        result.tactic.configuration=setup
        result.tactic.name=String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80))
        guard !result.tactic.name.isEmpty else {throw LabError("FMF 战术名称为空。")}
        return try result.validated(includeOpponent: false)
    }
}

/// Same FMF v8 envelope as upstream src/fm27_fmf.py. TAC is always supplied by
/// the original serializer. Raw Zstandard blocks need no external compressor.
public enum FMFArchive {
    public static func tactic(plan: Data, title: String) throws -> Data {
        guard (8...1_048_576).contains(plan.count), !title.isEmpty, title.utf8.count<=4096 else { throw LabError("战术文件或名称长度无效。") }
        let header=Data([2,1,0x66,0x6d,0x66,0x2e,8,0,0])
        let content=Data([3,1,0x63,0x61,0x74,0x2e,0x22,0])+plan
        var details=Data([3,1,0x6d,0x6f,0x61,0x2e,4,0])
        details += string("TACTICS_TYPE_HANDLER")+string(title)+string("FM27 tactics editor")+Data(repeating:0,count:6)+Data(repeating:255,count:16)+string("FM27 Tactics")
        details += Data([2,0,1,0,2,0x81,0x49,0x0d,3,1,0,0x10])
        var uuid=UUID().uuid;details += withUnsafeBytes(of:&uuid){Data($0.prefix(10))}
        let a=frame(content),b=frame(details),now=UInt64(Date().timeIntervalSince1970)
        func entry(_ name:String,_ ext:String,_ offset:Int,_ chunk:Data,_ raw:Data)->Data {
            var data=string(name)+string(ext)
            for v in [UInt64(offset),UInt64(chunk.count),UInt64(raw.count),now,now] {data += integer(v)};return data
        }
        let toc=string(title)+integer(UInt32(1))+entry(title,".tac",0,a,content)+integer(UInt32(1))+string("_data")+integer(UInt32(1))+entry("details",".aom",a.count,b,details)+integer(UInt32(0))
        return header+integer(UInt64(17+a.count+b.count))+integer(UInt64(17))+Data([3])+a+b+header+frame(toc)
    }
    private static func integer<T:FixedWidthInteger>(_ value:T)->Data {var v=value.littleEndian;return withUnsafeBytes(of:&v){Data($0)}}
    private static func string(_ value:String)->Data {let d=Data(value.utf8);return integer(UInt32(d.count))+d}
    private static func frame(_ raw:Data)->Data {
        var data=Data([0x28,0xb5,0x2f,0xfd,0xa0])+integer(UInt32(raw.count))
        for offset in stride(from:0,to:max(1,raw.count),by:65536) {
            let size=min(65536,raw.count-offset),last=offset+size==raw.count
            let word=UInt32(size<<3)|(last ? 1:0)
            data += integer(word).prefix(3);data += raw.subdata(in:offset..<offset+size)
        };return data
    }
}
