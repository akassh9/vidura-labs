# Vidura Labs Project Orientation

## Current Product

Vidura Labs is a native macOS research companion for particle-physics
simulations. A user can ask a question or request a simulation in natural
language. The app can answer directly, propose a runnable simulation, or run a
local Pythia 8 workflow that generates C++ code, compiles and executes it,
parses artifacts, and renders summary text plus charts in the chat UI.

The long-term direction is a physics-specific research assistant, starting with
HEP and Pythia. macOS is the primary platform. The old CLI and
sponsored-provider hackathon direction is no longer the active baseline.

## Architecture

```mermaid
flowchart TD
    User["User prompt"] --> UI["SwiftUI chat and project UI"]
    UI --> Store["GRDB stores"]
    UI --> Orchestrator["OrchestratorService"]
    Orchestrator --> Guide["Guide stage - OpenAI"]
    Guide --> Intent["Intent stage - OpenAI"]
    Intent --> Examples["ExampleIndex retrieval"]
    Examples --> Planner["AnalysisPlannerAgent"]
    Planner --> Codegen["Coding stage - OpenAI with deterministic fallback"]
    Codegen --> Gates["PolicyCheck + PhysicsCheck"]
    Gates --> Runner["RunnerService"]
    Runner --> Pythia["Local clang++ + Pythia 8"]
    Pythia --> Artifacts["summary, logs, histogram/table files"]
    Artifacts --> Plotting["PlottingAgent"]
    Artifacts --> Summary["PhysicsSummaryAgent - OpenAI with fallback"]
    Plotting --> UI
    Summary --> UI
    Store --> UI
```

## Data Model

Persistence is local SQLite through GRDB under Application Support:

- `research_projects`: top-level folders.
- `research_threads`: conversations grouped by project.
- `runs`: execution attempts and chat runs within a thread.
- `messages`: user/assistant/chart messages linked to runs.
- `settings`: single-row user settings table.

Generated simulation artifacts are stored under
`~/Library/Application Support/com.AL.PhysicsCompanion/simulations/<run-id>/`.

## Runtime Pipeline

1. `AppBootstrapView` checks command line tools, installs bundled Pythia into
   Application Support if needed, opens stores, and creates `OrchestratorService`.
2. The chat UI creates or reuses an active run, writes the user message, then
   calls `OrchestratorService.run`.
3. The guide stage uses OpenAI structured output to decide whether to answer,
   propose a simulation, or run one.
4. The intent stage extracts a structured simulation request.
5. `ExampleIndex` retrieves relevant Pythia examples from bundled/installed
   example files.
6. `AnalysisPlannerAgent` builds a deterministic `SimulationSpec`.
7. OpenAI generates Pythia C++ code, with `CodegenAgent` as a deterministic
   fallback for non-rate-limit failures.
8. `PhysicsCheckAgent` and `PolicyCheckAgent` validate generated code.
9. `RunnerService` writes `run.cc`, compiles it with `/usr/bin/clang++`, runs
   it with `PYTHIA8DATA`, captures logs, and parses `summary_lines.txt`.
10. `PlottingAgent` converts artifact files into `ChartPayload`.
11. `PhysicsSummaryAgent` asks OpenAI for final interpretation, falling back to
    a deterministic summary if needed.

## Supported Analysis Families

- `charged_multiplicity`
- `pt_spectrum`
- `eta_rapidity`
- `invariant_mass`
- `pid_yields`
- `event_scalars`

## Baseline Local Status

The active repository is `https://github.com/akassh9/vidura-labs`.
The canonical local workspace is `/Users/akash009/vidura`. Older public-repo
checkouts were archived under `/Users/akash009/vidura-legacy-archive-*`; verify
remotes before creating branches.

Local development uses a repository-root `.env` with `OPENAI_API_KEY`. The run
script exports `VIDURA_REPO_ROOT` so the app can resolve that file when launched
from Codex.

## Near-Term Cleanup Priorities

1. Add duplicate-and-modify run controls for event count, seed, and simple cuts.
2. Tighten the exact rerun, compare, export, and parameterized-rerun workflow
   into one reproducibility surface.
3. Remove the duplicate `pythia_dist 2` folder and confirm the release bundle
   still includes the expected `pythia_dist` resource.
4. Fix `moveThreadToProject` so it preserves runs/messages instead of
   delete/recreate semantics.
5. Decide where the line should sit between OpenAI-driven codegen and the
   deterministic `CodegenAgent` fallback.
6. Add focused tests around deterministic agents, summary parsing,
   policy/physics checks, and store migrations before expanding analyses.
