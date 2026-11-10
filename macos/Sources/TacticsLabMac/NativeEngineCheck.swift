import Foundation
import TacticsCore

struct NativeEngineCheck:Codable {
    let loaded:Bool
    let simulationReady:Bool
    let matchesExecuted:Int
    let appPath:String
    let architecture:String
    let error:String
    let symbols:[String:Bool]
    let timestamp:Double

    static func run(helper:URL,app:URL) throws -> NativeEngineCheck {
        let process=Process(),out=Pipe(),err=Pipe()
        process.executableURL=helper;process.arguments=[app.path]
        process.standardOutput=out;process.standardError=err
        // Child also has alarm(20). It never receives a save or writes to fm.app.
        try process.run()
        process.waitUntilExit()
        let data=out.fileHandleForReading.readDataToEndOfFile()
        let stderr=err.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else {throw LabError("加载验证进程退出（\(process.terminationStatus)）。\n"+(String(data:stderr,encoding:.utf8) ?? "无日志"))}
        return try JSONDecoder().decode(NativeEngineCheck.self,from:data)
    }
}
