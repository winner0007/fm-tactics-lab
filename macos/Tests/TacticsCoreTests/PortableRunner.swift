// The Command Line Tools installation does not ship XCTest. Keep the same tests
// runnable with swiftc, while full Xcode installations use XCTest normally.
#if !canImport(XCTest)
import Foundation
class XCTestCase {}
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    do { let lhs = try a(), rhs = try b(); if lhs != rhs { fatalError("\(lhs) != \(rhs) \(message)",file:file,line:line) } }
    catch { fatalError("Unexpected error: \(error)",file:file,line:line) }
}
func XCTAssertTrue(_ value: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) { if !value() { fatalError(message,file:file,line:line) } }
func XCTAssertFalse(_ value: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) { if value() { fatalError(message,file:file,line:line) } }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { if value != nil { fatalError("Expected nil",file:file,line:line) } }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    do { _ = try expression() } catch { return }
    fatalError("Expected error: \(message)",file:file,line:line)
}
@main struct PortableRunner {
    static func main() throws {
        let suite = CoreTests()
        let workflow=WorkflowTests()
        let stats=StatisticsWorkflowTests()
        let native=NativeWorkflowTests()
        let files=TacticFileTests()
        let management=ManagementAnalysisTests()
        let strategy=StrategyTests()
        let selection=TacticSelectionTests()
        let storage=StorageWorkflowTests()
        let tests: [(String,() throws -> Void)] = [
            ("History migration preserves editor data and original files",storage.testMigrationCopiesOnlyHistoryAndKeepsOriginal),
            ("History paths reject symlinks and escapes",storage.testHistoryRejectsEscapesAndSymlinks),
            ("Tactic labels follow effective selection",storage.testTacticModeLabelsRespectInheritanceAndLocks),
            ("League tactics preserve player attributes across fixtures",storage.testLeagueTacticModesNeverRandomizePlayerAttributes),
            ("AI modes, locks and legacy league",selection.testModesLocksAndLegacyLeague),
            ("Random tactics and copying preserve personnel",selection.testRandomAndCopyPreservePersonnelAndConditions),
            ("AI generation rejects identity and input tampering",selection.testGenerationReceiptRejectsIdentityAndInputTampering),
            ("Report focus preserves frozen setup and HTML escaping",selection.testReportFocusNeverChangesFrozenSetup),
            ("Three plans share lineup and conditions, persist and respect locks",strategy.testPlanEditingSharesPlayersButKeepsTactics),
            ("Score rule priority, boundaries and invalid strategies",strategy.testRulesPriorityBoundariesAndValidation),
            ("Parallel recovery holes, duplicates and seed overflow",strategy.testMissingSeedsAllowHolesButRejectDuplicates),
            ("Team locks and replacement boundaries",management.testLocksProtectReplacementAndAllowPersonnel),
            ("Only exact verified engine profiles accepted",management.testInstalledFilesDoNotAuthorizeNewEngine),
            ("League engine version pinned across resume",management.testLeagueVersionPinSurvivesPersistence),
            ("Tactic execution fingerprints",management.testTacticFingerprintUsesExecutionNotNamesOrAbility),
            ("Opponent tactics breakdown and frozen reports",management.testOpponentBreakdownCountsBothSidesAndKeepsSnapshots),
            ("Full independent named team snapshots",files.testTeamPresetRetainsFullTeamWithoutOpponent),
            ("FMF phase mapping, duty and preserved team data",files.testFMFPhaseMappingAndTeamIsolation),
            ("FMF unknown and conflicting data rejected",files.testFMFRejectsUnrepresentableInputs),
            ("All upstream formations and contextual roles",native.testFormationsAndRoleContexts),
            ("Upstream phase cell swap",native.testDragMatchesUpstreamCellsAndKeepsOtherPhase),
            ("Scenario determinism and marking targets",native.testScenarioDeterminismAndTargets),
            ("Native set-piece validation",native.testNativeSetPieceValidationAndDefaultIDs),
            ("Position profiles and independent hidden data",native.testPositionSpecificRandomAndHiddenIndependence),
            ("Odd/even round-robin schedules",native.testRoundRobinAndScheduleValidation),
            ("Spanish tie reapplication and unresolved rank",native.testSpanishTieReapplicationAndUnresolvedTies),
            ("Imported edits and input boundaries",native.testImportedEditsAndInputBoundaries),
            ("Tier ranges variability and seeded replay",stats.testTierRangesVariationAndReproducibility),
            ("Extended attributes missing data and candidates",stats.testExtendedAttributesAndLegacyUnknowns),
            ("Set piece priority and substitute fallback",stats.testPersonnelRecoversAfterSubstitutionAndAvoidsDuplicates),
            ("Unknown attributes not ranked",stats.testUnknownAttributesDoNotGenerateRecommendations),
            ("Team metrics missing versus zero and export",stats.testTeamMetricsMissingZeroAndRoundTrip),
            ("Invalid team stats rejected",stats.testInvalidTeamStatisticsRejected),
            ("Player stats linkage and dataset round trip",stats.testPlayerLinkageDuplicatesAndDatasetRoundTrip),
            ("Workspace round trip & phases",suite.testWorkspaceRoundTripAndPhaseIndependence),
            ("Input validation",suite.testRejectsInvalidLineupAndAttributes),
            ("Baseline differences",suite.testBaselineDiffDetectsInstructionsAndLineup),
            ("Baseline player snapshot",suite.testBaselineRestoresPlayerAttributes),
            ("Explainable analysis",suite.testAnalysisRespondsToActualPlayersAndInstructions),
            ("CSV quoting & Unicode",suite.testCSVHandlesBOMQuotesCommasNewlinesAndTrailingEmptyCells),
            ("Malformed CSV",suite.testCSVRejectsBrokenAndDuplicateHeaders),
            ("Player template & bounds",suite.testPlayerCSVTemplateAndValidation),
            ("Upstream CSV compatibility",suite.testUpstreamChineseCSVAndUnpairedResults),
            ("Opponent & venue pairing",suite.testPairingSeparatesOpponentAndVenue),
            ("Failed & duplicate matches",suite.testFailuresExcludedAndDuplicateKeysRejected),
            ("Score & xG validation",suite.testScoresAndXGValidation),
            ("Bootstrap boundaries",suite.testBootstrapRequiresEnoughPairsAndIsDeterministic),
            ("Mach-O architectures",suite.testMachOArchitecturesAndTruncation),
            ("Engine capability gate",suite.testEngineNeverClaimsSimulationFromFilePresence),
            ("Drop swap preserves tasks and phases",workflow.testDropSwapsPlayersAndPreservesBothPhaseTasks),
            ("Drop hit testing and clamping",workflow.testFreeDropClampsAndUsesActualPitchSize),
            ("Ability scopes and baseline",workflow.testAbilityTeamPositionIndividualAndBaseline),
            ("Random ability and multi-position",workflow.testRandomPresetsAndMultiPositionMatching),
            ("Set piece and instruction snapshots",workflow.testSetPiecesPhaseInstructionsPersistenceAndBaseline),
            ("Invalid tactical configuration",workflow.testInvalidInstructionsTakersAndUnknownTraitsRejected),
            ("Standard versus custom conditions",workflow.testStandardConditionsIgnoreStoredCustomFatigue),
            ("v0.1 JSON compatibility",workflow.testOldWorkspaceWithoutNewFieldsStillLoads),
            ("Custom Steam libraries and stale installs",workflow.testSteamLibraryAutodiscoverySkipsIncompleteInstallation),
            ("Applications external and preferred paths",workflow.testApplicationsExternalAndRememberedPathSearch),
            ("Manual folder and missing game fallback",workflow.testManualFolderWrongVersionAndMissingGame),
            ("External Application Support Steam",workflow.testExternalApplicationSupportSteamWithoutHomeSymlink),
            ("Manual Steam library levels and symlink",workflow.testManualSteamLibraryAtEverySupportedLevel),
            ("Manual search scope and actionable errors",workflow.testManualSearchDoesNotFallBackToUnrelatedInstall),
            ("Other user library and unsupported build",workflow.testOtherMachineLibrarySearchAndUnsupportedBuild)
        ]
        for (name,test) in tests { try test(); print("PASS \(name)") }
        print("\(tests.count) core checks passed")
    }
}
#endif
