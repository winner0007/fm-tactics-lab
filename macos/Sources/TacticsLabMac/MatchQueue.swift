import Foundation
import TacticsCore

struct MatchRequest {
    let index:Int
    let seed:UInt32
    let log:URL
    let scenario:NativeScenario?
}

/// Bounded independent engine hosts. The main actor commits each result before
/// admitting another job; cancellation also covers jobs not yet started.
final class MatchQueue:@unchecked Sendable {
    private let lock=NSLock()
    private var jobs:[Int:OriginalMatchJob]=[:]
    private var stopped=false
    var isStopped:Bool {lock.lock();defer{lock.unlock()};return stopped}
    var activeCount:Int {lock.lock();defer{lock.unlock()};return jobs.count}
    private func register(_ index:Int)->OriginalMatchJob? {
        lock.lock();defer{lock.unlock()}
        guard !stopped else{return nil}
        let job=OriginalMatchJob();jobs[index]=job;return job
    }
    private func remove(_ index:Int) {lock.lock();jobs[index]=nil;lock.unlock()}
    func cancel() {
        lock.lock();stopped=true;let active=Array(jobs.values);lock.unlock()
        active.forEach{$0.cancel()}
    }
    @MainActor func run(indices:[Int],workers:Int,helper:URL,app:URL,
                        request:(Int)throws->MatchRequest,
                        accept:(MatchRequest,OriginalMatchReport)throws->Void) async throws {
        guard (1...256).contains(workers) else{throw LabError("并行通道应为 1–256。")}
        typealias Outcome=(MatchRequest,Result<OriginalMatchReport,Error>)
        var cursor=0,firstError:Error?
        await withTaskGroup(of:Outcome.self) {group in
            func enqueue() {
                guard cursor<indices.count,!isStopped else{return}
                do {
                    let input=try request(indices[cursor]);cursor+=1
                    guard let job=register(input.index) else{return}
                    group.addTask {
                        let result=await Task.detached(priority:.userInitiated) {
                            Result {try job.run(helper:helper,app:app,seed:input.seed,log:input.log,scenario:input.scenario)}
                        }.value
                        self.remove(input.index)
                        return (input,result)
                    }
                } catch {firstError=firstError ?? error;cancel()}
            }
            for _ in 0..<min(workers,indices.count) {enqueue()}
            while let (input,result)=await group.next() {
                switch result {
                case .success(let report):
                    do {try accept(input,report)} catch {firstError=firstError ?? error;cancel()}
                case .failure(let error):
                    if !isStopped {firstError=firstError ?? error;cancel()}
                }
                enqueue()
            }
        }
        if let firstError {throw firstError}
    }
}
