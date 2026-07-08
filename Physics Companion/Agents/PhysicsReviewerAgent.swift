//
//  PhysicsReviewerAgent.swift
//  Physics Companion
//
//  Model-backed review of completed-run interpretation against persisted evidence.
//

import Foundation

enum PhysicsReviewerCategory: String, Codable, CaseIterable {
    case unsupportedInterpretation = "unsupported_interpretation"
    case evidenceConflict = "evidence_conflict"
    case citationGap = "citation_gap"
    case unitAmbiguity = "unit_ambiguity"
    case ignoredQualityFinding = "ignored_quality_finding"
    case cutProcessWording = "cut_process_wording"
    case artifactGap = "artifact_gap"
    case reviewerUnavailable = "reviewer_unavailable"
}

struct PhysicsReviewerFinding: Codable, Identifiable, Equatable {
    let id: String
    let severity: RunQualitySeverity
    let category: PhysicsReviewerCategory
    let message: String
    let evidenceReferences: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case severity
        case category
        case message
        case evidenceReferences = "evidence_references"
    }
}

struct PhysicsReviewerMessageSnapshot: Codable, Equatable {
    let role: String
    let sender: String
    let content: String
    let timestamp: String
}

struct PhysicsReviewerChartSnapshot: Codable, Equatable {
    let title: String
    let chartType: String
    let xLabel: String
    let yLabel: String
    let seriesCount: Int
    let pointCount: Int
    let metricSummaries: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case chartType = "chart_type"
        case xLabel = "x_label"
        case yLabel = "y_label"
        case seriesCount = "series_count"
        case pointCount = "point_count"
        case metricSummaries = "metric_summaries"
    }
}

struct PhysicsReviewerLogSnippet: Codable, Equatable {
    let name: String
    let lines: [String]
}

struct PhysicsReviewerInput: Codable, Equatable {
    let run: RunQualityRunSnapshot
    let spec: RunQualitySpecSnapshot?
    let summaryMetrics: [String: String]
    let chartSummaries: [PhysicsReviewerChartSnapshot]
    let messages: [PhysicsReviewerMessageSnapshot]
    let artifacts: [RunQualityArtifactSnapshot]
    let logSnippets: [PhysicsReviewerLogSnippet]
    let qualityFindings: [RunQualityFinding]
    let finalSummaryText: String

    enum CodingKeys: String, CodingKey {
        case run
        case spec
        case summaryMetrics = "summary_metrics"
        case chartSummaries = "chart_summaries"
        case messages
        case artifacts
        case logSnippets = "log_snippets"
        case qualityFindings = "quality_findings"
        case finalSummaryText = "final_summary_text"
    }
}

struct PhysicsReviewerEnvelope: Codable {
    let formatVersion: Int
    let generatedAt: String
    let runId: String
    let source: String
    let findings: [PhysicsReviewerFinding]

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case generatedAt = "generated_at"
        case runId = "run_id"
        case source
        case findings
    }
}

