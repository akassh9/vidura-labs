//
//  AgentTypes.swift
//  Physics Companion
//
//  Shared data contracts for the agent system.
//

import Foundation

// MARK: - Analysis Families

/// The six supported analysis families, exactly matching the backend.
enum AnalysisFamily: String, Codable, Sendable, CaseIterable {
    case chargedMultiplicity = "charged_multiplicity"
    case ptSpectrum          = "pt_spectrum"
    case etaRapidity         = "eta_rapidity"
    case invariantMass       = "invariant_mass"
    case pidYields           = "pid_yields"
    case eventScalars        = "event_scalars"
}

// MARK: - IntentResult

/// Parsed simulation request produced by the IntentAgent.
struct IntentResult: Codable, Sendable {
    let processHint: String            // e.g. "HardQCD:all = on"
    let beamFrame: String              // "pp" | "ee" | "ep"
    let eCmGev: Double                 // center-of-mass energy in GeV
    let eventCount: Int                // number of events to generate
    let observables: [String]          // user-visible observable hints
    let requestedAnalysisCandidates: [String]  // ranked requested families
    let prompt: String                 // original runnable prompt

    enum CodingKeys: String, CodingKey {
        case processHint = "process_hint"
        case beamFrame = "beam_frame"
        case eCmGev = "e_cm_gev"
        case eventCount = "event_count"
        case observables
        case requestedAnalysisCandidates = "requested_analysis_candidates"
        case prompt
    }
}

// MARK: - ResearchGuideDecision

/// Guide-stage decision: answer, propose_simulation, or run_simulation.
struct ResearchGuideDecision: Codable, Sendable {
    enum Action: String, Codable, Sendable {
        case answer             = "answer"
        case proposeSimulation  = "propose_simulation"
        case runSimulation      = "run_simulation"
    }

    let action: Action
    let assistantMessage: String
    let runnablePrompt: String?
    let analysisFamily: String?

    enum CodingKeys: String, CodingKey {
        case action
        case assistantMessage = "assistant_message"
        case runnablePrompt = "runnable_prompt"
        case analysisFamily = "analysis_family"
    }
}

// MARK: - BeamSpec

struct BeamSpec: Codable, Sendable {
    let frameType: String   // "pp" | "ee" | "ep"
    let eCmGev: Double

    enum CodingKeys: String, CodingKey {
        case frameType = "frame_type"
        case eCmGev = "e_cm_gev"
    }
}

// MARK: - ObservableSpec

struct ObservableSpec: Codable, Sendable {
    let id: String
    let kind: String          // "hist1d" | "table" | "summary"
    let unit: String
    let source: String        // "event" | "particle" | "pair"
    let op: String
    let selector: String
    let bins: Int?
    let min: Double?
    let max: Double?
    let outputKeys: [String]

    enum CodingKeys: String, CodingKey {
        case id, kind, unit, source, op, selector, bins, min, max
        case outputKeys = "output_keys"
    }

    init(id: String, kind: String, unit: String = "", source: String,
         op: String, selector: String, bins: Int? = nil, min: Double? = nil,
         max: Double? = nil, outputKeys: [String]) {
        self.id = id; self.kind = kind; self.unit = unit; self.source = source
        self.op = op; self.selector = selector; self.bins = bins
        self.min = min; self.max = max; self.outputKeys = outputKeys
    }
}

// MARK: - AnalysisPlan

struct AnalysisPlan: Codable, Sendable {
    let family: String
    let selectors: [String]
    let observables: [ObservableSpec]
}

// MARK: - OutputPlan

struct OutputPlan: Codable, Sendable {
    let summaryJson: Bool
    let logs: Bool
    let plots: Bool
    let extraFiles: [String]

    enum CodingKeys: String, CodingKey {
        case summaryJson = "summary_json"
        case logs, plots
        case extraFiles = "extra_files"
    }
}

// MARK: - SimulationSpec

