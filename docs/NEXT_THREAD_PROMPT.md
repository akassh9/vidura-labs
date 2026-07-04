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

Your task: implement the next slice, Export Run Bundle.

Context:
- Run Evidence / Provenance exists.
- Fresh smoke-gated reproducible runs are complete.
- Exact rerun from persisted `simulation_spec.json` and `run.cc` is complete.
- Run Compare is merged in PR #1 and compares completed runs inside the app.
- The next trust layer is portability: a completed run should export into a self-contained bundle that can be shared, cited, archived, or inspected outside the app database.

Implementation target:
1. Add an Export Bundle action for completed simulation runs from the Run Evidence surface.
2. Prefer a folder export for the first slice. Swift has no standard zip API; do not add archive complexity unless the repo already has a clean local pattern.
3. Use persisted evidence artifacts first, while preserving fallback disk discovery for historical runs where practical.
4. Include a machine-readable `manifest.json`.
5. Include a human-readable `README.md` or `run_report.md`.
6. Copy available evidence files into the bundle:
   - `run.cc`
   - `simulation_spec.json`
   - `summary.json`
   - `summary_lines.txt`
   - `compile.log`
   - `run.log`
   - plot/table artifacts such as `hist_primary.txt` and `hist_pt.txt`
7. Keep export deterministic and evidence-driven. Do not call OpenAI for export.
8. If a noncritical artifact is missing, record that in the manifest or UI without failing the entire export.

Manifest should include at least:
- export format version
- export timestamp
- thread ID and run ID
- run title/status/event count
- run created/updated timestamps
- artifact list with relative paths, byte sizes, and artifact type/source
- chart titles and point counts when available
- summary metrics when available
- simulation metadata from `simulation_spec.json` when available

UX expectations:
- The export action should be discoverable from the evidence panel for a completed simulation run.
- After export, provide a clear success state with Copy Path and Reveal in Finder, or use a standard macOS destination panel if that fits the existing SwiftUI/AppKit patterns.
- Existing Evidence and Compare behavior must keep working.

Validation:
1. Run `./script/build_and_run.sh build`.
2. Run `./script/build_and_run.sh --verify`.
3. Use an existing completed smoke run if available, such as `55C18C16-54E4-4A3C-BFFE-DEEE030A7459` or `98CA353A-941B-4B5A-B6A6-070D89FDE59F`, to verify the bundle contents.
4. Run `git diff --check`.
5. Confirm no `.env`, local DBs, DerivedData, generated simulation folders, exported bundles, key/cert-like files, or `.codex/backups` are tracked.
6. Push the branch and open a PR against `akassh9/vidura-labs/main`.

Report back with:
- PR URL
- changed files
- validation commands and results
- run ID used for export verification
- exported bundle file list
- known gaps or follow-up recommendations
```
