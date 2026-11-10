#if canImport(XCTest)
import XCTest
#else
import Foundation
#endif
#if canImport(TacticsCore)
@testable import TacticsCore
#endif

final class StatisticsWorkflowTests:XCTestCase {
    struct Seeded:RandomNumberGenerator {
        var state:UInt64=12345
        mutating func next()->UInt64 {state=state &* 6364136223846793005 &+ 1442695040888963407;return state}
    }
    func testTierRangesVariationAndReproducibility() throws {
        for tier in AbilityTier.allCases {
            var a=Workspace.example(),b=a,ra=Seeded(),rb=Seeded()
            let ids=a.players.map(\.id),slots=a.tactic.slots
            a.applyAbility(tier,scope:.team,using:&ra);b.applyAbility(tier,scope:.team,using:&rb)
            XCTAssertEqual(a,b);XCTAssertEqual(a.players.map(\.id),ids);XCTAssertEqual(a.tactic.slots,slots)
            XCTAssertTrue(a.players.allSatisfy { p in PlayerAttribute.all.allSatisfy {(1...20).contains(p.attributes[$0.id] ?? 0)} })
            XCTAssertTrue(a.players.allSatisfy { p in Attribute.allCases.allSatisfy {tier.range.contains(p.value($0))} })
            XCTAssertTrue(a.players.dropFirst().allSatisfy {($0.attributes["reflexes"] ?? 99)<=5})
            XCTAssertTrue(Set(a.players.map{$0.attributes["consistency"]!}).count>1)
            XCTAssertTrue(Set(a.players.map{$0.background!.traits["职业素养"]!}).count>1)
            XCTAssertTrue(Set(a.players.map{$0.attributes["pace"]!}).count>1)
            XCTAssertTrue(a.players.allSatisfy{Set($0.attributes.values).count>1})
            _ = try a.validated()
        }
    }
    func testExtendedAttributesAndLegacyUnknowns() throws {
        var w=Workspace.example()
        XCTAssertNil(w.players[0].attributes["corners"])
        let original=try CSV.players(CSV.playerTemplate())
        XCTAssertNil(original[0].attributes["reflexes"])
        w.players[0].attributes["corners"]=21;XCTAssertThrowsError(try w.validated())
        var rng=Seeded();w=Workspace.example();w.captureBaseline();w.addCandidate(using:&rng)
        XCTAssertEqual(w.players.count,12);XCTAssertNil(w.baseline)
        _ = try w.validated()
    }
    func testPersonnelRecoversAfterSubstitutionAndAvoidsDuplicates() throws {
        var w=Workspace.example(),rng=Seeded()
        w.addCandidate(using:&rng);w.applyAbility(.professional,scope:.team,using:&rng)
        var p=SetPiecePersonnel.initial(.attackingCorner)
        p.suggest(players:w.players,kind:.attackingCorner)
        p.takers=[w.players[8].id,w.players[10].id,w.players[11].id]
        let first=p.resolve(slots:w.tactic.slots,kind:.attackingCorner)
        XCTAssertEqual(first.count,9);XCTAssertNil(first[w.players[8].id])
        XCTAssertEqual(p.activeTaker(slots:w.tactic.slots),w.players[8].id)
        w.tactic.slots[8].playerID=w.players[11].id
        XCTAssertEqual(p.activeTaker(slots:w.tactic.slots),w.players[10].id)
        let second=p.resolve(slots:w.tactic.slots,kind:.attackingCorner)
        XCTAssertEqual(second.count,9);XCTAssertNil(second[w.players[8].id]);XCTAssertNil(second[w.players[10].id])
        try p.validate(ids:Set(w.players.map(\.id)),kind:.attackingCorner)
        p.takers.append(p.takers[0]);XCTAssertThrowsError(try p.validate(ids:Set(w.players.map(\.id)),kind:.attackingCorner))
    }
    func testUnknownAttributesDoNotGenerateRecommendations() {
        var p=SetPiecePersonnel.initial(.penalty);p.suggest(players:Workspace.example().players,kind:.penalty)
        XCTAssertTrue(p.takers.isEmpty);XCTAssertTrue(p.rankings.values.allSatisfy{$0.isEmpty})
    }
    private let csv="variant,seed,opponent,venue,goals_for,goals_against,xg_for,shots_for,shots_on_target_for,passes_for,completed_passes_for,possession_for,possession_against\nA,1,对手,home,2,0,1.8,12,5,400,300,55,45\nA,2,对手,away,0,0,,,,,,,\n"
    func testTeamMetricsMissingZeroAndRoundTrip() throws {
        let e=try Experiment.load(csv,source:"test")
        XCTAssertEqual(e.records[0].value("shots"),12)
        XCTAssertNil(e.records[1].value("shots"));XCTAssertEqual(e.records[1].value("goals"),0)
        let round=try Experiment.load(e.teamCSV,source:e.source)
        XCTAssertEqual(round,e);XCTAssertEqual(try e.validated(),e)
    }
    func testInvalidTeamStatisticsRejected() {
        for value in ["NaN","-1","12.5","10001"] {XCTAssertThrowsError(try Experiment.load(csv.replacingOccurrences(of:",12,5,",with:",\(value),5,"),source:"test"))}
        XCTAssertThrowsError(try Experiment.load(csv.replacingOccurrences(of:",12,5,",with:",12,13,"),source:"test"))
        XCTAssertThrowsError(try Experiment.load(csv.replacingOccurrences(of:",55,45",with:",0.55,0.45"),source:"test"))
    }
    func testPlayerLinkageDuplicatesAndDatasetRoundTrip() throws {
        var e=try Experiment.load(csv,source:"test")
        let header="variant,seed,opponent,venue,player_id,player_name,team,minutes,rating,goals,shots,shots_on_target\n"
        let row="A,1,对手,home,7,球员甲,for,90,7.4,2,4,2\n"
        e.playerRecords=try PlayerMatchRecord.load(header+row,experiment:e)
        XCTAssertEqual(e.playerRecords?.first?.statistics["goals"],2)
        XCTAssertThrowsError(try PlayerMatchRecord.load(header+row+row,experiment:e))
        XCTAssertThrowsError(try PlayerMatchRecord.load(header+row.replacingOccurrences(of:"A,1,",with:"A,3,"),experiment:e))
        XCTAssertThrowsError(try PlayerMatchRecord.load(header+row.replacingOccurrences(of:",4,2",with:",1,2"),experiment:e))
        XCTAssertEqual(try JSONDecoder().decode(Experiment.self,from:JSONEncoder().encode(e)).validated(),e)
        XCTAssertEqual(try PlayerMatchRecord.load(e.playerCSV,experiment:e),e.playerRecords!)
    }
}
