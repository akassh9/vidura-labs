//
//  RunnerSummaryParser.swift
//  Physics Companion
//
//  Pure summary_lines.txt parsing used by RunnerService and regression checks.
//

import Foundation

enum RunnerSummaryParser {
    /// Parses summary_lines.txt into a dictionary.
    /// Accepts both "key=value" and "key value" formats.
    /// Values are parsed as int, then float, then string.
    static func parse(_ content: String) -> [String: Any] {
        var result: [String: Any] = [:]
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let parts: [String]
            if trimmed.contains("=") {
                parts = trimmed.components(separatedBy: "=")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                parts = trimmed.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
            }

            guard parts.count >= 2 else { continue }
            let key = parts[0]
            let valueStr = parts.dropFirst().joined(separator: " ")

            if let intVal = Int(valueStr) {
                result[key] = intVal
            } else if let doubleVal = Double(valueStr) {
                result[key] = doubleVal
            } else {
                result[key] = valueStr
            }
        }
        return result
    }
}
