//
//  RunQualityAnalyzer.swift
//  Physics Companion
//
//  Deterministic run-quality checks for completed simulation evidence.
//

import Foundation

enum RunQualitySeverity: String, Codable, CaseIterable {
    case info
    case warning
    case error
}

struct RunQualityFinding: Codable, Identifiable, Equatable {
    let id: String
    let severity: RunQualitySeverity
    let title: String
    let detail: String
    let evidence: [String]
}

struct RunQualityRunSnapshot: Codable, Equatable {
    let id: String
    let title: String
    let status: String
    let eventCount: Int?
    let configuration: [String: String]
}

struct RunQualitySpecSnapshot: Codable, Equatable {
    let eventCount: Int?
    let analysisFamily: String?
    let outputFiles: [String]
    let processSettings: [String]
    let cutsSettings: [String]
}

struct RunQualityArtifactSnapshot: Codable, Equatable {
    let label: String
    let kind: String
    let path: String
    let byteSize: UInt64?
}

struct RunQualityInput: Codable, Equatable {
    let run: RunQualityRunSnapshot
    let spec: RunQualitySpecSnapshot?
    let summaryMetrics: [String: String]
    let artifacts: [RunQualityArtifactSnapshot]
    let compileLog: String?
    let runLog: String?
}

enum RunQualityAnalyzer {
    private static let expectedEvidenceNames = [
        "run.cc",
        "simulation_spec.json",
        "summary.json",
        "summary_lines.txt",
        "compile.log",
        "run.log"
    ]
    private static let expectedEvidenceAllowedEmpty = Set([
        "compile.log"
    ])
    private static let lowEventThreshold = 1_000

    static func analyze(_ input: RunQualityInput) -> [RunQualityFinding] {
        var findings: [RunQualityFinding] = []
        let artifactIndex = Dictionary(grouping: input.artifacts) { artifact in
            fileName(for: artifact)
        }

        if isCompleted(input.run.status) {
            findings.append(contentsOf: expectedEvidenceFindings(artifactIndex: artifactIndex))
        }

        findings.append(contentsOf: requestedOutputFindings(
            outputFiles: input.spec?.outputFiles ?? [],
            artifactIndex: artifactIndex
        ))
        findings.append(contentsOf: eventCountFindings(input))
        findings.append(contentsOf: overflowFindings(summaryMetrics: input.summaryMetrics))
        findings.append(contentsOf: interpretationCutFindings(input))
        findings.append(contentsOf: logFindings(compileLog: input.compileLog, runLog: input.runLog))

        if findings.allSatisfy({ $0.severity == .info }) || findings.isEmpty {
            findings.append(
                finding(
                    "quality-pass",
                    .info,
                    "Quality checks passed",
                    "Expected evidence, event counts, declared outputs, logs, cuts, and visible overflow counters did not raise warnings.",
                    []
                )
            )
        }

        return findings.sorted { lhs, rhs in
            let lhsRank = severityRank(lhs.severity)
            let rhsRank = severityRank(rhs.severity)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.title < rhs.title
        }
    }

    private static func expectedEvidenceFindings(
        artifactIndex: [String: [RunQualityArtifactSnapshot]]
    ) -> [RunQualityFinding] {
        expectedEvidenceNames.compactMap { name in
            guard let artifacts = artifactIndex[name],
                  artifacts.contains(where: { $0.byteSize != nil }) else {
                return finding(
                    "missing-evidence-\(name)",
                    .error,
                    "Missing expected evidence",
                    "Completed run has no readable \(name) artifact.",
                    [name]
                )
            }
            guard artifacts.contains(where: { ($0.byteSize ?? 0) > 0 }) != true else {
                return nil
            }
            if expectedEvidenceAllowedEmpty.contains(name) {
                return nil
            }
            return finding(
                "empty-evidence-\(name)",
                .error,
                "Empty expected evidence",
                "\(name) is present but empty.",
                [name]
            )
        }
    }

    private static func requestedOutputFindings(
        outputFiles: [String],
        artifactIndex: [String: [RunQualityArtifactSnapshot]]
    ) -> [RunQualityFinding] {
        let names = uniqueOutputFiles(outputFiles)
        return names.compactMap { name in
            guard !expectedEvidenceNames.contains(name) else { return nil }
            guard let artifacts = artifactIndex[name],
                  artifacts.contains(where: { $0.byteSize != nil }) else {
                return finding(
                    "missing-output-\(name)",
                    .error,
                    "Missing declared output",
                    "The simulation spec requested \(name), but no matching artifact was found.",
                    [name]
                )
            }
            guard artifacts.contains(where: { ($0.byteSize ?? 0) > 0 }) else {
                return finding(
                    "empty-output-\(name)",
                    .error,
                    "Empty declared output",
                    "The simulation spec requested \(name), but the artifact is empty.",
                    [name]
                )
            }
            return nil
        }
    }

    private static func eventCountFindings(_ input: RunQualityInput) -> [RunQualityFinding] {
        var findings: [RunQualityFinding] = []
        if let runCount = input.run.eventCount,
           let summaryCount = summaryEventCount(input.summaryMetrics),
           runCount != summaryCount {
            findings.append(
                finding(
                    "event-count-mismatch",
                    .error,
                    "Event count mismatch",
                    "Run metadata records \(runCount) events, but summary.json reports \(summaryCount).",
                    ["run.event_count", "summary.generated_events"]
                )
            )
        }

        let effectiveCount = input.run.eventCount
            ?? summaryEventCount(input.summaryMetrics)
            ?? input.spec?.eventCount
        if let effectiveCount, effectiveCount > 0, effectiveCount < lowEventThreshold {
            findings.append(
                finding(
                    "low-event-count",
                    .warning,
                    "Low event count",
                    "\(effectiveCount) events is below the \(lowEventThreshold)-event exploratory threshold.",
                    ["event_count=\(effectiveCount)"]
                )
            )
        }

        return findings
    }

