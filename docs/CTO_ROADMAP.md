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

Next:

- Fresh end-to-end smoke proving the evidence path.
- Exact rerun from audited source/spec.

### Phase 1: Make Runs Repeatable

Goal: users can rerun, branch, compare, and cite a run.

Needed:

- Rerun from exact `SimulationSpec`.
- Duplicate run with modified event count/seed/cuts.
- Compare two runs side by side.
- Export a run bundle with source, logs, summary, charts, and metadata.

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

Smoke-gated Reproducible Runs.

Why: the app now has inspectable run records, but the latest evidence slice was
not validated with a fresh Pythia GUI smoke. First prove that new runs populate
multi-chart/evidence state correctly, then add exact rerun from audited
`simulation_spec.json` plus `run.cc` without invoking OpenAI planning/codegen.
