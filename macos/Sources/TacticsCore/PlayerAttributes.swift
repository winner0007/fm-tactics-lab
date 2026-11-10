import Foundation

public struct PlayerAttribute: Identifiable {
    public let id: String
    public let title: String
    public let group: String
    public static let groups = ["基础", "技术", "精神", "身体", "门将", "定位球"]
    public static let all: [PlayerAttribute] = {
        let groups: [(String, [(String,String)])] = [
            ("技术", [("passing","传球"),("finishing","射门"),("tackling","抢断"),("crossing","传中"),("dribbling","盘带"),("first_touch","停球"),("heading","头球"),("long_shots","远射"),("marking","盯人"),("technique","技术")]),
            ("精神", [("decisions","决断"),("anticipation","预判"),("bravery","勇敢"),("composure","镇定"),("concentration","集中"),("determination","决心"),("flair","才华"),("leadership","领导力"),("off_the_ball","无球跑动"),("positioning","防守站位"),("teamwork","团队合作"),("vision","视野"),("work_rate","工作投入"),("aggression","侵略性")]),
            ("身体", [("pace","速度"),("stamina","耐力"),("acceleration","爆发力"),("agility","灵活"),("balance","平衡"),("jumping_reach","弹跳"),("natural_fitness","体质"),("strength","强壮")]),
            ("门将", [("aerial_reach","制空范围"),("command_of_area","拦截传中"),("communication","指挥防守"),("eccentricity","神经指数"),("handling","手控球"),("kicking","大脚开球"),("one_on_ones","一对一"),("reflexes","反应"),("rushing_out","出击"),("punching","击球倾向"),("throwing","手抛球")]),
            ("定位球", [("corners","角球"),("free_kick_taking","任意球"),("penalty_taking","点球"),("long_throws","界外球")])
        ]
        return groups.flatMap { group, fields in fields.map { PlayerAttribute(id:$0.0,title:$0.1,group:group) } }
    }()
    public static func fields(_ group:String) -> [PlayerAttribute] {
        if group == "基础" { return Attribute.allCases.compactMap { a in all.first { $0.id==a.key } } }
        return all.filter { $0.group==group }
    }
}

extension Workspace {
    public mutating func addCandidate<R:RandomNumberGenerator>(using random:inout R) {
        guard players.count < 100 else { return }
        let positions=["GK","DC","DR / DL","DM / MC","MC / AMC","AML / AMR","ST"]
        let p=Player(name:"候补 \(players.count+1)",position:positions[(players.count-11)%positions.count],attributes:[:])
        players.append(p)
        _ = applyAbility(.professional,scope:.individual(p.id),using:&random)
        // Roster membership changed; a snapshot with fewer players is no longer comparable.
        baseline=nil;baselinePlayers=nil;baselineRosterSource=nil
    }
}
