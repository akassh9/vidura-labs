import Foundation

private struct HarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func fail(_ message: String) throws -> Never {
    throw HarnessFailure(description: message)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        try fail(message)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        try fail("\(message): expected \(expected), got \(actual)")
    }
}

private func expectContains(_ haystack: String, _ needle: String, _ message: String) throws {
    if !haystack.contains(needle) {
        try fail("\(message): missing \(needle)")
    }
}

private func expectFinding(
    _ findings: [RunQualityFinding],
    id: String,
    severity: RunQualitySeverity,
    _ message: String
) throws {
    guard let finding = findings.first(where: { $0.id == id }) else {
        try fail("\(message): missing \(id)")
    }
    try expectEqual(finding.severity, severity, "\(message) severity")
}

private func testSummaryParsing() throws {
    let parsed = RunnerService.parseSummaryLines("""
    generated_events=200
    mean_pt 42.5
    status stable value
    ignored_single_token
    leading_spaces = trimmed
    """)

    try expectEqual(parsed["generated_events"] as? Int, 200, "summary parser preserves integer values")
    try expectEqual(parsed["mean_pt"] as? Double, 42.5, "summary parser preserves floating-point values")
    try expectEqual(parsed["status"] as? String, "stable value", "summary parser preserves string tails")
    try expectEqual(parsed["leading_spaces"] as? String, "trimmed", "summary parser trims key/value whitespace")
    try expect(parsed["ignored_single_token"] == nil, "summary parser ignores malformed lines")
}

private func testDeterministicCodegen() throws {
    let chargedMultiplicity = ObservableSpec(
        id: "charged_multiplicity",
        kind: "hist1d",
        source: "particle",
        op: "count",
        selector: "isFinal && isCharged",
        bins: 100,
        min: -0.5,
        max: 799.5,
        outputKeys: ["mean_charged"]
    )
    let ptSpectrum = ObservableSpec(
        id: "pt_spectrum",
        kind: "hist1d",
        unit: "GeV",
        source: "particle",
        op: "pT",
        selector: "isFinal && isCharged",
        bins: 80,
        min: 0.0,
        max: 200.0,
        outputKeys: ["mean_pt"]
    )
    let spec = SimulationSpec(
        runId: "regression-fixture",
        pythiaTag: "8.3",
        seed: 13579,
        beams: BeamSpec(frameType: "pp", eCmGev: 13_000),
        processSettings: ["HardQCD:all = on"],
        cutsSettings: ["PhaseSpace:pTHatMin = 18.5"],
        eventCount: 200,
        observables: [chargedMultiplicity, ptSpectrum],
        analysisPlan: AnalysisPlan(
            family: "charged_multiplicity",
            selectors: ["isFinal", "isCharged"],
            observables: [chargedMultiplicity]
        ),
        outputPlan: OutputPlan(
            summaryJson: true,
            logs: true,
            plots: true,
            extraFiles: ["hist_primary.txt", "hist_pt.txt"]
        )
    )

    let generated = CodegenAgent.run(spec: spec)
    try expectEqual(generated.origin, "deterministic", "codegen origin")
    try expectContains(generated.sourceCode, "Random:seed = 13579", "codegen emits deterministic seed")
    try expectContains(generated.sourceCode, "PhaseSpace:pTHatMin = 18.5", "codegen emits pTHatMin cut")
    try expectContains(generated.sourceCode, "for (int iEvent = 0; iEvent < 200; ++iEvent)", "codegen emits event count loop")
    try expectContains(generated.sourceCode, "std::ofstream histFile(\"hist_primary.txt\");", "codegen emits primary histogram")
    try expectContains(generated.sourceCode, "std::ofstream histPtFile(\"hist_pt.txt\");", "codegen emits secondary pT histogram")
}

