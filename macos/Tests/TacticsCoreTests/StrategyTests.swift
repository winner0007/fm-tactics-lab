#if canImport(XCTest)
import XCTest
#else
import Foundation
#endif
#if canImport(TacticsCore)
@testable import TacticsCore
#endif

final class StrategyTests:XCTestCase {
    func testPlanEditingSharesPlayersButKeepsTactics()throws {
        var w=Workspace.example();let name=w.tactic.name,initial=try NativeScenario(workspace:w)
        w.createStrategy();XCTAssertEqual(try NativeScenario(workspace:w),initial)
        w.selectStrategyPlan(1);w.tactic.apply(.fourFourTwo,phase:.possession);w.tactic.configuration!.nativeMentality=7
        let replacement=w.tactic.slots[1].playerID;w.tactic.slots[1].playerID=w.tactic.slots[2].playerID;w.tactic.slots[2].playerID=replacement
        w.tactic.configuration!.conditions.custom=true;w.tactic.configuration!.conditions.condition=85
        w.selectStrategyPlan(0)
        XCTAssertEqual(w.tactic.name,name);XCTAssertEqual(w.strategyPlans[1].formation,Formation.fourFourTwo.rawValue)
        XCTAssertEqual(w.strategyPlans[1].setup.nativeMentality,7)
        XCTAssertEqual(w.strategyPlans[0].slots.map(\.playerID),w.strategyPlans[1].slots.map(\.playerID))
        XCTAssertEqual(w.strategyPlans[0].setup.conditions,w.strategyPlans[1].setup.conditions)
        w.matchStrategy!.enabled=true
        let scenario=try NativeScenario(workspace:w);XCTAssertEqual(scenario.schemaVersion,2)
        let decoded=try JSONDecoder().decode(Workspace.self,from:JSONEncoder().encode(w)).validated()
        XCTAssertEqual(try NativeScenario(workspace:decoded),scenario)
        w.management.tacticLocked=true;var next=w;next.selectStrategyPlan(2);try w.checkReplacement(next)
        next.tactic.configuration!.nativeMentality=7;XCTAssertThrowsError(try w.checkReplacement(next))
    }
    func testRulesPriorityBoundariesAndValidation()throws {
        var w=Workspace.example();w.createStrategy();w.matchStrategy!.enabled=true
        let native=try NativeScenario(workspace:w).teams[0].strategy!
        XCTAssertEqual(native.target(minute:59,difference:-1)?.0,0)
        XCTAssertEqual(native.target(minute:60,difference:-1)?.0,1)
        XCTAssertEqual(native.target(minute:60,difference:2)?.0,0)
        XCTAssertEqual(native.target(minute:60,difference:3)?.0,2)
        XCTAssertEqual(native.target(minute:120,difference:3)?.0,2)
        w.matchStrategy!.rules[1].condition = .any
        XCTAssertEqual(try NativeScenario(workspace:w).teams[0].strategy!.target(minute:70,difference:-1)?.0,1)
        w.matchStrategy!.rules[0].throughMinute=10;XCTAssertThrowsError(try w.validated())
        w.matchStrategy!.rules[0].throughMinute=120;w.matchStrategy!.cooldownMinutes=0;XCTAssertThrowsError(try w.validated())
        w.matchStrategy!.cooldownMinutes=10;w.matchStrategy!.planNames=[];XCTAssertThrowsError(try w.validated())
    }
    func testMissingSeedsAllowHolesButRejectDuplicates()throws {
        XCTAssertEqual(try SimulationConcurrency.missing(requested:6,firstSeed:100,seeds:[105,101,103]),[0,2,4])
        XCTAssertThrowsError(try SimulationConcurrency.missing(requested:6,firstSeed:100,seeds:[101,101]))
        XCTAssertThrowsError(try SimulationConcurrency.missing(requested:6,firstSeed:100,seeds:[106]))
        XCTAssertThrowsError(try SimulationConcurrency.missing(requested:6,firstSeed:UInt32.max,seeds:[]))
    }
}
