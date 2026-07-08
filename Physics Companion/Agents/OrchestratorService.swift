//
//  OrchestratorService.swift
//  Physics Companion
//
//  Main orchestrator: assembles the 7-agent SDK pipeline with tool handoffs.
//

import Foundation
import SwiftUI
import Combine
import os.log

private let aiLogger = Logger(subsystem: "com.vidura.physicscompanion", category: "OpenAI")

// MARK: - AI Model Selection

enum AIModel: String, CaseIterable, Identifiable {
    case gpt55 = "gpt-5.5"
    case gpt54 = "gpt-5.4"
    case gpt54Mini = "gpt-5.4-mini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt55:     return "GPT-5.5"
        case .gpt54:     return "GPT-5.4"
        case .gpt54Mini: return "GPT-5.4 Mini"
        }
    }

    var subtitle: String {
        switch self {
        case .gpt55:     return "Most capable"
        case .gpt54:     return "Balanced"
        case .gpt54Mini: return "Fast & economical"
        }
    }
}

// MARK: - Orchestrator Run Context

/// Mutable state carried through the agent pipeline.
final class OrchestratorRunContext: @unchecked Sendable {
    var runId: String
    let chatRunId: String  // The original chat run for conversational messages
    var prompt: String
    let originalPrompt: String
    var intent: IntentResult?
    var templates: [TemplateCandidate] = []
    var precedence: PrecedenceContext?
    var spec: SimulationSpec?
    var generated: GeneratedCode?
    var lastDiagnostics: String?
    var lastAttempt: AttemptExecutionResult?
    var attemptNumber: Int = 0
    var guideDecision: ResearchGuideDecision?
    var legacyContract: Bool = false
    let maxAttempts: Int
    var events: [AgentEvent] = []

    // References for DB persistence
    let store: ResearchStore
    let settingsStore: SettingsStore
    let threadId: String

    init(
        runId: String,
        prompt: String,
        store: ResearchStore,
        settingsStore: SettingsStore,
        threadId: String,
        maxAttempts: Int = 3
    ) {
        self.runId = runId
        self.chatRunId = runId
        self.prompt = prompt
        self.originalPrompt = prompt
        self.store = store
        self.settingsStore = settingsStore
        self.threadId = threadId
        self.maxAttempts = maxAttempts
    }

    func emitEvent(phase: String, step: String, data: [String: String] = [:]) {
        let event = AgentEvent(phase: phase, step: step, data: data)
        events.append(event)
    }
}

// MARK: - Orchestrator Errors

enum OrchestratorError: LocalizedError {
    case rateLimitExceeded
    case stageFailed(stage: String, underlying: Error)
    case stageEmptyResponse(stage: String)
    case rerunUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .rateLimitExceeded:
            return "OpenAI API rate limit reached (error 429). Please try a different model in Settings, or wait a moment and try again."
        case .stageFailed(let stage, let underlying):
            return "\(stage) failed: \(underlying.localizedDescription)"
        case .stageEmptyResponse(let stage):
            return "\(stage) did not produce a valid response. Please try again."
        case .rerunUnavailable(let message):
            return message
        }
    }

    /// Checks whether an error represents a 429 / resource-exhausted condition.
    static func isRateLimitError(_ error: Error) -> Bool {
        if let openAIError = error as? OpenAIClientError {
            return openAIError.isRateLimit
        }
        let desc = String(describing: error)
        if desc.contains("Resource exhausted") || desc.contains("429") || desc.contains("RESOURCE_EXHAUSTED") {
            return true
        }
        if let nsError = error as NSError? {
            if nsError.code == 429 { return true }
            if nsError.domain.contains("ResourceExhausted") { return true }
            let userInfoStr = nsError.userInfo.description
            if userInfoStr.contains("429") || userInfoStr.contains("Resource exhausted") || userInfoStr.contains("RESOURCE_EXHAUSTED") {
                return true
            }
        }
        return false
    }
}

// MARK: - Orchestrator Service

/// Assembles and runs the local simulation pipeline using OpenAI and deterministic stages.
///
/// Agent pipeline:
///   GuideAgent → IntentAgent → PrecedenceAgent → CapabilityPlannerAgent
///   → CodingAgent → ExecutorAgent → ResultAgent → PlottingAgent → PhysicsSummaryAgent
///
/// Retry loop: ExecutorAgent → CodingAgent on failure (up to maxAttempts)
@MainActor
final class OrchestratorService: ObservableObject {
    private struct PlottingStageOutput {
        let chartPayloads: [ChartPayload]
        let chartMessageIds: [String]

        var lastChartMessageId: String? {
            chartMessageIds.last
        }
    }

    private struct CodegenStageResponse: Decodable {
        let sourceCode: String

        enum CodingKeys: String, CodingKey {
            case sourceCode = "source_code"
        }
    }