private func testRunLineage() throws {
    let sourceRunId = "55C18C16-54E4-4A3C-BFFE-DEEE030A7459"
    let exactRunId = "NEW-EXACT-RERUN-FIXTURE"
    let variantRunId = "B28DBDBC-B49D-4F40-AC6B-7F85113744B1"
    let historicalSourceRunId = "CC4B3F6C-83A1-44EB-9EBA-70FB6B995ACE"
    let historicalExactRunId = "98CA353A-941B-4B5A-B6A6-070D89FDE59F"

    let source = RunLineageRunSnapshot(id: sourceRunId, configuration: [:])
    let exact = RunLineageRunSnapshot(
        id: exactRunId,
        configuration: ["Vidura:exactRerunOfRunID": sourceRunId]
    )
    let variant = RunLineageRunSnapshot(
        id: variantRunId,
        configuration: [
            "Vidura:variantOfRunID": sourceRunId,
            "Vidura:variantChanges": "event_count 10000 -> 200; seed 625434 -> 13579; PhaseSpace:pTHatMin unset -> 18.5"
        ]
    )
    let historicalSource = RunLineageRunSnapshot(id: historicalSourceRunId, configuration: [:])
    let historicalExact = RunLineageRunSnapshot(id: historicalExactRunId, configuration: [:])
    let runs = [source, exact, variant, historicalSource, historicalExact]
    let messages = [
        RunLineageMessageSnapshot(
            content: "Rerun exact from run \(historicalSourceRunId)",
            originRunId: historicalExactRunId
        )
    ]

    let originalLineage = RunLineageResolver.classification(for: source, in: runs, messages: messages)
    try expectEqual(originalLineage.kind, .original, "source smoke run is original")
    try expect(originalLineage.sourceRunId == nil, "source smoke run has no source")

    let exactLineage = RunLineageResolver.classification(for: exact, in: runs, messages: messages)
    try expectEqual(exactLineage.kind, .exactRerun, "new exact rerun is exact")
    try expectEqual(exactLineage.sourceRunId, sourceRunId, "new exact rerun preserves source id")
    try expectEqual(exactLineage.isInferred, false, "new exact rerun is explicit")

    let variantLineage = RunLineageResolver.classification(for: variant, in: runs, messages: messages)
    try expectEqual(variantLineage.kind, .variant, "variant smoke run is variant")
    try expectEqual(variantLineage.sourceRunId, sourceRunId, "variant preserves source id")
    try expectEqual(variantLineage.changes.count, 3, "variant changes split into three entries")
    try expect(variantLineage.changes.contains("PhaseSpace:pTHatMin unset -> 18.5"), "variant changes preserve pTHatMin")

    let inferredLineage = RunLineageResolver.classification(for: historicalExact, in: runs, messages: messages)
    try expectEqual(inferredLineage.kind, .exactRerun, "historical fixture infers exact rerun")
    try expectEqual(inferredLineage.sourceRunId, historicalSourceRunId, "historical fixture source id")
    try expectEqual(inferredLineage.isInferred, true, "historical fixture is marked inferred")

    let relationship = RunLineageResolver.relationship(
        between: source,
        and: variant,
        in: runs,
        messages: messages
    )
    try expectEqual(relationship?.sourceRunId, sourceRunId, "relationship source id")
    try expectEqual(relationship?.derivedRunId, variantRunId, "relationship derived id")
    try expectEqual(relationship?.kind, .variant, "relationship kind")
}

