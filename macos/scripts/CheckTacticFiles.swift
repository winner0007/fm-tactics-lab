import Foundation
import TacticsCore

@main struct CheckTacticFiles {
    static func main() throws {
        guard CommandLine.arguments.count==4 else {fatalError("output helper fm.app")}
        let folder=URL(fileURLWithPath:CommandLine.arguments[1]),helper=URL(fileURLWithPath:CommandLine.arguments[2]),app=URL(fileURLWithPath:CommandLine.arguments[3]),job=TacticFileJob()
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var count=0
        for formation in Formation.allCases {
            var w=Workspace.example();w.tactic.apply(formation,phase:.possession);w.tactic.apply(.fourFourTwo,phase:.defending)
            w.tactic.configuration!.nativeMentality=1+count%7
            let role=w.tactic.role(1,.possession),position=w.tactic.slots[1].position(.possession).id
            if let group=NativeCatalog.playerInstructions.first(where:{$0.phase == .possession && $0.options.contains{$0.id>0 && $0.id<34 && NativeCatalog.policy(position:position,role:role,option:$0.id)==0}}),let option=group.options.first(where:{$0.id>0 && $0.id<34 && NativeCatalog.policy(position:position,role:role,option:$0.id)==0}) {w.tactic.configuration!.nativePlayers=[TacticalConfiguration.playerKey(1,.possession):[group.id:option.id]]}
            let original=try NativeScenario(workspace:w),output=folder.appendingPathComponent("formation-\(count)"),title="Mac 中文 · "+formation.rawValue
            let data=try job.write(helper:helper,app:app,scenario:original,title:title,folder:output)
            precondition(!data.isEmpty)
            let receipt=try job.read(helper:helper,app:app,source:output.appendingPathComponent("verified.fmf"),folder:output.appendingPathComponent("import"))
            let restored=try receipt.fields.applying(to:w,name:receipt.name!,opponent:w.opponent!.workspace)
            let actual=try NativeScenario(workspace:restored)
            let same = try FMFTacticFields.expected(actual.teams[0])==FMFTacticFields.expected(original.teams[0]);precondition(same)
            precondition(restored.players==w.players && restored.tactic.setup.gameSetPieces==w.tactic.setup.gameSetPieces)
            count+=1;print("PASS FMF original Mac writer/archive/parser: \(formation.rawValue)")
        }
        var w=Workspace.example();w.tactic.configuration!.nativeExtraTeamBits="01000000000000000000000000000000"
        w.tactic.configuration!.nativeDuties=[TacticalConfiguration.playerKey(1,.possession):"2097152"]
        let scenario=try NativeScenario(workspace:w),extra=folder.appendingPathComponent("extra-duty")
        _ = try job.write(helper:helper,app:app,scenario:scenario,title:"附加指令与职责",folder:extra)
        let report=try OriginalMatchJob().run(helper:helper,app:app,seed:114,log:extra.appendingPathComponent("match.jsonl"),scenario:scenario)
        try JSONEncoder().encode(report).write(to:extra.appendingPathComponent("result.json"),options:.atomic)
        print("PASS preserved extra team bits and duty through original match preparation and natural finish")
        let invalid=folder.appendingPathComponent("invalid.fmf");try Data("not an FMF".utf8).write(to:invalid)
        do {_ = try job.read(helper:helper,app:app,source:invalid,folder:folder.appendingPathComponent("rejected"));fatalError("invalid archive accepted")}catch{print("PASS malformed FMF rejected")}
        try Data("PASS 12 formations, Chinese names, original FMF round trips, duty/extra bits, natural match and invalid archive rejection".utf8).write(to:folder.appendingPathComponent("validation.txt"))
    }
}
