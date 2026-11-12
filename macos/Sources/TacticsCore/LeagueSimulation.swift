import Foundation

public enum LeagueRankingRule:String,Codable,CaseIterable,Identifiable {
    case goalDifference="积分 → 净胜球 → 进球"
    case headToHead="积分 → 相互战绩 → 净胜球 → 进球"
    case english="英超积分与排名规则"
    case spanish="西班牙联赛积分与排名规则"
    public var id:String {rawValue}
    public var source:String? {
        switch self {
        case .english:return "https://www.premierleague.com/en/news/58905"
        case .spanish:return "https://rfef.es/sites/default/files/2025-11/20251112_Reglamento_de_Competiciones_2025.pdf"
        default:return nil
        }
    }
}
public struct LeagueRules:Codable,Equatable {
    public var ranking:LeagueRankingRule = .goalDifference
    public var cycles=2
    public var winPoints=3
    public var drawPoints=1
    public var lossPoints=0
    /// Boundaries separating qualification/relegation groups, needed for C.17.
    public var decidingPlaces:[Int]=[1]
    public init() {}
    public var description:String {"\(cycles==2 ? "主客场双循环":"单循环") · 胜 \(winPoints) / 平 \(drawPoints) / 负 \(lossPoints) · \(ranking.rawValue)"}
    public var limitation:String {"固定阵容战术实验：每场重置开赛状态，不累积伤病、停赛或疲劳；不推进训练、成长、衰减、退役和转会。尚不处理分组、附加赛、公平竞赛分和行政扣分；未决同分保留并列，不以队名制造名次。"}
    public func validate(teamCount:Int) throws {
        guard [1,2].contains(cycles),(0...10).contains(winPoints),(0...10).contains(drawPoints),(0...10).contains(lossPoints),winPoints>=drawPoints,drawPoints>=lossPoints,decidingPlaces.allSatisfy({$0>=1 && $0<teamCount}) else {throw LabError("联赛积分或排名分界无效。")}
        if [.english,.spanish].contains(ranking) {guard cycles==2,winPoints==3,drawPoints==1,lossPoints==0 else {throw LabError("官方积分／排名预设使用双循环、胜 3 平 1 负 0；其他设置请选择自定义排序。")}}
    }
}
public struct LeagueTeam:Codable,Equatable,Identifiable {
    public var id:UUID
    public var savedClubID:Int?
    public var displayName:String? = nil
    public var plan:Workspace
    public var name:String {displayName ?? plan.tactic.name}
    public init(plan:Workspace,savedClubID:Int?=nil) {id=UUID();var own=plan;own.opponent=nil;self.plan=own;self.savedClubID=savedClubID;displayName=plan.tactic.name}
}
public struct LeagueFixture:Codable,Equatable,Identifiable {
    public let id:UUID
    public let home:UUID
    public let away:UUID
    public let round:Int
    public var date:String? = nil
    public init(home:UUID,away:UUID,round:Int,date:String?=nil) {id=UUID();self.home=home;self.away=away;self.round=round;self.date=date}
}
public struct LeagueSetup:Codable,Equatable {
    public var schemaVersion=1
    public var name="自定义联赛"
    public var rules=LeagueRules()
    public var teams:[LeagueTeam]=[]
    public var importedSchedule:[LeagueFixture]? = nil
    public var source="自定义球队与阵容"
    public init() {}
    public func validated() throws -> Self {
        guard schemaVersion==1,!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,(2...40).contains(teams.count),Set(teams.map(\.id)).count==teams.count,Set(teams.map(\.name)).count==teams.count else {throw LabError("联赛需要 2–40 支名称不同的球队。")}
        try rules.validate(teamCount:teams.count)
        for t in teams {guard !t.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,t.name.count<=80 else {throw LabError("请填写参赛球队名称。")};_ = try t.plan.validated(includeOpponent:false)}
        let schedule=fixtures(),members=Set(teams.map(\.id))
        guard Set(schedule.map(\.id)).count==schedule.count,schedule.allSatisfy({$0.home != $0.away && members.contains($0.home) && members.contains($0.away)}) else {throw LabError("赛程存在重复比赛或无效球队。")}
        let expected=teams.count*(teams.count-1)*rules.cycles/2
        guard schedule.count==expected else {throw LabError("赛程场数与循环规则不符。")}
        if rules.cycles==2 {
            guard Set(schedule.map{$0.home.uuidString+":"+$0.away.uuidString}).count==expected else {throw LabError("双循环赛程必须每队互为主客各赛一次。")}
        } else {
            guard Set(schedule.map{[$0.home.uuidString,$0.away.uuidString].sorted().joined(separator:":")}).count==expected else {throw LabError("单循环赛程存在重复对阵。")}
        }
        return self
    }
    public func fixtures()->[LeagueFixture] {
        if let importedSchedule{return importedSchedule}
        guard teams.count>=2 else{return []}
        var rotation=teams.map{Optional($0.id)}
        if rotation.count%2==1 {rotation.append(nil)}
        var first:[LeagueFixture]=[]
        for round in 0..<(rotation.count-1) {
            for pair in 0..<(rotation.count/2) {
                if let a=rotation[pair],let b=rotation[rotation.count-1-pair] {
                    first.append(LeagueFixture(home:round%2==0 ? a:b,away:round%2==0 ? b:a,round:round+1))
                }
            }
            let last=rotation.removeLast();rotation.insert(last,at:1)
        }
        return rules.cycles==1 ? first:first+first.map{LeagueFixture(home:$0.away,away:$0.home,round:$0.round+rotation.count-1)}
    }
    public func scenario(_ fixture:LeagueFixture)throws->NativeScenario {
        guard let home=teams.first(where:{$0.id==fixture.home}),let away=teams.first(where:{$0.id==fixture.away}) else {throw LabError("赛程球队不存在。")}
        var w=home.plan,opponent=away.plan;w.tactic.name=home.name;opponent.tactic.name=away.name;w.opponent=OpponentPlan(opponent)
        return try NativeScenario(workspace:w)
    }
}
public struct LeagueResult:Codable,Equatable,Identifiable {
    public let season:Int
    public let fixture:LeagueFixture
    public let report:OriginalMatchReport
    public var id:String {"\(season):\(fixture.id)"}
    public init(season:Int,fixture:LeagueFixture,report:OriginalMatchReport) {self.season=season;self.fixture=fixture;self.report=report}
}
public struct LeagueRun:Codable,Equatable,Identifiable {
    public var id=UUID()
    public let setup:LeagueSetup
    public let schedule:[LeagueFixture]
    public let seasons:Int
    public let firstSeed:UInt32
    public let startedAt:Date
    public var status="运行中"
    public var results:[LeagueResult]=[]
    public var failure:String? = nil
    public var engineSHA256:String? = nil
    public var workers:Int? = nil
    public var expected:Int {schedule.count*seasons}
    public init(setup:LeagueSetup,seasons:Int,seed:UInt32)throws {
        self.setup=try setup.validated();self.schedule=setup.fixtures();self.seasons=seasons;self.firstSeed=seed;startedAt=Date()
        guard (1...100).contains(seasons),expected<=20000,UInt64(seed)+UInt64(expected-1)<=UInt64(UInt32.max) else {throw LabError("最多 100 次赛季、共 20,000 场，且不能超出种子范围。")}
        // Preflight every pairing so invalid opposition targets cannot fail late.
        for fixture in schedule {_ = try setup.scenario(fixture)}
    }
    public func table(season:Int)->[LeagueStanding] {LeagueTable.calculate(teams:setup.teams,rules:setup.rules,results:results.filter{$0.season==season},complete:results.filter{$0.season==season}.count==schedule.count)}
    public var completedSeasons:[Int] {(1...seasons).filter{s in results.filter{$0.season==s}.count==schedule.count}}
    public func validateEngine(_ hash:String) throws {
        guard OriginalMatchReport.supportsEngine(hash),engineSHA256.map({$0==hash}) ?? true,
              results.allSatisfy({$0.report.engineSHA256==hash}) else {
            throw LabError("这份联赛实验使用的引擎与当前版本不同。历史结果已保留，请新建实验；不能混用版本续跑。")
        }
    }
    public func validated()throws->Self {
        if let hash=engineSHA256 ?? results.first?.report.engineSHA256 {try validateEngine(hash)}
        _ = try setup.validated()
        var actual=setup;actual.importedSchedule=schedule;_ = try actual.validated()
        guard (1...100).contains(seasons),expected<=20000,results.count<=expected,UInt64(firstSeed)+UInt64(expected-1)<=UInt64(UInt32.max),status != "已完成" || results.count==expected else {throw LabError("保存的联赛进度无效。")}
        if let imported=setup.importedSchedule {guard imported==schedule else {throw LabError("保存赛程与导入赛程不一致。")}}
        var configurations:[UUID:NativeScenario]=[:]
        _ = try SimulationConcurrency.missing(requested:expected,firstSeed:firstSeed,seeds:results.map{$0.report.seed})
        for result in results {
            let i=Int(result.report.seed-firstSeed)
            let fixture=schedule[i%schedule.count]
            guard result.season==i/schedule.count+1,result.fixture==fixture,result.report.seed==firstSeed+UInt32(i) else {throw LabError("联赛报告的轮次、种子或顺序不一致。")}
            if configurations[fixture.id]==nil {configurations[fixture.id]=try setup.scenario(fixture)}
            guard result.report.configuration==configurations[fixture.id] else {throw LabError("联赛报告的球队配置与实验快照不一致。")}
            _ = try OriginalMatchReport.experiment([result.report]).validated()
        }
        var sorted=self;sorted.results.sort{$0.report.seed<$1.report.seed};return sorted
    }
}
public struct LeagueStanding:Identifiable,Equatable {
    public let id:UUID
    public let name:String
    public var rank=0,played=0,wins=0,draws=0,losses=0,goalsFor=0,goalsAgainst=0,points=0
    public var tied=false
    public var goalDifference:Int {goalsFor-goalsAgainst}
}
public enum LeagueTable {
    public static func calculate(teams:[LeagueTeam],rules:LeagueRules,results:[LeagueResult],complete:Bool)->[LeagueStanding] {
        var rows=Dictionary(uniqueKeysWithValues:teams.map{($0.id,LeagueStanding(id:$0.id,name:$0.name))})
        for result in results {
            let score=result.report.score
            for (id,gf,ga) in [(result.fixture.home,score[0],score[1]),(result.fixture.away,score[1],score[0])] {
                guard var r=rows[id] else{continue}
                r.played+=1;r.goalsFor+=gf;r.goalsAgainst+=ga
                if gf>ga {r.wins+=1;r.points+=rules.winPoints}else if gf==ga {r.draws+=1;r.points+=rules.drawPoints}else{r.losses+=1;r.points+=rules.lossPoints}
                rows[id]=r
            }
        }
        func split(_ group:[LeagueStanding],key:(LeagueStanding)->Int)->[[LeagueStanding]] {
            Dictionary(grouping:group,by:key).sorted{$0.key>$1.key}.map(\.value)
        }
        func total(_ group:[LeagueStanding])->[[LeagueStanding]] {split(group,key:{$0.goalDifference}).flatMap{split($0,key:{$0.goalsFor})}}
        func head(_ group:[LeagueStanding],spanish:Bool=false)->[[LeagueStanding]] {
            let ids=Set(group.map(\.id)),games=results.filter{ids.contains($0.fixture.home)&&ids.contains($0.fixture.away)}
            var points=[UUID:Int](),gd=[UUID:Int](),away=[UUID:Int]()
            for g in games {
                let a=g.report.score[0],b=g.report.score[1],h=g.fixture.home,v=g.fixture.away
                points[h,default:0]+=a>b ? rules.winPoints:a==b ? rules.drawPoints:rules.lossPoints
                points[v,default:0]+=b>a ? rules.winPoints:a==b ? rules.drawPoints:rules.lossPoints
                gd[h,default:0]+=a-b;gd[v,default:0]+=b-a;away[v,default:0]+=b
            }
            if spanish {
                // RFEF art. 29: after separating any clubs, restart the
                // applicable two/multi-club criteria for each remaining tie.
                var criteria:[(LeagueStanding)->Int]=[]
                if group.count>2 {criteria.append{points[$0.id] ?? 0}}
                criteria += [{gd[$0.id] ?? 0},{$0.goalDifference},{$0.goalsFor}]
                for criterion in criteria {
                    let groups=split(group,key:criterion)
                    if groups.count>1 {return groups.flatMap{$0.count>1 ? head($0,spanish:true):[$0]}}
                }
                return [group]
            }
            let byPoints=split(group,key:{points[$0.id] ?? 0})
            if rules.ranking == .english {return byPoints.flatMap{split($0,key:{away[$0.id] ?? 0})}}
            return byPoints.flatMap{split($0,key:{gd[$0.id] ?? 0})}.flatMap(total)
        }
        var ordered:[[LeagueStanding]]=[]
        for equalPoints in split(Array(rows.values),key:{$0.points}) {
            if complete && [.headToHead,.spanish].contains(rules.ranking) {ordered+=head(equalPoints,spanish:rules.ranking == .spanish)}
            else {ordered+=total(equalPoints)}
        }
        if complete && rules.ranking == .english {
            var place=1,new:[[LeagueStanding]]=[]
            for group in ordered {
                let critical=rules.decidingPlaces.contains{place<=$0 && $0<place+group.count-1}
                new+=critical ? head(group):[group];place+=group.count
            }
            ordered=new
        }
        var rank=1,answer:[LeagueStanding]=[]
        for group in ordered {
            for var row in group.sorted(by:{$0.name<$1.name}) {row.rank=rank;row.tied=group.count>1;answer.append(row)}
            rank+=group.count
        }
        return answer
    }
}
