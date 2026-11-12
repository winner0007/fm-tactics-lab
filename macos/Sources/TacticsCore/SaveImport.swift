import Foundation
import CryptoKit

public struct SaveClub:Codable,Identifiable {public let id:Int;public let name:String}
public struct SavedFixture:Codable,Identifiable {
    public let id:String;public let home:Int;public let away:Int;public let date:String?
    public let homeGoals:Int?;public let awayGoals:Int?
}
public struct SavedLeague:Codable,Identifiable {
    public let id:String;public let competitionID:Int;public let stageID:Int;public let season:Int
    public let clubIDs:[Int];public let fixtures:[SavedFixture]
}
public struct SaveCatalog:Codable {
    public let schemaVersion:Int;public let sourceName:String;public let sourceSHA256:String
    public let gameDate:String;public let build:String;public let notes:[String]
    public let clubs:[SaveClub];public let managedClubIDs:[Int];public let leagues:[SavedLeague]
    public var calendarWarning:String? = nil
    public func validated() throws -> Self {
        let ids=Set(clubs.map(\.id))
        guard schemaVersion==1,sourceSHA256.count==64,sourceSHA256.allSatisfy({$0.isHexDigit}),ids.count==clubs.count,Set(leagues.map(\.id)).count==leagues.count,leagues.allSatisfy({l in
            let members=Set(l.clubIDs)
            return (4...40).contains(members.count) && members.count==l.clubIDs.count && members.isSubset(of:ids) && l.fixtures.count==members.count*(members.count-1) && Set(l.fixtures.map{"\($0.home):\($0.away)"}).count==l.fixtures.count && l.fixtures.allSatisfy{$0.home != $0.away && members.contains($0.home) && members.contains($0.away)}
        }) else {throw LabError("存档目录不完整。")}
        return self
    }
}
public struct SavedRosterExport:Decodable {
    public let schemaVersion:Int;public let sourceName:String;public let sourceSHA256:String
    public let gameDate:String;public let build:String;public let notes:[String]
    public let rosters:[SavedRoster]
}
public struct SavedRoster:Decodable {
    public let clubID:Int;public let name:String;public let players:[SavedPlayer]
    public func workspace(source:String) throws -> Workspace {
        var w=Workspace.example(includeOpponent:false)
        let sorted=players.sorted{($0.ability.current ?? 0)>($1.ability.current ?? 0)}
        w.players=try sorted.map{try $0.player()}
        guard (11...100).contains(w.players.count),Set(w.players.map(\.id)).count==w.players.count else {throw LabError("\(name) 的一线队名单不完整。")}
        w.tactic.name=name;w.rosterSource=source+" · 存档一线队 · 阵型为工具初始模板，需核对"
        w.management.tacticSource="工具初始模板 · 未读取存档 AI 战术"
        var used=Set<UUID>()
        for i in w.tactic.slots.indices {
            let position=w.tactic.slots[i].position(.possession).id,index=NativeTeamInput.positionAttribute[position]!
            let available=w.players.filter{!used.contains($0.id)}
            let selected=available.max {a,b in
                let aa=a.nativeAttributes?[index] ?? 0,bb=b.nativeAttributes?[index] ?? 0
                return aa==bb ? (a.nativeProfile?["11"] ?? 0)<(b.nativeProfile?["11"] ?? 0):aa<bb
            }!
            w.tactic.slots[i].playerID=selected.id;used.insert(selected.id)
        }
        return try w.validated(includeOpponent:false)
    }
}
public struct SavedAbility:Decodable {public let current:Int?}
public struct SavedPlayer:Decodable {
    public let uid:Int;public let uniqueID:Int?;public let name:String?
    public let positions:[String:Int];public let rawAttributes:[String:Int]
    public let rawLeftFoot:Int;public let rawRightFoot:Int
    public let heightCM:Int;public let age:Int?
    public let ability:SavedAbility;public let personality:[String:Int]?
    public let traitBits:UInt64?;public let reputation:[String:Int]
    enum CodingKeys:String,CodingKey {case uid,uniqueID="unique_id",name,positions,rawAttributes="raw_attributes",rawLeftFoot="raw_left_foot",rawRightFoot="raw_right_foot",heightCM="height_cm",age,ability,personality,traitBits="trait_bits",reputation}
    public func player() throws -> Player {
        let labels=["GK","SW","DL","DC","DR","DM","ML","MC","MR","AML","AMC","AMR","ST","WBL","WBR"]
        let keys=["gk","sw","dl","dc","dr","dm","ml","mc","mr","aml","amc","amr","stc","wbl","wbr"]
        var raw=keys.map{positions[$0] ?? 0}+Array(repeating:0,count:54),attributes:[String:Int]=[:]
        for (key,index) in NativeTeamInput.attributes {let value=rawAttributes[key] ?? 0;raw[index]=value;if value>0 {attributes[key]=max(1,Int((Double(value)/5).rounded()))}}
        raw[39]=rawLeftFoot;raw[40]=rawRightFoot
        for a in Attribute.allCases where attributes[a.key]==nil {attributes[a.key]=10}
        let positionsText=keys.indices.filter{raw[$0]>=15}.map{labels[$0]}.joined(separator:" / ")
        guard let name,!name.isEmpty,(140...220).contains(heightCM),let age,(14...60).contains(age),raw.count==69,raw.enumerated().allSatisfy({$0.offset<15 ? (0...20).contains($0.element):(0...100).contains($0.element)}) else {throw LabError("存档球员资料超出已验证范围，未导入该球队。")}
        var p=Player(name:name,position:positionsText.isEmpty ? labels[raw.prefix(15).enumerated().max{$0.element<$1.element}!.offset]:positionsText,attributes:attributes)
        let identity="fm27-person-\(uniqueID ?? uid)",bytes=Array(SHA256.hash(data:Data(identity.utf8))).prefix(16).map{String(format:"%02x",$0)}.joined()
        let a=Array(bytes);p.id=UUID(uuidString:String(a[0..<8])+"-"+String(a[8..<12])+"-"+String(a[12..<16])+"-"+String(a[16..<20])+"-"+String(a[20..<32]))!
        p.nativeAttributes=raw;p.sourceIdentity=identity
        let ca=ability.current
        guard let ca,(0...200).contains(ca) else {throw LabError("球员当前能力未解析。")}
        var profile:[String:UInt32]=["0":UInt32(heightCM),"1":UInt32(age),"9":UInt32(truncatingIfNeeded:traitBits ?? 0),"10":UInt32((traitBits ?? 0)>>32),"11":UInt32(ca)]
        for (i,key) in ["home","current","world"].enumerated() {guard let v=reputation[key],(0...10000).contains(v) else {throw LabError("球员声望未解析。")};profile[String(i+12)]=UInt32(v)}
        var background=PlayerBackground()
        for (i,key) in ["professionalism","loyalty","sportsmanship","temperament","pressure","ambition","adaptability"].enumerated() {
            if let v=personality?[key],(1...20).contains(v) {profile[String(i+2)]=UInt32(v);background.traits[PlayerBackground.traitNames[i]]=v}
        }
        p.nativeProfile=profile;p.background=background
        p.preferredFoot=rawLeftFoot>=75 && rawRightFoot>=75 ? "双脚":rawLeftFoot>rawRightFoot ? "左脚":"右脚"
        return p
    }
}
