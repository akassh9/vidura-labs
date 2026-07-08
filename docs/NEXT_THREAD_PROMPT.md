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
- benchmarks/hep_correctness/README.md
- script/hep_correctness_benchmark/main.swift

Do not redo the provider migration. The app is macOS-first, OpenAI-backed, and Pythia-focused. The old CLI direction is dropped. Do not print .env or API keys. Do not commit local DBs, DerivedData, generated simulation artifacts, exported bundles, benchmark reports, or secrets.

Strategic direction:
- Vidura should not compete on "AI writes Pythia code." That is commodity model behavior.
- The wedge is correctness verification for computational HEP.
- The model provider should stay swappable. The durable asset is a benchmark/corpus of verified HEP runs, failures, corrections, and reviewer judgments.
- Be explicit and honest about benchmark provenance. Do not claim live ChatGPT, Claude, Research Copilot, or other competitor results unless the exact outputs are real, captured, labeled, and committed with provenance.

Your task: implement the next slice, Public Benchmark Report v0.

Context:
- HEP Correctness Benchmark Harness v0 is merged.
- `./script/hep_correctness_benchmark.sh` runs fully offline.
- The harness has 11 synthetic fixtures under `benchmarks/hep_correctness/tasks/`.
- Current report outputs are generated into ignored paths:
  - `benchmark-results/hep_correctness/report.json`
  - `benchmark-results/hep_correctness/report.md`
- The harness already scores Vidura findings against expected category, severity, required substrings, evidence refs, reference IDs, false positives, and invalid reviewer reference IDs.
- Fixture `competitor_outputs` slots exist, but the harness does not yet produce a real head-to-head Vidura-versus-baseline report.
- The gap: the correctness moat is not legible until the benchmark produces a clear public-style report showing what Vidura caught and what the frozen baseline missed.

Implementation target:
1. Extend the existing benchmark harness, not a new runner.
2. Update the benchmark fixture schema/docs so `competitor_outputs` include explicit provenance and scoring metadata. Use minimal fields such as:
   - `baseline_type`: synthetic, hand_authored, live_captured, or similar;
   - `model_label` or `source_label`;
   - `captured_at` when applicable;
   - `expected_misses` or equivalent IDs/categories tied to benchmark expectations;
   - optional notes explaining why the baseline output is included.
3. Update the existing 11 fixtures with transparent baseline metadata. Keep them small and text-based.
4. Extend `script/hep_correctness_benchmark/main.swift` so `report.json` includes:
   - per-task Vidura score;
   - per-task baseline score/misses;
   - per-task comparison summary;
   - aggregate Vidura expected findings caught;
   - aggregate baseline expected misses/hits;
   - category breakdown;
   - false-positive and invalid-reference summaries.
5. Extend `report.md` with a public-style head-to-head section:
   - short methodology;
   - clear limitations;
   - aggregate table;
   - per-category or per-task comparison table;
   - explicit note that v0 baselines are frozen fixtures unless marked otherwise.
6. Keep generated reports under ignored `benchmark-results/`; do not commit them.
7. Keep the benchmark fully offline: no live OpenAI calls and no live network/source calls.
8. Keep existing Evidence, Exact Rerun, Parameterized Rerun, Compare, Export, Lineage, Run Quality, Physics Reviewer, HEP References, Refresh References, and both benchmark/regression harnesses working.

Implementation constraints:
- Do not add app UI in this slice.
- Do not call live competitor models.
- Do not call live arXiv, INSPIRE, HEPData, PDG, or other network sources.
- Do not make public claims stronger than the fixtures support.
- Do not commit generated benchmark reports.
- Do not print `.env` or API keys.

Validation:
1. Run `./script/hep_correctness_benchmark.sh`.
2. Inspect `benchmark-results/hep_correctness/report.json` and `report.md` and summarize the aggregate head-to-head numbers.
3. Run `./script/reproducibility_regression.sh`.
4. Run `./script/build_and_run.sh build`.
5. Run `./script/build_and_run.sh --verify`.
6. Confirm launch with `pgrep -x "Vidura Labs"`.
7. Run `git diff --check` and `git diff --cached --check`.
8. Confirm no `.env`, local DBs, DerivedData, generated simulation folders, exported bundles, benchmark reports, key/cert-like files, or `.codex/backups` are tracked.
9. Run diff and staged-diff secret scans before pushing.
10. Push the branch and open a PR against `akassh9/vidura-labs/main`.

Report back with:
- PR URL
- changed files
- baseline schema fields added
- report JSON/Markdown additions
- aggregate Vidura-versus-baseline results from the generated report
- validation commands and results
- whether the benchmark remains fully offline
- known gaps or follow-up recommendations
```