/// Canonical execution contract produced by AnalysisPlannerAgent.
struct SimulationSpec: Codable, Sendable {
    let runId: String
    let pythiaTag: String
    let seed: Int
    let beams: BeamSpec
    let processSettings: [String]
    let cutsSettings: [String]
    let eventCount: Int
    let observables: [ObservableSpec]
    let analysisPlan: AnalysisPlan?
    let outputPlan: OutputPlan

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case pythiaTag = "pythia_tag"
        case seed
        case beams
        case processSettings = "process_settings"
        case cutsSettings = "cuts_settings"
        case eventCount = "event_count"
        case observables
        case analysisPlan = "analysis_plan"
        case outputPlan = "output_plan"
    }
}

/// User-controlled changes for a deterministic sibling run derived from persisted evidence.
struct ParameterizedRerunRequest: Sendable {
    let eventCount: Int
    let seed: Int
    let pTHatMin: Double?
}

// MARK: - GeneratedCode

/// Output of the code generation stage.
struct GeneratedCode: Codable, Sendable {
    let sourceCode: String
    let commandFile: String?
    let origin: String   // "deterministic" | "agentic"

    enum CodingKeys: String, CodingKey {
        case sourceCode = "source_code"
        case commandFile = "command_file"
        case origin
    }
}

// MARK: - AttemptExecutionResult

/// Result from RunnerService.executeAttempt().
struct AttemptExecutionResult: Codable, Sendable {
    let status: String
    let compileLogPath: String
    let runtimeLogPath: String
    let summaryJsonPath: String?
    let diagnostics: String?
    let plotPaths: [String]
    let generatedCodePath: String

    enum CodingKeys: String, CodingKey {
        case status
        case compileLogPath = "compile_log_path"
        case runtimeLogPath = "runtime_log_path"
        case summaryJsonPath = "summary_json_path"
        case diagnostics
        case plotPaths = "plot_paths"
        case generatedCodePath = "generated_code_path"
    }
}

// MARK: - SnippetSelection

/// A reference to a line range in a template file.
struct SnippetSelection: Codable, Sendable {
    let filename: String
    let startLine: Int
    let endLine: Int

    enum CodingKeys: String, CodingKey {
        case filename
        case startLine = "start_line"
        case endLine = "end_line"
    }
}

// MARK: - PrecedenceContext

/// Context captured by the PrecedenceAgent after selecting templates.
struct PrecedenceContext: Codable, Sendable {
    let notes: String
    let selections: [SnippetSelection]
    let materializedSnippets: [String]

    enum CodingKeys: String, CodingKey {
        case notes
        case selections
        case materializedSnippets = "materialized_snippets"
    }
}

// MARK: - TemplateCandidate

/// A candidate template from the retrieval service.
struct TemplateCandidate: Codable, Sendable {
    let filename: String
    let section: String
    let description: String
    let keywords: [String]?
    let familyTags: [String]?
    let score: Double?
    let lines: String?

    enum CodingKeys: String, CodingKey {
        case filename, section, description, keywords
        case familyTags = "family_tags"
        case score, lines
    }

    init(filename: String, section: String = "", description: String = "",
         keywords: [String]? = nil, familyTags: [String]? = nil,
         score: Double? = nil, lines: String? = nil) {
        self.filename = filename; self.section = section
        self.description = description; self.keywords = keywords
        self.familyTags = familyTags; self.score = score; self.lines = lines
    }
}

// MARK: - AgentEvent

/// An event emitted during orchestration for traceability.
struct AgentEvent: Codable, Sendable {
    let phase: String
    let step: String
    let data: [String: String]
    let timestamp: String

    init(phase: String, step: String, data: [String: String] = [:]) {
        self.phase = phase
        self.step = step
        self.data = data
        self.timestamp = ISO8601DateFormatter().string(from: Date())
    }
}

// MARK: - Supported Analyses Metadata

/// Static metadata for each supported analysis family.
struct SupportedAnalysis: Codable, Sendable {
    let analysisFamily: String
    let whenToUse: String
    let examplePrompt: String

    enum CodingKeys: String, CodingKey {
        case analysisFamily = "analysis_family"
        case whenToUse = "when_to_use"
        case examplePrompt = "example_prompt"
    }
}
