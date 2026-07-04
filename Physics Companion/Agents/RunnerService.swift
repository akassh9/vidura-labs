//
//  RunnerService.swift
//  Physics Companion
//
//  Compiles and executes Pythia simulations locally (no Docker needed).
//

import Foundation
import os.log

enum RunnerService {

    private static let runnerLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhysicsCompanion", category: "RunnerService")

    // MARK: - Errors

    enum RunnerError: LocalizedError {
        case compilationFailed(log: String)
        case executionFailed(log: String)
        case timeout
        case missingCompiler

        var errorDescription: String? {
            switch self {
            case .compilationFailed(let log): return "Compilation failed:\n\(log)"
            case .executionFailed(let log):   return "Execution failed:\n\(log)"
            case .timeout:                    return "Simulation timed out."
            case .missingCompiler:            return "C++ compiler not found."
            }
        }
    }

    // MARK: - Execute Attempt

    /// Compiles and runs a Pythia C++ simulation, returning structured results.
    ///
    /// The attempt directory structure:
    ///   <attemptDir>/run.cc
    ///   <attemptDir>/compile.log
    ///   <attemptDir>/run.log
    ///   <attemptDir>/summary_lines.txt (written by the simulation)
    ///   <attemptDir>/summary.json (parsed from summary_lines.txt)
    ///   <attemptDir>/*.txt (histograms, pid counts, etc.)
    static func executeAttempt(
        generatedCode: GeneratedCode,
        spec: SimulationSpec,
        attemptDir: URL,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> AttemptExecutionResult {
        let fm = FileManager.default

        // Ensure attempt directory exists
        try fm.createDirectory(at: attemptDir, withIntermediateDirectories: true)

        let sourceFile = attemptDir.appendingPathComponent("run.cc")
        let compileLog = attemptDir.appendingPathComponent("compile.log")
        let runtimeLog = attemptDir.appendingPathComponent("run.log")
        let binaryFile = attemptDir.appendingPathComponent("run")

        // Write source code
        try generatedCode.sourceCode.write(to: sourceFile, atomically: true, encoding: .utf8)

        // Write spec as JSON
        let specFile = attemptDir.appendingPathComponent("simulation_spec.json")
        let specData = try JSONEncoder().encode(spec)
        try specData.write(to: specFile)

        // Compile
        onProgress("Compiling simulation...")
        let pythiaDir = PathUtils.pythiaDir

        let compileArgs: [String] = [
            "-std=c++17", "-O2",
            sourceFile.path,
            "-o", binaryFile.path,
            "-I\(pythiaDir.appendingPathComponent("include").path)",
            pythiaDir.appendingPathComponent("lib/libpythia8.a").path,
            "-ldl", "-lz"
        ]

        let compileResult = await runProcess(
            executable: "/usr/bin/clang++",
            arguments: compileArgs,
            workingDirectory: attemptDir,
            timeoutSeconds: 120,
            onOutput: onProgress
        )

        // Write compile log
        try compileResult.output.write(to: compileLog, atomically: true, encoding: .utf8)

        guard compileResult.exitCode == 0 else {
            return AttemptExecutionResult(
                status: "compile_error",
                compileLogPath: compileLog.path,
                runtimeLogPath: runtimeLog.path,
                summaryJsonPath: nil,
                diagnostics: compileResult.output,
                plotPaths: [],
                generatedCodePath: sourceFile.path
            )
        }

        // Run
        onProgress("Running simulation (\(spec.eventCount) events)...")

        // Set PYTHIA8DATA environment variable
        let xmldocPath = pythiaDir
            .appendingPathComponent("share")
            .appendingPathComponent("Pythia8")
            .appendingPathComponent("xmldoc")
            .path

        let runResult = await runProcess(
            executable: binaryFile.path,
            arguments: [],
            workingDirectory: attemptDir,
            timeoutSeconds: 300,
            environment: ["PYTHIA8DATA": xmldocPath],
            onOutput: onProgress
        )

        // Write runtime log
        try runResult.output.write(to: runtimeLog, atomically: true, encoding: .utf8)

        guard runResult.exitCode == 0 else {
            return AttemptExecutionResult(
                status: "runtime_error",
                compileLogPath: compileLog.path,
                runtimeLogPath: runtimeLog.path,
                summaryJsonPath: nil,
                diagnostics: runResult.output,
                plotPaths: [],
                generatedCodePath: sourceFile.path
            )
        }

        // Parse summary
        onProgress("Parsing results...")
        let summaryLinesPath = attemptDir.appendingPathComponent("summary_lines.txt")
        let summaryJsonPath = attemptDir.appendingPathComponent("summary.json")

        var summaryDict: [String: Any] = [:]
        if fm.fileExists(atPath: summaryLinesPath.path) {
            let content = try String(contentsOf: summaryLinesPath, encoding: .utf8)
            summaryDict = parseSummaryLines(content)

            // Write summary.json
            if let jsonData = try? JSONSerialization.data(
                withJSONObject: summaryDict,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                try jsonData.write(to: summaryJsonPath)
            }
        }

        // Collect artifact files
        var plotPaths: [String] = []
        var seenPlotPaths = Set<String>()
        let excludedEvidenceFiles: Set<String> = [
            "run.cc",
            "run",
            "compile.log",
            "run.log",
            "summary.json",
            "summary_lines.txt",
            "simulation_spec.json"
        ]
        var artifactFiles = ["hist_primary.txt", "hist_pt.txt", "pid_counts.txt", "event_scalars.txt"]
        artifactFiles.append(contentsOf: spec.outputPlan.extraFiles.filter { !excludedEvidenceFiles.contains($0) })

        func appendPlotPathIfPresent(_ path: URL) {
            guard fm.fileExists(atPath: path.path), !seenPlotPaths.contains(path.path) else {
                return
            }
            plotPaths.append(path.path)
            seenPlotPaths.insert(path.path)
        }

        for filename in artifactFiles {
            appendPlotPathIfPresent(attemptDir.appendingPathComponent(filename))
        }

        if let files = try? fm.contentsOfDirectory(at: attemptDir, includingPropertiesForKeys: nil) {
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = file.lastPathComponent
                if name.hasPrefix("hist_") && name.hasSuffix(".txt") {
                    appendPlotPathIfPresent(file)
                }
            }
        }

        return AttemptExecutionResult(
            status: "success",
            compileLogPath: compileLog.path,
            runtimeLogPath: runtimeLog.path,
            summaryJsonPath: fm.fileExists(atPath: summaryJsonPath.path) ? summaryJsonPath.path : nil,
            diagnostics: nil,
            plotPaths: plotPaths,
            generatedCodePath: sourceFile.path
        )
    }

