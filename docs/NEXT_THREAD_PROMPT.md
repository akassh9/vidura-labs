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

Your task: implement the next slice, Run Quality / Sanity Checks.

Context:
- Run Evidence / Provenance exists.
- Exact Rerun is merged.
- Run Compare is merged.
- Export Run Bundle is merged.
- Parameterized Rerun is merged.
- Run Lineage & Reproducibility Surface is merged.
- Reproducibility Regression Harness is merged.
- The app can now produce, replay, compare, export, trace, and regression-test the run record.
- The next trust gap is physics quality: a completed run can still be low-statistics, missing declared outputs, biased by cuts, or internally inconsistent.

Implementation target:
1. Keep this slice deterministic and evidence-driven. Do not call OpenAI for quality analysis.
2. Add a small pure `RunQualityAnalyzer` or similarly named helper that accepts run/spec/summary/artifact/log snapshots and returns structured findings.
3. Use simple severity levels: info, warning, error.
4. First checks should include:
   - completed run has expected evidence: `run.cc`, `simulation_spec.json`, `summary.json`, `summary_lines.txt`, `compile.log`, `run.log`, and declared plot/table files
   - `summary.json` event counts agree with the run event count when present
   - low event count warning for exploratory physics
   - requested output files are missing or empty
   - histogram overflow counters are nonzero when visible in summary data
   - hard-process or `PhaseSpace:pTHatMin` cuts are present while title/family implies inclusive or minimum-bias interpretation
   - run/compile logs contain obvious failure or warning markers despite completed status
5. Surface findings compactly in Run Evidence. Keep the UI dense and operational.
6. Include quality findings in Export Run Bundle if straightforward without broad exporter refactor.
7. Add regression coverage to `./script/reproducibility_regression.sh` for the pure quality analyzer.
8. Keep Evidence, Exact Rerun, Parameterized Rerun, Compare, Export, Lineage, and the existing regression harness working.

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
- quality checks implemented
- where findings are surfaced
- harness cases added
- known gaps or follow-up recommendations
```
