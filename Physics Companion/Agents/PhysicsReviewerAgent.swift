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
    let referenceIds: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case severity
        case category
        case message
        case evidenceReferences = "evidence_references"
        case referenceIds = "reference_ids"
    }

    init(
        id: String,
        severity: RunQualitySeverity,
        category: PhysicsReviewerCategory,
        message: String,
        evidenceReferences: [String],
        referenceIds: [String] = []
    ) {
        self.id = id
        self.severity = severity
        self.category = category
        self.message = message
        self.evidenceReferences = evidenceReferences
        self.referenceIds = referenceIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.severity = try container.decode(RunQualitySeverity.self, forKey: .severity)
        self.category = try container.decode(PhysicsReviewerCategory.self, forKey: .category)
        self.message = try container.decode(String.self, forKey: .message)
        self.evidenceReferences = try container.decodeIfPresent([String].self, forKey: .evidenceReferences) ?? []
        self.referenceIds = try container.decodeIfPresent([String].self, forKey: .referenceIds) ?? []
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

struct PhysicsReviewerReferencePackSnapshot: Codable, Equatable {
    let query: String
    let tags: [String]
    let references: [PhysicsReviewerReferenceSnapshot]
    let sourceStatuses: [PhysicsReviewerReferenceSourceStatusSnapshot]

    enum CodingKeys: String, CodingKey {
        case query
        case tags
        case references
        case sourceStatuses = "source_statuses"
    }
}

struct PhysicsReviewerReferenceSnapshot: Codable, Equatable {
    let id: String
    let sources: [String]
    let title: String
    let authors: [String]
    let collaboration: String?
    let year: Int?
    let snippet: String?
    let doi: String?
    let arxivId: String?
    let inspireId: String?
    let hepDataId: String?
    let url: String?
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case sources
        case title
        case authors
        case collaboration
        case year
        case snippet
        case doi
        case arxivId = "arxiv_id"
        case inspireId = "inspire_id"
        case hepDataId = "hepdata_id"
        case url
        case tags
    }
}

