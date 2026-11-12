import Foundation
import TacticsCore

/// Each match owns one short-lived process. Stdout goes to a file so a full
/// pipe cannot deadlock the parent; incomplete logs never become results.
final class OriginalMatchJob: @unchecked Sendable {
    private let lock=NSLock()
    private var process:Process?
    private var cancelled=false
    private var finished=false
    var isCancelled:Bool {lock.lock();defer{lock.unlock()};return cancelled}
    func cancel() {
        lock.lock();defer{lock.unlock()}
        // A naturally exited child still has a report to parse and commit.
        if finished || (process.map{!$0.isRunning} ?? false) {return}
        cancelled=true
        if let p=process,p.isRunning {p.terminate()}
    }
    func run(helper:URL,app:URL,seed:UInt32,log:URL,scenario:NativeScenario?=nil) throws -> OriginalMatchReport {
        try FileManager.default.createDirectory(at:log.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data().write(to:log)
        let stderr=log.deletingPathExtension().appendingPathExtension("stderr.txt")
        try Data().write(to:stderr)
        let output=try FileHandle(forWritingTo:log),errors=try FileHandle(forWritingTo:stderr)
        defer {try? output.close();try? errors.close()}
        let p=Process();p.executableURL=helper;p.arguments=[app.path,"--seed",String(seed)]
        if let scenario {
            let url=log.deletingLastPathComponent().appendingPathComponent("configuration.json")
            if FileManager.default.fileExists(atPath:url.path) {
                guard try Data(contentsOf:url)==scenario.data else {throw LabError("该比赛目录已有其他配置，拒绝覆盖实验输入。")}
            } else {try scenario.data.write(to:url,options:.atomic)}
            p.arguments! += ["--scenario",url.path]
        }
        p.standardOutput=output;p.standardError=errors
        lock.lock()
        if cancelled {lock.unlock();throw LabError("已取消比赛。")}
        process=p
        do {try p.run();lock.unlock()} catch {process=nil;lock.unlock();throw error}
        // The helper has its own 45-second alarm; this also bounds an abnormal
        // helper before it installs that alarm. It only terminates our child.
        let timeout=DispatchWorkItem { [weak self] in self?.cancel() }
        DispatchQueue.global().asyncAfter(deadline:.now()+60,execute:timeout)
        p.waitUntilExit();timeout.cancel()
        lock.lock();process=nil;finished=true;let stopped=cancelled;lock.unlock()
        try output.synchronize()
        if stopped {throw LabError("运行已停止；已完成场次与本场日志均已保留。")}
        return try OriginalMatchReport.parse(Data(contentsOf:log),exitCode:p.terminationStatus,expectedSeed:seed,scenario:scenario)
    }
}
