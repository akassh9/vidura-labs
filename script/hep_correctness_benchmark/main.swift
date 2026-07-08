import Foundation

private struct BenchmarkFailure: Error, CustomStringConvertible {
    let description: String
}

private struct BenchmarkTask: Decodable {
    let id: String
    let title: String
    let category: String
    let prompt: String
    let fixtures: BenchmarkFixtures
    let expectedFindings: [ExpectedFinding]
    let competitorOutputs: [CompetitorOutput]
    let notes: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case prompt
        case fixtures
        case expectedFindings = "expected_findings"
        case competitorOutputs = "competitor_outputs"
        case notes
    }
}

private struct BenchmarkFixtures: Decodable {
    let runMetadata: RunMetadataFixture
    let simulationSpec: SpecFixture?
    let summaryMetrics: [String: String]
    let artifacts: [ArtifactFixture]
    let compileLog: String?
    let runLog: String?
    let chartPayloads: [ChartPayload]
    let referencePack: HEPReferencePack?
    let assistantInterpretation: String
    let offlineReviewerResponse: JSONValue?

    enum CodingKeys: String, CodingKey {
        case runMetadata = "run_metadata"
        case simulationSpec = "simulation_spec"
        case summaryMetrics = "summary_metrics"
        case artifacts
        case compileLog = "compile_log"
        case runLog = "run_log"
        case chartPayloads = "chart_payloads"
        case referencePack = "reference_pack"
        case assistantInterpretation = "assistant_interpretation"
        case offlineReviewerResponse = "offline_reviewer_response"
    }
}

private struct RunMetadataFixture: Decodable {
    let id: String
    let title: String
    let status: String
    let eventCount: Int?
    let configuration: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case eventCount = "event_count"
        case configuration
    }
}

private struct SpecFixture: Decodable {
    let eventCount: Int?
    let analysisFamily: String?
    let outputFiles: [String]
    let processSettings: [String]
    let cutsSettings: [String]

    enum CodingKeys: String, CodingKey {
        case eventCount = "event_count"
        case analysisFamily = "analysis_family"
        case outputFiles = "output_files"
        case processSettings = "process_settings"
        case cutsSettings = "cuts_settings"
    }
}

private struct ArtifactFixture: Decodable {
    let label: String
    let kind: String
    let path: String
    let byteSize: UInt64?

    enum CodingKeys: String, CodingKey {
        case label
        case kind
        case path
        case byteSize = "byte_size"
    }
}

private struct ExpectedFinding: Decodable, Encodable {
    let category: String
    let severity: RunQualitySeverity
    let mustInclude: [String]
    let evidenceRefs: [String]
    let referenceIds: [String]

    enum CodingKeys: String, CodingKey {
        case category
        case severity
        case mustInclude = "must_include"
        case evidenceRefs = "evidence_refs"
        case referenceIds = "reference_ids"
    }
}

private struct CompetitorOutput: Decodable, Encodable {
    let label: String
    let interpretation: String
    let knownFailures: [String]

    enum CodingKeys: String, CodingKey {
        case label
        case interpretation
        case knownFailures = "known_failures"
    }
}

private struct RawReviewerResponse: Decodable {
    let findings: [RawReviewerFinding]
}

private struct RawReviewerFinding: Decodable {
    let referenceIds: [String]

    enum CodingKeys: String, CodingKey {
        case referenceIds = "reference_ids"
    }
}

private struct BenchmarkFinding: Codable {
    let source: String
    let id: String
    let category: String
    let severity: RunQualitySeverity
    let message: String
    let evidenceRefs: [String]
    let referenceIds: [String]

    enum CodingKeys: String, CodingKey {
        case source
        case id
        case category
        case severity
        case message
        case evidenceRefs = "evidence_refs"
        case referenceIds = "reference_ids"
    }
}

private struct TaskReport: Codable {
    let id: String
    let title: String
    let category: String
    let passed: Bool
    let expectedCount: Int
    let matchedCount: Int
    let falsePositiveCount: Int
    let missingExpectations: [ExpectedFinding]
    let findings: [BenchmarkFinding]
    let competitorOutputs: [CompetitorOutput]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case passed
        case expectedCount = "expected_count"
        case matchedCount = "matched_count"
        case falsePositiveCount = "false_positive_count"
        case missingExpectations = "missing_expectations"
        case findings
        case competitorOutputs = "competitor_outputs"
    }
}

private struct BenchmarkReport: Codable {
    let formatVersion: Int
    let generatedAt: String
    let offline: Bool
    let taskCount: Int
    let passedTaskCount: Int
    let failedTaskCount: Int
    let expectedFindingCount: Int
    let matchedFindingCount: Int
    let falsePositiveCount: Int
    let tasks: [TaskReport]

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case generatedAt = "generated_at"
        case offline
        case taskCount = "task_count"
        case passedTaskCount = "passed_task_count"
        case failedTaskCount = "failed_task_count"
        case expectedFindingCount = "expected_finding_count"
        case matchedFindingCount = "matched_finding_count"
        case falsePositiveCount = "false_positive_count"
        case tasks
    }
}

private enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    var foundationObject: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .object(let value): return value.mapValues(\.foundationObject)
        case .array(let value): return value.map(\.foundationObject)
        case .null: return NSNull()
        }
    }

    var prettyJSONString: String? {
        guard JSONSerialization.isValidJSONObject(foundationObject),
              let data = try? JSONSerialization.data(
                withJSONObject: foundationObject,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

private func loadTasks(from directory: URL) throws -> [BenchmarkTask] {
    let files = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

    let decoder = JSONDecoder()
    return try files.map { url in
        do {
            return try decoder.decode(BenchmarkTask.self, from: Data(contentsOf: url))
        } catch {
            throw BenchmarkFailure(description: "Failed to decode \(url.path): \(error)")
        }
    }
}

private func evaluate(_ task: BenchmarkTask) -> TaskReport {
    let qualityInput = RunQualityInput(
        run: RunQualityRunSnapshot(
            id: task.fixtures.runMetadata.id,
            title: task.fixtures.runMetadata.title,
            status: task.fixtures.runMetadata.status,
            eventCount: task.fixtures.runMetadata.eventCount,
            configuration: task.fixtures.runMetadata.configuration
        ),
        spec: task.fixtures.simulationSpec.map {
            RunQualitySpecSnapshot(
                eventCount: $0.eventCount,
                analysisFamily: $0.analysisFamily,
                outputFiles: $0.outputFiles,
                processSettings: $0.processSettings,
                cutsSettings: $0.cutsSettings
            )
        },
        summaryMetrics: task.fixtures.summaryMetrics,
        artifacts: task.fixtures.artifacts.map {
            RunQualityArtifactSnapshot(
                label: $0.label,
                kind: $0.kind,
                path: $0.path,
                byteSize: $0.byteSize
            )
        },
        compileLog: task.fixtures.compileLog,
        runLog: task.fixtures.runLog
    )

    let qualityFindings = RunQualityAnalyzer.analyze(qualityInput)
    let reviewerInput = PhysicsReviewerEvidenceBuilder.buildInput(
        qualityInput: qualityInput,
        chartPayloads: task.fixtures.chartPayloads,
        messages: [
            PhysicsReviewerMessageSnapshot(
                role: "assistant",
                sender: "result",
                content: task.fixtures.assistantInterpretation,
                timestamp: "2026-07-08T00:00:00Z"
            )
        ],
        qualityFindings: qualityFindings,
        referencePack: task.fixtures.referencePack,
        finalSummaryText: task.fixtures.assistantInterpretation
    )

    let reviewerFindings: [PhysicsReviewerFinding]
    if let reviewerResponse = task.fixtures.offlineReviewerResponse?.prettyJSONString,
       let parsed = PhysicsReviewerAgent.parseResponseJSON(
        reviewerResponse,
        qualityFindings: qualityFindings,
        input: reviewerInput
       ) {
        reviewerFindings = parsed
    } else {
        reviewerFindings = PhysicsReviewerAgent.fallbackFindings(
            input: reviewerInput,
            reason: "benchmark offline deterministic fallback"
        )
    }

    var findings = qualityFindings.map(benchmarkFinding)
    findings.append(contentsOf: reviewerFindings.map(benchmarkFinding))
    findings.append(contentsOf: referenceSanitizationFindings(
        response: task.fixtures.offlineReviewerResponse,
        referencePack: task.fixtures.referencePack
    ))

    let matched = task.expectedFindings.filter { expected in
        findings.contains { findingMatches($0, expected: expected) }
    }
    let missing = task.expectedFindings.filter { expected in
        !findings.contains { findingMatches($0, expected: expected) }
    }
    let expectedCategories = Set(task.expectedFindings.map(\.category))
    let falsePositiveCount = findings.filter {
        $0.severity != .info && !expectedCategories.contains($0.category)
    }.count
    let invalidReferenceCount = invalidActualReferenceCount(
        findings: findings,
        referencePack: task.fixtures.referencePack
    )
    let passed = missing.isEmpty && invalidReferenceCount == 0

    return TaskReport(
        id: task.id,
        title: task.title,
        category: task.category,
        passed: passed,
        expectedCount: task.expectedFindings.count,
        matchedCount: matched.count,
        falsePositiveCount: falsePositiveCount + invalidReferenceCount,
        missingExpectations: missing,
        findings: findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return severityRank(lhs.severity) < severityRank(rhs.severity)
            }
            if lhs.category != rhs.category {
                return lhs.category < rhs.category
            }
            return lhs.id < rhs.id
        },
        competitorOutputs: task.competitorOutputs
    )
}

