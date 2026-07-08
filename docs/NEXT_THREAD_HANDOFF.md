# Next Thread Handoff

Date: 2026-07-08
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

Reproducibility Regression Harness:

- PR #10: `https://github.com/akassh9/vidura-labs/pull/10`
- Merged at `e71c587f09ea6f8204e63a73c227357a7ab72749`.
- Added repeatable regression command:
  - `./script/reproducibility_regression.sh`
- Confirmed `xcodebuild -list -project "Vidura Labs.xcodeproj"` shows one app
  target/scheme and no existing test target, so this slice uses a project-local
  script harness instead of XCTest.
- Extracted pure helpers:
  - `RunnerSummaryParser` backs `RunnerService.parseSummaryLines`.
  - `RunLineageResolver` backs the Run Evidence / Run Compare lineage UI through
    a small SwiftUI adapter in `ResearchThreadDetailView.swift`.
- Harness coverage:
  - `RunnerService.parseSummaryLines` integer, floating-point, string, trimming,
    and malformed-line behavior.
  - deterministic `CodegenAgent.run(spec:)` output for event count, seed,
    `PhaseSpace:pTHatMin`, `hist_primary.txt`, and `hist_pt.txt`.
  - lineage classification for original, explicit exact rerun, variant,
    historical inferred exact rerun, and source/derived relationship context.
- Review validation before merge:
  - `xcodebuild -list -project "Vidura Labs.xcodeproj"` succeeded.
  - `./script/build_and_run.sh build` succeeded.
  - `./script/build_and_run.sh --verify` succeeded.
  - `pgrep -x "Vidura Labs"` confirmed launch.
  - `./script/reproducibility_regression.sh` succeeded.
  - `git diff --check` passed.
  - Tracked-file and strict secret-value scans were clean.
- Known residual gap: export manifest assembly remains UI-adjacent inside
  `RunBundleExporter` and is not covered by the first harness.

Run Quality / Sanity Checks:

- PR #13: `https://github.com/akassh9/vidura-labs/pull/13`
- Merged at `b08e921f708d331e4924d3b2b42b4401eb5baa2e`.
- Added `RunQualityAnalyzer`, a pure deterministic analyzer for completed-run
  evidence, summaries, specs, artifacts, and logs.
- Run Evidence cards now show a compact completed-run-only `Run Quality` block.
- Export Run Bundle now writes quality findings into `manifest.json` under
  `quality_findings` and into `run_report.md`.
- Checks implemented:
  - expected completed-run evidence: `run.cc`, `simulation_spec.json`,
    `summary.json`, `summary_lines.txt`, `compile.log`, and `run.log`;
  - missing or empty declared plot/table outputs;
  - `summary.json` event-count mismatch with run metadata;
  - low exploratory event-count warning below `1000`;
  - nonzero visible histogram overflow counters;
  - inclusive/minimum-bias interpretation warning when hard-process or
    `PhaseSpace:pTHatMin` cuts are present;
  - warning/error markers in compile/run logs despite completed status.
- Harness coverage in `./script/reproducibility_regression.sh`:
  - healthy pass state;
  - missing expected evidence;
  - missing and empty declared output;
  - low event count;
  - event-count mismatch;
  - overflow and compile-log warning markers;
  - inclusive/minimum-bias with hard-process / pT-hat cut warning.
- CTO review validation before merge:
  - `./script/build_and_run.sh build` succeeded.
  - `./script/build_and_run.sh --verify` succeeded.
  - `pgrep -x "Vidura Labs"` confirmed launch from `.codex/DerivedData`.
  - `./script/reproducibility_regression.sh` succeeded.
  - `git diff --check origin/main...HEAD` passed.
  - Tracked-file hygiene and diff secret scans were clean.
- Known residual gap: no fresh simulation smoke or manual export-dialog
  click-through was done during the merge review.

Physics Reviewer Agent v1:

- PR #15: `https://github.com/akassh9/vidura-labs/pull/15`
- Merged at `3f4fcbbf5a7ef6aaeb7e2f32deb7411267705cc2`.
- Added `PhysicsReviewerAgent` with OpenAI structured output, pure input
  construction, response parsing, and deterministic fallback.
- The reviewer runs after completed original, exact rerun, and parameterized
  run summaries.
- Reviewer evidence is persisted as `physics_reviewer.json` and as compact
  reviewer chat messages.
- Run Evidence shows reviewer findings near Run Quality.
- Export Run Bundle writes reviewer findings into `manifest.json` under
  `reviewer_findings` and into `run_report.md`.
