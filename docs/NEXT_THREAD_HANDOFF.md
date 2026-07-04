# Next Thread Handoff

Date: 2026-07-04
Workspace: `/Users/akash009/vidura`
Repo: `https://github.com/Alfagov/ViduraLabs`

## CTO Direction

Vidura Labs is a native macOS physics research companion, starting with
HEP/Pythia. The product thesis is not "chat with a model"; it is "ask for a
physics analysis and receive a reproducible scientific run record."

Strategic decisions:

- macOS first.
- Drop the old CLI direction.
- Do not reintroduce the old hackathon sponsored-provider stack.
- Use OpenAI for model-backed agent stages.
- Keep local Pythia execution and local SQLite persistence.
- Treat generated code, logs, plots, run metadata, and replayability as product
  surface, not implementation details.

## Current Baseline

The repo is intentionally dirty with ongoing modernization work. Do not discard
uncommitted changes unless the user explicitly asks.

Local `.env` exists and contains `OPENAI_API_KEY`. It is ignored. Never print it.

Run path:

```bash
./script/build_and_run.sh build
./script/build_and_run.sh --verify
```

Latest reported launch verification from the Run Evidence thread:

```text
Vidura Labs PID 41069
```

Process IDs drift, so verify with:

```bash
pgrep -x "Vidura Labs"
```

## Already Completed

Provider/runtime migration:

- Removed Firebase app initialization and package/resource references.
- Removed stale provider-specific generated pipeline diagrams.
- Added `OpenAIClient.swift` for OpenAI Responses API calls, structured outputs,
  and local `.env` credential resolution.
- Rewired guide, intent, codegen, summary, and thread naming stages to OpenAI.
- Preserved deterministic fallbacks where they already made sense.

Persistence fixes:

- Fixed `messages.sender` loading in `ResearchStore`.
- Removed the dead `chat_history` write path.
- Fixed branch-run message copying into normalized `messages`.
- Prevented follow-up parent links from crossing unrelated runs.

Multi-chart slice:

- `PlottingAgent.runAll(...)` emits multiple `ChartPayload`s.
- `OrchestratorService` persists multiple chart messages per run and chains the
  summary after the last chart.
- `PhysicsSummaryAgent` receives all chart payloads.
- `RunnerService` collects `hist_pt.txt` and future `hist_*.txt` artifacts.
- `AnalysisPlannerAgent` includes secondary artifact filenames in the output
  contract when requested.
- Five-column histogram parsing uses `bin_center` for x and `count` for y.

Run Evidence / Provenance slice:

- Successful runs persist evidence artifacts for:
  - `run.cc`
  - `simulation_spec.json`
  - `summary.json`
  - `summary_lines.txt`
  - `compile.log`
  - `run.log`
  - plot/table outputs
- Runner artifact collection includes declared extra output files while excluding
  source/log/summary files handled as evidence.
- The old source-only `Run Configurations` panel was replaced with a `Run
  Evidence` surface.
- Added grouped artifact sections, read-only artifact viewing, Copy Path, Reveal
  in Finder, Copy Run ID, and Reveal Run Folder.
- Added fallback disk discovery for historical runs under Application Support.
- Reported validation:
  - `./script/build_and_run.sh build` succeeded.
  - `./script/build_and_run.sh --verify` succeeded.
  - `pgrep -x "Vidura Labs"` confirmed PID `41069`.
  - `git diff --check` passed for touched files.

Important gap: Run Evidence was not validated with a fresh GUI Pythia smoke.
The next thread must do that before building more features.

## Existing Smoke Evidence

Known pre-evidence smoke run:

- Run ID: `49B0EFE9-1BE2-4661-A2B6-DCD419D12DD3`.
- Prompt:
  `pp collisions at 13 TeV, 10,000 minimum-bias events, measuring charged-particle multiplicity, pT spectrum`
