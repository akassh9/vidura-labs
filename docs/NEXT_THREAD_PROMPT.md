# Prompt For Next Thread

Use this prompt in a fresh Codex thread:

```text
You are taking over Vidura Labs as the implementation agent under CTO direction.

Work in the canonical local repo:
- /Users/akash009/vidura
- Source of truth: https://github.com/akassh9/vidura-labs
- Create a codex/ branch and open a PR when done. Do not push directly to main.

Start by reading:
- AGENTS.md
- docs/PROJECT_ORIENTATION.md
- docs/NEXT_THREAD_HANDOFF.md
- docs/CTO_ROADMAP.md

Do not redo the provider migration. The app is macOS-first, OpenAI-backed, and Pythia-focused. The old CLI direction is dropped. Do not print .env or API keys. Do not commit local DBs, DerivedData, generated simulation artifacts, exported bundles, or secrets.

Your task: implement the next slice, Physics Reviewer Agent v1.

Context:
- Run Evidence / Provenance exists.
- Exact Rerun is merged.
- Run Compare is merged.
- Export Run Bundle is merged.
- Parameterized Rerun is merged.
- Run Lineage & Reproducibility Surface is merged.
- Reproducibility Regression Harness is merged.
- Run Quality / Sanity Checks is merged.
- The app can now produce, replay, compare, export, trace, quality-check, and regression-test the run record.
- The next trust gap is interpretation: a completed run can have a plausible-looking summary that overstates the evidence, ignores quality warnings, mislabels cuts/processes, or describes charts/metrics incorrectly.

Implementation target:
1. Build on `RunQualityAnalyzer`; do not duplicate or replace deterministic quality checks.
2. Add a small model-backed `PhysicsReviewerAgent` or equivalent helper using `OpenAIClient` structured output.
3. Add a pure input assembly layer that gathers completed-run evidence:
   - `simulation_spec.json`
   - `summary.json`
   - chart payloads/messages
   - `compile.log` and `run.log` snippets or marker summaries
   - artifact names/sizes/kinds
   - deterministic `RunQualityAnalyzer` findings
   - the final physics summary text
4. Return structured reviewer findings with severity, category, message, and evidence references where possible.
5. Reviewer findings must respect deterministic quality findings. If Run Quality has warnings/errors, the reviewer must not summarize the run as clean.
6. Include deterministic fallback behavior when OpenAI is unavailable or returns malformed output.
7. Surface compact reviewer findings in Run Evidence near the Run Quality block. Keep the UI dense and operational.
8. Include reviewer notes in Export Run Bundle if this fits the current exporter without a broad refactor.
9. Add regression coverage to `./script/reproducibility_regression.sh` for pure input construction, response parsing, and fallback behavior. Do not make the harness depend on a live OpenAI call.
10. Keep Evidence, Exact Rerun, Parameterized Rerun, Compare, Export, Lineage, Run Quality, and the existing regression harness working.

Reviewer categories to prioritize:
- unsupported or overconfident physics interpretation
- summary claims that conflict with chart payloads or `summary.json`
- missing citations/reference data when comparing to real measurements
- unit or observable-name ambiguity
- deterministic quality warnings that the final summary ignores
- cuts/process choices that make inclusive/minimum-bias wording misleading

Implementation constraints:
- No schema migration unless you can justify why existing messages, artifacts, or run configuration cannot carry the first reviewer notes.
- Avoid broad UI redesign. Add a compact operational block to the existing Run Evidence surface.
- Avoid live OpenAI calls in the regression harness.
- Do not print `.env` or API keys.

Validation:
1. Run `./script/build_and_run.sh build`.
2. Run `./script/build_and_run.sh --verify`.
3. Run `./script/reproducibility_regression.sh`.
4. Use existing runs if useful:
   - source: `55C18C16-54E4-4A3C-BFFE-DEEE030A7459`
   - exact rerun: `98CA353A-941B-4B5A-B6A6-070D89FDE59F`
   - variant: `B28DBDBC-B49D-4F40-AC6B-7F85113744B1`
5. Run `git diff --check`.
6. Confirm no `.env`, local DBs, DerivedData, generated simulation folders, exported bundles, key/cert-like files, or `.codex/backups` are tracked.
7. Push the branch and open a PR against `akassh9/vidura-labs/main`.

Report back with:
- PR URL
- changed files
- validation commands and results
- reviewer categories implemented
- where reviewer findings are surfaced
- whether reviewer notes are included in exports
- harness cases added
- known gaps or follow-up recommendations
```