    // MARK: - Summary Parsing

    /// Parses summary_lines.txt into a dictionary.
    /// Accepts both "key=value" and "key value" formats.
    /// Values are parsed as int, then float, then string.
    static func parseSummaryLines(_ content: String) -> [String: Any] {
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

            // Try int
            if let intVal = Int(valueStr) {
                result[key] = intVal
            }
            // Try float
            else if let doubleVal = Double(valueStr) {
                result[key] = doubleVal
            }
            // Raw string
            else {
                result[key] = valueStr
            }
        }
        return result
    }

    // MARK: - Process Execution

    private struct ProcessResult: Sendable {
        let exitCode: Int32
        let output: String
    }

    /// Runs a subprocess off the main thread with streaming output.
    ///
    /// Fixes vs. the previous implementation:
    /// - Uses separate pipes for stdout / stderr to avoid buffer-full deadlock.
    /// - Reads pipe data asynchronously via `readabilityHandler` so the OS
    ///   buffer never fills up (Pythia can emit megabytes of output).
    /// - Uses `terminationHandler` instead of `waitUntilExit()` so the
    ///   calling async context (often @MainActor) is never blocked.
    /// - Streams every chunk to the unified logging system (`os_log`) so
    ///   output appears in the Xcode debug console in real-time.
    private static func runProcess(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: Int,
        environment: [String: String]? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory

            if let env = environment {
                var processEnv = ProcessInfo.processInfo.environment
                for (key, value) in env {
                    processEnv[key] = value
                }
                process.environment = processEnv
            }

            // Separate pipes to avoid deadlock when one stream fills its buffer.
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe

            // Thread-safe accumulator for captured output.
            let accumulator = OutputAccumulator(logger: runnerLog, onOutput: onOutput)

            // Stream stdout asynchronously.
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    // EOF – remove handler so we don't spin.
                    handle.readabilityHandler = nil
                } else {
                    accumulator.append(data, label: "stdout")
                }
            }

            // Stream stderr asynchronously.
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    accumulator.append(data, label: "stderr")
                }
            }

            // Timeout – terminate the process if it runs too long.
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + .seconds(timeoutSeconds))
            timer.setEventHandler {
                if process.isRunning {
                    runnerLog.warning("Process timed out after \(timeoutSeconds)s – terminating.")
                    process.terminate()
                }
            }
            timer.resume()

            // Completion – fires on a background queue, never blocks main.
            process.terminationHandler = { terminatedProcess in
                timer.cancel()

                // Drain any remaining data that arrived after the last
                // readabilityHandler callback but before EOF.
                let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                accumulator.append(remainingStdout, label: "stdout")
                accumulator.append(remainingStderr, label: "stderr")

                // Remove handlers to break retain cycles.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let combined = accumulator.combined()

                continuation.resume(returning: ProcessResult(
                    exitCode: terminatedProcess.terminationStatus,
                    output: combined
                ))
            }

            do {
                try process.run()
            } catch {
                timer.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: ProcessResult(
                    exitCode: -1,
                    output: "Failed to launch process: \(error.localizedDescription)"
                ))
            }
        }
    }

}

// MARK: - Output Accumulator

/// Thread-safe, Sendable accumulator that streams process output to the
/// debug console and collects it for the final result.
private nonisolated final class OutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [String] = []
    private let onOutput: (@Sendable (String) -> Void)?
    private let logger: Logger

    init(logger: Logger, onOutput: (@Sendable (String) -> Void)?) {
        self.logger = logger
        self.onOutput = onOutput
    }

    func append(_ data: Data, label: String) {
        guard !data.isEmpty else { return }
        guard let str = String(data: data, encoding: .utf8) else { return }

        // Log every line to Xcode debug console in real-time.
        for line in str.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            logger.info("[\(label)] \(line)")
        }
        onOutput?(str)

        lock.lock()
        chunks.append(str)
        lock.unlock()
    }

    func combined() -> String {
        lock.lock()
        defer { lock.unlock() }
        return chunks.joined()
    }
}