private func testRunQualityAnalyzer() throws {
    let healthyFindings = RunQualityAnalyzer.analyze(qualityInput())
    try expectFinding(healthyFindings, id: "quality-pass", severity: .info, "healthy run pass state")
    try expect(!healthyFindings.contains(where: { $0.severity != .info }), "healthy run has no warning/error findings")

    let missingFindings = RunQualityAnalyzer.analyze(qualityInput(
        artifacts: qualityArtifacts(excluding: ["compile.log", "hist_primary.txt"])
    ))
    try expectFinding(
        missingFindings,
        id: "missing-evidence-compile.log",
        severity: .error,
        "missing compile log"
    )
    try expectFinding(
        missingFindings,
        id: "missing-output-hist_primary.txt",
        severity: .error,
        "missing declared output"
    )

    let emptyFindings = RunQualityAnalyzer.analyze(qualityInput(
        artifacts: qualityArtifacts(byteSizes: ["hist_primary.txt": 0])
    ))
    try expectFinding(
        emptyFindings,
        id: "empty-output-hist_primary.txt",
        severity: .error,
        "empty declared output"
    )

    let lowEventFindings = RunQualityAnalyzer.analyze(qualityInput(eventCount: 200, summaryEvents: 200))
    try expectFinding(lowEventFindings, id: "low-event-count", severity: .warning, "low event count")

    let mismatchFindings = RunQualityAnalyzer.analyze(qualityInput(eventCount: 300, summaryEvents: 200))
    try expectFinding(
        mismatchFindings,
        id: "event-count-mismatch",
        severity: .error,
        "event count mismatch"
    )

    let overflowAndLogFindings = RunQualityAnalyzer.analyze(qualityInput(
        summaryMetrics: [
            "generated_events": "10000",
            "hist_primary.overflow": "3"
        ],
        compileLog: "clang warning: argument unused during compilation"
    ))
    try expectFinding(
        overflowAndLogFindings,
        id: "histogram-overflow-hist_primary-overflow",
        severity: .warning,
        "histogram overflow"
    )
    try expectFinding(
        overflowAndLogFindings,
        id: "log-warning-compile.log",
        severity: .warning,
        "compile warning marker"
    )

    let cutFindings = RunQualityAnalyzer.analyze(qualityInput(
        title: "Minimum-bias charged multiplicity",
        processSettings: ["HardQCD:all = on"],
        cutsSettings: ["PhaseSpace:pTHatMin = 18.5"]
    ))
    try expectFinding(
        cutFindings,
        id: "inclusive-interpretation-with-hard-cuts",
        severity: .warning,
        "inclusive/minimum-bias cut warning"
    )
}

private func qualityInput(
    title: String = "Charged multiplicity",
    eventCount: Int = 10_000,
    summaryEvents: Int = 10_000,
    summaryMetrics: [String: String]? = nil,
    artifacts: [RunQualityArtifactSnapshot]? = nil,
    processSettings: [String] = ["SoftQCD:nonDiffractive = on"],
    cutsSettings: [String] = [],
    compileLog: String = "",
    runLog: String = ""
) -> RunQualityInput {
    RunQualityInput(
        run: RunQualityRunSnapshot(
            id: "quality-fixture",
            title: title,
            status: "completed",
            eventCount: eventCount,
            configuration: ["event_count": "\(eventCount)"]
        ),
        spec: RunQualitySpecSnapshot(
            eventCount: eventCount,
            analysisFamily: "charged_multiplicity",
            outputFiles: ["summary_lines.txt", "hist_primary.txt"],
            processSettings: processSettings,
            cutsSettings: cutsSettings
        ),
        summaryMetrics: summaryMetrics ?? ["generated_events": "\(summaryEvents)"],
        artifacts: artifacts ?? qualityArtifacts(),
        compileLog: compileLog,
        runLog: runLog
    )
}

private func qualityArtifacts(
    excluding excludedNames: Set<String> = [],
    byteSizes: [String: UInt64] = [:]
) -> [RunQualityArtifactSnapshot] {
    [
        "run.cc",
        "simulation_spec.json",
        "summary.json",
        "summary_lines.txt",
        "compile.log",
        "run.log",
        "hist_primary.txt"
    ]
    .filter { !excludedNames.contains($0) }
    .map { name in
        RunQualityArtifactSnapshot(
            label: name,
            kind: name.hasPrefix("hist_") ? "data" : "evidence",
            path: "/tmp/vidura-quality-fixture/\(name)",
            byteSize: byteSizes[name] ?? 128
        )
    }
}

let tests: [(String, () throws -> Void)] = [
    ("RunnerService.parseSummaryLines", testSummaryParsing),
    ("CodegenAgent.run(spec:)", testDeterministicCodegen),
    ("RunLineageResolver", testRunLineage),
    ("RunQualityAnalyzer", testRunQualityAnalyzer)
]

do {
    for (name, test) in tests {
        try test()
        print("PASS \(name)")
    }
    print("Reproducibility regression harness passed.")
} catch {
    fputs("FAIL \(error)\n", stderr)
    exit(1)
}
