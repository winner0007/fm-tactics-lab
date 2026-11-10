import Foundation
import TacticsCore

struct TacticFileReceipt: Codable {
    let event: String
    let accepted: Bool
    let fields: FMFTacticFields
    let name: String?
}
final class TacticFileJob: @unchecked Sendable {
    private func run(helper:URL,app:URL,arguments:[String],folder:URL,name:String,event:String)throws->TacticFileReceipt {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let log=folder.appendingPathComponent(name+".jsonl"),err=folder.appendingPathComponent(name+".stderr.txt")
        try Data().write(to:log);try Data().write(to:err)
        let output=try FileHandle(forWritingTo:log),errors=try FileHandle(forWritingTo:err)
        defer {try? output.close();try? errors.close()}
        let process=Process();process.executableURL=helper;process.arguments=[app.path]+arguments;process.standardOutput=output;process.standardError=errors
        try process.run()
        let timeout=DispatchWorkItem{if process.isRunning {process.terminate()}}
        DispatchQueue.global().asyncAfter(deadline:.now()+60,execute:timeout)
        process.waitUntilExit();timeout.cancel();try output.synchronize()
        let lines=try String(contentsOf:log,encoding:.utf8).split(separator:"\n").compactMap{$0.data(using:.utf8)}
        let events=lines.compactMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}
        guard process.terminationStatus==0,!events.contains(where:{$0["event"] as? String=="failed" || $0["event"] as? String=="native_fault"}),
              events.contains(where:{$0["event"] as? String=="original_engine_loaded" && $0["sha256"] as? String==OriginalMatchReport.engineHash}) else {
            let reason=events.last?["reason"] as? String ?? "引擎未完成读取／写入"
            throw LabError("FMF 操作未完成：\(reason)。当前配置和目标文件未改动。")
        }
        let receipts=lines.compactMap{try? JSONDecoder().decode(TacticFileReceipt.self,from:$0)}.filter{$0.event==event && $0.accepted}
        guard receipts.count==1 else {throw LabError("原版引擎未返回完整战术数据。")};return receipts[0]
    }
    func read(helper:URL,app:URL,source:URL,folder:URL)throws->TacticFileReceipt {
        let size=try source.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard (1...4_194_304).contains(size) else {throw LabError("FMF 文件必须小于 4 MB。")}
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let input=folder.appendingPathComponent("input.fmf");try Data(contentsOf:source).write(to:input,options:.atomic)
        return try run(helper:helper,app:app,arguments:["--import-tactic",input.path],folder:folder,name:"read",event:"native_tactic_parsed")
    }
    func write(helper:URL,app:URL,scenario:NativeScenario,title:String,folder:URL)throws->Data {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let input=folder.appendingPathComponent("configuration.json"),raw=folder.appendingPathComponent("tactic.tac"),fmf=folder.appendingPathComponent("verified.fmf")
        try scenario.data.write(to:input,options:.atomic)
        let written=try run(helper:helper,app:app,arguments:["--export-tactic",input.path,raw.path,"0",title],folder:folder,name:"write",event:"native_tactic_written")
        guard written.fields == (try FMFTacticFields.expected(scenario.teams[0])) else {throw LabError("原版写入的战术与工作台配置不一致，未导出。")}
        let data=try FMFArchive.tactic(plan:Data(contentsOf:raw),title:title)
        try data.write(to:fmf,options:.atomic)
        let parsed=try run(helper:helper,app:app,arguments:["--import-tactic",fmf.path],folder:folder,name:"verify",event:"native_tactic_parsed")
        guard parsed.fields==written.fields,parsed.name==title else {throw LabError("FMF 经 Mac 原版回读后与工作台不同，未导出。")}
        try JSONEncoder().encode(parsed).write(to:folder.appendingPathComponent("verification.json"),options:.atomic)
        return data
    }
}
