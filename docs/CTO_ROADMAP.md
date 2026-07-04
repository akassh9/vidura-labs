# CTO Roadmap

Date: 2026-07-04

## Product Thesis

Vidura Labs should become a physics-specific research companion, starting with
HEP/Pythia. The core promise is not "chat with a model"; it is "ask for a
physics analysis and receive a reproducible scientific run record."

## Execution Principles

- macOS first.
- Local Pythia execution is a product strength, not an implementation detail.
- Every generated result needs provenance: prompt, plan, spec, generated code,
  logs, outputs, charts, and interpretation.
- Prefer narrow, compounding slices over broad rewrites.
- Add physics breadth only after the run record is trustworthy.
- Keep OpenAI calls structured where possible and deterministic fallbacks
  available for core supported analyses.

## Near-Term Phases

### Phase 0: Stabilize The Science Loop

Goal: one user prompt reliably produces a readable, inspectable Pythia run.

Completed:

- OpenAI-backed agent path.
- Local build/run script.
- Basic Pythia execution.
- Multi-chart output path.
- Run Evidence / Provenance UI and artifact persistence.
- Fresh smoke-gated run proving multi-chart and evidence persistence.

### Phase 1: Make Runs Repeatable

Goal: users can rerun, branch, compare, and cite a run.

Completed:

- Exact rerun from audited source/spec.
- Compare two runs side by side.

Needed:

- Export a run bundle with source, logs, summary, charts, and metadata.
- Duplicate run with modified event count/seed/cuts.
- Promote exact rerun and compare into a tighter reproducibility workflow.

### Phase 2: Raise Physics Quality

Goal: generated analyses are correct enough to trust for exploratory work.

Needed:

- Better intent-to-analysis planning for multiple observables.
- Hard validation gates for generated C++.
- Explicit warnings for biased samples and cut choices.
- Known-good templates for common HEP workflows.
- Unit or regression tests around deterministic planning, plotting, and summary
  parsing.

### Phase 3: Become A Research Workspace

Goal: projects become durable notebooks, not chat transcripts.

Needed:

- Thread/run notebooks.
- Saved datasets and reusable analysis presets.
- Artifact search.
- Citation/export workflows.
- User-editable analysis plans before execution.

## Current Next Slice

Export Run Bundle.

Why: the app can now produce evidence, rerun exact source/spec, and compare
completed runs. The next trust layer is portability. A completed run should be
exportable as a self-contained folder with source, spec, logs, summaries,
plots/tables, and a manifest so it can be shared, cited, archived, or inspected
outside the live app database.

## GitHub Operating Model

The active repo is `https://github.com/akassh9/vidura-labs`. Implementation
agents should branch from current `main`, use a `codex/` branch name, open a PR,
and report validation. The CTO/user verifies and merges. Direct pushes to
`main` are not the default workflow.
