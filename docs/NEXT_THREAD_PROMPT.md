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
- docs/HEP_CORRECTNESS_BENCHMARK.md

Do not redo the provider migration. The app is macOS-first, OpenAI-backed, and Pythia-focused. The old CLI direction is dropped. Do not print .env or API keys. Do not commit local DBs, DerivedData, generated simulation artifacts, exported bundles, benchmark reports, or secrets.

Strategic direction:
- Vidura should not compete on "AI writes Pythia code." That is commodity model behavior.
- The wedge is correctness verification for computational HEP.
- The model provider should stay swappable. The durable asset is a benchmark/corpus of verified HEP runs, failures, corrections, and reviewer judgments.

Your task: implement the next slice, HEP Correctness Benchmark Harness v0.

Context:
- Run Evidence / Provenance exists.
- Exact Rerun is merged.
- Run Compare is merged.
- Export Run Bundle is merged.
- Parameterized Rerun is merged.
- Run Lineage & Reproducibility Surface is merged.
- Reproducibility Regression Harness is merged.
- Run Quality / Sanity Checks is merged.
- Physics Reviewer Agent v1 is merged.
- HEP Source Connectors v1 is merged.
- HEP Reference Pack Retrieval v1 is merged.
- Reference-Grounded Physics Reviewer v2 is merged.
- The app can now run, rerun, compare, export, refresh references, and review completed runs against artifacts and references.
- The gap: we need benchmarkable proof that Vidura catches HEP correctness failures that general AI workflows miss.

Implementation target:
1. Add a benchmark fixture directory, likely `benchmarks/hep_correctness/`, with a documented task schema.
2. Add a local benchmark runner script, likely `./script/hep_correctness_benchmark.sh`.
3. Keep v0 deterministic and offline: no live OpenAI calls and no live network/source calls.
4. Include at least 10 initial HEP correctness fixtures covering:
   - low event statistics;
   - missing expected evidence;
   - empty declared output files;
   - event-count mismatch;
   - histogram overflow;
   - hard-process or `PhaseSpace:pTHatMin` cuts described as inclusive/minimum-bias;
   - unsupported external-measurement or published-result claims;
   - missing citations/reference coverage;
   - invented or irrelevant reference IDs;
   - figure/summary mismatch;
   - unit or observable ambiguity.
5. Reuse existing pure analyzer/reviewer code where possible:
   - `RunQualityAnalyzer`
   - `PhysicsReviewerAgent`
   - `HEPReferencePack` / `HEPReferences.swift`
   - existing regression harness patterns in `script/reproducibility_regression/`
6. Score Vidura findings against expected benchmark findings:
   - category match;
   - severity match;
   - evidence reference coverage;
   - reference ID coverage where applicable.
7. Emit a machine-readable report and human-readable report, for example:
   - `benchmark-results/hep_correctness/report.json`
   - `benchmark-results/hep_correctness/report.md`
   The output directory must be ignored and not committed.
8. Include competitor-output fixture slots in the schema so later slices can compare Vidura against ChatGPT/Claude/other general AI outputs without adding live model calls to v0.
9. Keep existing Evidence, Exact Rerun, Parameterized Rerun, Compare, Export, Lineage, Run Quality, Physics Reviewer, HEP References, Refresh References, and the reproducibility regression harness working.

Implementation constraints:
- Do not add live model calls to the benchmark runner.
- Do not add live network/source calls to the benchmark runner.
- Do not commit generated benchmark reports.
- Keep fixture artifacts small and text-based.
- Avoid broad app UI changes in this slice.
- Do not print `.env` or API keys.

Validation:
1. Run `./script/hep_correctness_benchmark.sh`.
2. Run `./script/reproducibility_regression.sh`.
3. Run `./script/build_and_run.sh build`.
4. Run `./script/build_and_run.sh --verify`.
5. Confirm launch with `pgrep -x "Vidura Labs"`.
6. Run `git diff --check` and `git diff --cached --check`.
7. Confirm no `.env`, local DBs, DerivedData, generated simulation folders, exported bundles, benchmark reports, key/cert-like files, or `.codex/backups` are tracked.
8. Run a diff and staged-diff secret scan before pushing.
9. Push the branch and open a PR against `akassh9/vidura-labs/main`.

Report back with:
- PR URL
- changed files
- benchmark task schema
- fixture categories included
- scoring behavior
- benchmark report output paths
- validation commands and results
- whether the benchmark is fully offline
- known gaps or follow-up recommendations
```