private func benchmarkFinding(_ finding: RunQualityFinding) -> BenchmarkFinding {
    BenchmarkFinding(
        source: "run_quality",
        id: finding.id,
        category: category(for: finding),
        severity: finding.severity,
        message: "\(finding.title): \(finding.detail)",
        evidenceRefs: finding.evidence,
        referenceIds: []
    )
}

private func benchmarkFinding(_ finding: PhysicsReviewerFinding) -> BenchmarkFinding {
    BenchmarkFinding(
        source: "physics_reviewer",
        id: finding.id,
        category: category(for: finding),
        severity: finding.severity,
        message: finding.message,
        evidenceRefs: finding.evidenceReferences,
        referenceIds: finding.referenceIds
    )
}

private func category(for finding: RunQualityFinding) -> String {
    if finding.id == "low-event-count" { return "low_statistics" }
    if finding.id.hasPrefix("missing-evidence-") { return "missing_evidence" }
    if finding.id.hasPrefix("missing-output-") { return "missing_declared_output" }
    if finding.id.hasPrefix("empty-output-") { return "empty_declared_output" }
    if finding.id.hasPrefix("empty-evidence-") { return "empty_expected_evidence" }
    if finding.id == "event-count-mismatch" { return "event_count_mismatch" }
    if finding.id.hasPrefix("histogram-overflow-") { return "histogram_overflow" }
    if finding.id == "inclusive-interpretation-with-hard-cuts" { return "cut_process_wording" }
    if finding.id.hasPrefix("log-") { return "log_marker" }
    return "quality_pass"
}

private func category(for finding: PhysicsReviewerFinding) -> String {
    if finding.id.contains("quality-low-event-count") { return "low_statistics" }
    if finding.id.contains("quality-missing-evidence") { return "missing_evidence" }
    if finding.id.contains("quality-missing-output") { return "missing_declared_output" }
    if finding.id.contains("quality-empty-output") { return "empty_declared_output" }
    if finding.id.contains("quality-event-count-mismatch") { return "event_count_mismatch" }
    if finding.id.contains("quality-histogram-overflow") { return "histogram_overflow" }
    if finding.id.contains("quality-inclusive-interpretation") { return "cut_process_wording" }
    if finding.id.contains("figure") || finding.message.localizedCaseInsensitiveContains("figure") {
        return "figure_summary_mismatch"
    }
    if finding.id.contains("external") || finding.id.contains("overclaim") {
        return "unsupported_external_claim"
    }

    switch finding.category {
    case .unsupportedInterpretation:
        return "unsupported_external_claim"
    case .evidenceConflict:
        return "evidence_conflict"
    case .citationGap:
        return "citation_gap"
    case .unitAmbiguity:
        return "unit_ambiguity"
    case .ignoredQualityFinding:
        return "ignored_quality_finding"
    case .cutProcessWording:
        return "cut_process_wording"
    case .artifactGap:
        return "artifact_gap"
    case .reviewerUnavailable:
        return "reviewer_unavailable"
    }
}

private func referenceSanitizationFindings(
    response: JSONValue?,
    referencePack: HEPReferencePack?
) -> [BenchmarkFinding] {
    guard let responseJSON = response?.prettyJSONString,
          let data = responseJSON.data(using: .utf8),
          let raw = try? JSONDecoder().decode(RawReviewerResponse.self, from: data) else {
        return []
    }
    let validIds = Set(referencePack?.references.map(\.id) ?? [])
    let rawIds = raw.findings.flatMap(\.referenceIds)
    let removed = rawIds.filter { !validIds.contains($0) }
    guard !removed.isEmpty else { return [] }
    let kept = rawIds.filter { validIds.contains($0) }
    return [
        BenchmarkFinding(
            source: "physics_reviewer",
            id: "benchmark-invalid-reference-ids-removed",
            category: "invented_reference",
            severity: .warning,
            message: "Offline reviewer response included unsupported reference IDs that were removed: \(Array(Set(removed)).sorted().joined(separator: ", ")).",
            evidenceRefs: ["offline_reviewer_response.reference_ids", "reference_pack.references"],
            referenceIds: Array(Set(kept)).sorted()
        )
    ]
}

private func findingMatches(_ finding: BenchmarkFinding, expected: ExpectedFinding) -> Bool {
    guard finding.category == expected.category,
          finding.severity == expected.severity else {
        return false
    }
    let lowerMessage = finding.message.lowercased()
    let messageMatches = expected.mustInclude.allSatisfy {
        lowerMessage.contains($0.lowercased())
    }
    let evidenceMatches = expected.evidenceRefs.allSatisfy { expectedRef in
        finding.evidenceRefs.contains { actual in
            actual.range(of: expectedRef, options: [.caseInsensitive]) != nil
        }
    }
    let referenceMatches = expected.referenceIds.allSatisfy { expectedId in
        finding.referenceIds.contains(expectedId)
    }
    return messageMatches && evidenceMatches && referenceMatches
}

