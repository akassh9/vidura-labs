//
//  AnalysisPlannerAgent.swift
//  Physics Companion
//
//  Deterministic analysis planner: converts IntentResult + templates into SimulationSpec.
//

import Foundation

enum AnalysisPlannerAgent {

    // MARK: - Supported Families Set

    private static let supportedFamilies: Set<String> = [
        "charged_multiplicity", "pt_spectrum", "eta_rapidity",
        "invariant_mass", "pid_yields", "event_scalars"
    ]

    // MARK: - Main Run

    /// Converts intent + templates into a canonical SimulationSpec.
    static func run(
        runId: String,
        pythiaTag: String,
        seed: Int,
        intent: IntentResult,
        templates: [TemplateCandidate],
        legacyContract: Bool
    ) -> SimulationSpec {
        // 1. process_settings starts with only intent.process_hint
        let processSettings = [intent.processHint]

        // 2. cuts_settings starts empty
        var cutsSettings: [String] = []

        // 3. top_template
        let topTemplate = templates.first?.filename ?? "main101.cc"

        // 4. If top_template == "main101.cc", append pTHatMin = 20
        if topTemplate == "main101.cc" {
            cutsSettings.append("PhaseSpace:pTHatMin = 20.")
        }

        // 5. If lowercase joined observables contain "pt", append pTHatMin = 15
        let joinedObs = intent.observables.joined(separator: " ").lowercased()
        if joinedObs.contains("pt") {
            cutsSettings.append("PhaseSpace:pTHatMin = 15.")
        }

        // 6. Determine family
        let family = selectFamily(intent: intent, legacyContract: legacyContract)

        // 7. Build observables
        let observables = buildObservables(family: family)

        // 8-11. Build output artifacts
        var outputArtifacts = ["summary_lines.txt"]
        switch family {
        case .chargedMultiplicity, .ptSpectrum, .etaRapidity, .invariantMass:
            outputArtifacts.append("hist_primary.txt")
        case .pidYields:
            outputArtifacts.append("pid_counts.txt")
        case .eventScalars:
            outputArtifacts.append("event_scalars.txt")
        }

        for requestedFamily in requestedFamilies(intent: intent) where requestedFamily != family {
            switch requestedFamily {
            case .ptSpectrum:
                appendUnique("hist_pt.txt", to: &outputArtifacts)
            case .etaRapidity:
                appendUnique("hist_eta.txt", to: &outputArtifacts)
            case .invariantMass:
                appendUnique("hist_mass.txt", to: &outputArtifacts)
            case .chargedMultiplicity:
                appendUnique("hist_multiplicity.txt", to: &outputArtifacts)
            case .pidYields:
                appendUnique("pid_counts.txt", to: &outputArtifacts)
            case .eventScalars:
                appendUnique("event_scalars.txt", to: &outputArtifacts)
            }
        }

        // 12. Build analysis plan
        let analysisPlan = AnalysisPlan(
            family: family.rawValue,
            selectors: selectorsFor(family: family),
            observables: observables
        )

        // 13. Return SimulationSpec
        return SimulationSpec(
            runId: runId,
            pythiaTag: pythiaTag,
            seed: seed,
            beams: BeamSpec(frameType: intent.beamFrame, eCmGev: intent.eCmGev),
            processSettings: processSettings,
            cutsSettings: cutsSettings,
            eventCount: intent.eventCount,
            observables: observables,
            analysisPlan: analysisPlan,
            outputPlan: OutputPlan(
                summaryJson: true,
                logs: true,
                plots: true,
                extraFiles: outputArtifacts
            )
        )
    }

    // MARK: - Family Selection

    private static func selectFamily(
        intent: IntentResult,
        legacyContract: Bool
    ) -> AnalysisFamily {
        // 1. Legacy contract forces charged_multiplicity
        if legacyContract {
            return .chargedMultiplicity
        }

        // 2. Iterate requested candidates
        for candidate in intent.requestedAnalysisCandidates {
            let normalized = candidate.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "-", with: "_")
            if supportedFamilies.contains(normalized),
               let family = AnalysisFamily(rawValue: normalized) {
                return family
            }
        }

        // 3. Keyword heuristics on prompt + observables
        let text = (intent.prompt + " " + intent.observables.joined(separator: " ")).lowercased()

        let keywordRules: [(tokens: [String], family: AnalysisFamily)] = [
            (["multiplicity", "charged"], .chargedMultiplicity),
            (["p_t", "pt", "transverse momentum", "spectrum"], .ptSpectrum),
            (["eta", "rapidity", "pseudorapidity"], .etaRapidity),
            (["invariant mass", "resonance", "mass peak"], .invariantMass),
            (["pid", "particle id", "species", "yield"], .pidYields),
            (["ht", "visible energy", "scalar sum"], .eventScalars)
        ]

