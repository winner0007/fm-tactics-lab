import Foundation
import TacticsCore

final class SaveReaderJob:@unchecked Sendable {
    private let lock=NSLock()
    private var process:Process?
    private var cancelled=false
    func cancel(){lock.lock();defer{lock.unlock()};cancelled=true;if process?.isRunning==true {process?.terminate()}}
    func run(helper:URL,source:URL,folder:URL,clubs:[Int]=[],hash:String?=nil)throws->Data {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let output=folder.appendingPathComponent("data.json"),log=folder.appendingPathComponent("reader.log")
        try Data().write(to:log);let handle=try FileHandle(forWritingTo:log);defer{try? handle.close()}
        let p=Process();p.executableURL=helper;p.arguments=[source.path,output.path]
        if !clubs.isEmpty {p.arguments! += ["--clubs",clubs.map(String.init).joined(separator:",")]}
        if let hash {p.arguments! += ["--expected-sha256",hash]}
        p.standardOutput=handle;p.standardError=handle
        lock.lock();if cancelled {lock.unlock();throw LabError("数据读取已取消。")};process=p
        do {try p.run();lock.unlock()}catch{process=nil;lock.unlock();throw error}
        let timeout=DispatchWorkItem{[weak self] in self?.cancel()}
        DispatchQueue.global().asyncAfter(deadline:.now()+310,execute:timeout)
        p.waitUntilExit();timeout.cancel();try handle.synchronize()
        lock.lock();process=nil;let stopped=cancelled;lock.unlock()
        guard !stopped,p.terminationStatus==0 else {
            let lines=(try? String(contentsOf:log,encoding:.utf8)) ?? ""
            let failure=lines.split(separator:"\n").reversed().compactMap{try? JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:Any]}.first? ["error"] as? String
            throw LabError(stopped ? "数据读取已取消或超过时限。":failure ?? "数据读取失败。原文件未修改，诊断日志已保留。")
        }
        guard (try output.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<=60_000_000 else {throw LabError("读取结果超过 60 MB，请减少导入球队。")}
        return try Data(contentsOf:output)
    }
}