- Added `MessageSender.reviewer` for normalized reviewer messages.
- Harness coverage in `./script/reproducibility_regression.sh`:
  - reviewer evidence/input construction;
  - prompt payload includes quality findings and final summary text;
  - structured response parsing;
  - malformed response fallback;
  - quality-warning fallback that must not call the run clean.
- CTO review validation before merge:
  - `./script/build_and_run.sh build` succeeded.
  - `./script/build_and_run.sh --verify` succeeded.
  - `pgrep -x "Vidura Labs"` confirmed launch from `.codex/DerivedData`.
  - `./script/reproducibility_regression.sh` succeeded.
  - `git diff --check origin/main...HEAD` passed.
  - `git diff --cached --check` passed.
  - Tracked-file hygiene and diff secret scans were clean.
  - GitHub reported no checks configured for the branch.
- Known residual gap: no fresh simulation smoke run and no manual native
  UI/export click-through of a newly generated reviewer artifact.

HEP Source Connectors v1:

- PR #17: `https://github.com/akassh9/vidura-labs/pull/17`
- Merged at `82840f92fc65154851f137939a08ef8622f309c5`.
- Added typed `HEPReference`, `HEPReferencePack`, and `HEPReferenceSource`.
- Added connector helpers/parsers for arXiv, INSPIRE, HEPData, and PDG.
- Added deterministic reference-pack assembly with DOI, arXiv, INSPIRE,
  HEPData, URL, and title dedupe while preserving source attribution and IDs.
- Completed runs now get a deterministic baseline `reference_pack.json`
  evidence artifact.
- Run Evidence shows a compact References block when a reference pack exists.
- Export Run Bundle includes `reference_pack` in `manifest.json` and a
  `## References` section in `run_report.md` when present.
- Harness coverage in `./script/reproducibility_regression.sh`:
  - arXiv Atom parsing and ID normalization;
  - INSPIRE JSON result normalization;
  - HEPData record normalization;
  - PDG record normalization;
  - DOI/arXiv/INSPIRE/HEPData/URL/title dedupe;
  - export-style reference-pack serialization.
- CTO review validation before merge:
  - `./script/build_and_run.sh build` succeeded.
  - `./script/build_and_run.sh --verify` succeeded.
  - `pgrep -x "Vidura Labs"` confirmed launch from `.codex/DerivedData`.
  - `./script/reproducibility_regression.sh` succeeded.
  - `git diff --check origin/main...HEAD` passed.
  - `git diff --cached --check` passed.
  - Tracked-file hygiene and diff/staged diff secret scans were clean.
  - GitHub reported no checks configured for the branch.
- Known residual gap: no fresh simulation smoke run, no manual native UI/export
  click-through, and live fetch helpers are not yet wired into automatic or
  user-triggered retrieval. New completed runs get the deterministic baseline
  HEP reference pack.

HEP Reference Pack Retrieval v1:

- PR #19: `https://github.com/akassh9/vidura-labs/pull/19`
- Merged at `de1ce8e17a91b96d02e962b5f004a560c62d33d1`.
- Added a completed-run Refresh References action in Run Evidence.
- Added deterministic query construction from run title, prompt/messages,
  `simulation_spec.json`, analysis family, process/cut context, observables,
  and chart titles.
- Added bounded arXiv, INSPIRE, HEPData, and PDG refresh flow with per-source
  statuses: success, skipped, failed, and partial failure.
- Refreshed references merge into the existing `reference_pack.json` while
  preserving baseline references, source IDs, source attribution, URLs, and
  tags.
- Refresh status is persisted inside `reference_pack.json` as
  `source_statuses`; older packs decode with an empty status list.
- Run Evidence shows compact source-status chips in the References block.
- Export Run Bundle remains deterministic and serializes the persisted
  reference pack only; it does not call live source APIs.
- Harness coverage in `./script/reproducibility_regression.sh`:
  - query construction;
  - merge behavior with existing baseline references;
  - partial HEPData failure handling;
  - per-source status serialization and decoding.
- CTO review validation before merge:
  - `./script/reproducibility_regression.sh` succeeded.
  - `./script/build_and_run.sh build` succeeded.
  - `./script/build_and_run.sh --verify` succeeded.
  - `pgrep -x "Vidura Labs"` confirmed launch from `.codex/DerivedData`.
  - `git diff --check origin/main...HEAD` passed.
  - `git diff --cached --check` passed.
  - Tracked-file hygiene and diff/staged diff secret scans were clean.
  - GitHub reported no checks configured for the branch.
