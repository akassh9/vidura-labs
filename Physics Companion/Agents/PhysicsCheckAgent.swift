//
//  PhysicsCheckAgent.swift
//  Physics Companion
//
//  Deterministic preflight validator for generated C++ code.
//

import Foundation

enum PhysicsCheckAgent {

    /// Validates generated code for physical plausibility and structural correctness.
    /// Returns (passed: Bool, message: String?)
    static func run(code: String, intent: IntentResult) -> (Bool, String?) {

        // 1-4. Search for Beams:eCM = <number>
        var eCm: Double = intent.eCmGev
        let ecmPattern = try? NSRegularExpression(pattern: #"Beams:eCM\s*=\s*([0-9]*\.?[0-9]+)"#)
        if let match = ecmPattern?.firstMatch(
            in: code, range: NSRange(code.startIndex..., in: code)
        ) {
            if let range = Range(match.range(at: 1), in: code),
               let parsed = Double(code[range]) {
                eCm = parsed
            }
        }

        // 4. Fail if eCM <= 0
        if eCm <= 0 {
            return (false, "Physics check failed: Beams:eCM must be positive.")
        }

        // 5. Fail if eCM > 1e7
        if eCm > 1e7 {
            return (false, "Physics check failed: Beams:eCM unreasonably large.")
        }

        // 6-7. Check frameType if present
        let framePattern = try? NSRegularExpression(pattern: #"Beams:frameType\s*=\s*(\d+)"#)
        if let match = framePattern?.firstMatch(
            in: code, range: NSRange(code.startIndex..., in: code)
        ) {
            if let range = Range(match.range(at: 1), in: code),
               let frameType = Int(code[range]) {
                if ![1, 2, 3].contains(frameType) {
                    return (false, "Physics check failed: Beams:frameType should be 1, 2, or 3.")
                }
            }
        }

        // 8. Fail if code does not contain pythia.init() or pythia.init(
        if !code.contains("pythia.init()") && !code.contains("pythia.init(") {
            return (false, "Physics check failed: missing pythia.init call.")
        }

        // 9. Fail if no process setting enabled (regex: \w+:\w+\s*=\s*on)
        let processPattern = try? NSRegularExpression(pattern: #"\w+:\w+\s*=\s*on"#)
        let hasProcess = processPattern?.firstMatch(
            in: code, range: NSRange(code.startIndex..., in: code)
        ) != nil
        if !hasProcess {
            return (false, "Physics check failed: no process setting enabled (e.g., HardQCD:all = on).")
        }

        // 10. Pass
        return (true, nil)
    }
}