private func invalidActualReferenceCount(
    findings: [BenchmarkFinding],
    referencePack: HEPReferencePack?
) -> Int {
    let validIds = Set(referencePack?.references.map(\.id) ?? [])
    guard !validIds.isEmpty else {
        return findings.flatMap(\.referenceIds).count
    }
    return findings.flatMap(\.referenceIds).filter { !validIds.contains($0) }.count
}

private func severityRank(_ severity: RunQualitySeverity) -> Int {
    switch severity {
    case .error: return 0
    case .warning: return 1
    case .info: return 2
    }
}

private func writeReports(_ report: BenchmarkReport, to outputDirectory: URL) throws {
    try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(report).write(to: outputDirectory.appendingPathComponent("report.json"))
    try markdown(report).write(
        to: outputDirectory.appendingPathComponent("report.md"),
        atomically: true,
        encoding: .utf8
    )
}

private func markdown(_ report: BenchmarkReport) -> String {
    var lines: [String] = []
    lines.append("# HEP Correctness Benchmark Report")
    lines.append("")
    lines.append("- Generated: \(report.generatedAt)")
    lines.append("- Offline: \(report.offline)")
    lines.append("- Tasks: \(report.passedTaskCount)/\(report.taskCount) passed")
    lines.append("- Expected findings: \(report.matchedFindingCount)/\(report.expectedFindingCount) matched")
    lines.append("- False positives: \(report.falsePositiveCount)")
    lines.append("")
    lines.append("| Task | Category | Result | Findings | False Positives |")
    lines.append("| --- | --- | --- | ---: | ---: |")
    for task in report.tasks {
        lines.append("| `\(task.id)` | `\(task.category)` | \(task.passed ? "PASS" : "FAIL") | \(task.matchedCount)/\(task.expectedCount) | \(task.falsePositiveCount) |")
    }
    lines.append("")
    for task in report.tasks {
        lines.append("## \(task.title)")
        lines.append("")
        lines.append("- ID: `\(task.id)`")
        lines.append("- Category: `\(task.category)`")
        lines.append("- Result: \(task.passed ? "PASS" : "FAIL")")
        if !task.missingExpectations.isEmpty {
            lines.append("- Missing expectations:")
            for missing in task.missingExpectations {
                lines.append("  - `\(missing.severity.rawValue)` `\(missing.category)` evidence=`\(missing.evidenceRefs.joined(separator: ", "))` refs=`\(missing.referenceIds.joined(separator: ", "))`")
            }
        }
        lines.append("- Vidura findings:")
        for finding in task.findings.filter({ $0.severity != .info }) {
            lines.append("  - `\(finding.severity.rawValue)` `\(finding.category)` \(finding.message)")
        }
        if task.findings.filter({ $0.severity != .info }).isEmpty {
            lines.append("  - No warning/error findings.")
        }
        lines.append("")
    }
    return lines.joined(separator: "\n") + "\n"
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: hep_correctness_benchmark <tasks-dir> <output-dir>\n", stderr)
    exit(2)
}

do {
    let tasksURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
    let outputURL = URL(fileURLWithPath: arguments[2], isDirectory: true)
    let tasks = try loadTasks(from: tasksURL)
    guard tasks.count >= 10 else {
        throw BenchmarkFailure(description: "Expected at least 10 benchmark tasks, found \(tasks.count)")
    }

    let taskReports = tasks.map(evaluate)
    let expectedCount = taskReports.reduce(0) { $0 + $1.expectedCount }
    let matchedCount = taskReports.reduce(0) { $0 + $1.matchedCount }
    let falsePositiveCount = taskReports.reduce(0) { $0 + $1.falsePositiveCount }
    let passedCount = taskReports.filter(\.passed).count
    let report = BenchmarkReport(
        formatVersion: 1,
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        offline: true,
        taskCount: taskReports.count,
        passedTaskCount: passedCount,
        failedTaskCount: taskReports.count - passedCount,
        expectedFindingCount: expectedCount,
        matchedFindingCount: matchedCount,
        falsePositiveCount: falsePositiveCount,
        tasks: taskReports
    )

    try writeReports(report, to: outputURL)
    print("HEP correctness benchmark: \(passedCount)/\(taskReports.count) tasks passed")
    print("Reports: \(outputURL.appendingPathComponent("report.json").path)")
    print("Reports: \(outputURL.appendingPathComponent("report.md").path)")

    if passedCount != taskReports.count {
        exit(1)
    }
} catch {
    fputs("FAIL \(error)\n", stderr)
    exit(1)
}