        for rule in keywordRules {
            if rule.tokens.contains(where: { text.contains($0) }) {
                return rule.family
            }
        }

        // 4. Default
        return .chargedMultiplicity
    }

    private static func requestedFamilies(intent: IntentResult) -> [AnalysisFamily] {
        let candidates = intent.requestedAnalysisCandidates + intent.observables
        var result: [AnalysisFamily] = []

        for candidate in candidates {
            let normalized = candidate.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "-", with: "_")
            if let family = AnalysisFamily(rawValue: normalized), !result.contains(family) {
                result.append(family)
            }
        }

        let text = (intent.prompt + " " + candidates.joined(separator: " ")).lowercased()
        let keywordRules: [(tokens: [String], family: AnalysisFamily)] = [
            (["multiplicity", "charged"], .chargedMultiplicity),
            (["p_t", "pt", "transverse momentum", "spectrum"], .ptSpectrum),
            (["eta", "rapidity", "pseudorapidity"], .etaRapidity),
            (["invariant mass", "resonance", "mass peak"], .invariantMass),
            (["pid", "particle id", "species", "yield"], .pidYields),
            (["ht", "visible energy", "scalar"], .eventScalars)
        ]

        for rule in keywordRules {
            if rule.tokens.contains(where: { text.contains($0) }),
               !result.contains(rule.family) {
                result.append(rule.family)
            }
        }

        return result
    }

    private static func appendUnique(_ value: String, to values: inout [String]) {
        if !values.contains(value) {
            values.append(value)
        }
    }

    // MARK: - Selectors

    private static func selectorsFor(family: AnalysisFamily) -> [String] {
        switch family {
        case .chargedMultiplicity: return ["isFinal", "isCharged"]
        case .ptSpectrum:          return ["isFinal", "isCharged"]
        case .etaRapidity:         return ["isFinal", "isCharged"]
        case .invariantMass:       return ["isFinal", "idAbs=13"]
        case .pidYields:           return ["isFinal", "id"]
        case .eventScalars:        return ["isFinal", "isVisible"]
        }
    }

    // MARK: - Build Observables

    private static func buildObservables(family: AnalysisFamily) -> [ObservableSpec] {
        let generatedEvents = ObservableSpec(
            id: "generated_events", kind: "counter", source: "event",
            op: "count", selector: "", outputKeys: ["generated_events"]
        )

        switch family {
        case .chargedMultiplicity:
            return [
                ObservableSpec(
                    id: "charged_multiplicity", kind: "hist1d", unit: "count",
                    source: "event", op: "count",
                    selector: "isFinal && isCharged",
                    bins: 100, min: -0.5, max: 799.5,
                    outputKeys: ["mean_charged"]
                ),
                generatedEvents
            ]
        case .ptSpectrum:
            return [
                ObservableSpec(
                    id: "pt_spectrum", kind: "hist1d", unit: "GeV",
                    source: "particle", op: "pt",
                    selector: "isFinal && isCharged",
                    bins: 80, min: 0.0, max: 200.0,
                    outputKeys: ["mean_pt"]
                ),
                generatedEvents
            ]
        case .etaRapidity:
            return [
                ObservableSpec(
                    id: "eta_distribution", kind: "hist1d",
                    source: "particle", op: "eta",
                    selector: "isFinal && isCharged",
                    bins: 80, min: -8.0, max: 8.0,
                    outputKeys: ["mean_abs_eta"]
                ),
                generatedEvents
            ]
        case .invariantMass:
            return [
                ObservableSpec(
                    id: "dimuon_mass", kind: "hist1d", unit: "GeV",
                    source: "pair", op: "invariant_mass",
                    selector: "isFinal && idAbs==13",
                    bins: 80, min: 0.0, max: 200.0,
                    outputKeys: ["dimuon_pairs"]
                ),
                generatedEvents
            ]
        case .pidYields:
            return [
                ObservableSpec(
                    id: "pid_yields", kind: "table",
                    source: "particle", op: "pid_count",
                    selector: "isFinal",
                    outputKeys: ["pid_211", "pid_-211", "pid_321", "pid_-321", "pid_2212"]
                ),
                generatedEvents
            ]
        case .eventScalars:
            return [
                ObservableSpec(
                    id: "event_scalars", kind: "summary", unit: "GeV",
                    source: "event", op: "scalar_sums",
                    selector: "isFinal && isVisible",
                    outputKeys: ["mean_visible_energy", "mean_ht"]
                ),
                generatedEvents
            ]
        }
    }
}
