import Foundation

public enum GameSetPieceKind:Int,CaseIterable,Identifiable,Codable {
    case defendCorner,defendDirect,defendWide,defendDeep,defendThrow,attackCorner,attackDirect,attackWide,attackDeep,attackThrow
    public var id:Int {rawValue}
    public var label:String {["防守角球","防守直接任意球","防守边路任意球","防守远距离任意球","防守界外球","进攻角球","进攻直接任意球","进攻边路任意球","进攻远距离任意球","进攻界外球"][rawValue]}
    public var attacking:Bool {rawValue>=5}
    public var taskCount:Int {attacking ? 9:10}
    public var strategyLabels:[String] {
        if self == .attackCorner {return ["近门柱","中路","远门柱"]}
        if [.attackDirect,.attackWide,.attackDeep].contains(self) {return ["防守转换","平衡","进攻禁区"]}
        if [.defendWide,.defendDeep].contains(self) {return ["靠前防线","平衡","守住禁区"]}
        return []
    }
    public var hasSwing:Bool {self == .attackCorner || self == .attackWide}
    public var categories:[Int] {attacking ? [4,5,7,6]:[.defendCorner,.defendThrow].contains(self) ? [0,2,1]:[0,3,2,1]}
}
public struct GameSetPieceRoutine:Codable,Equatable,Identifiable {
    public var id=UUID()
    public var name:String
    public var frequency=1
    public var strategy:Int
    public var swing:Int
    public var groups:[[Int]]
    public var backups:[[Int]]
    public var priority:[Int]
    public static func initial(_ kind:GameSetPieceKind) -> Self {
        // Same role/task allocations as the upstream editor's initial routines.
        var groups=Array(repeating:[Int](),count:8),priority=kind.categories
        switch kind {
        case .defendCorner:groups[0]=[9,8,10,6,3,4];groups[1]=[2];groups[2]=[6,12,1]
        case .defendDirect:groups[2]=[6,6,1,1,1];groups[3]=[5,5,5,15,15];priority=[3,0,2,1]
        case .defendWide:groups[0]=[6,6,6,6,6];groups[1]=[12];groups[2]=[1];groups[3]=[5,15,15]
        case .defendDeep:groups[0]=[6,6,6,6,1,1];groups[1]=[2];groups[2]=[1,1,1];priority=[0,2,3,1]
        case .defendThrow:groups[0]=[9,8,10,6,1,1];groups[1]=[2];groups[2]=[6,12,1]
        case .attackCorner,.attackWide,.attackThrow:groups[4]=[6,5,7,4];groups[5]=[2,2];groups[6]=[10,14];groups[7]=[4]
        case .attackDirect:groups[4]=[6,5,7,4];groups[5]=[2,2];groups[6]=[13];groups[7]=[4,4]
        case .attackDeep:groups[4]=[4,4];groups[5]=[2,2,2];groups[7]=[4,4,4,4]
        }
        var backups=groups.map{Array(repeating:0,count:$0.count)}
        if kind == .defendDirect {backups[3]=[0,0,0,2,2]}
        if kind == .defendWide {backups[3]=[0,2,2]}
        var result=Self(name:kind.label+" 1",strategy:kind.strategyLabels.isEmpty ? 255:0,swing:kind.hasSwing ? 0:255,groups:groups,backups:backups,priority:priority)
        result.id=UUID(uuidString:String(format:"00000000-0000-0000-0000-%012d",kind.id+1))!
        return result
    }
    public func validate(_ kind:GameSetPieceKind,complete:Bool=true) throws {
        let count=groups.reduce(0,{$0+$1.count})
        guard !name.isEmpty,name.count<=64,(0...2).contains(frequency),groups.count==8,backups.count==8,(complete ? count==kind.taskCount:count<=kind.taskCount),Set(priority)==Set(kind.categories),priority.count==kind.categories.count,
              (kind.hasSwing ? (0...1).contains(swing):swing==255),
              (kind.strategyLabels.isEmpty ? strategy==255:kind.strategyLabels.indices.contains(strategy)) else {throw LabError("\(kind.label)：需分配 \(kind.taskCount) 项任务，检查套路频率、策略和角色顺序。")}
        for g in 0..<8 {
            guard backups[g].count==groups[g].count,groups[g].allSatisfy({GameSetPieces.allowed[g].contains($0)}),backups[g].allSatisfy({(0...15).contains($0)}),priority.contains(g)||groups[g].isEmpty else {throw LabError("\(kind.label)：存在不适用于该角色的任务。")}
        }
    }
}
public struct GameSetPieces:Codable,Equatable {
    public var routines:[String:[GameSetPieceRoutine]]
    /// 0 captains, 1 penalties, 2–11 left/right takers, 12–19 role rankings.
    public var priorities:[String:[UUID]]=[:]
    public var throwStyles=[0,0,0]
    public init(){routines=Dictionary(uniqueKeysWithValues:GameSetPieceKind.allCases.map{(String($0.id),[.initial($0)])})}
    public static let categories=["防空塔","反击攻击手","盯防者","封堵者","空中威胁","反击阻击者","机会创造者","禁区内杀器"]
    public static let allowed=[[1,3,4,6,7,8,9,10,11],[2,5,12,13,14,15],[1,3,4,6,12],[5,15],[4,5,6,7,8,9,11],[2,3,10,14,15],[10,12,13,14,15],[4,5,6,7,8,9,11]]
    public static let attackTasks=["无具体指令","主罚定位球","留在后场防守","必要时留在后场防守","前压","从近门柱进攻","从远门柱进攻","从禁区边缘进攻","埋伏在近门柱","埋伏在远门柱","埋伏在大禁区外（中路）","盯守门员","接应短传","佯攻","埋伏在大禁区外（近端）","埋伏在大禁区外（远端）"]
    public static let defendTasks=["门将","回撤","留在前场（中路）","盯近门柱","盯远门柱","组成人墙","盯人","小禁区区域防守（近门柱）","小禁区区域防守（中间靠近门柱）","小禁区区域防守（中间）","小禁区区域防守（中间靠远门柱）","小禁区区域防守（远门柱）","禁区边缘","留在前场（近端）","留在前场（远端）","必要时当人墙"]
    public static let listNames=["队长顺序","点球主罚顺序","角球 · 左脚","角球 · 右脚","左侧直接任意球","右侧直接任意球","边路任意球 · 左脚","边路任意球 · 右脚","左侧远距离任意球","右侧远距离任意球","左侧界外球","右侧界外球"]+categories.map{$0+" · 球员顺序"}
    public func validate(ids:Set<UUID>,complete:Bool=true) throws {
        guard Set(routines.keys)==Set((0..<10).map(String.init)),throwStyles.count==3,throwStyles.allSatisfy({(0...1).contains($0)}) else {throw LabError("定位球类型或界外球设置不完整。")}
        for kind in GameSetPieceKind.allCases {
            let list=routines[String(kind.id)]!
            guard (1...3).contains(list.count),Set(list.map(\.id)).count==list.count else {throw LabError("每种定位球保留 1–3 套套路。")}
            for routine in list {try routine.validate(kind,complete:complete)}
        }
        for (key,list) in priorities {
            guard let i=Int(key),(0..<20).contains(i),Set(list).count==list.count,Set(list).isSubset(of:ids) else {throw LabError("定位球候选名单无效。")}
        }
    }
}
public struct NativeSetPieceInput:Codable,Equatable {
    public let routines:[[GameSetPieceRoutine]]
    public let priorities:[String:[Int]]
    public let throwStyles:[Int]
    public init(_ setup:GameSetPieces,players:[NativePlayerInput]) {
        routines=(0..<10).map{setup.routines[String($0)]!};throwStyles=setup.throwStyles
        priorities=setup.priorities.mapValues{list in list.compactMap{id in players.firstIndex{$0.id==id.uuidString}}}
    }
}