    private static func overflowFindings(summaryMetrics: [String: String]) -> [RunQualityFinding] {
        summaryMetrics.compactMap { key, value in
            guard key.range(of: "overflow", options: .caseInsensitive) != nil,
                  let numeric = numericValue(value),
                  numeric != 0 else {
                return nil
            }
            return finding(
                "histogram-overflow-\(normalizedID(key))",
                .warning,
                "Histogram overflow",
                "\(key) reports \(value), so visible histogram bins may exclude events.",
                [key]
            )
        }
    }

    private static func interpretationCutFindings(_ input: RunQualityInput) -> [RunQualityFinding] {
        guard let spec = input.spec else { return [] }
        let titleAndFamily = "\(input.run.title) \(spec.analysisFamily ?? "")".lowercased()
        let impliesInclusive = [
            "inclusive",
            "minimum bias",
            "minimum-bias",
            "min bias",
            "min-bias",
            "min_bias",
            "minimum_bias"
        ].contains { titleAndFamily.contains($0) }
        guard impliesInclusive else { return [] }

        let hardProcesses = spec.processSettings.filter { setting in
            let lower = setting.lowercased()
            return lower.contains("hard") || lower.contains("top:") || lower.contains("weak") || lower.contains("promptphoton")
        }
        let hardCuts = spec.cutsSettings.filter { setting in
            setting.lowercased().contains("phasespace:pthatmin")
        }
        guard !hardProcesses.isEmpty || !hardCuts.isEmpty else { return [] }

        let evidence = hardProcesses + hardCuts
        return [
            finding(
                "inclusive-interpretation-with-hard-cuts",
                .warning,
                "Inclusive interpretation with hard cuts",
                "The run title or family implies inclusive/minimum-bias interpretation, but hard-process or pT-hat cuts are present.",
                evidence
            )
        ]
    }

    private static func logFindings(compileLog: String?, runLog: String?) -> [RunQualityFinding] {
        [
            logFinding(logName: "compile.log", content: compileLog),
            logFinding(logName: "run.log", content: runLog)
        ].compactMap { $0 }
    }

    private static func logFinding(logName: String, content: String?) -> RunQualityFinding? {
        guard let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let line = lines.first(where: { isErrorLine($0) }) {
            return finding(
                "log-error-\(logName)",
                .error,
                "Completed run log contains error marker",
                "\(logName): \(line)",
                [logName]
            )
        }

        if let line = lines.first(where: { isWarningLine($0) }) {
            return finding(
                "log-warning-\(logName)",
                .warning,
                "Completed run log contains warning marker",
                "\(logName): \(line)",
                [logName]
            )
        }

        return nil
    }

    private static func isErrorLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("fatal error")
            || lower.contains("error:")
            || lower.contains("segmentation fault")
            || lower.contains("runtime_error")
            || lower.contains("failed")
            || lower.contains("exception")
    }

    private static func isWarningLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("warning:")
            || lower.contains(" warning ")
            || lower.hasPrefix("warning")
            || lower.contains("warn:")
    }

    private static func summaryEventCount(_ summaryMetrics: [String: String]) -> Int? {
        for key in ["generated_events", "event_count", "events", "n_events"] {
            if let value = summaryMetrics[key], let parsed = Int(value) {
                return parsed
            }
        }

        for (key, value) in summaryMetrics {
            guard key.range(of: "generated_events", options: .caseInsensitive) != nil
                || key.range(of: "event_count", options: .caseInsensitive) != nil else {
                continue
            }
            if let parsed = Int(value) {
                return parsed
            }
        }
        return nil
    }

    private static func uniqueOutputFiles(_ outputFiles: [String]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for outputFile in outputFiles {
            let name = URL(fileURLWithPath: outputFile).lastPathComponent
            guard !name.isEmpty, !seen.contains(name) else { continue }
            names.append(name)
            seen.insert(name)
        }
        return names
    }

    private static func fileName(for artifact: RunQualityArtifactSnapshot) -> String {
        let pathName = URL(fileURLWithPath: artifact.path).lastPathComponent
        if !pathName.isEmpty {
            return pathName
        }
        return artifact.label
    }

    private static func numericValue(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let double = Double(trimmed) {
            return double
        }
        let filtered = trimmed.filter { character in
            character.isNumber || character == "." || character == "-" || character == "+"
        }
        return Double(filtered)
    }

    private static func normalizedID(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value
            .lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private static func finding(
        _ id: String,
        _ severity: RunQualitySeverity,
        _ title: String,
        _ detail: String,
        _ evidence: [String]
    ) -> RunQualityFinding {
        RunQualityFinding(
            id: id,
            severity: severity,
            title: title,
            detail: detail,
            evidence: evidence
        )
    }

    private static func severityRank(_ severity: RunQualitySeverity) -> Int {
        switch severity {
        case .error: return 0
        case .warning: return 1
        case .info: return 2
        }
    }

    private static func isCompleted(_ status: String) -> Bool {
        let lower = status.lowercased()
        return lower == "completed" || lower == "succeeded"
    }
}
