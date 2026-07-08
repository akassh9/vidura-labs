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

The strategic wedge is correctness, not generation. Pythia code generation is a
commodity model capability. Vidura's defensible position is the verified side of
the loop: catching physics mistakes, proving claims against artifacts, and
eventually checking generated results against HEPData, Rivet, PDG values, and
published measurements.

The core promise is not "chat with a model" or "AI writes physics code." It is:

> Ask a physics question, get a reproducible scientific work product.

The moat should become:

> A growing benchmark and corpus of verified computational-HEP runs, failures,
> corrections, and reviewer judgments that general AI tools do not have.

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

### 2.5. Verified Correctness, Not Model Wrapping

The wrapper critique is valid if Vidura competes on generation alone. The
product should instead compete on verification in a domain with ground truth.

Near-term correctness assets:

- HEP correctness benchmark tasks with expected findings and traceable ground
  truth;
- head-to-head reviewer scorecards against general AI outputs;
- run artifacts that prove a claim or expose why a claim is wrong;
- public-data comparison paths through HEPData/Rivet/YODA where feasible;
- a proprietary corpus of verified specs, code, outputs, reviewer findings, and
  corrections from real users.

Success means Vidura catches physics errors that a general copilot ships
silently: wrong units, weak statistics, biased cuts, unsupported agreement
claims, invented citations, mismatched figures, and untraceable numbers.

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
- HEP Correctness Benchmark Harness v0 with 11 offline synthetic fixtures,
  deterministic scoring, competitor-output slots, and generated JSON/Markdown
  reports under `benchmark-results/hep_correctness/`.

This is a strong Phase 0/1 foundation. It is also enough to start testing the
real wedge: whether Vidura can catch HEP correctness failures better than a
general-purpose model workflow. It is still far from the full workbench because
it lacks public benchmark proof from real or clearly labeled frozen competitor
outputs, HEPData/Rivet comparison, managed compute, native physics artifact
viewers, richer review workflows, and publication workflows.

## Execution Principles

- macOS first, but architect toward local/SSH/HPC compute.
- Local physics execution is a product strength, not an implementation detail.
- Prefer narrow, compounding slices over broad rewrites.
- Every visible scientific claim should have evidence.
- Every generated artifact should carry provenance.
- Deterministic checks and fixtures should protect core physics contracts.
- Benchmarkable correctness beats feature breadth.
- Treat the reviewer and quality analyzers as the company seed, not a side
  feature.
- Model providers should remain swappable; the durable asset is validated
  physics evidence and correction data.
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

### Phase 2: Prove The Correctness Loop

Goal: show that Vidura catches real HEP mistakes that general AI workflows miss.

Status: benchmark harness foundation complete; public benchmark proof not
started.

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
- HEP Correctness Benchmark Harness v0:
  `./script/hep_correctness_benchmark.sh`;
- 11 fixture tasks covering low statistics, missing evidence, empty outputs,
  event-count mismatch, overflow, misleading process/cut wording, unsupported
  external claims, citation gaps, invented references, figure/summary mismatch,
  and unit ambiguity;
- benchmark scoring for expected category, severity, required message
  substrings, evidence references, reference IDs, false positives, and invalid
  reviewer reference IDs;
- offline JSON/Markdown reports written to ignored
  `benchmark-results/hep_correctness/` paths.

Needed:

- head-to-head evaluation artifacts for Vidura reviewer versus general model
  outputs on the same tasks;
- a public-style benchmark report generated from the harness that clearly
  labels synthetic, frozen, and live-captured baselines;
- fresh smoke runs that exercise persisted reference-grounded reviewer artifacts
  end to end;
- reviewer checks that compare generated distributions to actual public data
  once HEPData comparison is available.

The next trust gap is external proof. The codebase has a promising reviewer
loop and a first benchmark harness; now Vidura needs a report that makes the
correctness claim legible and defensible.

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
- Rivet/YODA and HEPData comparison paths for benchmark-grade validation;
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

Public Benchmark Report v0.

Why: the harness now exists, but the product still needs a credible artifact
that communicates the correctness edge. The next step is to turn the offline
fixtures and competitor-output slots into a transparent head-to-head benchmark
report: Vidura findings versus frozen general-AI baseline outputs, with clear
provenance and no live model dependency.

Scope:

- extend benchmark reporting to produce a public-style summary suitable for a
  README, blog post, or paper appendix;
- score each frozen competitor output against expected task failures without
  adding live model calls;
- make provenance explicit: fixture ID, task category, expected finding, Vidura
  match, competitor miss/hit, and evidence references;
- report aggregate metrics such as expected findings caught, baseline misses,
  false positives, invalid reference IDs, and category breakdown;
- update fixture schema/docs only as needed to distinguish synthetic baseline
  outputs from future live-captured competitor outputs;
- do not claim ChatGPT/Claude/Research Copilot results unless the underlying
  outputs are real, captured, labeled, and committed with provenance;
- keep `./script/hep_correctness_benchmark.sh` deterministic and offline.

## Next 8 Product Slices

1. Public benchmark report v0: Vidura reviewer versus general AI output
   fixtures.
2. Replace or augment synthetic competitor fixtures with live-captured,
   provenance-labeled model outputs where legally and operationally clean.
3. HEPData/Rivet/YODA comparison path for benchmark-grade published-measurement
   reproduction.
4. Analysis Plan Editor so users can review/edit assumptions before execution.
5. Linux/SSH execution lane with environment capture for real HEP stacks.
6. Native physics artifact viewer upgrades: richer histograms, tables, and
   event-output inspection.
7. Reusable HEP analysis templates and skills.
8. Portable cited run bundles with stronger manifest/environment capture.

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
