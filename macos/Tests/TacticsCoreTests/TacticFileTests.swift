#if canImport(XCTest)
import XCTest
#else
import Foundation
#endif
#if canImport(TacticsCore)
@testable import TacticsCore
#endif

final class TacticFileTests:XCTestCase {
    func testTeamPresetRetainsFullTeamWithoutOpponent()throws {
        var w=Workspace.example(),rng=StatisticsWorkflowTests.Seeded()
        w.addCandidate(using:&rng);w.applyAbility(.professional,scope:.team,using:&rng);w.captureBaseline()
        w.tactic.configuration!.conditions.custom=true;w.tactic.configuration!.conditions.condition=82
        let preset=try TeamPreset(name:"  杯赛轮换  ",plan:w),restored=try TeamPreset.decode(preset.data)
        XCTAssertEqual(restored,preset);XCTAssertEqual(preset.name,"杯赛轮换")
        XCTAssertEqual(preset.plan.players,w.players);XCTAssertEqual(preset.plan.tactic,w.tactic)
        XCTAssertNil(preset.plan.opponent);XCTAssertNil(preset.plan.baseline)
        var bad=preset;bad.schema="other";XCTAssertThrowsError(try bad.validated())
        bad=preset;bad.plan.opponent=w.opponent;XCTAssertThrowsError(try bad.validated())
        XCTAssertThrowsError(try TeamPreset(name:" ",plan:w))
    }
    func testFMFPhaseMappingAndTeamIsolation()throws {
        var source=Workspace.example(),target=Workspace.example(),rng=StatisticsWorkflowTests.Seeded()
        source.tactic.apply(.threeFiveTwo,phase:.possession)
        source.tactic.configuration!.nativeMentality=7
        source.tactic.configuration!.nativeDuties=[TacticalConfiguration.playerKey(1,.possession):"2097152"]
        source.tactic.configuration!.nativeExtraTeamBits="01000000000000000000000000000000"
        target.applyAbility(.amateur,scope:.team,using:&rng)
        let input=try NativeScenario(workspace:source),fields=try FMFTacticFields.expected(input.teams[0])
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(fields)) as! [String:Any]
        var phases=object["phases"] as! [[[String:Any]]];phases[1].swapAt(1,2)
        var mapping=Array(0..<11);mapping.swapAt(1,2);object["mapping"]=mapping;object["phases"]=phases
        let reordered=try JSONDecoder().decode(FMFTacticFields.self,from:JSONSerialization.data(withJSONObject:object))
        let value=try reordered.applying(to:target,name:"Imported",opponent:target.opponent!.workspace)
        XCTAssertEqual(value.players,target.players);XCTAssertEqual(value.opponent,target.opponent)
        XCTAssertEqual(value.tactic.setup.gameSetPieces,target.tactic.setup.gameSetPieces)
        XCTAssertEqual(value.tactic.setup.conditions,target.tactic.setup.conditions)
        XCTAssertEqual(value.tactic.slots.map(\.playerID),target.tactic.slots.map(\.playerID))
        let actual=try NativeScenario(workspace:value).teams[0]
        XCTAssertEqual(try FMFTacticFields.expected(actual),fields)
    }
    func testFMFRejectsUnrepresentableInputs()throws {
        let w=Workspace.example(),f=try FMFTacticFields.expected(NativeScenario(workspace:w).teams[0])
        var obj=try JSONSerialization.jsonObject(with:JSONEncoder().encode(f)) as! [String:Any]
        obj["mapping"]=Array(repeating:0,count:11)
        var bad=try JSONDecoder().decode(FMFTacticFields.self,from:JSONSerialization.data(withJSONObject:obj))
        XCTAssertThrowsError(try bad.applying(to:w,name:"invalid",opponent:w.opponent!.workspace))
        obj["mapping"]=Array(0..<11)
        var phases=obj["phases"] as! [[[String:Any]]];phases[0][1]["flags"]=String(UInt64(1)<<63);obj["phases"]=phases
        bad=try JSONDecoder().decode(FMFTacticFields.self,from:JSONSerialization.data(withJSONObject:obj))
        XCTAssertThrowsError(try bad.applying(to:w,name:"invalid",opponent:w.opponent!.workspace))
        XCTAssertThrowsError(try FMFTacticFields.validateExtras("zz"))
        XCTAssertThrowsError(try FMFArchive.tactic(plan:Data(),title:"test"))
    }
}