- Live endpoint probe during CTO review:
  - arXiv API returned HTTP 200.
  - INSPIRE API returned HTTP 200.
  - HEPData base returned HTTP 200.
  - The specific Pythia-generator HEPData record probe returned HTTP 404, which
    is covered by per-source failed/partial-failure status handling.
- Known residual gap: no manual native UI click-through of the refresh button
  was done during merge review. The next product gap is not fetching sources;
  it is making reviewer output use those sources.

## Next Product Slice

Reference-Grounded Physics Reviewer v2.

Why this next: Vidura now has deterministic run evidence, run quality checks,
Physics Reviewer v1, baseline HEP reference packs, and an explicit source
refresh workflow. The next trust gap is whether the reviewer can use those
references to separate artifact-backed claims, citation-backed claims, and
unsupported claims.

This should stay small: extend reviewer input and output around persisted
reference packs. Do not add another retrieval workflow, do not redesign Run
Evidence, and do not make reviewer/export paths call live source APIs.

Recommended scope:

- extend the pure reviewer input builder to include the persisted
  `reference_pack.json`: query, tags, references, URLs, DOI/arXiv/INSPIRE/
  HEPData IDs, source attribution, and `source_statuses`;
- update `PhysicsReviewerAgent` structured output and prompt so findings can
  cite reference IDs from the pack and must not invent citations;
- add deterministic fallback warnings for missing reference packs, failed or
  partial source refreshes, and final-summary language that mentions external
  measurements/literature without a reference;
- keep the reviewer artifact-driven: it may consume existing reference packs but
  must not refresh references or call live APIs;
- show reference-backed reviewer findings compactly in the existing reviewer
  area near Run Quality and References;
- ensure `physics_reviewer.json`, Export Run Bundle `manifest.json`, and
  `run_report.md` preserve any reference IDs attached to reviewer findings;
- add fixture-driven regression coverage for reference input shaping, missing
  pack fallback, source-status warnings, response parsing with reference IDs,
  and export-style serialization.

Acceptance criteria:

- existing Evidence, Exact Rerun, Parameterized Rerun, Compare, Export, Lineage,
  Run Quality, Physics Reviewer, and regression harness behavior remains intact;
- reviewer output can distinguish artifact evidence from reference/citation
  evidence;
- reviewer findings never cite sources that are not present in
  `reference_pack.json`;
- missing/failed reference coverage is surfaced as a warning rather than hiding
  behind a clean review;
- no live source APIs are called during reviewer execution or export;
- validation includes build, verify launch, regression harness, diff check,
  tracked-file hygiene scan, and diff secret scan.

## Recommended Implementation

Start with `PhysicsReviewerAgent` and the pure evidence/input-building path.
Avoid wiring this into source retrieval. The reviewer should consume the
persisted pack that already exists for the run.

Suggested shape:

- Reuse `HEPReferencePack` and the existing artifact resolver/adapter patterns.
- Add small Codable fields to reviewer findings only if the current model cannot
  attach reference IDs cleanly.
- Keep old `physics_reviewer.json` artifacts decodable if the reviewer schema
  changes.
- In the model prompt, require reference IDs to come from supplied references
  only; if no reference supports a claim, the reviewer should say that.
- Let deterministic fallback produce conservative warnings rather than pretending
  a run is citation-grounded.
- Keep UI changes quiet and dense: a few reference chips/IDs in existing
  reviewer findings are enough for this slice.

## Acceptance Criteria

- Reviewer input includes persisted reference-pack content when available.
- Reviewer findings can carry reference IDs/URLs from the pack.
- Missing packs, failed source statuses, and unsupported citation-sensitive
  claims produce warnings in deterministic fallback coverage.
- Export behavior remains deterministic and serializes persisted reviewer
  findings and reference packs only.
- Existing Physics Reviewer, Run Quality, HEP Reference, and lineage harness
  cases still pass.
- `./script/build_and_run.sh build` succeeds.
- `./script/build_and_run.sh --verify` succeeds.
- `./script/reproducibility_regression.sh` succeeds.
- Branch is pushed and a PR is opened against `akassh9/vidura-labs/main`.

## Useful Commands

```bash
git remote -v
git status --short --branch
./script/build_and_run.sh build
./script/build_and_run.sh --verify
./script/reproducibility_regression.sh
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
- Keep export deterministic and evidence-driven; export should serialize
  existing reviewer findings and reference packs, not call OpenAI or live source
  APIs.
