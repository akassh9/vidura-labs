# CTO Roadmap

Date: 2026-07-08

## Product North Star

Vidura Labs should become the physics equivalent of Claude Science: an AI
workbench where a physicist can move from question to literature, data,
simulation, analysis, figures, manuscript-ready artifacts, and reproducible
run history inside one environment.

Reference benchmark:
[Claude Science, an AI workbench for scientists](https://www.anthropic.com/news/claude-science-ai-workbench).

Claude Science is optimized for biology and chemistry. Vidura should optimize
the same product pattern for physics, starting with HEP and Pythia:

- domain-ready tools and data sources;
- auditable artifacts with code, environment, inputs, logs, and history;
- local and remote compute access;
- specialist agents for subdomains and workflows;
- reviewer agents that check calculations, citations, figures, and provenance;
- reusable lab workflows that become durable skills.

The core promise is not "chat with a model." It is:

> Ask a physics question, get a reproducible scientific work product.

## Product Pillars

### 1. Physics Workbench, Not Chat

The app should feel like a research environment, not a transcript. Chat is the
coordination layer, but the product surface is made of runs, artifacts, plans,
figures, notebooks, datasets, citations, and decisions.

Target capabilities:

- project notebooks that combine conversation, equations, code, data, plots,
  run records, and written interpretation;
- artifact-native viewers for physics outputs, not generic file previews;
- inline editing of figures, captions, analysis plans, and manuscript sections;
- forkable research sessions for comparing approaches without losing lineage.

### 2. Reproducible Physics Artifacts

Every output should be traceable months later. A figure or table is incomplete
unless the app can show how it was produced.

Required artifact contract:

- original prompt and refined task;
- analysis plan and physics assumptions;
- simulation spec and random seed;
- generated source code and command/environment;
- compile/run logs;
- raw outputs and parsed summaries;
- plots/tables and the code that created them;
- quality checks and reviewer notes;
- full lineage for exact reruns, variants, forks, exports, and citations.

### 3. Domain-Ready HEP Toolchain

Vidura starts with local Pythia because it gives the product a real scientific
spine. The workbench should expand into the trusted HEP stack rather than a
generic coding assistant.

Priority tool families:

- event generation: Pythia first, then MadGraph where appropriate;
- analysis: ROOT, uproot, Awkward Array, FastJet, Rivet;
- detector and reconstruction, later: Delphes, Geant4, experiment-specific
  public workflows;
- physics data and references: arXiv, INSPIRE, HEPData, PDG, CERN Open Data,
  LHAPDF, Zenodo, experiment public notes;
- figure and writing tools: matplotlib/ROOT plots, LaTeX equations, notebooks,
  markdown, PDF/export pipelines.

### 4. Managed Compute

The near-term product is macOS-first, but the long-term workbench must run where
physics work already runs.

Compute ladder:

1. Local macOS execution with bundled Pythia and local SQLite.
2. Local environment capture for reproducibility.
3. SSH execution on a user-controlled Linux box.
4. HPC login node submission with explicit review before resource use.
5. Optional cloud/on-demand compute only after local and lab infrastructure are
   solid.

Principles:

- ask before using new resources;
- let users review or revoke compute decisions;
- keep sensitive datasets on the user's machine or lab infrastructure;
- send only the minimum context needed to the model;
- make job status, logs, artifacts, failures, and costs visible.

### 5. Physics Specialist Agents

Vidura needs a coordinating agent plus specialist agents. The coordinator should
not pretend to know every workflow itself.

Initial specialist agents:

- simulation planner: maps physics intent to run specs and assumptions;
- codegen and repair: writes and patches analysis code;
- run executor: compiles, executes, watches logs, and captures evidence;
- plotting and artifact agent: creates and edits publication-quality figures;
- physics reviewer: checks statistical power, units, cuts, samples, artifacts,
  and interpretation;
- literature agent: queries and cites arXiv/INSPIRE/PDG/HEPData;
- compute agent: prepares local, SSH, and HPC jobs with user approval.

The reviewer agent is a product feature, not an internal nice-to-have. It should
flag untraceable numbers, figures that do not match code, missing citations,
low-statistics samples, misleading cuts, and unsupported physical claims.

### 6. Reusable Lab Skills

Physicists and labs already have trusted pipelines. Vidura should let users turn
validated workflows into reusable skills.

Examples:

- "minimum-bias Pythia sanity run";
- "compare generated pT spectrum against HEPData";
- "Rivet validation for a named analysis";
- "make a publication figure with this lab style";
- "produce a systematic-uncertainty checklist";
- "write a literature-backed analysis note section."

Future sessions should inherit these skills without the user reconstructing
context every time.

## Current Baseline

Completed:

- OpenAI-backed macOS agent path.
- Local build/run script and Codex Run action.
- Local Pythia execution.
- Multi-chart output path.
- Run Evidence / Provenance UI and artifact persistence.
- Exact rerun from audited source/spec.
- Compare two completed runs side by side.
- Export a run bundle with source, logs, summary, charts, and metadata.
- Parameterized rerun for event count, seed, and `PhaseSpace:pTHatMin`.
- Run lineage and one-click Compare to Source for exact reruns and variants.
- Script-based reproducibility regression harness:
  `./script/reproducibility_regression.sh`.
- Deterministic Run Quality / Sanity Checks in Run Evidence and exported
  bundles.
- Physics Reviewer Agent v1 in completed-run flow, Run Evidence, exports, and
  the regression harness.
- HEP Source Connectors v1 with typed arXiv, INSPIRE, HEPData, and PDG
  reference models, fixture-tested parsers, baseline `reference_pack.json`
  evidence, Run Evidence display, and export metadata.
- HEP Reference Pack Retrieval v1 with an explicit completed-run refresh action,
  deterministic query construction, bounded arXiv/INSPIRE/HEPData/PDG retrieval,
  per-source statuses, persisted refreshed `reference_pack.json`, compact Run
  Evidence status chips, and fixture-backed regression coverage.
- Reference-Grounded Physics Reviewer v2 with persisted reference-pack input,
  sanitized `reference_ids`, deterministic citation-gap fallbacks, compact
  reference ID chips in reviewer findings, and export preservation of reviewer
  reference IDs.

This is a strong Phase 0/1 foundation. It is still far from the workbench
benchmark because users cannot yet inspect and edit planned physics assumptions
before execution, and it still lacks managed compute, native physics artifact
viewers, richer review workflows, and publication workflows.

## Execution Principles

- macOS first, but architect toward local/SSH/HPC compute.
- Local physics execution is a product strength, not an implementation detail.
- Prefer narrow, compounding slices over broad rewrites.
- Every visible scientific claim should have evidence.
- Every generated artifact should carry provenance.
- Deterministic checks and fixtures should protect core physics contracts.
- OpenAI calls should be structured where possible, with deterministic fallbacks
  for supported workflows.
- Do not add physics breadth before the run record and reviewer loop are
  trustworthy.

## Roadmap Phases

### Phase 0: Stabilize The Science Loop

Goal: one user prompt reliably produces a readable, inspectable local Pythia
run.

Status: mostly complete.

Completed:

- OpenAI-backed guide, intent, codegen, summary, and naming path.
- Basic Pythia execution.
- Deterministic codegen fallback.
- Multi-chart artifacts.
- Evidence persistence and historical disk discovery.
- Build, launch, and regression scripts.

Remaining:

- remove duplicate vendor/local baggage such as `pythia_dist 2`;
- clean up stale bootstrap paths that are no longer active.

### Phase 1: Make Runs Repeatable

Goal: users can rerun, branch, compare, export, and cite a run.

Status: mostly complete.

Completed:

- exact rerun;
- parameterized rerun;
- run compare;
- run export bundle;
- lineage/reproducibility surface;
- reproducibility regression harness.

Remaining:

- make run bundles more portable as cited artifacts.

### Phase 2: Add The Physics Reviewer Loop

Goal: completed analyses are trustworthy enough for exploratory physics work.

Status: mostly complete for the first Pythia workbench loop.

Completed:

- deterministic Run Quality / Sanity Checks;
- quality findings in Run Evidence and exports;
- checks for low statistics, missing artifacts, event-count mismatches, overflow,
  suspicious cuts, process/sample mismatch, and log warning/error markers;
- regression coverage for deterministic quality rules.
- model-backed Physics Reviewer Agent that consumes deterministic quality
  findings and checks interpretation text against evidence;
- reviewer checks for unit issues, figure/summary mismatch, untraceable
  numbers, missing citations, and unsupported physical claims;
- reviewer findings in Run Evidence and exports;
- structured reviewer output that downstream agents must respect;
- regression coverage for reviewer input shaping, parsing, and fallback paths.
- reviewer checks that consume persisted HEP reference packs and distinguish
  artifact-backed, citation-backed, and unsupported claims;
- sanitized reviewer `reference_ids` that can only point to references present
  in the persisted pack;
- deterministic fallback warnings for missing reference packs, failed/partial
  source coverage, citation-sensitive overclaims, and external-measurement
  claims without support;
- reviewer reference IDs in Run Evidence, `physics_reviewer.json`, exported
  `manifest.json`, and `run_report.md`.

Needed:

- fresh smoke runs that exercise persisted reference-grounded reviewer artifacts
  end to end;
- reviewer checks that compare generated distributions to actual public data
  once HEPData comparison is available.

The next trust gap is now upstream of execution. Vidura can review completed
runs, but users still need to inspect and edit the generated physics plan before
spending time on a simulation.

### Phase 3: Become Domain-Ready For HEP

Goal: Vidura understands common HEP workflows and sources on day one.

Status: started.

Completed:

- typed `HEPReference`, `HEPReferencePack`, and `HEPReferenceSource` models;
- parser/helper layer for arXiv, INSPIRE, HEPData, and PDG;
- deterministic reference-pack assembler with DOI/arXiv/INSPIRE/HEPData/URL
  and title dedupe while preserving source attribution and IDs;
- baseline `reference_pack.json` evidence for completed runs;
- compact References block in Run Evidence;
- reference-pack metadata in exported run bundles;
- fixture regression coverage for parsing, normalization, dedupe, and export
  serialization.
- user-triggered live retrieval/refresh using arXiv, INSPIRE, HEPData, and PDG;
- deterministic reference query construction from run title, prompt,
  `simulation_spec.json`, process/cut context, observables, and chart titles;
- per-source refresh statuses for success, skipped, failed, and partial-failure
  states;
- refreshed `reference_pack.json` persistence without a schema migration;
- compact Run Evidence status chips for refreshed source counts and failures;
- fixture regression coverage for query construction, merge behavior, partial
  failures, and status serialization.
- reviewer/summary stages that consume real reference packs for citation-aware
  findings without calling live source APIs during review or export.

Needed:

- connectors for CERN Open Data, LHAPDF, and relevant experiment public
  repositories;
- analysis templates for common Pythia/Rivet/ROOT tasks;
- import/export for common formats: ROOT, HepMC, LHE, YODA, CSV/Parquet,
  JSON summaries, LaTeX snippets;
- HEP-specific artifact viewers for histograms, event records, tables, and
  equations;
- citation-aware literature and data retrieval;
- comparison against public reference measurements where available.

### Phase 4: Managed Compute And Environment Capture

Goal: Vidura can run real physics workloads where the user's compute lives.

Needed:

- local job queue with resumable status and artifact collection;
- explicit environment capture for local runs;
- SSH runner for user-controlled Linux machines;
- HPC job-draft and submit workflow with user approval;
- remote artifact sync back into the same evidence model;
- failure triage for compile, runtime, scheduler, filesystem, and environment
  errors.

### Phase 5: Research Workspace And Publication Outputs

Goal: projects become durable scientific notebooks, not chat logs.

Needed:

- notebook-style project pages with runs, figures, notes, equations, and
  citations;
- figure editor that edits code and preserves provenance;
- manuscript/analysis-note drafting with citation and calculation reviewer;
- export to PDF/Markdown/LaTeX and reproducible run bundles;
- artifact search across projects;
- reviewer-agent audit pass before export.

### Phase 6: Custom Skills And Lab Workflows

Goal: users can encode lab-specific physics workflows once and reuse them.

Needed:

- skill creation from validated pipelines;
- connector framework for private datasets and lab tools;
- versioned workflow templates;
- reusable analysis presets and style guides;
- team/lab sharing and review controls later.

### Phase 7: Physics Beyond HEP

Goal: expand only after HEP workbench foundations are strong.

Candidate domains:

- cosmology and astrophysics;
- condensed matter;
- quantum information;
- plasma physics;
- nuclear physics;
- lattice/QFT workflows.

Expansion should follow the same pattern: trusted domain tools, auditable
artifacts, compute integration, specialist agents, and reviewer checks.

## Current Next Slice

Analysis Plan Editor v1.

Why: Vidura should not be a black-box run button. The workbench now produces
auditable runs and reviewer findings after execution, but users still cannot
inspect and adjust the generated physics assumptions before execution. The next
step is a compact pre-run review surface for the deterministic `SimulationSpec`
and `AnalysisPlan` so a user can accept, edit, or cancel before Pythia work
starts.

Scope:

- add a pre-execution Analysis Plan review state after intent/planning and
  before codegen/runner;
- surface the generated plan in the existing thread UI with editable fields for
  event count, seed, process settings, cuts, observables/output files, and
  analysis-family assumptions;
- support Accept Run, Edit & Run, and Cancel without introducing a schema
  migration;
- persist the accepted/edited plan into the existing run evidence path as
  `simulation_spec.json` and record whether the plan was user-edited in run
  configuration or evidence metadata;
- reuse existing parameterized-rerun editing helpers where they fit, but do not
  collapse this into rerun-only behavior;
- add deterministic validation for edits before codegen so malformed cuts,
  empty observables, invalid event counts, and duplicate output files do not
  reach the runner;
- keep exact rerun, parameterized rerun, export, reviewer, reference refresh,
  and the regression harness behavior intact;
- add fixture-driven regression coverage for plan edit validation and spec
  serialization.

## Next 8 Product Slices

1. Analysis Plan Editor so users can review/edit assumptions before execution.
2. Native physics artifact viewer upgrades: richer histograms, tables, and
   event-output inspection.
3. Reusable HEP analysis templates and skills.
4. Public-data comparison v1 against HEPData where compatible observables exist.
5. Local compute session model with environment capture, preparing for SSH/HPC.
6. Portable cited run bundles with stronger manifest/environment capture.
7. Publication/analysis-note export with reviewer-gated claims.
8. Formalize the script regression harness into an Xcode test target.

## Non-Goals

- Do not become a generic chat app.
- Do not optimize for chemistry or biology workflows.
- Do not make cloud execution the default before local and lab infrastructure
  are reliable.
- Do not add broad physics domains before HEP workflows are credible.
- Do not treat model-written explanations as scientific evidence unless they are
  linked to artifacts, citations, or calculations.

## GitHub Operating Model

The active repo is `https://github.com/akassh9/vidura-labs`. Implementation
agents should branch from current `main`, use a `codex/` branch name, open a PR,
and report validation. The CTO/user verifies and merges. Direct pushes to
`main` are not the default workflow.
