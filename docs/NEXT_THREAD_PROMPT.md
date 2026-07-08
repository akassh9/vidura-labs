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

Your task: implement the next slice, HEP Source Connectors v1.

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
- The app can now produce, replay, compare, export, trace, quality-check, and model-review the run record.
- The next trust gap is external grounding: future summaries and reviewers need typed HEP references, public data links, and canonical source attribution instead of generic unsupported claims.

Implementation target:
1. Add typed source models such as `HEPReference`, `HEPReferencePack`, and a source enum covering `arxiv`, `inspire`, `hepdata`, and `pdg`.
2. Add small source-specific connector helpers/clients for:
   - arXiv Atom API search and arXiv ID URL normalization
   - INSPIRE literature search/result normalization
   - HEPData record/search normalization where the public API shape is stable
   - PDG canonical links/search seeds for common particles/constants
3. Add a deterministic reference-pack assembler that merges/dedupes references by DOI, arXiv ID, INSPIRE record ID, HEPData record ID, and URL while preserving all source-specific identifiers.
4. Expose a compact reference pack in the existing research surface. Prefer a small References block or side-panel section over a broad UI redesign.
5. Include reference-pack metadata in Export Run Bundle if this fits without a broad exporter refactor.
6. Add fixture-based regression coverage to `./script/reproducibility_regression.sh` for parsing, normalization, dedupe, and export serialization if included.
7. Do not make the regression harness depend on live network calls.
8. Keep live network failures visible and non-fatal.
9. Keep Evidence, Exact Rerun, Parameterized Rerun, Compare, Export, Lineage, Run Quality, Physics Reviewer, and the existing regression harness working.

Connector result fields to prioritize:
- source
- title
- authors or collaboration
- year
- abstract/snippet
- DOI
- arXiv ID
- INSPIRE record ID
- HEPData record ID
- URL
- tags/observables when available

Implementation constraints:
- No schema migration unless you can justify why existing messages, artifacts, or run configuration cannot carry the first reference pack.
- Avoid broad UI redesign. Add a compact operational reference surface.
- Export should serialize existing reference packs only; export should not perform live network calls.
- If model-assisted query planning is added, it must have deterministic fallback query strings.
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
- connector sources implemented
- how references are surfaced
- whether reference metadata is included in exports
- harness cases added
- known gaps or follow-up recommendations
```
