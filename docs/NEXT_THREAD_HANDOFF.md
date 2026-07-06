# Next Thread Handoff

Date: 2026-07-06
Active repo: `https://github.com/akassh9/vidura-labs`
Canonical local workspace: `/Users/akash009/vidura`

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
- Treat generated code, logs, plots, run metadata, replayability, and export as
  product surface.

## Current Baseline

The source-of-truth repo is the private GitHub repo:

```text
https://github.com/akassh9/vidura-labs
```

The canonical local checkout at `/Users/akash009/vidura` points at
`akassh9/vidura-labs`. Older public-repo checkouts were archived under
`/Users/akash009/vidura-legacy-archive-*`. Always verify `git remote -v` before
creating a branch or PR.

Local `.env` contains `OPENAI_API_KEY`. It is ignored. Never print it.

Run path:

```bash
./script/build_and_run.sh build
./script/build_and_run.sh --verify
```

Process IDs drift, so verify launches with:

```bash
pgrep -x "Vidura Labs"
```

## GitHub Workflow

Implementation agents should:

- start from current `main` on `akassh9/vidura-labs`,
- create a `codex/` branch,
- make the scoped change,
- run validation,
- push the branch,
- open a PR,
- report the PR URL, validation, smoke run IDs, secret/artifact checks, and
  known gaps.

Do not push directly to `main`. The CTO/user verifies and merges PRs.

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

- Successful runs persist evidence artifacts for `run.cc`,
  `simulation_spec.json`, `summary.json`, `summary_lines.txt`, `compile.log`,
  `run.log`, and plot/table outputs.
- The old source-only `Run Configurations` panel was replaced with a `Run
  Evidence` surface.
- Added grouped artifact sections, read-only artifact viewing, Copy Path, Reveal
  in Finder, Copy Run ID, and Reveal Run Folder.
- Added fallback disk discovery for historical runs under Application Support.

Smoke-gated reproducible runs:

- Fresh smoke run `55C18C16-54E4-4A3C-BFFE-DEEE030A7459` completed with
  `event_count=10000`.
- Persisted two chart messages: `Charged Multiplicity` and
  `Transverse Momentum Spectrum`.
- Persisted evidence for `run.cc`, `simulation_spec.json`, `summary.json`,
  `summary_lines.txt`, `compile.log`, `run.log`, `hist_primary.txt`, and
  `hist_pt.txt`.
- Added `OrchestratorService.rerunExact(run:)`.
- Exact rerun uses persisted `simulation_spec.json` and `run.cc`, bypassing
  OpenAI guide/intent/codegen.
- Verified exact rerun `98CA353A-941B-4B5A-B6A6-070D89FDE59F` with byte-equal
  `run.cc` and `simulation_spec.json`.

Run Compare:

- PR #1: `https://github.com/akassh9/vidura-labs/pull/1`
- Merged at `6e744a9d40a92513239c970118313e0665a43241`.
- Adds a Compare tab beside Run Evidence.
- Compares two completed runs in the current thread across identity,
  configuration, summary metrics, artifact presence, chart titles/point counts,
  and byte-level `run.cc`/`simulation_spec.json` equality.
- Validation before merge:
  - `./script/build_and_run.sh build` succeeded.
  - `./script/build_and_run.sh --verify` succeeded.
  - `pgrep -x "Vidura Labs"` confirmed launch.
  - `git diff --check` passed.
  - Secret/artifact tracked-file scan was clean.

Export Run Bundle:

- PR #3: `https://github.com/akassh9/vidura-labs/pull/3`
- Merged at `5bb22ac5764bcb819fcb1e33e079dde391568210`.
- Adds an Export Run Bundle action to completed Run Evidence cards.
- Folder export writes `manifest.json` and `run_report.md`.
- Copies run evidence only: `run.cc`, `simulation_spec.json`, summaries, logs,
  and plot/table artifacts.
- Manifest includes run identity, configuration, flattened
  `simulation_spec.json`, flattened `summary.json` metrics, chart titles/point
  counts, copied artifacts, missing artifact references, and missing expected
  artifacts.
- Uses existing `RunEvidenceResolver`; no OpenAI calls.
- Smoke bundle inspected for run `55C18C16-54E4-4A3C-BFFE-DEEE030A7459`.
- Validation before merge:
  - `./script/build_and_run.sh build` succeeded.
  - `./script/build_and_run.sh --verify` succeeded.
  - `pgrep -x "Vidura Labs"` confirmed launch.
  - `git diff --check` passed.
  - Secret/artifact tracked-file scan was clean.

Parameterized Rerun:

- PR #6: `https://github.com/akassh9/vidura-labs/pull/6`
- Merged at `459a37f32f15b7e50d1925a1ac69b397bb746193`.
- Adds a Parameterized Rerun action to completed Run Evidence cards.
- Loads persisted `simulation_spec.json`, applies controlled changes, and
  regenerates deterministic C++ with `CodegenAgent`.
- Supports event count, random seed, and `PhaseSpace:pTHatMin`.
- Creates a sibling run in the same thread and records source-run provenance in
  configuration:
  - `Vidura:variantOfRunID`
  - `Vidura:variantChanges`
  - `Vidura:variantCodegen`
- Bypasses OpenAI guide/intent/codegen. The existing post-run physics summary
  stage still follows the normal path.
