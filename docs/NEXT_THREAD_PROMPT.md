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

Your task: implement the next slice, Analysis Plan Editor v1.

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
- The gap: users still cannot inspect or adjust the generated `SimulationSpec` / `AnalysisPlan` before codegen and Pythia execution. This makes the app feel too black-box for a physics workbench.

Implementation target:
1. Add a compact pre-execution Analysis Plan review state after `AnalysisPlannerAgent` produces a `SimulationSpec` and before codegen/runner execution.
2. Surface the pending plan in the existing thread UI with editable fields for:
   - event count;
   - random seed;
   - process settings;
   - cuts/settings such as `PhaseSpace:pTHatMin`;
   - observables and output files;
   - analysis family / assumptions.
3. Support three actions:
   - Accept Run: use the generated plan unchanged and continue to existing codegen/runner behavior.
   - Edit & Run: validate edits, then use the edited `SimulationSpec` as the source of truth for codegen and evidence.
   - Cancel: stop the pending execution cleanly without producing a misleading completed run.
4. Persist the accepted/edited spec through the existing evidence path as `simulation_spec.json`.
5. Record whether a plan was user-edited in run configuration or evidence metadata without a schema migration if possible.
6. Add deterministic validation before codegen for invalid event counts, invalid seed values, empty observables, unsafe/empty process or cut settings, and duplicate output filenames.
7. Reuse existing parameterized-rerun editing helpers where they fit, but this must work for first-run execution, not only variants.
8. Keep downstream behavior unchanged: generated `run.cc`, charts, evidence, reference packs, Run Quality, Physics Reviewer, Run Compare, exports, exact reruns, and parameterized reruns should all see the accepted/edited spec as the actual run spec.
9. Add fixture-driven regression coverage to `./script/reproducibility_regression.sh` for plan edit validation and spec serialization.

Implementation constraints:
- Keep the UI quiet, dense, and operational. Do not add a wizard or broad redesign.
- Avoid a schema migration unless there is a hard reason.
- Do not route this through OpenAI after the user edits the plan unless existing codegen already does that for execution.
- Do not break exact rerun or parameterized rerun contracts.
- Do not print `.env` or API keys.

Validation:
1. Run `./script/reproducibility_regression.sh`.
2. Run `./script/build_and_run.sh build`.
3. Run `./script/build_and_run.sh --verify`.
4. Confirm launch with `pgrep -x "Vidura Labs"`.
5. Run `git diff --check` and `git diff --cached --check`.
6. Confirm no `.env`, local DBs, DerivedData, generated simulation folders, exported bundles, key/cert-like files, or `.codex/backups` are tracked.
7. Run a diff and staged-diff secret scan before pushing.
8. Push the branch and open a PR against `akassh9/vidura-labs/main`.

Report back with:
- PR URL
- changed files
- validation commands and results
- where the pending-plan state lives
- how Accept Run, Edit & Run, and Cancel work
- which `SimulationSpec` fields are editable
- validation rules added
- how edited specs are persisted and marked
- harness cases added
- any fresh smoke run or why it was skipped
- known gaps or follow-up recommendations
```
