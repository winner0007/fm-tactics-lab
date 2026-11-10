import Foundation

public struct SimulationBatch:Codable,Equatable {
    public var id=UUID()
    public var startedAt=Date()
    public var finishedAt:Date?
    public var requested:Int
    public var completed=0
    public var firstSeed:UInt32
    public var configuration:NativeScenario?
    public var status="运行中"
    public var failure:String?
    public init(requested:Int,firstSeed:UInt32,configuration:NativeScenario?) {self.requested=requested;self.firstSeed=firstSeed;self.configuration=configuration}
}
public struct BatchSummary {
    public let matches:[OriginalMatchReport]
    public init(_ matches:[OriginalMatchReport]) {self.matches=matches}
    public var wins:Int {matches.filter{$0.score[0]>$0.score[1]}.count}
    public var draws:Int {matches.filter{$0.score[0]==$0.score[1]}.count}
    public var losses:Int {matches.count-wins-draws}
    public var winRate:Double {Double(wins)/Double(max(1,matches.count))}
    public var points:Double {Double(wins*3+draws)/Double(max(1,matches.count))}
    public var winInterval:ClosedRange<Double> {
        guard !matches.isEmpty else{return 0...1}
        let n=Double(matches.count),z=1.95996398454,p=winRate
        let denominator=1+z*z/n,centre=(p+z*z/(2*n))/denominator
        let radius=z*sqrt(p*(1-p)/n+z*z/(4*n*n))/denominator
        return max(0,centre-radius)...min(1,centre+radius)
    }
    public func mean(_ key:String,side:Int) -> Double? {
        let values=matches.compactMap {m in key=="goals" ? Double(m.score[side]):m.teams.first{$0.side==side}?.statistics[key]}
        return values.isEmpty ? nil:values.reduce(0,+)/Double(values.count)
    }
}