- Smoke validation:
  - Source run: `55C18C16-54E4-4A3C-BFFE-DEEE030A7459`.
  - Variant run: `B28DBDBC-B49D-4F40-AC6B-7F85113744B1`.
  - Tested `event_count 10000 -> 200`, `seed 625434 -> 13579`,
    `PhaseSpace:pTHatMin unset -> 18.5`.
  - Variant completed with modified `simulation_spec.json`, deterministic
    `run.cc`, `summary.json`, logs, `hist_primary.txt`, `hist_pt.txt`, two
    chart messages, and evidence artifacts.
  - Export manifest for the variant included two charts, all expected artifacts,
    and no missing artifacts.
- Validation before merge:
  - `./script/build_and_run.sh build` succeeded.
  - `./script/build_and_run.sh --verify` succeeded.
  - `pgrep -x "Vidura Labs"` confirmed launch.
  - `git diff --check` passed.
  - Tracked-file and diff secret scans were clean.

Run Lineage & Reproducibility Surface:

- PR #8: `https://github.com/akassh9/vidura-labs/pull/8`
- Merged at `9d5f5e8cb8b968f62dd63a22d928e7cc20d46535`.
- New exact reruns record source-run provenance in configuration:
  - `Vidura:exactRerunOfRunID`
- Variants resolve source runs and changes from:
  - `Vidura:variantOfRunID`
  - `Vidura:variantChanges`
- Historical exact reruns infer source relationships from request messages like
  `Rerun exact from run <id>` when the source run still exists in the thread.
- Run Evidence cards now show a compact reproducibility row:
  original/exact rerun/variant, source short ID, inferred marker, and variant
  changes when present.
- Derived completed runs expose Compare to Source, which switches to Run Compare
  and preselects source as A and derived as B.
- Run Compare now shows relationship context for source/derived pairs.
- Review validation before merge:
  - `./script/build_and_run.sh build` succeeded.
  - `./script/build_and_run.sh --verify` succeeded.
  - `pgrep -x "Vidura Labs"` confirmed launch.
  - `git diff --check` passed.
  - Tracked-file and diff secret scans were clean.
- Fixture checks:
  - Variant `B28DBDBC-B49D-4F40-AC6B-7F85113744B1` resolves to source
    `55C18C16-54E4-4A3C-BFFE-DEEE030A7459` with `event_count 10000 -> 200`,
    `seed 625434 -> 13579`, and `PhaseSpace:pTHatMin unset -> 18.5`.
  - Historical exact rerun `98CA353A-941B-4B5A-B6A6-070D89FDE59F` infers
    immediate source `CC4B3F6C-83A1-44EB-9EBA-70FB6B995ACE`.
  - Known residual gap: no manual native UI click-through in the merge review.

## Next Product Slice

Reproducibility Regression Harness.

Why this next: the reproducible run loop now exists, but it spans several
fragile contracts: deterministic specs, deterministic C++ fallback, runner
artifact parsing, evidence discovery, export manifests, lineage inference, and
Run Compare. Before adding broader HEP analysis features, add a focused test or
script harness so future agents can change those contracts without relying only
on manual smoke runs.

## Recommended Implementation

Start by auditing the current Xcode project. There is no established test target
as of this handoff, so choose the smallest maintainable path:

Suggested shape:

- Prefer a real XCTest target if it can be added cleanly without destabilizing
  the project file.
- If an XCTest target is too much churn for one slice, add a project-local
  verification script that exercises pure Swift or fixture-level contracts and
  can be promoted into XCTest later.
- Extract pure helpers only where useful for testability. Do not broadly refactor
  `ResearchThreadDetailView.swift` just to make the file smaller.
- Cover at least these contracts:
  - `RunnerService.parseSummaryLines` behavior for existing summary lines.
  - deterministic `CodegenAgent.run(spec:)` output for event count, seed,
    `PhaseSpace:pTHatMin`, `hist_primary.txt`, and `hist_pt.txt`;
  - run-lineage resolution for original, variant, new exact rerun, and historical
    inferred exact rerun fixtures;
  - export manifest expectations for a completed smoke fixture if the exporter
    can be reached without GUI interaction.
- If necessary, move `RunLineageResolver` or exporter manifest assembly into a
  small non-view helper so it can be tested without rendering SwiftUI.
- Keep runtime behavior unchanged unless a test exposes a real bug.

## Acceptance Criteria

- The repo has a repeatable regression command for deterministic reproducibility
  contracts.
- The harness does not require clicking the macOS UI.
- The harness can run from a clean checkout with the normal local Pythia/OpenAI
  setup and ignored `.env`; it must not print secrets.
- The harness uses fixtures or pure functions where practical, not live OpenAI
  calls.
- Existing Evidence, Exact Rerun, Parameterized Rerun, Compare, Export, and
  Lineage behavior still builds and launches.
- `./script/build_and_run.sh build` succeeds.
- `./script/build_and_run.sh --verify` succeeds.
- Any added test command succeeds, or the PR clearly explains why no formal test
  target was added in this slice.
- Branch is pushed and a PR is opened against `akassh9/vidura-labs/main`.

## Useful Commands

```bash
git remote -v
git status --short --branch
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
- Do not commit local databases, DerivedData, generated simulation folders, or
  exported run bundles.
- Do not revert unrelated user or agent changes.
- Back up live Application Support DB before manual data patching.
- Keep export deterministic and evidence-driven; do not call OpenAI for export.
