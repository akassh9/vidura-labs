//
//  DiagnoseFixAgent.swift
//  Physics Companion
//
//  Deterministic fallback patcher for SimulationSpec.
//

import Foundation

enum DiagnoseFixAgent {

    /// Patches a SimulationSpec based on the attempt number.
    /// Note: diagnostics is currently ignored, matching the backend.
    static func run(
        spec: SimulationSpec,
        diagnostics: String?,
        attemptNumber: Int
    ) -> SimulationSpec {

        if attemptNumber == 1 {
            // Replace process_settings with HardQCD:all = on
            var newCuts = spec.cutsSettings
            if !newCuts.contains("PhaseSpace:pTHatMin = 20.") {
                newCuts.append("PhaseSpace:pTHatMin = 20.")
            }
            return SimulationSpec(
                runId: spec.runId,
                pythiaTag: spec.pythiaTag,
                seed: spec.seed,
                beams: spec.beams,
                processSettings: ["HardQCD:all = on"],
                cutsSettings: newCuts,
                eventCount: spec.eventCount,
                observables: spec.observables,
                analysisPlan: spec.analysisPlan,
                outputPlan: spec.outputPlan
            )
        } else if attemptNumber == 2 {
            // Reduce event count and force cuts
            return SimulationSpec(
                runId: spec.runId,
                pythiaTag: spec.pythiaTag,
                seed: spec.seed,
                beams: spec.beams,
                processSettings: spec.processSettings,
                cutsSettings: ["PhaseSpace:pTHatMin = 20."],
                eventCount: min(spec.eventCount, 300),
                observables: spec.observables,
                analysisPlan: spec.analysisPlan,
                outputPlan: spec.outputPlan
            )
        }

        // Otherwise return unchanged
        return spec
    }
}
