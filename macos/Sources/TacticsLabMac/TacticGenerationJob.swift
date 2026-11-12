import Foundation
import TacticsCore

final class TacticGenerationJob:@unchecked Sendable {
    private let lock=NSLock()
    private var process:Process?
    private var cancelled=false
    func cancel(){lock.lock();defer{lock.unlock()};cancelled=true;if process?.isRunning==true {process?.terminate()}}
    func run(helper:URL,app:URL,scenario:NativeScenario,seed:UInt32,folder:URL)throws->PreparedTactics {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let input=folder.appendingPathComponent("requested.json"),log=folder.appendingPathComponent("generation.jsonl"),err=folder.appendingPathComponent("generation.stderr.txt")
        try scenario.data.write(to:input,options:.atomic);try Data().write(to:log);try Data().write(to:err)
        let output=try FileHandle(forWritingTo:log),errors=try FileHandle(forWritingTo:err)
        defer {try? output.close();try? errors.close()}
        let p=Process();p.executableURL=helper;p.arguments=[app.path,"--seed",String(seed),"--generate-tactics",input.path];p.standardOutput=output;p.standardError=errors
        lock.lock();if cancelled {lock.unlock();throw LabError("已停止战术准备。")};process=p
        do {try p.run();lock.unlock()}catch{process=nil;lock.unlock();throw error}
        let timeout=DispatchWorkItem{[weak self] in self?.cancel()}
        DispatchQueue.global().asyncAfter(deadline:.now()+60,execute:timeout);p.waitUntilExit();timeout.cancel();try output.synchronize()
        lock.lock();process=nil;let stopped=cancelled;lock.unlock()
        guard !stopped else {throw LabError("战术准备已停止或超过时限。")}
        let lines=try String(contentsOf:log,encoding:.utf8).split(separator:"\n").map{Data($0.utf8)}
        let events=lines.compactMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}
        guard p.terminationStatus==0,!events.contains(where:{["failed","native_fault"].contains($0["event"] as? String ?? "")}),let hash=events.first(where:{$0["event"] as? String=="original_engine_loaded"})?["sha256"] as? String,hash==OriginalMatchReport.updatedEngineHash else {throw LabError("原版 AI 战术未能生成："+(events.last?["reason"] as? String ?? "引擎提前退出")+"。没有使用模板代替。")}
        let receipts=lines.compactMap{try? JSONDecoder().decode(TacticGenerationReceipt.self,from:$0)}
        guard receipts.count==1,receipts[0].seed==seed else {throw LabError("原版 AI 战术回执缺失。")}
        let result=PreparedTactics(requested:scenario,receipt:receipts[0],engineSHA256:hash)
        try result.resolved.data.write(to:folder.appendingPathComponent("resolved.json"),options:.atomic)
        try JSONEncoder().encode(result).write(to:folder.appendingPathComponent("preparation.json"),options:.atomic)
        return result
    }
}
