import Foundation

public enum SimulationConcurrency {
    /// Conservative initial choice. This is a resource budget, not a measured
    /// optimum: leave capacity for the application, game and macOS.
    public static var recommended:Int {
        max(1,min(8,ProcessInfo.processInfo.activeProcessorCount/2,Int(ProcessInfo.processInfo.physicalMemory/(4*1024*1024*1024))))
    }
    public static func missing(requested:Int,firstSeed:UInt32,seeds:[UInt32])throws->[Int] {
        guard requested>0,requested<=20000,UInt64(firstSeed)+UInt64(requested-1)<=UInt64(UInt32.max),
              Set(seeds).count==seeds.count,seeds.allSatisfy({$0>=firstSeed && UInt64($0)<UInt64(firstSeed)+UInt64(requested)}) else {throw LabError("比赛种子重复或超出本批次范围。")}
        let completed=Set(seeds.map{Int($0-firstSeed)})
        return (0..<requested).filter{!completed.contains($0)}
    }
}