- Status: completed.
- Generated events: 10000.
- Mean charged multiplicity: 114.374.
- Mean charged-particle pT: 0.516 GeV.
- Artifacts:
  `~/Library/Application Support/com.AL.PhysicsCompanion/simulations/49B0EFE9-1BE2-4661-A2B6-DCD419D12DD3/attempt_1/`

That run predates the latest persistence/evidence changes. Use it only as a
reference artifact set, not as proof that new runs populate the new evidence UI.

## Next Product Slice

Smoke-gated Reproducible Runs.

This has two stages:

1. Run a fresh end-to-end Pythia smoke through the app and verify the new
   multi-chart plus evidence behavior is real in persisted data and UI.
2. If the smoke is clean, implement "Rerun Exact" from an existing completed run.

Why this next: now that runs are inspectable, the next trust layer is
repeatability. A user should be able to take an audited run record and rerun the
exact same generated C++/spec into a new run, then compare the new evidence.

## Recommended Implementation

Stage 1: Fresh smoke and fix fallout.

- Use this prompt:

```text
pp collisions at 13 TeV, 10,000 minimum-bias events, measuring charged-particle multiplicity, pT spectrum
```

- Verify the new run has:
  - completed status,
  - at least two chart messages for multiplicity and pT,
  - artifacts for source/spec/summary/logs/plots,
  - evidence panel entries for those files,
  - no summary claim that pT is missing.

- If GUI automation is impractical, ask the user to submit the smoke prompt in
  the running app, then inspect SQLite and Application Support afterward.

Stage 2: Exact rerun.

- Add a `Rerun Exact` action to the Run Evidence surface for completed simulation
  runs.
- Prefer rerunning from persisted evidence:
  - load `simulation_spec.json`,
  - load `run.cc`,
  - create a new sibling run in the same thread,
  - execute the same generated source through `RunnerService`,
  - persist the same evidence artifact types,
  - emit result/chart/summary messages for the new run.
- Avoid using OpenAI guide/intent/codegen for exact rerun. Exact rerun should be
  deterministic and evidence-driven.
- If the existing orchestration shape makes this too large, implement the
  internal service path first and expose the UI action second.

## Acceptance Criteria

- Fresh smoke run proves multi-chart and evidence persistence on a new run.
- Any smoke fallout is fixed before adding rerun.
- `Rerun Exact` creates a new run from an existing completed run without going
  through OpenAI planning/codegen.
- The rerun has its own run ID, status, messages, artifacts, and run folder.
- The rerun preserves the original generated source and simulation settings.
- Build succeeds.
- Verify launch succeeds.
- No secrets are printed or logged.

## Useful Commands

```bash
./script/build_and_run.sh build
./script/build_and_run.sh --verify
pgrep -x "Vidura Labs"
```

Inspect latest runs:

```bash
sqlite3 -header -column "$HOME/Library/Application Support/com.AL.PhysicsCompanion/research.db" \
  "SELECT id, title, status, event_count, updated_at FROM runs ORDER BY datetime(updated_at) DESC LIMIT 10;"
```

Inspect messages for a run:

```bash
sqlite3 -header -column "$HOME/Library/Application Support/com.AL.PhysicsCompanion/research.db" \
  "SELECT id, sender, role, length(content) AS content_len, length(chart_payload) AS chart_len, created_at FROM messages WHERE run_id = '<RUN_ID>' ORDER BY datetime(created_at);"
```

Inspect artifacts for a run:

```bash
sqlite3 "$HOME/Library/Application Support/com.AL.PhysicsCompanion/research.db" \
  "SELECT artifacts FROM runs WHERE id = '<RUN_ID>';" | python3 -m json.tool
```

## Guardrails

- Do not redo provider migration.
- Do not reintroduce Firebase/Gemini.
- Do not restart CLI work.
- Do not print `.env`.
- Do not revert unrelated uncommitted changes.
- Back up live Application Support DB before manual data patching.
- Keep repeatability deterministic; do not call OpenAI for exact reruns.

