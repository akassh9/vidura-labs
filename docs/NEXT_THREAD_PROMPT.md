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

Your task: implement the next slice, HEP Reference Pack Retrieval v1.

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
- The app now has typed `HEPReference`, `HEPReferencePack`, source parsers/helpers for arXiv, INSPIRE, HEPData, and PDG, deterministic baseline `reference_pack.json` artifacts, a References block in Run Evidence, and reference metadata in exports.
- The gap: live fetch helpers exist, but users cannot yet explicitly refresh a run's references from the UI. Normal run completion should not depend on network access.

Implementation target:
1. Add a user-triggered Refresh References action for completed runs, likely in the existing Run Evidence card near the References block.
2. Build deterministic query construction from run title, original prompt/messages, `simulation_spec.json`, analysis family, process settings, and chart labels.
3. Add a small `HEPReferenceRetrievalService` or equivalent helper that calls the existing arXiv, INSPIRE, HEPData, and PDG helpers with bounded result counts.
4. Capture per-source status: success count, skipped, failed reason, and timestamp.
5. Merge live results with the existing baseline pack using `HEPReferencePackAssembler`, preserving all DOI, arXiv, INSPIRE, HEPData, URL, source attribution, and tags.
6. Persist the refreshed `reference_pack.json` artifact and update Run Evidence without a schema migration if possible.
7. Show compact retrieval state in the References block: last refreshed time, source counts, and partial failures.
8. Keep Export Run Bundle deterministic. It should serialize the persisted reference pack only and must not call live source APIs during export.
9. Add fixture-driven regression coverage to `./script/reproducibility_regression.sh` for query construction, per-source status serialization, partial source failure handling, merge behavior, and no-network fallback.
10. Keep Evidence, Exact Rerun, Parameterized Rerun, Compare, Export, Lineage, Run Quality, Physics Reviewer, HEP References, and the existing regression harness working.

Implementation constraints:
- Do not introduce a parallel reference model. Reuse `HEPReferences.swift`.
- Do not make the regression harness depend on live network calls.
- A small live smoke query is useful if network is available, but it must be separate from the harness and non-blocking if source services are unavailable.
- Refreshing references should be explicit and non-fatal when one source fails.
- No schema migration unless you can justify why artifacts/messages/run configuration cannot carry refresh status.
- Avoid broad UI redesign. Add a compact operational control/state to the existing Run Evidence surface.
- Do not print `.env` or API keys.

Validation:
1. Run `./script/build_and_run.sh build`.
2. Run `./script/build_and_run.sh --verify`.
3. Run `./script/reproducibility_regression.sh`.
4. Run `git diff --check`.
5. Confirm no `.env`, local DBs, DerivedData, generated simulation folders, exported bundles, key/cert-like files, or `.codex/backups` are tracked.
6. Run a diff secret scan before pushing.
7. Push the branch and open a PR against `akassh9/vidura-labs/main`.

Report back with:
- PR URL
- changed files
- validation commands and results
- refresh workflow implemented
- how query construction works
- how partial source failures are surfaced
- whether export behavior changed
- harness cases added
- any live smoke result or why it was skipped
- known gaps or follow-up recommendations
```
