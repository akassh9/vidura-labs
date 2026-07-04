//
//  PolicyCheckAgent.swift
//  Physics Companion
//
//  Deterministic safety/policy gate for generated C++ code.
//

import Foundation

enum PolicyCheckAgent {

    // MARK: - Banned Patterns

    /// Regex patterns that cause immediate rejection.
    private static let bannedPatterns: [String] = [
        #"\bsystem\s*\("#,
        #"\bfork\s*\("#,
        #"\bexec\w*\s*\("#,
        #"<sys/socket\.h>"#,
        #"\bsocket\s*\("#,
        #"\bdlopen\s*\("#,
        #"\bLoadLibrary\s*\("#,
        #"\bstd::filesystem::remove"#,
        #"\bunlink\s*\("#
    ]

    // MARK: - Allowed Includes

    /// The exact set of permitted #include lines.
    private static let allowedIncludes: Set<String> = [
        "#include <cmath>",
        "#include <fstream>",
        "#include <iostream>",
        "#include <string>",
        "#include <vector>",
        "#include <map>",
        "#include \"Pythia8/Pythia.h\""
    ]

    // MARK: - Run

    /// Validates generated C++ code against policy rules.
    /// Returns (passed: Bool, message: String?)
    static func run(code: String) -> (Bool, String?) {

        // Check banned patterns
        for pattern in bannedPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil {
                return (false, "Policy violation: banned pattern matched (\(pattern)).")
            }
        }

        // Check all #include lines
        let lines = code.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#include") {
                if !allowedIncludes.contains(trimmed) {
                    return (false, "Policy violation: disallowed include: \(trimmed)")
                }
            }
        }

        return (true, nil)
    }
}
