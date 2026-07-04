//
//  ResearchGuideAgent.swift
//  Physics Companion
//
//  Deterministic guide-stage logic and prompt contracts.
//

import Foundation

enum ResearchGuideAgent {

    // MARK: - Supported Analyses

    /// The six supported analysis families with metadata.
    static let supportedAnalyses: [SupportedAnalysis] = [
        SupportedAnalysis(
            analysisFamily: "charged_multiplicity",
            whenToUse: "Counting the number of charged particles per event.",
            examplePrompt: "Run 10k pp collisions at 13 TeV and plot the charged-particle multiplicity."
        ),
        SupportedAnalysis(
            analysisFamily: "pt_spectrum",
            whenToUse: "Measuring the transverse-momentum distribution of final-state charged particles.",
            examplePrompt: "Generate the pT spectrum for charged hadrons in pp at 13 TeV."
        ),
        SupportedAnalysis(
            analysisFamily: "eta_rapidity",
            whenToUse: "Measuring the pseudorapidity (eta) distribution of final-state charged particles.",
            examplePrompt: "Show the eta distribution for minimum-bias pp events at 13 TeV."
        ),
        SupportedAnalysis(
            analysisFamily: "invariant_mass",
            whenToUse: "Reconstructing the invariant mass of particle pairs (e.g. dimuon).",
            examplePrompt: "Simulate Drell-Yan dimuon production and plot the invariant mass spectrum."
        ),
        SupportedAnalysis(
            analysisFamily: "pid_yields",
            whenToUse: "Counting yields of specific particle species (pions, kaons, protons).",
            examplePrompt: "Count pion, kaon, and proton yields in 5000 pp collisions at 13 TeV."
        ),
        SupportedAnalysis(
            analysisFamily: "event_scalars",
            whenToUse: "Computing event-level scalar quantities like visible energy and HT.",
            examplePrompt: "Measure mean visible energy and HT in QCD dijet events."
        )
    ]

    // MARK: - System Prompt

    /// The system prompt for the runtime GuideAgent.
    static let defaultSystemPrompt: String = """
    You are the research guide for a Pythia 8 Monte Carlo simulation companion.

    Your responsibilities:
    - Explain particle-physics concepts plainly when the user asks conceptual questions.
    - Only propose or launch simulations that match the supported analysis families listed below.
    - If the user is asking a conceptual question, choose action="answer" and explain.
    - If the user seems exploratory but has not confirmed they want to run a simulation, choose action="propose_simulation" and describe what you could simulate.
    - If the conversation contains a concrete, supported simulation request and the user confirms, choose action="run_simulation".
    - Never claim you can do analyses outside the supported set.
    - Never claim you have live web access.
    - Call the record_guide_decision tool exactly once.
    - Hand off to IntentAgent only when action == "run_simulation".

    Supported analysis families:
    \(supportedAnalyses.map { "- \($0.analysisFamily): \($0.whenToUse)" }.joined(separator: "\n"))

    When action="run_simulation", the runnable_prompt must be a self-contained simulation request \
    including beam type, energy, event count, process, and observable.
    """

    // MARK: - Build Guide Payload

    /// Constructs the guide-stage input from the last 8 messages.
    static func buildGuidePayload(messages: [ChatMessage]) -> String {
        let recent = Array(messages.suffix(8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        struct Payload: Encodable {
            let messages: [[String: String]]
            let supportedAnalyses: [SupportedAnalysis]
            let outputContract: String

            enum CodingKeys: String, CodingKey {
                case messages
                case supportedAnalyses = "supported_analyses"
                case outputContract = "output_contract"
            }
        }

        let payload = Payload(
            messages: recent.map { ["role": $0.role, "content": $0.content] },
            supportedAnalyses: supportedAnalyses,
            outputContract: """
            Call record_guide_decision with:
            - action: "answer" | "propose_simulation" | "run_simulation"
            - assistant_message: your message to the user
            - runnable_prompt: (required if action=run_simulation) a fully self-contained simulation request
            - analysis_family: (optional) one of the supported family names
            """
        )

        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: - Fallback Guide Decision

    /// Deterministic fallback when model output is unavailable or invalid.
    /// Implements Rules A, B, C, D in exact order.
    static func fallbackGuideDecision(
        content: String,
        recentMessages: [ChatMessage]? = nil
    ) -> ResearchGuideDecision {
        let lower = content.lowercased()

        // Build history text from last 4 recent messages
        let historyMessages = Array((recentMessages ?? []).suffix(4))
        let historyText = historyMessages.map { $0.content.lowercased() }.joined(separator: " ")
        let combined = lower + " " + historyText

        // Rule A: confirmation of earlier dimuon discussion
        let confirmationTokens = ["run it", "go ahead", "yes run", "simulate it", "do that"]
        let hasConfirmation = confirmationTokens.contains { lower.contains($0) }
        if hasConfirmation && combined.contains("dimuon") {
            return ResearchGuideDecision(
                action: .runSimulation,
                assistantMessage: "Launching your dimuon invariant-mass simulation now.",
                runnablePrompt: """
                Run a proton-proton collision simulation at 13 TeV center-of-mass energy, \
                generating 12000 events with HardQCD enabled. \
                Analyze the dimuon invariant-mass spectrum for final-state muon pairs.
                """,
                analysisFamily: "invariant_mass"
            )
        }

        // Rule B: conceptual dimuon question
        let hasDimuonMass = lower.contains("dimuon invariant mass")
        let hasZBosonPeak = lower.contains("z boson") && lower.contains("peak")
        if hasDimuonMass || hasZBosonPeak {
            return ResearchGuideDecision(
                action: .proposeSimulation,
                assistantMessage: """
                The dimuon invariant-mass spectrum is a classic observable in collider physics. \
                Resonance peaks (like the Z boson at ~91 GeV) appear as bumps in the mass \
                distribution of muon-antimuon pairs. I can simulate this for you — \
                shall I run a Drell-Yan simulation and plot the dimuon mass spectrum?
                """,
                runnablePrompt: nil,
                analysisFamily: "invariant_mass"
            )
        }

        // Rule C: direct supported simulation request
        let simTokens = ["run ", "simulate", "generate", "collisions", "events"]
        let isSimRequest = simTokens.contains { lower.contains($0) }

        let familyTokens = [
            "charged multiplicity", "pt spectrum", "transverse momentum",
            "pseudorapidity", "eta distribution", "dimuon", "invariant mass",
            "particle-id yields", "particle id yields",
            "pion", "kaon", "proton", "visible energy", "mean_ht", "ht"
        ]
        let matchesFamily = familyTokens.contains { lower.contains($0) }

        if isSimRequest && matchesFamily {
            return ResearchGuideDecision(
                action: .runSimulation,
                assistantMessage: "Launching that simulation now.",
                runnablePrompt: content.trimmingCharacters(in: .whitespacesAndNewlines),
                analysisFamily: nil
            )
        }

        // Rule D: generic answer fallback
        return ResearchGuideDecision(
            action: .answer,
            assistantMessage: """
            I'm a Pythia 8 simulation companion. I can help you understand particle-physics \
            concepts or run Monte Carlo simulations. I support these analyses: \
            charged multiplicity, pT spectrum, eta/rapidity distributions, invariant mass, \
            particle-ID yields, and event scalars. What would you like to explore?
            """,
            runnablePrompt: nil,
            analysisFamily: nil
        )
    }
}