enum PhysicsReviewerEvidenceBuilder {
    nonisolated static func buildInput(
        qualityInput: RunQualityInput,
        chartPayloads: [ChartPayload],
        messages: [PhysicsReviewerMessageSnapshot],
        qualityFindings: [RunQualityFinding],
        finalSummaryText: String
    ) -> PhysicsReviewerInput {
        PhysicsReviewerInput(
            run: qualityInput.run,
            spec: qualityInput.spec,
            summaryMetrics: qualityInput.summaryMetrics,
            chartSummaries: chartPayloads.map(chartSnapshot),
            messages: messages.map(trimmedMessage),
            artifacts: qualityInput.artifacts,
            logSnippets: logSnippets(
                compileLog: qualityInput.compileLog,
                runLog: qualityInput.runLog
            ),
            qualityFindings: qualityFindings,
            finalSummaryText: finalSummaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    nonisolated static func finalSummaryText(
        explicit: String?,
        messages: [PhysicsReviewerMessageSnapshot]
    ) -> String {
        if let explicit = explicit?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }

        return messages
            .last { message in
                message.sender == "result" && !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func promptPayload(_ input: PhysicsReviewerInput) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(input),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private nonisolated static func chartSnapshot(_ chart: ChartPayload) -> PhysicsReviewerChartSnapshot {
        PhysicsReviewerChartSnapshot(
            title: chart.title,
            chartType: chart.chartType.rawValue,
            xLabel: chart.xLabel,
            yLabel: chart.yLabel,
            seriesCount: chart.series.count,
            pointCount: chart.series.reduce(0) { $0 + $1.points.count },
            metricSummaries: chart.metrics.map { metric in
                let unit = metric.unit.map { " \($0)" } ?? ""
                return "\(metric.label)=\(metric.value)\(unit)"
            }
        )
    }

    private nonisolated static func trimmedMessage(_ message: PhysicsReviewerMessageSnapshot) -> PhysicsReviewerMessageSnapshot {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return PhysicsReviewerMessageSnapshot(
            role: message.role,
            sender: message.sender,
            content: String(trimmed.prefix(1_200)),
            timestamp: message.timestamp
        )
    }

    private nonisolated static func logSnippets(
        compileLog: String?,
        runLog: String?,
        maxLines: Int = 8
    ) -> [PhysicsReviewerLogSnippet] {
        [
            ("compile.log", compileLog),
            ("run.log", runLog)
        ].compactMap { name, content in
            let lines = markerLines(in: content).prefix(maxLines)
            guard !lines.isEmpty else { return nil }
            return PhysicsReviewerLogSnippet(name: name, lines: Array(lines))
        }
    }

    private nonisolated static func markerLines(in content: String?) -> [String] {
        guard let content else { return [] }
        let markerNeedles = ["error", "fatal", "failed", "exception", "warning", "warn"]
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                let lower = line.lowercased()
                return markerNeedles.contains { lower.contains($0) }
            }
            .map { String($0.prefix(240)) }
    }
}

enum PhysicsReviewerAgent {
    private struct ReviewerResponse: Decodable {
        let findings: [RawFinding]
    }

    private struct RawFinding: Decodable {
        let severity: RunQualitySeverity
        let category: PhysicsReviewerCategory
        let message: String
        let evidenceReferences: [String]

        enum CodingKeys: String, CodingKey {
            case severity
            case category
            case message
            case evidenceReferences = "evidence_references"
        }
    }

    static func run(
        modelName: String,
        settingsApiKey: String?,
        input: PhysicsReviewerInput
    ) async -> [PhysicsReviewerFinding] {
        do {
            let client = OpenAIClient(
                apiKey: try OpenAICredentials.resolve(settingsApiKey: settingsApiKey),
                model: modelName
            )
            let response = try await client.responseObject(
                ReviewerResponse.self,
                instructions: reviewerInstructions,
                input: PhysicsReviewerEvidenceBuilder.promptPayload(input),
                textFormat: OpenAIResponseFormats.physicsReviewer,
                reasoningEffort: "low"
            )
            return normalizedFindings(response.findings, qualityFindings: input.qualityFindings)
        } catch {
            return fallbackFindings(input: input, reason: error.localizedDescription)
        }
    }

    static func parseResponseJSON(
        _ json: String,
        qualityFindings: [RunQualityFinding]
    ) -> [PhysicsReviewerFinding]? {
        guard let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(ReviewerResponse.self, from: data) else {
            return nil
        }
        return normalizedFindings(response.findings, qualityFindings: qualityFindings)
    }

    static func fallbackFindings(
        input: PhysicsReviewerInput,
        reason: String
    ) -> [PhysicsReviewerFinding] {
        let blockingQuality = input.qualityFindings.filter { $0.severity != .info }
        if blockingQuality.isEmpty {
            return [
                PhysicsReviewerFinding(
                    id: "reviewer-fallback-no-model",
                    severity: .info,
                    category: .reviewerUnavailable,
                    message: "Model-backed physics review was unavailable. Deterministic Run Quality did not report warnings or errors, but interpretation claims were not model-reviewed.",
                    evidenceReferences: fallbackEvidenceReferences(input: input, extra: [reason])
                )
            ]
        }

        return blockingQuality.map { finding in
            PhysicsReviewerFinding(
                id: "reviewer-quality-\(finding.id)",
                severity: finding.severity,
                category: category(for: finding),
                message: "Run Quality reported \(finding.title.lowercased()). The reviewer cannot mark this run clean until that deterministic finding is addressed or explained.",
                evidenceReferences: qualityEvidenceReferences(finding)
            )
        }
    }

    static func envelope(
        runId: String,
        source: String,
        findings: [PhysicsReviewerFinding],
        generatedAt: Date = Date()
    ) -> PhysicsReviewerEnvelope {
        PhysicsReviewerEnvelope(
            formatVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: generatedAt),
            runId: runId,
            source: source,
            findings: findings
        )
    }

    static func compactText(findings: [PhysicsReviewerFinding]) -> String {
        var lines = ["Physics Reviewer"]
        for finding in findings.prefix(4) {
            lines.append("- `\(finding.severity.rawValue)`: \(finding.category.rawValue) - \(finding.message)")
            if !finding.evidenceReferences.isEmpty {
                lines.append("  Evidence: \(finding.evidenceReferences.prefix(4).joined(separator: "; "))")
            }
        }
        if findings.count > 4 {
            lines.append("- \(findings.count - 4) more reviewer findings in Run Evidence.")
        }
        return lines.joined(separator: "\n")
    }

    private static let reviewerInstructions = """
    You are PhysicsReviewerAgent for Vidura Labs.

    Review the supplied completed-run evidence. Do not redo deterministic Run Quality checks; treat them as hard input. Check whether the final physics summary text and chart descriptions are supported by simulation_spec.json, summary.json metrics, chart payload summaries, logs, artifact metadata, and Run Quality findings.

    Return structured findings only. Use:
    - unsupported_interpretation for overconfident or unsupported physics claims.
    - evidence_conflict for summary claims conflicting with summary metrics or chart data.
    - citation_gap when the text compares to real measurements, experiments, PDG, or literature without supplied references.
    - unit_ambiguity when units or observable names are unclear.
    - ignored_quality_finding when final text ignores Run Quality warnings/errors.
    - cut_process_wording when process or pT-hat cuts make inclusive/minimum-bias wording misleading.
    - artifact_gap when an interpretation depends on missing or empty artifacts.
    - reviewer_unavailable only if the supplied evidence is too incomplete to review.

    If Run Quality contains warning or error findings, do not summarize the run as clean. Emit at least one warning/error finding that references those Run Quality findings unless the final summary explicitly handles them.
    """

    private static func normalizedFindings(
        _ rawFindings: [RawFinding],
        qualityFindings: [RunQualityFinding]
    ) -> [PhysicsReviewerFinding] {
        var findings: [PhysicsReviewerFinding] = []
        for raw in rawFindings {
            let message = raw.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { continue }
            findings.append(
                PhysicsReviewerFinding(
                    id: "reviewer-\(findings.count + 1)-\(raw.category.rawValue)",
                    severity: raw.severity,
                    category: raw.category,
                    message: String(message.prefix(600)),
                    evidenceReferences: raw.evidenceReferences
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .map { String($0.prefix(160)) }
                )
            )
        }

        let blockingQuality = qualityFindings.filter { $0.severity != .info }
        if !blockingQuality.isEmpty {
            for quality in blockingQuality where !referencesQuality(findingId: quality.id, in: findings) {
                findings.append(
                    PhysicsReviewerFinding(
                        id: "reviewer-quality-\(quality.id)",
                        severity: quality.severity,
                        category: category(for: quality),
                        message: "Run Quality reported \(quality.title.lowercased()). The run should not be treated as clean without addressing this deterministic finding.",
                        evidenceReferences: qualityEvidenceReferences(quality)
                    )
                )
            }
        }

        if findings.isEmpty {
            findings.append(
                PhysicsReviewerFinding(
                    id: "reviewer-no-findings",
                    severity: .info,
                    category: .unsupportedInterpretation,
                    message: "No reviewer findings were returned for the supplied evidence.",
                    evidenceReferences: []
                )
            )
        }

        return findings.sorted { lhs, rhs in
            let lhsRank = severityRank(lhs.severity)
            let rhsRank = severityRank(rhs.severity)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.id < rhs.id
        }
    }

    private static func referencesQuality(
        findingId: String,
        in findings: [PhysicsReviewerFinding]
    ) -> Bool {
        findings.contains { finding in
            finding.evidenceReferences.contains { reference in
                reference.range(of: findingId, options: .caseInsensitive) != nil
            }
        }
    }

    private static func category(for finding: RunQualityFinding) -> PhysicsReviewerCategory {
        if finding.id.contains("missing") || finding.id.contains("empty") {
            return .artifactGap
        }
        if finding.id.contains("inclusive") {
            return .cutProcessWording
        }
        return .ignoredQualityFinding
    }

    private static func qualityEvidenceReferences(_ finding: RunQualityFinding) -> [String] {
        var references = ["Run Quality: \(finding.id)"]
        references.append(contentsOf: finding.evidence)
        return references
    }

    private static func fallbackEvidenceReferences(
        input: PhysicsReviewerInput,
        extra: [String]
    ) -> [String] {
        var references = input.qualityFindings.prefix(3).map { "Run Quality: \($0.id)" }
        references.append(contentsOf: input.artifacts.prefix(3).map { $0.label })
        references.append(contentsOf: extra.filter { !$0.isEmpty }.prefix(1))
        return references
    }

    private static func severityRank(_ severity: RunQualitySeverity) -> Int {
        switch severity {
        case .error: return 0
        case .warning: return 1
        case .info: return 2
        }
    }
}
