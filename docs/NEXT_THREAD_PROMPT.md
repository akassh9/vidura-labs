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

Your task: implement the next slice, Reproducibility Regression Harness.

Context:
- Run Evidence / Provenance exists.
- Exact Rerun is merged.
- Run Compare is merged.
- Export Run Bundle is merged.
- Parameterized Rerun is merged.
- Run Lineage & Reproducibility Surface is merged.
- The app now has a real reproducible run loop, but too much of it is protected only by manual smoke validation.

Implementation target:
1. Audit the current Xcode project/test setup first. There may be no existing test target.
2. Add the smallest maintainable repeatable regression path for deterministic reproducibility contracts.
3. Prefer a real XCTest target if it can be added cleanly. If that is too much project-file churn for one slice, add a project-local verification script that can be promoted into XCTest later.
4. Do not rely on GUI clicking. Do not call OpenAI from the harness.
5. Extract pure helpers only where needed for testability. Avoid a broad view refactor.
6. Cover these contracts if practical:
   - `RunnerService.parseSummaryLines`
   - deterministic `CodegenAgent.run(spec:)` output for event count, seed, `PhaseSpace:pTHatMin`, `hist_primary.txt`, and `hist_pt.txt`
   - run lineage for original, variant, new exact rerun, and historical inferred exact rerun fixtures
   - export manifest expectations for completed smoke fixtures, if exporter logic can be reached without UI
7. If `RunLineageResolver` or export manifest assembly needs to move out of `ResearchThreadDetailView.swift` to be tested, make that extraction small and behavior-preserving.
8. Keep Evidence, Exact Rerun, Parameterized Rerun, Compare, Export, and Lineage behavior working.

Validation:
1. Run `./script/build_and_run.sh build`.
2. Run `./script/build_and_run.sh --verify`.
3. Run the new regression command you add.
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
- test or harness command added
- contracts covered
- any helpers extracted for testability
- known gaps or follow-up recommendations
```
