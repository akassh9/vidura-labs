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

Your task: implement the next slice, Reference-Grounded Physics Reviewer v2.

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
- Completed runs persist `reference_pack.json`; users can explicitly refresh it from Run Evidence; refreshed packs include `source_statuses`.
- The gap: `PhysicsReviewerAgent` still mostly reviews against run artifacts and deterministic quality findings. It should now consume persisted HEP reference packs so it can distinguish artifact-backed claims, citation-backed claims, and unsupported claims.

Implementation target:
1. Extend the pure reviewer input/evidence builder to include persisted `reference_pack.json` content when available: query, tags, references, URLs, DOI/arXiv/INSPIRE/HEPData IDs, source attribution, and `source_statuses`.
2. Update `PhysicsReviewerAgent` structured output and prompt so reviewer findings can attach reference IDs from the provided pack. The model must not invent citations or cite references not present in the pack.
3. Add deterministic fallback checks for:
   - missing reference pack on a completed run;
   - failed or partial source refresh statuses;
   - final-summary language that mentions external measurements, literature, PDG, HEPData, arXiv, INSPIRE, citations, or published results without a supporting reference;
   - citation-sensitive overclaims where only local simulation artifacts exist.
4. Keep reviewer execution artifact-only. Do not call arXiv, INSPIRE, HEPData, PDG, OpenAI source retrieval, or Refresh References from the reviewer or export path.
5. Persist the upgraded reviewer result in `physics_reviewer.json` while keeping old reviewer artifacts decodable if the schema changes.
6. Show reference-backed reviewer findings compactly in the existing reviewer area near Run Quality and References. Avoid a broad Run Evidence redesign.
7. Ensure Export Run Bundle preserves reviewer reference IDs in `manifest.json` and `run_report.md`, while continuing to serialize the persisted reference pack only.
8. Add fixture-driven regression coverage to `./script/reproducibility_regression.sh` for reference-pack input shaping, missing-pack fallback, source-status warnings, response parsing with reference IDs, old-artifact decode compatibility if schema changes, and export-style serialization.
9. Keep Evidence, Exact Rerun, Parameterized Rerun, Compare, Export, Lineage, Run Quality, Physics Reviewer, HEP References, Refresh References, and the existing regression harness working.

Implementation constraints:
- Do not introduce a parallel reference model. Reuse `HEPReferences.swift`.
- Do not make the regression harness depend on live network calls or live OpenAI calls.
- Do not trigger live reference refresh from reviewer execution.
- No schema migration unless you can justify why artifacts/messages/run configuration cannot carry this.
- Keep UI quiet and dense. Prefer small reference chips/IDs in existing reviewer rows over a new panel.
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
- how reviewer input now includes reference packs
- structured output/schema changes, if any
- deterministic fallback cases added
- how unsupported or missing-citation claims are surfaced
- export behavior
- harness cases added
- any fresh smoke run or why it was skipped
- known gaps or follow-up recommendations
```