    @Published var selectedModel: AIModel = AIModel(
        rawValue: UserDefaults.standard.string(forKey: "selectedAIModel") ?? ""
    ) ?? .gpt55 {
        didSet { UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedAIModel") }
    }

    private var modelName: String { selectedModel.rawValue }

    @Published private(set) var currentPhase: String = "idle"
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastError: String?
    /// Simulation event-generation progress (0.0 … 1.0). `nil` when not in the execution phase.
    @Published private(set) var simulationProgress: Double? = nil
    /// Estimated seconds remaining for event generation. `nil` when unavailable.
    @Published private(set) var estimatedSecondsRemaining: Double? = nil
    /// The thread ID for which the orchestrator is currently running.
    @Published private(set) var activeThreadId: String? = nil
    /// Timestamp when event generation started, used to compute ETA.
    private var simulationStartDate: Date? = nil

    private let store: ResearchStore
    private let settingsStore: SettingsStore

    init(store: ResearchStore, settingsStore: SettingsStore) {
        self.store = store
        self.settingsStore = settingsStore
    }

    private func openAIClient(ctx: OrchestratorRunContext) throws -> OpenAIClient {
        OpenAIClient(
            apiKey: try OpenAICredentials.resolve(settingsApiKey: ctx.settingsStore.data.apiKey),
            model: modelName
        )
    }

    // MARK: - Main Entry Point

    /// Runs the full orchestration pipeline for a user prompt.
    /// Returns the final assistant message to display.
    func run(
        runId: String,
        threadId: String,
        prompt: String,
        chatHistory: [ChatMessage]
    ) async throws -> String {
        isRunning = true
        currentPhase = "queued"
        lastError = nil
        simulationProgress = nil
        estimatedSecondsRemaining = nil
        simulationStartDate = nil
        activeThreadId = threadId

        defer {
            isRunning = false
            currentPhase = "idle"
            simulationProgress = nil
            estimatedSecondsRemaining = nil
            simulationStartDate = nil
            activeThreadId = nil
        }

        let ctx = OrchestratorRunContext(
            runId: runId,
            prompt: prompt,
            store: store,
            settingsStore: settingsStore,
            threadId: threadId
        )

        // Auto-name the thread if it still has the default title
        let thread = store.threads.first { $0.id == threadId }
        if let thread, thread.title == "New Thread" {
            let capturedPrompt = prompt
            let capturedStore = store
            let capturedThreadId = threadId
            Task.detached {
                let title = await ThreadNamingAgent.generateTitle(
                    for: capturedPrompt
                )
                try? await capturedStore.updateThread(
                    id: capturedThreadId,
                    title: title
                )
            }
        }

        // Mark chat run as running (guide phase)
        ctx.emitEvent(phase: "queued", step: "started")
        try await store.updateRunStatus(id: runId, status: .running)
        
        var lastMsgId = chatHistory.last!.id

        do {
            // STEP 1: Guide Decision
            currentPhase = "guide"
            ctx.emitEvent(phase: "guide", step: "started")
            let guideResult = try await runGuideStage(ctx: ctx, chatHistory: chatHistory)

            if guideResult.action != .runSimulation {
                // Guide-only success (answer or propose_simulation)
                try await finalizeGuideOnly(ctx: ctx, decision: guideResult, lastMsgId: lastMsgId)
                return guideResult.assistantMessage
            }

            // Update prompt to runnable version
            if let runnablePrompt = guideResult.runnablePrompt {
                ctx.prompt = runnablePrompt
            }

            // STEP 2: Intent Extraction
            currentPhase = "discovery"
            ctx.emitEvent(phase: "discovery", step: "intent_started")
            let intent = try await runIntentStage(ctx: ctx)
            ctx.intent = intent

            // STEP 3: Precedence / Template Selection
            ctx.emitEvent(phase: "discovery", step: "precedence_started")
            try await runPrecedenceStage(ctx: ctx)

            // STEP 4: Analysis Planning
            ctx.emitEvent(phase: "discovery", step: "planning_started")
            let spec = runCapabilityPlannerStage(ctx: ctx)
            ctx.spec = spec

            // Create a new simulation run with the Pythia configuration
            let simConfig = buildConfigurationDict(from: spec)
            try await store.updateRunConfiguration(id: ctx.runId, configuration: simConfig)

            try await store.updateRunStatus(id: ctx.runId, status: .running)

            // STEP 5-6: Code Generation + Execution (with retry loop)
            var finalResult: String?
            for attempt in 0..<ctx.maxAttempts {
                ctx.attemptNumber = attempt + 1

                // Code generation
                currentPhase = "codegen"
                ctx.emitEvent(phase: "codegen", step: "started", data: ["attempt": "\(attempt + 1)"])
                let generated = try await runCodingStage(ctx: ctx)
                ctx.generated = generated

                // Execution
                currentPhase = "compile"
                ctx.emitEvent(phase: "compile", step: "started", data: ["attempt": "\(attempt + 1)"])
                let attemptResult = try await runExecutorStage(ctx: ctx)
                ctx.lastAttempt = attemptResult

                if attemptResult.status == "success" {
                    // STEP 7: Result Summary
                    currentPhase = "results"
                    ctx.emitEvent(phase: "done", step: "summarizing")
                    let summary = try await runResultStage(ctx: ctx)
                    lastMsgId = try await finalizeSuccess(ctx: ctx, summaryText: summary, lastMsgId: lastMsgId)

                    // STEP 8: Plotting (chart data for inline rendering)
                    currentPhase = "plotting"
                    ctx.emitEvent(phase: "plotting", step: "started")
                    let plottingOutput = try await runPlottingStage(ctx: ctx, lastMsgId: lastMsgId)
                    ctx.emitEvent(phase: "plotting", step: "completed")

                    // STEP 9: Physics-Informed Summary (uses graph data when available)
                    currentPhase = "physics_summary"
                    ctx.emitEvent(phase: "physics_summary", step: "started")
                    let physicsSummary = try await runPhysicsSummaryStage(
                        ctx: ctx,
                        chatHistory: chatHistory,
                        chartPayloads: plottingOutput.chartPayloads,
                        lastMsgId: plottingOutput.lastChartMessageId ?? lastMsgId
                    )
                    ctx.emitEvent(
                        phase: "physics_summary",
                        step: physicsSummary == nil ? "no_output" : "completed"
                    )

                    currentPhase = "physics_review"
                    ctx.emitEvent(phase: "physics_review", step: "started")
                    let reviewerMessages = try await store.fetchRunMessagesAndParents(forRun: ctx.runId)
                    let reviewerFindings = await runPhysicsReviewerStage(
                        ctx: ctx,
                        runMessages: reviewerMessages,
                        chartPayloads: plottingOutput.chartPayloads,
                        finalSummaryText: physicsSummary ?? summary,
                        lastMsgId: plottingOutput.lastChartMessageId ?? lastMsgId
                    )
                    ctx.emitEvent(
                        phase: "physics_review",
                        step: reviewerFindings.isEmpty ? "no_output" : "completed"
                    )

                    finalResult = physicsSummary ?? summary
                    break
                } else {
                    ctx.lastDiagnostics = attemptResult.diagnostics
                    if attempt + 1 >= ctx.maxAttempts {
                        try await finalizeFailure(
                            ctx: ctx,
                            diagnostics: attemptResult.diagnostics ?? "Unknown error",
                            lastMsgId: lastMsgId
                        )
                        return "Simulation failed after \(ctx.maxAttempts) attempts. \(attemptResult.diagnostics ?? "")"
                    }
                    ctx.emitEvent(phase: "compile", step: "retry", data: [
                        "attempt": "\(attempt + 1)",
                        "diagnostics": attemptResult.diagnostics ?? ""
                    ])
                }
            }

            return finalResult ?? "Simulation completed."

        } catch {
            lastError = error.localizedDescription
            try? await finalizeFailure(ctx: ctx, diagnostics: error.localizedDescription, lastMsgId: lastMsgId)
            throw error
        }
    }

    /// Creates a sibling run from persisted evidence and executes the exact saved source/spec.
    /// This intentionally bypasses guide, intent extraction, planning, and code generation.
    @discardableResult
    func rerunExact(run sourceRun: SimulationRun) async throws -> SimulationRun {
        guard sourceRun.status == .completed else {
            throw OrchestratorError.rerunUnavailable("Only completed simulation runs can be rerun exactly.")
        }

        isRunning = true
        currentPhase = "queued"
        lastError = nil
        simulationProgress = nil
        estimatedSecondsRemaining = nil
        simulationStartDate = nil
        activeThreadId = sourceRun.threadId

        defer {
            isRunning = false
            currentPhase = "idle"
            simulationProgress = nil
            estimatedSecondsRemaining = nil
            simulationStartDate = nil
            activeThreadId = nil
        }

        let sourcePath = try evidencePath(for: sourceRun, named: "run.cc")
        let specPath = try evidencePath(for: sourceRun, named: "simulation_spec.json")
        let source = try String(contentsOfFile: sourcePath, encoding: .utf8)
        let specData = try Data(contentsOf: URL(fileURLWithPath: specPath))
        let spec = try JSONDecoder().decode(SimulationSpec.self, from: specData)

        let baseTitle = sourceRun.title.hasPrefix("Exact rerun: ")
            ? String(sourceRun.title.dropFirst("Exact rerun: ".count))
            : sourceRun.title

        var configuration = buildConfigurationDict(from: spec)
        configuration["Vidura:exactRerunOfRunID"] = sourceRun.id

        let rerun = try await store.createRun(
            threadId: sourceRun.threadId,
            title: "Exact rerun: \(baseTitle)",
            configuration: configuration
        )

        let ctx = OrchestratorRunContext(
            runId: rerun.id,
            prompt: "Exact rerun of \(sourceRun.id)",
            store: store,
            settingsStore: settingsStore,
            threadId: sourceRun.threadId,
            maxAttempts: 1
        )
        ctx.spec = spec
        ctx.generated = GeneratedCode(sourceCode: source, commandFile: nil, origin: "exact_rerun")
        ctx.attemptNumber = 1
        ctx.emitEvent(phase: "queued", step: "exact_rerun_started", data: ["source_run_id": sourceRun.id])

        let requestMessage = ChatMessage(
            id: UUID().uuidString,
            role: "user",
            content: "Rerun exact from run \(sourceRun.id).",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            originRunId: rerun.id,
            sender: .user
        )
        try await store.addChatMessage(runId: rerun.id, message: requestMessage)

        do {
            try await store.updateRunStatus(id: rerun.id, status: .running)

            currentPhase = "compile"
            ctx.emitEvent(phase: "compile", step: "exact_rerun_executing")
            let attempt = try await runExactExecutorStage(ctx: ctx)
            ctx.lastAttempt = attempt

            guard attempt.status == "success" else {
                try await finalizeFailure(
                    ctx: ctx,
                    diagnostics: attempt.diagnostics ?? "Exact rerun failed.",
                    lastMsgId: requestMessage.id
                )
                throw OrchestratorError.rerunUnavailable(attempt.diagnostics ?? "Exact rerun failed.")
            }

            let rerunSpecURL = URL(fileURLWithPath: attempt.generatedCodePath)
                .deletingLastPathComponent()
                .appendingPathComponent("simulation_spec.json")
            try specData.write(to: rerunSpecURL)

            currentPhase = "results"
            ctx.emitEvent(phase: "done", step: "summarizing")
            let summary = try await runResultStage(ctx: ctx)
            let summaryMessageId = try await finalizeSuccess(
                ctx: ctx,
                summaryText: summary,
                lastMsgId: requestMessage.id
            )

            currentPhase = "plotting"
            ctx.emitEvent(phase: "plotting", step: "started")
            let plottingOutput = try await runPlottingStage(ctx: ctx, lastMsgId: summaryMessageId)
            ctx.emitEvent(phase: "plotting", step: "completed")

            currentPhase = "physics_summary"
            ctx.emitEvent(phase: "physics_summary", step: "started")
            let runMessages = try await store.fetchRunMessagesAndParents(forRun: rerun.id)
            let physicsSummary = try await runPhysicsSummaryStage(
                ctx: ctx,
                chatHistory: runMessages,
                chartPayloads: plottingOutput.chartPayloads,
                lastMsgId: plottingOutput.lastChartMessageId ?? summaryMessageId
            )
            ctx.emitEvent(
                phase: "physics_summary",
                step: physicsSummary == nil ? "no_output" : "completed"
            )

            currentPhase = "physics_review"
            ctx.emitEvent(phase: "physics_review", step: "started")
            let reviewerMessages = try await store.fetchRunMessagesAndParents(forRun: rerun.id)
            let reviewerFindings = await runPhysicsReviewerStage(
                ctx: ctx,
                runMessages: reviewerMessages,
                chartPayloads: plottingOutput.chartPayloads,
                finalSummaryText: physicsSummary ?? summary,
                lastMsgId: plottingOutput.lastChartMessageId ?? summaryMessageId
            )
            ctx.emitEvent(
                phase: "physics_review",
                step: reviewerFindings.isEmpty ? "no_output" : "completed"
            )

            try await store.loadRuns(forThread: sourceRun.threadId)
            return try await store.fetchRun(id: rerun.id)
        } catch {
            lastError = error.localizedDescription
            if (try? await store.fetchRun(id: rerun.id).status) != .failed {
                try? await finalizeFailure(
                    ctx: ctx,
                    diagnostics: error.localizedDescription,
                    lastMsgId: requestMessage.id
                )
            }
            throw error
        }
    }

    /// Creates a sibling run from persisted spec evidence, applies controlled parameter changes,
    /// regenerates deterministic source, and executes through the normal runner path.
    @discardableResult
    func rerunParameterized(
        run sourceRun: SimulationRun,
        request: ParameterizedRerunRequest
    ) async throws -> SimulationRun {
        guard sourceRun.status == .completed else {
            throw OrchestratorError.rerunUnavailable("Only completed simulation runs can create a parameterized rerun.")
        }
        guard (1...50_000).contains(request.eventCount) else {
            throw OrchestratorError.rerunUnavailable("Event count must be between 1 and 50,000.")
        }
        guard (1...900_000_000).contains(request.seed) else {
            throw OrchestratorError.rerunUnavailable("Random seed must be between 1 and 900,000,000.")
        }
        if let pTHatMin = request.pTHatMin, pTHatMin < 0 {
            throw OrchestratorError.rerunUnavailable("PhaseSpace:pTHatMin must be non-negative.")
        }

        isRunning = true
        currentPhase = "queued"
        lastError = nil
        simulationProgress = nil
        estimatedSecondsRemaining = nil
        simulationStartDate = nil
        activeThreadId = sourceRun.threadId

        defer {
            isRunning = false
            currentPhase = "idle"
            simulationProgress = nil
            estimatedSecondsRemaining = nil
            simulationStartDate = nil
            activeThreadId = nil
        }

        let specPath = try evidencePath(for: sourceRun, named: "simulation_spec.json")
        let specData = try Data(contentsOf: URL(fileURLWithPath: specPath))
        let sourceSpec = try JSONDecoder().decode(SimulationSpec.self, from: specData)

        let baseTitle = sourceRun.title
            .replacingOccurrences(of: "Exact rerun: ", with: "")
            .replacingOccurrences(of: "Variant: ", with: "")
        let variant = try await store.createRun(
            threadId: sourceRun.threadId,
            title: "Variant: \(baseTitle)",
            configuration: sourceRun.configuration
        )

        let modifiedSpec = buildParameterizedSpec(
            from: sourceSpec,
            runId: variant.id,
            request: request
        )
        var configuration = buildConfigurationDict(from: modifiedSpec)
        let changes = parameterChangeSummary(sourceSpec: sourceSpec, modifiedSpec: modifiedSpec)
        configuration["Vidura:variantOfRunID"] = sourceRun.id
        configuration["Vidura:variantChanges"] = changes.joined(separator: "; ")
        configuration["Vidura:variantCodegen"] = "deterministic"
        try await store.updateRunConfiguration(id: variant.id, configuration: configuration)

        let prompt = "Parameterized rerun of \(sourceRun.id): \(changes.joined(separator: "; "))."
        let ctx = OrchestratorRunContext(
            runId: variant.id,
            prompt: prompt,
            store: store,
            settingsStore: settingsStore,
            threadId: sourceRun.threadId,
            maxAttempts: 1
        )
        ctx.spec = modifiedSpec
        ctx.intent = buildIntent(from: modifiedSpec, prompt: prompt)
        ctx.generated = CodegenAgent.run(spec: modifiedSpec)
        ctx.attemptNumber = 1
        ctx.emitEvent(phase: "queued", step: "parameterized_rerun_started", data: [
            "source_run_id": sourceRun.id,
            "event_count": "\(modifiedSpec.eventCount)",
            "seed": "\(modifiedSpec.seed)",
            "PhaseSpace:pTHatMin": formattedCutValue(phaseSpacePTHatMin(in: modifiedSpec.cutsSettings)) ?? "unset"
        ])
        ctx.emitEvent(phase: "codegen", step: "deterministic_variant", data: [
            "origin": ctx.generated?.origin ?? "deterministic"
        ])

        let requestMessage = ChatMessage(
            id: UUID().uuidString,
            role: "user",
            content: "Create a parameterized rerun from run \(sourceRun.id).\n\(changes.joined(separator: "\n"))",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            originRunId: variant.id,
            sender: .user
        )
        try await store.addChatMessage(runId: variant.id, message: requestMessage)

        do {
            try await store.updateRunStatus(id: variant.id, status: .running)

            currentPhase = "compile"
            ctx.emitEvent(phase: "compile", step: "parameterized_rerun_executing")
            let attempt = try await runExecutorStage(ctx: ctx)
            ctx.lastAttempt = attempt

            guard attempt.status == "success" else {
                try await finalizeFailure(
                    ctx: ctx,
                    diagnostics: attempt.diagnostics ?? "Parameterized rerun failed.",
                    lastMsgId: requestMessage.id
                )
                throw OrchestratorError.rerunUnavailable(attempt.diagnostics ?? "Parameterized rerun failed.")
            }

            currentPhase = "results"
            ctx.emitEvent(phase: "done", step: "summarizing")
            let summary = try await runResultStage(ctx: ctx)
            let summaryMessageId = try await finalizeSuccess(
                ctx: ctx,
                summaryText: summary,
                lastMsgId: requestMessage.id
            )

            currentPhase = "plotting"
            ctx.emitEvent(phase: "plotting", step: "started")
            let plottingOutput = try await runPlottingStage(ctx: ctx, lastMsgId: summaryMessageId)
            ctx.emitEvent(phase: "plotting", step: "completed")

            currentPhase = "physics_summary"
            ctx.emitEvent(phase: "physics_summary", step: "started")
            let runMessages = try await store.fetchRunMessagesAndParents(forRun: variant.id)
            let physicsSummary = try await runPhysicsSummaryStage(
                ctx: ctx,
                chatHistory: runMessages,
                chartPayloads: plottingOutput.chartPayloads,
                lastMsgId: plottingOutput.lastChartMessageId ?? summaryMessageId
            )
            ctx.emitEvent(
                phase: "physics_summary",
                step: physicsSummary == nil ? "no_output" : "completed"
            )

            currentPhase = "physics_review"
            ctx.emitEvent(phase: "physics_review", step: "started")
            let reviewerMessages = try await store.fetchRunMessagesAndParents(forRun: variant.id)
            let reviewerFindings = await runPhysicsReviewerStage(
                ctx: ctx,
                runMessages: reviewerMessages,
                chartPayloads: plottingOutput.chartPayloads,
                finalSummaryText: physicsSummary ?? summary,
                lastMsgId: plottingOutput.lastChartMessageId ?? summaryMessageId
            )
            ctx.emitEvent(
                phase: "physics_review",
                step: reviewerFindings.isEmpty ? "no_output" : "completed"
            )

            try await store.loadRuns(forThread: sourceRun.threadId)
            return try await store.fetchRun(id: variant.id)
        } catch {
            lastError = error.localizedDescription
            if (try? await store.fetchRun(id: variant.id).status) != .failed {
                try? await finalizeFailure(
                    ctx: ctx,
                    diagnostics: error.localizedDescription,
                    lastMsgId: requestMessage.id
                )
            }
            throw error
        }
    }

    // MARK: - Stage 1: Guide

    private func runGuideStage(
        ctx: OrchestratorRunContext,
        chatHistory: [ChatMessage]
    ) async throws -> ResearchGuideDecision {
        let payload = ResearchGuideAgent.buildGuidePayload(messages: chatHistory)

        do {
            aiLogger.info("[GuideStage] Starting OpenAI guide stage with payload length: \(payload.count)")
            let client = try openAIClient(ctx: ctx)
            var decision = try await client.responseObject(
                ResearchGuideDecision.self,
                instructions: """
                \(ResearchGuideAgent.defaultSystemPrompt)

                Return only the structured decision object. Use null for runnable_prompt \
                and analysis_family when they are not applicable.
                """,
                input: payload,
                textFormat: OpenAIResponseFormats.guideDecision,
                reasoningEffort: "low"
            )

            if decision.assistantMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let fallback = ResearchGuideAgent.fallbackGuideDecision(
                    content: ctx.originalPrompt,
                    recentMessages: chatHistory
                )
                decision = ResearchGuideDecision(
                    action: decision.action,
                    assistantMessage: fallback.assistantMessage,
                    runnablePrompt: decision.runnablePrompt ?? fallback.runnablePrompt,
                    analysisFamily: decision.analysisFamily ?? fallback.analysisFamily
                )
            }

            if decision.action == .runSimulation,
               decision.runnablePrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                let fallback = ResearchGuideAgent.fallbackGuideDecision(
                    content: ctx.originalPrompt,
                    recentMessages: chatHistory
                )
                decision = ResearchGuideDecision(
                    action: .runSimulation,
                    assistantMessage: decision.assistantMessage,
                    runnablePrompt: fallback.runnablePrompt ?? ctx.originalPrompt,
                    analysisFamily: decision.analysisFamily ?? fallback.analysisFamily
                )
            }

            ctx.guideDecision = decision
            aiLogger.info("[GuideStage] Returning decision: \(decision.action.rawValue, privacy: .public)")
            return decision
        } catch let orchError as OrchestratorError {
            throw orchError
        } catch {
            aiLogger.error("[GuideStage] Error: \(error.localizedDescription, privacy: .public)")
            aiLogger.error("[GuideStage] Full error: \(String(describing: error), privacy: .public)")
            if let nsError = error as NSError? {
                aiLogger.error("[GuideStage] NSError domain: \(nsError.domain, privacy: .public), code: \(nsError.code)")
                aiLogger.error("[GuideStage] NSError userInfo: \(nsError.userInfo.description, privacy: .public)")
            }
            if OrchestratorError.isRateLimitError(error) {
                throw OrchestratorError.rateLimitExceeded
            }
            throw OrchestratorError.stageFailed(stage: "Guide", underlying: error)
        }
    }

    // MARK: - Stage 2: Intent

    private func runIntentStage(
        ctx: OrchestratorRunContext
    ) async throws -> IntentResult {
        let intentInstructions = """
        You are the IntentAgent. Parse the simulation request and call record_intent exactly once with:
        - process_hint: a Pythia process setting (e.g. "HardQCD:all = on")
        - beam_frame: one of "pp", "ee", "ep"
        - e_cm_gev: center-of-mass energy in GeV
        - event_count: number of events
        - observables: list of observable hints
        - requested_analysis_candidates: ranked list from: charged_multiplicity, pt_spectrum, eta_rapidity, invariant_mass, pid_yields, event_scalars

        Then hand off to PrecedenceAgent immediately.
        """

        do {
            aiLogger.info("[IntentStage] Starting OpenAI intent stage with prompt: \(ctx.prompt.prefix(100), privacy: .public)")
            let client = try openAIClient(ctx: ctx)
            let parsed = try await client.responseObject(
                IntentResult.self,
                instructions: """
                \(intentInstructions)

                Return only the structured intent object. Keep event_count modest when \
                the user does not specify a count; 1000 is a good default for exploratory runs.
                """,
                input: ctx.prompt,
                textFormat: OpenAIResponseFormats.intent,
                reasoningEffort: "low"
            )

            let intent = validatedIntent(parsed, originalPrompt: ctx.prompt)
            ctx.intent = intent
            aiLogger.info("[IntentStage] Intent parsed: process=\(intent.processHint, privacy: .public), beam=\(intent.beamFrame, privacy: .public), eCm=\(intent.eCmGev)")
            return intent
        } catch let orchError as OrchestratorError {
            throw orchError
        } catch {
            aiLogger.error("[IntentStage] Error: \(error.localizedDescription, privacy: .public)")
            aiLogger.error("[IntentStage] Full error: \(String(describing: error), privacy: .public)")
            if let nsError = error as NSError? {
                aiLogger.error("[IntentStage] NSError domain: \(nsError.domain, privacy: .public), code: \(nsError.code)")
                aiLogger.error("[IntentStage] NSError userInfo: \(nsError.userInfo.description, privacy: .public)")
            }
            if OrchestratorError.isRateLimitError(error) {
                throw OrchestratorError.rateLimitExceeded
            }
            throw OrchestratorError.stageFailed(stage: "Intent", underlying: error)
        }
    }

    // MARK: - Stage 3: Precedence

    private func runPrecedenceStage(ctx: OrchestratorRunContext) async throws {
        let candidates = await ExampleIndex.shared.search(
            query: ctx.prompt,
            intent: ctx.intent,
            topK: 3
        )

        if candidates.isEmpty {
            ctx.templates = [
                TemplateCandidate(
                    filename: "main101.cc",
                    section: "Basic Examples",
                    description: "fallback"
                )
            ]
            ctx.precedence = PrecedenceContext(
                notes: "No examples matched; using default main101.cc template.",
                selections: [],
                materializedSnippets: []
            )
        } else {
            ctx.templates = candidates

            let notes = candidates.map { c in
                "\(c.filename) (score: \(String(format: "%.3f", c.score ?? 0))): \(c.description)"
            }.joined(separator: "\n")

            let snippets = candidates.compactMap { $0.lines }

            ctx.precedence = PrecedenceContext(
                notes: "Selected \(candidates.count) examples via hybrid retrieval.\n\(notes)",
                selections: [],
                materializedSnippets: snippets
            )
        }

        ctx.emitEvent(phase: "discovery", step: "precedence_selected", data: [
            "template_count": "\(ctx.templates.count)",
            "top_template": ctx.templates.first?.filename ?? "none"
        ])
    }

    // MARK: - Stage 4: Capability Planner

    private func runCapabilityPlannerStage(ctx: OrchestratorRunContext) -> SimulationSpec {
        guard let intent = ctx.intent else {
            fatalError("runCapabilityPlannerStage called without intent")
        }

        let seed = Int.random(in: 1...999999)
        let spec = AnalysisPlannerAgent.run(
            runId: ctx.runId,
            pythiaTag: "8.317",
            seed: seed,
            intent: intent,
            templates: ctx.templates,
            legacyContract: ctx.legacyContract
        )
        ctx.emitEvent(phase: "discovery", step: "plan_built", data: [
            "family": spec.analysisPlan?.family ?? "unknown",
            "event_count": "\(spec.eventCount)"
        ])
        return spec
    }

    // MARK: - Stage 5: Coding

    private func runCodingStage(ctx: OrchestratorRunContext) async throws -> GeneratedCode {
        guard ctx.spec != nil else {
            fatalError("runCodingStage called without spec")
        }

        do {
            aiLogger.info("[CodingStage] Starting attempt \(ctx.attemptNumber)")
            let codingContext = buildCodingContext(ctx: ctx)
            aiLogger.info("[CodingStage] Coding context length: \(codingContext.count)")

            let codingInstructions = """
            You are the CodingAgent. Write a complete C++ Pythia8 simulation program.

            1. Call get_coding_context once to get the simulation specification.
            2. Write a complete C++ program using ONLY these includes:
               #include <cmath>, <fstream>, <iostream>, <map>, <string>, <vector>, "Pythia8/Pythia.h"
            3. Initialize Pythia with `using namespace Pythia8;` and `Pythia pythia;`
            4. Set beams, process, and cuts settings using `pythia.readString(...)`.
            5. Call `pythia.init();` to initialize.
            6. Run the event loop for the specified number of events.
            7. Write summary_lines.txt with generated_events=<int> plus family-specific metrics.
            8. Write any requested histogram or table artifacts (e.g. hist_primary.txt).
            9. Keep filesystem access to output artifacts only.
            10. Call record_codegen exactly once with the complete source code.

            If previous diagnostics are provided, fix the issues in the new code.
            Do NOT wrap the source code in markdown code fences.
            """

            let client = try openAIClient(ctx: ctx)
            let codegen = try await client.responseObject(
                CodegenStageResponse.self,
                instructions: """
                \(codingInstructions)

                The coding context is supplied as the user input. Return only the structured \
                object containing source_code.
                """,
                input: codingContext,
                textFormat: OpenAIResponseFormats.codegen,
                reasoningEffort: ctx.attemptNumber == 1 ? "low" : "medium"
            )

            let code = sanitizeSourceCode(codegen.sourceCode)
            if code.contains("Pythia") || code.contains("pythia") {
                let generated = GeneratedCode(
                    sourceCode: code,
                    commandFile: nil,
                    origin: "openai"
                )
                ctx.generated = generated
                aiLogger.info("[CodingStage] Code generated successfully with OpenAI, length=\(code.count)")
                ctx.emitEvent(phase: "codegen", step: "completed", data: ["origin": generated.origin])
                return generated
            }

            aiLogger.error("[CodingStage] OpenAI codegen did not return usable Pythia source")
            throw OrchestratorError.stageEmptyResponse(stage: "Code Generation")
        } catch let orchError as OrchestratorError {
            throw orchError
        } catch {
            aiLogger.error("[CodingStage] Error: \(error.localizedDescription, privacy: .public)")
            aiLogger.error("[CodingStage] Full error: \(String(describing: error), privacy: .public)")
            if let nsError = error as NSError? {
                aiLogger.error("[CodingStage] NSError domain: \(nsError.domain, privacy: .public), code: \(nsError.code)")
                aiLogger.error("[CodingStage] NSError userInfo: \(nsError.userInfo.description, privacy: .public)")
            }
            if OrchestratorError.isRateLimitError(error) {
                throw OrchestratorError.rateLimitExceeded
            }
            if let spec = ctx.spec {
                let fallback = CodegenAgent.run(spec: spec)
                ctx.generated = fallback
                ctx.emitEvent(phase: "codegen", step: "fallback", data: [
                    "origin": fallback.origin,
                    "reason": error.localizedDescription
                ])
                return fallback
            }
            throw OrchestratorError.stageFailed(stage: "Code Generation", underlying: error)
        }
    }

    // MARK: - Stage 6: Executor

    private func runExecutorStage(ctx: OrchestratorRunContext) async throws -> AttemptExecutionResult {
        guard let generated = ctx.generated, let spec = ctx.spec else {
            fatalError("runExecutorStage called without generated code or spec")
        }

        guard let intent = ctx.intent else {
            fatalError("runExecutorStage called without intent")
        }

        let (physicsOk, physicsMsg) = PhysicsCheckAgent.run(code: generated.sourceCode, intent: intent)
        if !physicsOk {
            ctx.emitEvent(phase: "compile", step: "physics_failed")
            return AttemptExecutionResult(
                status: "physics_check_failed",
                compileLogPath: "",
                runtimeLogPath: "",
                summaryJsonPath: nil,
                diagnostics: physicsMsg,
                plotPaths: [],
                generatedCodePath: ""
            )
        }

        let (policyOk, policyMsg) = PolicyCheckAgent.run(code: generated.sourceCode)
        if !policyOk {
            ctx.emitEvent(phase: "compile", step: "policy_failed")
            return AttemptExecutionResult(
                status: "policy_check_failed",
                compileLogPath: "",
                runtimeLogPath: "",
                summaryJsonPath: nil,
                diagnostics: policyMsg,
                plotPaths: [],
                generatedCodePath: ""
            )
        }

        ctx.emitEvent(phase: "compile", step: "executing")
        let attemptDir = PathUtils.simulationsDir
            .appendingPathComponent(ctx.runId)
            .appendingPathComponent("attempt_\(ctx.attemptNumber)")

        let totalEvents = spec.eventCount
        simulationProgress = 0.0
        estimatedSecondsRemaining = nil
        let startDate = Date()
        simulationStartDate = startDate

        let result = try await RunnerService.executeAttempt(
            generatedCode: generated,
            spec: spec,
            attemptDir: attemptDir
        ) { [weak self] progress in
            let lines = progress.components(separatedBy: CharacterSet.newlines)
            for line in lines {
                if line.contains("Pythia::next()"),
                   line.contains("events have been generated") {
                    let parts = line.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    if let numStr = parts.first(where: { !$0.isEmpty }),
                       let generated = Int(numStr), totalEvents > 0 {
                        let fraction = min(Double(generated) / Double(totalEvents), 1.0)
                        let elapsed = Date().timeIntervalSince(startDate)
                        let eta: Double? = fraction > 0.01
                            ? (elapsed / fraction) * (1.0 - fraction)
                            : nil
                        let orchestrator = self
                        Task { @MainActor in
                            orchestrator?.simulationProgress = fraction
                            orchestrator?.estimatedSecondsRemaining = eta
                        }
                    }
                }
            }
        }

        simulationProgress = nil
        estimatedSecondsRemaining = nil
        simulationStartDate = nil
        return result
    }

    private func runExactExecutorStage(ctx: OrchestratorRunContext) async throws -> AttemptExecutionResult {
        guard let generated = ctx.generated, let spec = ctx.spec else {
            fatalError("runExactExecutorStage called without generated code or spec")
        }

        ctx.emitEvent(phase: "compile", step: "executing_exact_source")
        let attemptDir = PathUtils.simulationsDir
            .appendingPathComponent(ctx.runId)
            .appendingPathComponent("attempt_1")

        let totalEvents = spec.eventCount
        simulationProgress = 0.0
        estimatedSecondsRemaining = nil
        let startDate = Date()
        simulationStartDate = startDate

        let result = try await RunnerService.executeAttempt(
            generatedCode: generated,
            spec: spec,
            attemptDir: attemptDir
        ) { [weak self] progress in
            let lines = progress.components(separatedBy: CharacterSet.newlines)
            for line in lines {
                if line.contains("Pythia::next()"),
                   line.contains("events have been generated") {
                    let parts = line.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    if let numStr = parts.first(where: { !$0.isEmpty }),
                       let generated = Int(numStr), totalEvents > 0 {
                        let fraction = min(Double(generated) / Double(totalEvents), 1.0)
                        let elapsed = Date().timeIntervalSince(startDate)
                        let eta: Double? = fraction > 0.01
                            ? (elapsed / fraction) * (1.0 - fraction)
                            : nil
                        let orchestrator = self
                        Task { @MainActor in
                            orchestrator?.simulationProgress = fraction
                            orchestrator?.estimatedSecondsRemaining = eta
                        }
                    }
                }
            }
        }

        simulationProgress = nil
        estimatedSecondsRemaining = nil
        simulationStartDate = nil
        return result
    }

    // MARK: - Stage 7: Result

    private func runResultStage(ctx: OrchestratorRunContext) async throws -> String {
        guard let attempt = ctx.lastAttempt else {
            return "Simulation completed successfully."
        }

        var summaryDict: [String: Any] = [:]
        if let summaryPath = attempt.summaryJsonPath {
            let url = URL(fileURLWithPath: summaryPath)
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                summaryDict = json
            }
        }

        var parts: [String] = []
        if let events = summaryDict["generated_events"] {
            parts.append("Generated \(events) events.")
        }

        if let spec = ctx.spec, let plan = spec.analysisPlan {
            for observable in plan.observables {
                for key in observable.outputKeys {
                    if let value = summaryDict[key] {
                        let label = key.replacingOccurrences(of: "_", with: " ")
                        parts.append("\(label): \(value)")
                    }
                }
            }
        }

        if !attempt.plotPaths.isEmpty {
            let names = attempt.plotPaths.map { URL(fileURLWithPath: $0).lastPathComponent }
            parts.append("Artifacts: \(names.joined(separator: ", "))")
        }

        if parts.isEmpty {
            return "Simulation completed successfully."
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Stage 8: Plotting

    private func runPlottingStage(ctx: OrchestratorRunContext, lastMsgId: String) async throws -> PlottingStageOutput {
        guard let spec = ctx.spec,
              let attempt = ctx.lastAttempt else {
            return PlottingStageOutput(chartPayloads: [], chartMessageIds: [])
        }

        let family = AnalysisFamily(
            rawValue: spec.analysisPlan?.family ?? ""
        ) ?? .chargedMultiplicity

        let attemptDir: URL
        if let firstPlot = attempt.plotPaths.first {
            attemptDir = URL(fileURLWithPath: firstPlot).deletingLastPathComponent()
        } else {
            attemptDir = PathUtils.simulationsDir
                .appendingPathComponent(ctx.runId)
                .appendingPathComponent("attempt_\(ctx.attemptNumber)")
        }

        var summaryDict: [String: Any] = [:]
        if let summaryPath = attempt.summaryJsonPath {
            let url = URL(fileURLWithPath: summaryPath)
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                summaryDict = json
            }
        }

        let chartPayloads = PlottingAgent.runAll(
            family: family,
            attemptDir: attemptDir,
            summaryDict: summaryDict
        )

        guard !chartPayloads.isEmpty else {
            ctx.emitEvent(phase: "plotting", step: "no_data")
            return PlottingStageOutput(chartPayloads: [], chartMessageIds: [])
        }

        var parentMessageId = lastMsgId
        var chartMessageIds: [String] = []

        for chartPayload in chartPayloads {
            let chartMsg = ChatMessage(
                id: UUID().uuidString,
                role: "assistant",
                content: "",
                timestamp: ISO8601DateFormatter().string(from: Date()),
                chartPayload: chartPayload,
                originRunId: ctx.runId,
                parentMessageId: parentMessageId,
                sender: .plotting
            )

            try await store.addChatMessage(runId: ctx.runId, message: chartMsg)
            chartMessageIds.append(chartMsg.id)
            parentMessageId = chartMsg.id
        }

        return PlottingStageOutput(chartPayloads: chartPayloads, chartMessageIds: chartMessageIds)
    }

    // MARK: - Stage 9: Physics Summary

    private func runPhysicsSummaryStage(
        ctx: OrchestratorRunContext,
        chatHistory: [ChatMessage],
        chartPayloads: [ChartPayload],
        lastMsgId: String
    ) async throws -> String? {
        guard let attempt = ctx.lastAttempt else { return nil }

        var summaryDict: [String: Any] = [:]
        if let summaryPath = attempt.summaryJsonPath {
            let url = URL(fileURLWithPath: summaryPath)
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                summaryDict = json
            }
        }

        let runScopedMessages = chatHistory.filter { $0.originRunId == ctx.chatRunId }

        guard let summaryText = await PhysicsSummaryAgent.run(
            modelName: modelName,
            settingsApiKey: ctx.settingsStore.data.apiKey,
            runId: ctx.runId,
            originalPrompt: ctx.originalPrompt,
            runnablePrompt: ctx.prompt,
            runMessages: runScopedMessages,
            simulationSpec: ctx.spec,
            executionResult: attempt,
            summaryDict: summaryDict,
            chartPayloads: chartPayloads
        ) else {
            return nil
        }

        let msg = ChatMessage(
            id: UUID().uuidString,
            role: "assistant",
            content: summaryText,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            originRunId: ctx.runId,
            parentMessageId: lastMsgId,
            sender: .result
        )
        try await store.addChatMessage(runId: ctx.runId, message: msg)
        return summaryText
    }

    // MARK: - Stage 10: Physics Reviewer

    private func runPhysicsReviewerStage(
        ctx: OrchestratorRunContext,
        runMessages: [ChatMessage],
        chartPayloads: [ChartPayload],
        finalSummaryText: String,
        lastMsgId: String
    ) async -> [PhysicsReviewerFinding] {
        do {
            let run = try await store.fetchRun(id: ctx.runId)
            let qualityInput = reviewerQualityInput(for: run)
            let qualityFindings = RunQualityAnalyzer.analyze(qualityInput)
            let messageSnapshots = runMessages.map(reviewerMessageSnapshot)
            let reviewerInput = PhysicsReviewerEvidenceBuilder.buildInput(
                qualityInput: qualityInput,
                chartPayloads: chartPayloads,
                messages: messageSnapshots,
                qualityFindings: qualityFindings,
                finalSummaryText: finalSummaryText
            )
            let findings = await PhysicsReviewerAgent.run(
                modelName: modelName,
                settingsApiKey: ctx.settingsStore.data.apiKey,
                input: reviewerInput
            )
            try await persistPhysicsReviewerEvidence(ctx: ctx, findings: findings)
            try await store.addChatMessage(
                runId: ctx.runId,
                message: ChatMessage(
                    id: UUID().uuidString,
                    role: "assistant",
                    content: PhysicsReviewerAgent.compactText(findings: findings),
                    timestamp: ISO8601DateFormatter().string(from: Date()),
                    originRunId: ctx.runId,
                    parentMessageId: lastMsgId,
                    sender: .reviewer
                )
            )
            return findings
        } catch {
            aiLogger.error("[PhysicsReviewerStage] Error: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Finalization

    private func finalizeGuideOnly(
        ctx: OrchestratorRunContext,
        decision: ResearchGuideDecision,
        lastMsgId: String
    ) async throws {
        let msg = ChatMessage(
            id: UUID().uuidString,
            role: "assistant",
            content: decision.assistantMessage,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            originRunId: ctx.runId,
            parentMessageId: lastMsgId,
            sender: .guide
        )
        try await store.addChatMessage(runId: ctx.runId, message: msg)
        try await store.updateRunStatus(id: ctx.runId, status: .completed)
        try await store.loadRuns(forThread: ctx.threadId)
        ctx.emitEvent(phase: "done", step: "success", data: ["guide_only": "true"])
    }

    private func finalizeSuccess(
        ctx: OrchestratorRunContext,
        summaryText: String,
        lastMsgId: String
    ) async throws -> String {
        let msg = ChatMessage(
            id: UUID().uuidString,
            role: "assistant",
            content: summaryText,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            originRunId: ctx.runId,
            parentMessageId: lastMsgId,
            sender: .result
        )
        try await store.addChatMessage(runId: ctx.runId, message: msg)
        try await store.updateRunStatus(id: ctx.runId, status: .completed)

        var eventCount: Int?
        if let attempt = ctx.lastAttempt, let summaryPath = attempt.summaryJsonPath {
            let url = URL(fileURLWithPath: summaryPath)
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                eventCount = json["generated_events"] as? Int
            }
        }

        try await store.updateRunResults(
            id: ctx.runId,
            resultSummary: summaryText,
            eventCount: eventCount
        )

        if let attempt = ctx.lastAttempt {
            try await persistEvidenceArtifacts(ctx: ctx, attempt: attempt)
            try await persistReferencePackEvidence(ctx: ctx, attempt: attempt)
        }

        try await store.loadRuns(forThread: ctx.threadId)
        try writeTrace(ctx: ctx)
        ctx.emitEvent(phase: "done", step: "success")
        
        return msg.id
    }

    private func persistEvidenceArtifacts(
        ctx: OrchestratorRunContext,
        attempt: AttemptExecutionResult
    ) async throws {
        let existingRun = try? await store.fetchRun(id: ctx.runId)
        var seenPaths = Set(existingRun?.artifacts.map { $0.relativePath } ?? [])
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fm = FileManager.default

        let attemptDir = !attempt.generatedCodePath.isEmpty
            ? URL(fileURLWithPath: attempt.generatedCodePath).deletingLastPathComponent()
            : PathUtils.simulationsDir
                .appendingPathComponent(ctx.runId)
                .appendingPathComponent("attempt_\(ctx.attemptNumber)")

        func appendArtifact(path: String?, kind: String, label: String? = nil) async throws {
            guard let path, !path.isEmpty, !seenPaths.contains(path), fm.fileExists(atPath: path) else {
                return
            }

            let url = URL(fileURLWithPath: path)
            let artifact = ArtifactRef(
                id: UUID().uuidString,
                kind: kind,
                label: label ?? url.lastPathComponent,
                relativePath: path,
                createdAt: timestamp
            )
            try await store.addArtifact(runId: ctx.runId, artifact: artifact)
            seenPaths.insert(path)
        }

        try await appendArtifact(path: attempt.generatedCodePath, kind: "source", label: "run.cc")
        try await appendArtifact(path: attemptDir.appendingPathComponent("simulation_spec.json").path, kind: "spec")
        try await appendArtifact(path: attempt.summaryJsonPath, kind: "summary", label: "summary.json")
        try await appendArtifact(path: attemptDir.appendingPathComponent("summary_lines.txt").path, kind: "summary")
        try await appendArtifact(path: attempt.compileLogPath, kind: "log", label: "compile.log")
        try await appendArtifact(path: attempt.runtimeLogPath, kind: "log", label: "run.log")

        for path in attempt.plotPaths {
            try await appendArtifact(path: path, kind: "data")
        }
    }

    private func persistReferencePackEvidence(
        ctx: OrchestratorRunContext,
        attempt: AttemptExecutionResult
    ) async throws {
        let attemptDir = !attempt.generatedCodePath.isEmpty
            ? URL(fileURLWithPath: attempt.generatedCodePath).deletingLastPathComponent()
            : PathUtils.simulationsDir
                .appendingPathComponent(ctx.runId)
                .appendingPathComponent("attempt_\(ctx.attemptNumber)")
        try FileManager.default.createDirectory(at: attemptDir, withIntermediateDirectories: true)

        let pack = HEPReferencePackAssembler.baselinePack(
            query: ctx.originalPrompt,
            simulationSpec: ctx.spec
        )
        guard !pack.references.isEmpty else {
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(pack)
        let url = attemptDir.appendingPathComponent("reference_pack.json")
        try data.write(to: url, options: .atomic)

        let run = try await store.fetchRun(id: ctx.runId)
        guard !run.artifacts.contains(where: { $0.relativePath == url.path }) else {
            return
        }

        let artifact = ArtifactRef(
            id: UUID().uuidString,
            kind: "reference",
            label: "reference_pack.json",
            relativePath: url.path,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        try await store.addArtifact(runId: ctx.runId, artifact: artifact)
    }

    private func persistPhysicsReviewerEvidence(
        ctx: OrchestratorRunContext,
        findings: [PhysicsReviewerFinding]
    ) async throws {
        guard let attempt = ctx.lastAttempt else { return }
        let attemptDir = !attempt.generatedCodePath.isEmpty
            ? URL(fileURLWithPath: attempt.generatedCodePath).deletingLastPathComponent()
            : PathUtils.simulationsDir
                .appendingPathComponent(ctx.runId)
                .appendingPathComponent("attempt_\(ctx.attemptNumber)")
        try FileManager.default.createDirectory(at: attemptDir, withIntermediateDirectories: true)

        let envelope = PhysicsReviewerAgent.envelope(
            runId: ctx.runId,
            source: "openai_structured_or_deterministic_fallback",
            findings: findings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        let url = attemptDir.appendingPathComponent("physics_reviewer.json")
        try data.write(to: url, options: .atomic)

        let run = try await store.fetchRun(id: ctx.runId)
        guard !run.artifacts.contains(where: { $0.relativePath == url.path }) else {
            return
        }
        let artifact = ArtifactRef(
            id: UUID().uuidString,
            kind: "review",
            label: "physics_reviewer.json",
            relativePath: url.path,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        try await store.addArtifact(runId: ctx.runId, artifact: artifact)
    }

    private func reviewerQualityInput(for run: SimulationRun) -> RunQualityInput {
        let artifacts = run.artifacts
        return RunQualityInput(
            run: RunQualityRunSnapshot(
                id: run.id,
                title: run.title,
                status: run.status.rawValue,
                eventCount: run.eventCount,
                configuration: run.configuration
            ),
            spec: reviewerSimulationSpec(in: artifacts).map(reviewerSpecSnapshot),
            summaryMetrics: reviewerSummaryMetrics(in: artifacts),
            artifacts: artifacts.map(reviewerArtifactSnapshot),
            compileLog: reviewerTextArtifact(named: "compile.log", in: artifacts),
            runLog: reviewerTextArtifact(named: "run.log", in: artifacts)
        )
    }

    private func reviewerSpecSnapshot(_ spec: SimulationSpec) -> RunQualitySpecSnapshot {
        RunQualitySpecSnapshot(
            eventCount: spec.eventCount,
            analysisFamily: spec.analysisPlan?.family,
            outputFiles: spec.outputPlan.extraFiles,
            processSettings: spec.processSettings,
            cutsSettings: spec.cutsSettings
        )
    }

    private func reviewerArtifactSnapshot(_ artifact: ArtifactRef) -> RunQualityArtifactSnapshot {
        RunQualityArtifactSnapshot(
            label: artifact.label,
            kind: artifact.kind,
            path: artifact.relativePath,
            byteSize: reviewerFileSize(for: URL(fileURLWithPath: artifact.relativePath))
        )
    }

    private func reviewerMessageSnapshot(_ message: ChatMessage) -> PhysicsReviewerMessageSnapshot {
        PhysicsReviewerMessageSnapshot(
            role: message.role,
            sender: message.sender.rawValue,
            content: message.content,
            timestamp: message.timestamp
        )
    }

    private func reviewerSummaryMetrics(in artifacts: [ArtifactRef]) -> [String: String] {
        guard let url = reviewerArtifactURL(named: "summary.json", in: artifacts),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }
        return reviewerFlattenJSONValues(object)
    }

    private func reviewerSimulationSpec(in artifacts: [ArtifactRef]) -> SimulationSpec? {
        guard let url = reviewerArtifactURL(named: "simulation_spec.json", in: artifacts),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(SimulationSpec.self, from: data)
    }

    private func reviewerTextArtifact(named fileName: String, in artifacts: [ArtifactRef]) -> String? {
        guard let url = reviewerArtifactURL(named: fileName, in: artifacts) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func reviewerArtifactURL(named fileName: String, in artifacts: [ArtifactRef]) -> URL? {
        artifacts.first { artifact in
            URL(fileURLWithPath: artifact.relativePath).lastPathComponent == fileName
                && FileManager.default.fileExists(atPath: artifact.relativePath)
        }
        .map { URL(fileURLWithPath: $0.relativePath) }
    }

    private func reviewerFileSize(for url: URL) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.uint64Value
    }

    private func reviewerFlattenJSONValues(_ value: Any, prefix: String = "") -> [String: String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [:]) { result, pair in
                let key = prefix.isEmpty ? pair.key : "\(prefix).\(pair.key)"
                result.merge(reviewerFlattenJSONValues(pair.value, prefix: key), uniquingKeysWith: { _, new in new })
            }
        }
        if let array = value as? [Any] {
            return [prefix: "\(array.count) items"]
        }
        if let number = value as? NSNumber {
            return [prefix: number.stringValue]
        }
        if let string = value as? String {
            return [prefix: string]
        }
        if value is NSNull {
            return [prefix: "null"]
        }
        return [prefix: String(describing: value)]
    }

    private func evidencePath(for run: SimulationRun, named fileName: String) throws -> String {
        if let artifact = run.artifacts.first(where: {
            URL(fileURLWithPath: $0.relativePath).lastPathComponent == fileName
        }), FileManager.default.fileExists(atPath: artifact.relativePath) {
            return artifact.relativePath
        }

        let runFolder = PathUtils.simulationsDir.appendingPathComponent(run.id, isDirectory: true)
        guard let attemptDirs = try? FileManager.default.contentsOfDirectory(
            at: runFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw OrchestratorError.rerunUnavailable("No persisted run folder was found for exact rerun.")
        }

        let sortedAttemptDirs = attemptDirs.filter { url in
            guard url.lastPathComponent.hasPrefix("attempt_") else { return false }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for attemptDir in sortedAttemptDirs {
            let candidate = attemptDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }

        throw OrchestratorError.rerunUnavailable("Missing \(fileName) evidence for exact rerun.")
    }

    private func finalizeFailure(
        ctx: OrchestratorRunContext,
        diagnostics: String,
        lastMsgId: String
    ) async throws {
        let msg = ChatMessage(
            id: UUID().uuidString,
            role: "assistant",
            content: "Simulation failed: \(diagnostics)",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            originRunId: ctx.runId,
            parentMessageId: lastMsgId,
            sender: .result
        )
        try await store.addChatMessage(runId: ctx.runId, message: msg)
        try await store.updateRunStatus(
            id: ctx.runId,
            status: .failed,
            errorMessage: diagnostics
        )
        try await store.loadRuns(forThread: ctx.threadId)
        try writeTrace(ctx: ctx)
        ctx.emitEvent(phase: "failed", step: "failed")
    }

    // MARK: - Trace Writing

    private func writeTrace(ctx: OrchestratorRunContext) throws {
        let traceDir = PathUtils.simulationsDir.appendingPathComponent(ctx.runId)
        try FileManager.default.createDirectory(at: traceDir, withIntermediateDirectories: true)

        let tracePath = traceDir.appendingPathComponent("agent_trace.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(ctx.events)
        try data.write(to: tracePath)
    }

    // MARK: - Helper: Build Configuration Dict

    private func buildParameterizedSpec(
        from spec: SimulationSpec,
        runId: String,
        request: ParameterizedRerunRequest
    ) -> SimulationSpec {
        SimulationSpec(
            runId: runId,
            pythiaTag: spec.pythiaTag,
            seed: request.seed,
            beams: spec.beams,
            processSettings: spec.processSettings,
            cutsSettings: cutsSettings(
                spec.cutsSettings,
                replacingPTHatMinWith: request.pTHatMin
            ),
            eventCount: request.eventCount,
            observables: spec.observables,
            analysisPlan: spec.analysisPlan,
            outputPlan: spec.outputPlan
        )
    }

    private func buildIntent(from spec: SimulationSpec, prompt: String) -> IntentResult {
        IntentResult(
            processHint: spec.processSettings.first ?? "",
            beamFrame: spec.beams.frameType,
            eCmGev: spec.beams.eCmGev,
            eventCount: spec.eventCount,
            observables: spec.observables.map(\.id),
            requestedAnalysisCandidates: [spec.analysisPlan?.family ?? AnalysisFamily.chargedMultiplicity.rawValue],
            prompt: prompt
        )
    }

    private func cutsSettings(
        _ settings: [String],
        replacingPTHatMinWith pTHatMin: Double?
    ) -> [String] {
        var updated = settings.filter { !isPTHatMinSetting($0) }
        if let pTHatMin {
            updated.append("PhaseSpace:pTHatMin = \(formattedCutValue(pTHatMin) ?? "\(pTHatMin)")")
        }
        return updated
    }

    private func parameterChangeSummary(
        sourceSpec: SimulationSpec,
        modifiedSpec: SimulationSpec
    ) -> [String] {
        var changes: [String] = [
            "event_count: \(sourceSpec.eventCount) -> \(modifiedSpec.eventCount)",
            "seed: \(sourceSpec.seed) -> \(modifiedSpec.seed)"
        ]

        let sourcePTHat = formattedCutValue(phaseSpacePTHatMin(in: sourceSpec.cutsSettings)) ?? "unset"
        let modifiedPTHat = formattedCutValue(phaseSpacePTHatMin(in: modifiedSpec.cutsSettings)) ?? "unset"
        if sourcePTHat != modifiedPTHat {
            changes.append("PhaseSpace:pTHatMin: \(sourcePTHat) -> \(modifiedPTHat)")
        }

        return changes
    }

    private func phaseSpacePTHatMin(in settings: [String]) -> Double? {
        for setting in settings where isPTHatMinSetting(setting) {
            let parts = setting.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.count == 2, let value = Double(parts[1]) {
                return value
            }
        }
        return nil
    }

    private func isPTHatMinSetting(_ setting: String) -> Bool {
        let key = setting.split(separator: "=", maxSplits: 1).first.map(String.init) ?? setting
        return key.trimmingCharacters(in: .whitespacesAndNewlines) == "PhaseSpace:pTHatMin"
    }

    private func formattedCutValue(_ value: Double?) -> String? {
        guard let value else { return nil }
        return String(format: "%.6g", value)
    }

    private func validatedIntent(_ intent: IntentResult, originalPrompt: String) -> IntentResult {
        let fallback = buildFallbackIntent(from: originalPrompt)

        let processHint = intent.processHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallback.processHint
            : intent.processHint

        let beamFrame = ["pp", "ee", "ep"].contains(intent.beamFrame.lowercased())
            ? intent.beamFrame.lowercased()
            : fallback.beamFrame

        let eCmGev = intent.eCmGev > 0 && intent.eCmGev < 1_000_000
            ? intent.eCmGev
            : fallback.eCmGev

        let eventCount = min(max(intent.eventCount, 10), 50_000)
        let candidates = intent.requestedAnalysisCandidates.isEmpty
            ? fallback.requestedAnalysisCandidates
            : intent.requestedAnalysisCandidates
        let observables = intent.observables.isEmpty ? candidates : intent.observables

        return IntentResult(
            processHint: processHint,
            beamFrame: beamFrame,
            eCmGev: eCmGev,
            eventCount: eventCount,
            observables: observables,
            requestedAnalysisCandidates: candidates,
            prompt: originalPrompt
        )
    }

    private func sanitizeSourceCode(_ raw: String) -> String {
        var code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.hasPrefix("```") {
            var lines = code.components(separatedBy: CharacterSet.newlines)
            if !lines.isEmpty {
                lines.removeFirst()
            }
            if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
                lines.removeLast()
            }
            code = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return code
    }

    private func buildConfigurationDict(from spec: SimulationSpec) -> [String: String] {
        var config: [String: String] = [:]
        config["Beams:frameType"] = spec.beams.frameType
        config["Beams:eCM"] = String(format: "%.1f", spec.beams.eCmGev)

        for setting in spec.processSettings {
            let parts = setting.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                config[parts[0]] = parts[1]
            } else {
                config[setting] = "on"
            }
        }

        for setting in spec.cutsSettings {
            let parts = setting.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                config[parts[0]] = parts[1]
            }
        }

        config["Main:numberOfEvents"] = "\(spec.eventCount)"
        config["Random:seed"] = "\(spec.seed)"

        return config
    }

    // MARK: - Helper: Build Coding Context

    private func buildCodingContext(ctx: OrchestratorRunContext) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var parts: [String] = []

        if let intent = ctx.intent,
           let data = try? encoder.encode(intent),
           let json = String(data: data, encoding: .utf8) {
            parts.append("INTENT:\n\(json)")
        }

        if let spec = ctx.spec,
           let data = try? encoder.encode(spec),
           let json = String(data: data, encoding: .utf8) {
            parts.append("SIMULATION SPEC:\n\(json)")
        }

        if let precedence = ctx.precedence {
            parts.append("PRECEDENCE NOTES:\n\(precedence.notes)")
            if !precedence.materializedSnippets.isEmpty {
                parts.append("SNIPPETS:\n\(precedence.materializedSnippets.joined(separator: "\n---\n"))")
            }
        }

        if let diag = ctx.lastDiagnostics {
            parts.append("PREVIOUS DIAGNOSTICS (attempt \(ctx.attemptNumber - 1)):\n\(diag)")
        }

        parts.append("ATTEMPT NUMBER: \(ctx.attemptNumber)")

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Helper: Fallback Intent

    private func buildFallbackIntent(from prompt: String) -> IntentResult {
        let lower = prompt.lowercased()

        let beamFrame: String
        if lower.contains("electron") || lower.contains("e+e-") || lower.contains("ee") {
            beamFrame = "ee"
        } else if lower.contains("ep") {
            beamFrame = "ep"
        } else {
            beamFrame = "pp"
        }

        var eCm: Double = 13000.0
        let energyPattern = try? NSRegularExpression(pattern: #"(\d+\.?\d*)\s*(?:tev|TeV)"#)
        if let match = energyPattern?.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
           let range = Range(match.range(at: 1), in: prompt),
           let val = Double(prompt[range]) {
            eCm = val * 1000.0
        }

        var eventCount = 10000
        let countPattern = try? NSRegularExpression(pattern: #"(\d+)\s*events?"#, options: .caseInsensitive)
        if let match = countPattern?.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
           let range = Range(match.range(at: 1), in: prompt),
           let val = Int(prompt[range]) {
            eventCount = val
        }

        var processHint = "HardQCD:all = on"
        if lower.contains("z boson") || lower.contains("drell-yan") || lower.contains("drell yan") {
            processHint = "WeakSingleBoson:ffbar2gmZ = on"
        } else if lower.contains("w boson") {
            processHint = "WeakSingleBoson:ffbar2W = on"
        } else if lower.contains("top") || lower.contains("ttbar") {
            processHint = "Top:gg2ttbar = on"
        } else if lower.contains("minimum bias") || lower.contains("minbias") {
            processHint = "SoftQCD:all = on"
        }

        var candidates: [String] = []
        let candidateRules: [(tokens: [String], family: String)] = [
            (["multiplicity", "charged"], "charged_multiplicity"),
            (["pt", "transverse momentum", "spectrum"], "pt_spectrum"),
            (["eta", "rapidity", "pseudorapidity"], "eta_rapidity"),
            (["invariant mass", "dimuon", "resonance"], "invariant_mass"),
            (["pid", "particle id", "pion", "kaon", "proton", "yield"], "pid_yields"),
            (["ht", "visible energy", "scalar"], "event_scalars")
        ]

        for rule in candidateRules {
            if rule.tokens.contains(where: { lower.contains($0) }) {
                candidates.append(rule.family)
            }
        }
        if candidates.isEmpty {
            candidates = ["charged_multiplicity"]
        }

        return IntentResult(
            processHint: processHint,
            beamFrame: beamFrame,
            eCmGev: eCm,
            eventCount: eventCount,
            observables: candidates,
            requestedAnalysisCandidates: candidates,
            prompt: prompt
        )
    }
}