struct PhysicsReviewerReferenceSourceStatusSnapshot: Codable, Equatable {
    let source: String
    let state: String
    let query: String
    let resultCount: Int
    let message: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case source
        case state
        case query
        case resultCount = "result_count"
        case message
        case updatedAt = "updated_at"
    }
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
    let referencePack: PhysicsReviewerReferencePackSnapshot?
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
        case referencePack = "reference_pack"
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
        referencePack: HEPReferencePack? = nil,
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
            referencePack: referencePack.map(referencePackSnapshot),
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

    private nonisolated static func referencePackSnapshot(_ pack: HEPReferencePack) -> PhysicsReviewerReferencePackSnapshot {
        PhysicsReviewerReferencePackSnapshot(
            query: pack.query,
            tags: pack.tags,
            references: pack.references.map(referenceSnapshot),
            sourceStatuses: pack.sourceStatuses.map(sourceStatusSnapshot)
        )
    }

    private nonisolated static func referenceSnapshot(_ reference: HEPReference) -> PhysicsReviewerReferenceSnapshot {
        PhysicsReviewerReferenceSnapshot(
            id: HEPReferenceNormalizer.stableKey(for: reference),
            sources: reference.sources.map(\.rawValue),
            title: reference.title,
            authors: reference.authors,
            collaboration: reference.collaboration,
            year: reference.year,
            snippet: reference.snippet,
            doi: reference.doi,
            arxivId: reference.arxivId,
            inspireId: reference.inspireId,
            hepDataId: reference.hepDataId,
            url: reference.url,
            tags: reference.tags
        )
    }

    private nonisolated static func sourceStatusSnapshot(_ status: HEPReferenceSourceStatus) -> PhysicsReviewerReferenceSourceStatusSnapshot {
        PhysicsReviewerReferenceSourceStatusSnapshot(
            source: status.source.rawValue,
            state: status.state.rawValue,
            query: status.query,
            resultCount: status.resultCount,
            message: status.message,
            updatedAt: status.updatedAt
        )
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
        let referenceIds: [String]

        enum CodingKeys: String, CodingKey {
            case severity
            case category
            case message
            case evidenceReferences = "evidence_references"
            case referenceIds = "reference_ids"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.severity = try container.decode(RunQualitySeverity.self, forKey: .severity)
            self.category = try container.decode(PhysicsReviewerCategory.self, forKey: .category)
            self.message = try container.decode(String.self, forKey: .message)
            self.evidenceReferences = try container.decodeIfPresent([String].self, forKey: .evidenceReferences) ?? []
            self.referenceIds = try container.decodeIfPresent([String].self, forKey: .referenceIds) ?? []
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
            return normalizedFindings(response.findings, input: input)
        } catch {
            return fallbackFindings(input: input, reason: error.localizedDescription)
        }
    }

    static func parseResponseJSON(
        _ json: String,
        qualityFindings: [RunQualityFinding],
        input: PhysicsReviewerInput? = nil
    ) -> [PhysicsReviewerFinding]? {
        guard let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(ReviewerResponse.self, from: data) else {
            return nil
        }
        if let input {
            return normalizedFindings(response.findings, input: input)
        }
        return normalizedFindings(response.findings, qualityFindings: qualityFindings, validReferenceIds: [])
    }

    static func fallbackFindings(
        input: PhysicsReviewerInput,
        reason: String
    ) -> [PhysicsReviewerFinding] {
        var deterministic = deterministicReferenceFindings(input: input)
        let blockingQuality = input.qualityFindings.filter { $0.severity != .info }
        if blockingQuality.isEmpty && deterministic.isEmpty {
            deterministic.append(
                PhysicsReviewerFinding(
                    id: "reviewer-fallback-no-model",
                    severity: .info,
                    category: .reviewerUnavailable,
                    message: "Model-backed physics review was unavailable. Deterministic Run Quality did not report warnings or errors, but interpretation claims were not model-reviewed.",
                    evidenceReferences: fallbackEvidenceReferences(input: input, extra: [reason])
                )
            )
            return deterministic
        }

        deterministic.append(contentsOf: blockingQuality.map { finding in
            PhysicsReviewerFinding(
                id: "reviewer-quality-\(finding.id)",
                severity: finding.severity,
                category: category(for: finding),
                message: "Run Quality reported \(finding.title.lowercased()). The reviewer cannot mark this run clean until that deterministic finding is addressed or explained.",
                evidenceReferences: qualityEvidenceReferences(finding)
            )
        })
        return sortedFindings(dedupedFindings(deterministic))
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
            if !finding.referenceIds.isEmpty {
                lines.append("  References: \(finding.referenceIds.prefix(4).joined(separator: ", "))")
            }
        }
        if findings.count > 4 {
            lines.append("- \(findings.count - 4) more reviewer findings in Run Evidence.")
        }
        return lines.joined(separator: "\n")
    }

    private static let reviewerInstructions = """
    You are PhysicsReviewerAgent for Vidura Labs.

    Review the supplied completed-run evidence. Do not redo deterministic Run Quality checks; treat them as hard input. Check whether the final physics summary text and chart descriptions are supported by simulation_spec.json, summary.json metrics, chart payload summaries, logs, artifact metadata, Run Quality findings, and the supplied persisted reference_pack.

    Reference rules:
    - Findings may attach reference_ids only from reference_pack.references[].id in the supplied input.
    - Do not invent citations, URLs, paper titles, DOI/arXiv/INSPIRE/HEPData IDs, or reference IDs.
    - Use evidence_references for local artifacts and Run Quality IDs; use reference_ids only for supplied HEP references.
    - Treat local simulation artifacts as support for what this run produced, not as support for claims about external measurements, PDG/literature agreement, or published results.
    - If the final text makes citation-sensitive claims and no supplied reference supports them, emit citation_gap or unsupported_interpretation instead of attaching an unrelated reference.
    - If source_statuses show failed or partial_failure sources, do not treat source coverage as complete.

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
        input: PhysicsReviewerInput
    ) -> [PhysicsReviewerFinding] {
        normalizedFindings(
            rawFindings,
            qualityFindings: input.qualityFindings,
            validReferenceIds: validReferenceIds(input),
            deterministicFindings: deterministicReferenceFindings(input: input)
        )
    }

    private static func normalizedFindings(
        _ rawFindings: [RawFinding],
        qualityFindings: [RunQualityFinding],
        validReferenceIds: Set<String>,
        deterministicFindings: [PhysicsReviewerFinding] = []
    ) -> [PhysicsReviewerFinding] {
        var findings = deterministicFindings
        for raw in rawFindings {
            let message = raw.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { continue }
            let referenceIds = sanitizedReferenceIds(raw.referenceIds, validReferenceIds: validReferenceIds)
            findings.append(
                PhysicsReviewerFinding(
                    id: "reviewer-\(findings.count + 1)-\(raw.category.rawValue)",
                    severity: raw.severity,
                    category: raw.category,
                    message: String(message.prefix(600)),
                    evidenceReferences: raw.evidenceReferences
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .map { String($0.prefix(160)) },
                    referenceIds: referenceIds
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

        return sortedFindings(dedupedFindings(findings))
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

    private static func deterministicReferenceFindings(input: PhysicsReviewerInput) -> [PhysicsReviewerFinding] {
        var findings: [PhysicsReviewerFinding] = []
        let summary = input.finalSummaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerSummary = summary.lowercased()
        let pack = input.referencePack

        if input.run.status == "completed", pack == nil {
            findings.append(
                PhysicsReviewerFinding(
                    id: "reviewer-missing-reference-pack",
                    severity: .warning,
                    category: .citationGap,
                    message: "This completed run has no persisted reference_pack.json, so external-literature or measurement claims cannot be citation-grounded by the reviewer.",
                    evidenceReferences: ["reference_pack.json missing"]
                )
            )
        }

        for status in pack?.sourceStatuses ?? [] where status.state == HEPReferenceRetrievalState.failed.rawValue || status.state == HEPReferenceRetrievalState.partialFailure.rawValue {
            var evidence = ["reference_pack.source_statuses.\(status.source)=\(status.state)"]
            if let message = status.message, !message.isEmpty {
                evidence.append(message)
            }
            findings.append(
                PhysicsReviewerFinding(
                    id: "reviewer-reference-source-\(status.source)-\(status.state)",
                    severity: .warning,
                    category: .citationGap,
                    message: "\(status.source) reference refresh status is \(status.state), so reviewer coverage for source-backed claims is incomplete.",
                    evidenceReferences: evidence
                )
            )
        }

        guard !summary.isEmpty else {
            return findings
        }

        let sensitiveNeedles = [
            "external measurement",
            "external measurements",
            "measurement",
            "measurements",
            "literature",
            "published result",
            "published results",
            "citation",
            "citations",
            "pdg",
            "hepdata",
            "arxiv",
            "inspire",
            "experiment",
            "experimental data"
        ]
        let mentionsCitationSensitiveClaim = sensitiveNeedles.contains { lowerSummary.contains($0) }
        if mentionsCitationSensitiveClaim && (pack?.references.isEmpty ?? true) {
            findings.append(
                PhysicsReviewerFinding(
                    id: "reviewer-external-claim-without-reference",
                    severity: .warning,
                    category: .citationGap,
                    message: "The final summary mentions external measurements, literature, citations, PDG, HEPData, arXiv, INSPIRE, experiments, or published results, but no persisted reference supports that claim.",
                    evidenceReferences: ["final_summary_text", "reference_pack.references empty"]
                )
            )
        }

        for gap in sourceSpecificCitationGaps(lowerSummary: lowerSummary, pack: pack) {
            findings.append(gap)
        }

        let overclaimNeedles = [
            "agrees with",
            "consistent with",
            "matches",
            "validated against",
            "confirms",
            "reproduces",
            "in agreement with"
        ]
        let hasOverclaim = overclaimNeedles.contains { lowerSummary.contains($0) }
        if hasOverclaim && !mentionsLocalOnlyQualifier(lowerSummary) {
            let hasReferences = !(pack?.references.isEmpty ?? true)
            let hasSourceSuccess = pack?.sourceStatuses.contains { $0.state == HEPReferenceRetrievalState.success.rawValue && $0.resultCount > 0 } ?? false
            if !hasReferences || !hasSourceSuccess {
                findings.append(
                    PhysicsReviewerFinding(
                        id: "reviewer-citation-sensitive-overclaim",
                        severity: .warning,
                        category: .unsupportedInterpretation,
                        message: "The final summary uses agreement/validation language that requires citation-backed external evidence; local simulation artifacts alone do not support that claim.",
                        evidenceReferences: ["final_summary_text", "local run artifacts only"]
                    )
                )
            }
        }

        return findings
    }

    private static func sourceSpecificCitationGaps(
        lowerSummary: String,
        pack: PhysicsReviewerReferencePackSnapshot?
    ) -> [PhysicsReviewerFinding] {
        let sourceChecks: [(needle: String, source: String, label: String)] = [
            ("pdg", "pdg", "PDG"),
            ("hepdata", "hepdata", "HEPData"),
            ("arxiv", "arxiv", "arXiv"),
            ("inspire", "inspire", "INSPIRE")
        ]
        var findings: [PhysicsReviewerFinding] = []
        for check in sourceChecks where lowerSummary.contains(check.needle) && !hasReferenceSource(check.source, pack: pack) {
            findings.append(
                PhysicsReviewerFinding(
                    id: "reviewer-missing-\(check.source)-reference",
                    severity: .warning,
                    category: .citationGap,
                    message: "The final summary mentions \(check.label), but the persisted reference pack does not include a \(check.label) reference.",
                    evidenceReferences: ["final_summary_text", "reference_pack.references"]
                )
            )
        }

        let measurementNeedles = ["external measurement", "external measurements", "measurements", "published result", "published results", "experimental data"]
        let mentionsMeasurementClaim = measurementNeedles.contains { lowerSummary.contains($0) }
        if mentionsMeasurementClaim && !hasMeasurementReference(pack) {
            findings.append(
                PhysicsReviewerFinding(
                    id: "reviewer-missing-measurement-reference",
                    severity: .warning,
                    category: .citationGap,
                    message: "The final summary mentions external measurements or published results, but the persisted reference pack does not include a measurement/data reference.",
                    evidenceReferences: ["final_summary_text", "reference_pack.references"]
                )
            )
        }
        return findings
    }

    private static func hasReferenceSource(
        _ source: String,
        pack: PhysicsReviewerReferencePackSnapshot?
    ) -> Bool {
        pack?.references.contains { reference in
            reference.sources.contains(source)
        } ?? false
    }

    private static func hasMeasurementReference(_ pack: PhysicsReviewerReferencePackSnapshot?) -> Bool {
        pack?.references.contains { reference in
            reference.sources.contains("hepdata")
                || reference.tags.contains { tag in
                    let lower = tag.lowercased()
                    return lower.contains("measurement") || lower.contains("data")
                }
        } ?? false
    }

    private static func mentionsLocalOnlyQualifier(_ lowerSummary: String) -> Bool {
        lowerSummary.contains("within this simulation")
            || lowerSummary.contains("within the generated sample")
            || lowerSummary.contains("in this run")
            || lowerSummary.contains("local simulation")
    }

    private static func validReferenceIds(_ input: PhysicsReviewerInput) -> Set<String> {
        Set(input.referencePack?.references.map(\.id) ?? [])
    }

    private static func sanitizedReferenceIds(
        _ ids: [String],
        validReferenceIds: Set<String>
    ) -> [String] {
        var seen = Set<String>()
        return ids.compactMap { raw in
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, validReferenceIds.contains(id), !seen.contains(id) else {
                return nil
            }
            seen.insert(id)
            return id
        }
    }

    private static func dedupedFindings(_ findings: [PhysicsReviewerFinding]) -> [PhysicsReviewerFinding] {
        var seen = Set<String>()
        return findings.filter { finding in
            guard !seen.contains(finding.id) else { return false }
            seen.insert(finding.id)
            return true
        }
    }

    private static func sortedFindings(_ findings: [PhysicsReviewerFinding]) -> [PhysicsReviewerFinding] {
        findings.sorted { lhs, rhs in
            let lhsRank = severityRank(lhs.severity)
            let rhsRank = severityRank(rhs.severity)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.id < rhs.id
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
