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

Your task: implement the next slice, Run Lineage & Reproducibility Surface.

Context:
- Run Evidence / Provenance exists.
- Exact Rerun is merged.
- Run Compare is merged.
- Export Run Bundle is merged.
- Parameterized Rerun is merged.
- The problem now is product coherence: the app can create exact reruns and variants, compare runs, and export bundles, but the relationships between runs are not visible enough.

Implementation target:
1. Keep this slice inside the current data model unless a hard blocker appears. Prefer existing run configuration, messages, titles, and evidence over a migration.
2. Add a small lineage resolver for simulation runs.
3. Detect parameterized variants via configuration key `Vidura:variantOfRunID`.
4. Detect variant changes via `Vidura:variantChanges`.
5. Add exact-rerun provenance going forward by recording a configuration key such as `Vidura:exactRerunOfRunID` in `OrchestratorService.rerunExact(run:)`.
6. For historical exact reruns, infer source cautiously from existing request messages like `Rerun exact from run <id>` when available.
7. In Run Evidence cards, show a compact reproducibility row:
   - original / exact rerun / variant
   - source run short ID when derived
   - parameter changes when present
8. Add a direct Compare to Source action for exact reruns and variants. It should switch the side panel to Run Compare and preselect source + derived run.
9. In Run Compare, show source/derived relationship context when the selected pair has a lineage relationship.
10. Keep Exact Rerun, Parameterized Rerun, Compare, and Export behavior working.

Validation:
1. Run `./script/build_and_run.sh build`.
2. Run `./script/build_and_run.sh --verify`.
3. Use existing runs if available:
   - source: `55C18C16-54E4-4A3C-BFFE-DEEE030A7459`
   - exact rerun: `98CA353A-941B-4B5A-B6A6-070D89FDE59F`
   - variant: `B28DBDBC-B49D-4F40-AC6B-7F85113744B1`
4. Verify the variant shows its source run and changes.
5. Verify the exact rerun either records or infers its source.
6. Verify Compare to Source preselects the intended pair.
7. Verify Run Compare displays relationship context for source/derived pairs.
8. Run `git diff --check`.
9. Confirm no `.env`, local DBs, DerivedData, generated simulation folders, exported bundles, key/cert-like files, or `.codex/backups` are tracked.
10. Push the branch and open a PR against `akassh9/vidura-labs/main`.

Report back with:
- PR URL
- changed files
- validation commands and results
- source/derived runs used for verification
- exact-rerun provenance behavior
- Compare to Source behavior
- known gaps or follow-up recommendations
```
