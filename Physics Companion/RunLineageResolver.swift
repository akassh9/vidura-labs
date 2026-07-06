//
//  RunLineageResolver.swift
//  Physics Companion
//
//  Pure run-lineage classification for reproducibility UI and regression checks.
//

import Foundation

enum RunLineageKind {
    case original
    case exactRerun
    case variant

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .exactRerun: return "Exact rerun"
        case .variant: return "Variant"
        }
    }

    var iconName: String {
        switch self {
        case .original: return "record.circle"
        case .exactRerun: return "arrow.trianglehead.clockwise"
        case .variant: return "slider.horizontal.3"
        }
    }
}

struct RunLineageRunSnapshot {
    let id: String
    let configuration: [String: String]
}

struct RunLineageMessageSnapshot {
    let content: String
    let originRunId: String?
}

struct RunLineageClassification {
    let kind: RunLineageKind
    let sourceRunId: String?
    let changes: [String]
    let isInferred: Bool

    var isDerived: Bool {
        sourceRunId != nil
    }
}

struct RunLineagePairClassification {
    let kind: RunLineageKind
    let sourceRunId: String
    let derivedRunId: String
    let sourceLabel: String
    let derivedLabel: String
    let changes: [String]
    let isInferred: Bool
}

enum RunLineageResolver {
    private static let exactRerunSourceKey = "Vidura:exactRerunOfRunID"
    private static let variantSourceKey = "Vidura:variantOfRunID"
    private static let variantChangesKey = "Vidura:variantChanges"
    private static let exactRerunMessagePrefix = "Rerun exact from run "

    static func classification(
        for run: RunLineageRunSnapshot,
        in runs: [RunLineageRunSnapshot],
        messages: [RunLineageMessageSnapshot]
    ) -> RunLineageClassification {
        if let sourceRunId = normalized(run.configuration[variantSourceKey]) {
            return RunLineageClassification(
                kind: .variant,
                sourceRunId: sourceRunId,
                changes: changes(from: run.configuration[variantChangesKey]),
                isInferred: false
            )
        }

        if let sourceRunId = normalized(run.configuration[exactRerunSourceKey]) {
            return RunLineageClassification(
                kind: .exactRerun,
                sourceRunId: sourceRunId,
                changes: [],
                isInferred: false
            )
        }

        if let sourceRunId = inferredExactRerunSourceID(for: run, in: runs, messages: messages) {
            return RunLineageClassification(
                kind: .exactRerun,
                sourceRunId: sourceRunId,
                changes: [],
                isInferred: true
            )
        }

        return RunLineageClassification(
            kind: .original,
            sourceRunId: nil,
            changes: [],
            isInferred: false
        )
    }

    static func relationship(
        between left: RunLineageRunSnapshot,
        and right: RunLineageRunSnapshot,
        in runs: [RunLineageRunSnapshot],
        messages: [RunLineageMessageSnapshot]
    ) -> RunLineagePairClassification? {
        let leftLineage = classification(for: left, in: runs, messages: messages)
        if leftLineage.sourceRunId == right.id {
            return RunLineagePairClassification(
                kind: leftLineage.kind,
                sourceRunId: right.id,
                derivedRunId: left.id,
                sourceLabel: "B",
                derivedLabel: "A",
                changes: leftLineage.changes,
                isInferred: leftLineage.isInferred
            )
        }

        let rightLineage = classification(for: right, in: runs, messages: messages)
        if rightLineage.sourceRunId == left.id {
            return RunLineagePairClassification(
                kind: rightLineage.kind,
                sourceRunId: left.id,
                derivedRunId: right.id,
                sourceLabel: "A",
                derivedLabel: "B",
                changes: rightLineage.changes,
                isInferred: rightLineage.isInferred
            )
        }

        return nil
    }

    static func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func changes(from value: String?) -> [String] {
        guard let value = normalized(value) else { return [] }
        return value
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func inferredExactRerunSourceID(
        for run: RunLineageRunSnapshot,
        in runs: [RunLineageRunSnapshot],
        messages: [RunLineageMessageSnapshot]
    ) -> String? {
        for message in messages where message.originRunId == run.id {
            guard let sourceRunId = exactRerunSourceID(from: message.content),
                  sourceRunId != run.id,
                  runs.contains(where: { $0.id == sourceRunId }) else {
                continue
            }
            return sourceRunId
        }
        return nil
    }

    private static func exactRerunSourceID(from content: String) -> String? {
        guard let range = content.range(of: exactRerunMessagePrefix, options: .caseInsensitive) else {
            return nil
        }

        let tail = String(content[range.upperBound...])
        guard let candidate = tail.split(whereSeparator: { character in
            !(character.isLetter || character.isNumber || character == "-")
        }).first else {
            return nil
        }

        let sourceRunId = String(candidate)
        guard sourceRunId.count >= 8 else {
            return nil
        }
        return sourceRunId
    }
}
