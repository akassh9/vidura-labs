# Prompt For Next Thread

Use this prompt in a fresh Codex thread:

```text
You are taking over Vidura Labs as the implementation agent under CTO direction.

Use the active repo, not the old hackathon remote:
- Source of truth: https://github.com/akassh9/vidura-labs
- Work from a fresh clone or a checkout whose `git remote -v` points at `akassh9/vidura-labs`
- Create a `codex/` branch and open a PR when done. Do not push directly to main.

Start by reading:
- AGENTS.md
- docs/PROJECT_ORIENTATION.md
- docs/NEXT_THREAD_HANDOFF.md
- docs/CTO_ROADMAP.md

Do not redo the provider migration. The app is macOS-first, OpenAI-backed, and Pythia-focused. The old CLI direction is dropped. Do not print `.env` or API keys. Do not commit local DBs, DerivedData, generated simulation artifacts, exported bundles, or secrets.

Your task: implement the next slice, Parameterized Rerun.

Context:
- Run Evidence / Provenance exists.
- Fresh smoke-gated reproducible runs are complete.
- Exact rerun from persisted `simulation_spec.json` and `run.cc` is complete.
- Run Compare is merged.
- Export Run Bundle is merged.
- The next trust layer is controlled variation: a user should be able to take an audited completed run, change event count and random seed, optionally adjust a simple cut, run a sibling simulation, then compare/export it.

Implementation target:
1. Add a controlled variant action for completed simulation runs from the Run Evidence surface.
2. Load the source run's persisted `simulation_spec.json` from evidence.
3. Let the user change at least:
   - event count
   - random seed
4. Support `PhaseSpace:pTHatMin` as the first editable simple cut if it is already present or if adding one is straightforward.
5. Create a modified `SimulationSpec` with a new `run_id`.
6. Generate deterministic C++ from the modified spec with `CodegenAgent`; do not reuse the old exact `run.cc`.
7. Create a new sibling run in the same thread.
8. Execute through the normal `RunnerService` path so the new run gets normal messages, charts, summaries, and evidence artifacts.
9. Record the source run ID and modified parameters in the new run configuration or evidence/event trace.
10. Do not call OpenAI guide/intent/codegen for this parameterized rerun path.

UX expectations:
- Add a small sheet or popover from the Evidence card.
- Show current event count and seed.
- Provide a "new random seed" affordance.
- Show pT-hat minimum when present, or allow adding/removing that simple cut if the implementation stays small.
- Provide Cancel and Run Variant actions.
- Keep Exact Rerun, Compare, and Export behavior working.

Validation:
1. Run `./script/build_and_run.sh build`.
2. Run `./script/build_and_run.sh --verify`.
3. Use an existing completed smoke run if available, such as `55C18C16-54E4-4A3C-BFFE-DEEE030A7459` or `98CA353A-941B-4B5A-B6A6-070D89FDE59F`, to create a parameterized rerun with a changed seed and smaller event count.
4. Verify the new run completes and persists:
   - its own run ID
   - modified `simulation_spec.json`
   - generated `run.cc`
   - charts
   - summary
   - evidence artifacts
5. Compare source and variant in Run Compare.
6. Export the variant bundle and inspect `manifest.json`.
7. Run `git diff --check`.
8. Confirm no `.env`, local DBs, DerivedData, generated simulation folders, exported bundles, key/cert-like files, or `.codex/backups` are tracked.
9. Push the branch and open a PR against `akassh9/vidura-labs/main`.

Report back with:
- PR URL
- changed files
- validation commands and results
- source run ID and variant run ID
- exact parameter changes tested
- compare/export verification notes
- known gaps or follow-up recommendations
```
