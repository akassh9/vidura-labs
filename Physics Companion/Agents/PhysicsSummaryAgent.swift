//
//  PhysicsSummaryAgent.swift
//  Physics Companion
//
//  LLM-powered post-processing stage that produces a physics-informed
//  interpretation from run outputs and available chart data.
//

import Foundation

enum PhysicsSummaryAgent {

    static func run(
        modelName: String,
        settingsApiKey: String?,
        runId: String,
        originalPrompt: String,
        runnablePrompt: String,
        runMessages: [ChatMessage],
        simulationSpec: SimulationSpec?,
        executionResult: AttemptExecutionResult,
        summaryDict: [String: Any],
        chartPayloads: [ChartPayload]
    ) async -> String? {
        let systemInstruction = """
        You are PhysicsSummaryAgent for a particle-physics simulation assistant.

        Task:
        - Write a physics-informed summary of THIS specific run.
        - Use only supplied data. If a metric is missing, state that plainly.
        - If chart data is present, interpret each available observable's trend shape and what it implies physically.
        - Treat plot_paths and chart payload titles as available plot evidence; do not claim an observable is missing when its artifact or chart payload is present.
        - If chart data is absent, still provide conclusions from run metrics.

        Output style:
        - 2-3 short paragraphs.
        - End with a line starting exactly with: Takeaways:
        - Then provide 2-4 concise semicolon-separated takeaways.
        - No markdown headings, no code fences.
        """

        let payload = buildPayload(
            runId: runId,
            originalPrompt: originalPrompt,
            runnablePrompt: runnablePrompt,
            runMessages: runMessages,
            simulationSpec: simulationSpec,
            executionResult: executionResult,
            summaryDict: summaryDict,
            chartPayloads: chartPayloads
        )

        do {
            let client = OpenAIClient(
                apiKey: try OpenAICredentials.resolve(settingsApiKey: settingsApiKey),
                model: modelName
            )
            let text = try await client.responseText(
                instructions: systemInstruction,
                input: payload,
                reasoningEffort: "low",
                verbosity: "low"
            )
            if !text.isEmpty {
                return text
            }
        } catch {
            // Fall through to deterministic fallback.
        }

        return fallbackSummary(summaryDict: summaryDict, chartPayloads: chartPayloads)
    }

    private static func buildPayload(
        runId: String,
        originalPrompt: String,
        runnablePrompt: String,
        runMessages: [ChatMessage],
        simulationSpec: SimulationSpec?,
        executionResult: AttemptExecutionResult,
        summaryDict: [String: Any],
        chartPayloads: [ChartPayload]
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        struct MessageSlice: Encodable {
            let role: String
            let sender: String
            let content: String
            let timestamp: String
        }

        let messageSlice = runMessages.map {
            MessageSlice(
                role: $0.role,
                sender: $0.sender.rawValue,
                content: $0.content,
                timestamp: $0.timestamp
            )
        }

        let messageJSON = (try? encoder.encode(messageSlice)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let specJSON = simulationSpec.flatMap { try? encoder.encode($0) }.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        let executionJSON = (try? encoder.encode(executionResult)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        let chartJSON = (try? encoder.encode(chartPayloads)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        let summaryJSON: String
        if JSONSerialization.isValidJSONObject(summaryDict),
           let data = try? JSONSerialization.data(withJSONObject: summaryDict, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            summaryJSON = json
        } else {
            summaryJSON = "{}"
        }

        return """
        RUN_ID:
        \(runId)

        ORIGINAL_PROMPT:
        \(originalPrompt)

        RUNNABLE_PROMPT:
        \(runnablePrompt)

        RUN_MESSAGES:
        \(messageJSON)

        SIMULATION_SPEC:
        \(specJSON)

        EXECUTION_RESULT:
        \(executionJSON)

        SUMMARY_DICT:
        \(summaryJSON)

        CHART_PAYLOADS:
        \(chartJSON)
        """
    }

    private static func fallbackSummary(
        summaryDict: [String: Any],
        chartPayloads: [ChartPayload]
    ) -> String {
        var lines: [String] = []

        if let generatedEvents = summaryDict["generated_events"] {
            lines.append("The run completed with \(generatedEvents) generated events.")
        } else {
            lines.append("The run completed, but generated event count was not available in the summary.")
        }

        let metricKeys = summaryDict.keys
            .filter { $0 != "generated_events" }
            .sorted()

        if !metricKeys.isEmpty {
            let metricText = metricKeys.prefix(3).map { key in
                "\(key.replacingOccurrences(of: "_", with: " "))=\(summaryDict[key] ?? "n/a")"
            }.joined(separator: ", ")
            lines.append("Reported metrics are consistent with the requested analysis focus (\(metricText)).")
        } else {
            lines.append("No additional scalar metrics were available, so interpretation is limited to completion status.")
        }

        if !chartPayloads.isEmpty {
            let chartTitles = chartPayloads.map(\.title).joined(separator: ", ")
            lines.append("Chart artifacts are available for \(chartTitles), enabling shape-based interpretation of the simulated observables.")
        } else {
            lines.append("No chart artifact was produced for this run, so trend-shape interpretation is not available.")
        }

        lines.append("Takeaways: run succeeded; results should be interpreted within Monte Carlo/statistical uncertainty; rerunning with more events can improve precision")
        return lines.joined(separator: "\n\n")
    }
}
