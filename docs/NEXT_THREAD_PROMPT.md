# Prompt For Next Thread

Use this prompt in a fresh Codex thread from `/Users/akash009/vidura`:

```text
You are taking over Vidura Labs in `/Users/akash009/vidura`.

Act as the implementation agent under the project CTO direction. Start by reading:
- `/Users/akash009/vidura/AGENTS.md`
- `/Users/akash009/vidura/docs/PROJECT_ORIENTATION.md`
- `/Users/akash009/vidura/docs/NEXT_THREAD_HANDOFF.md`
- `/Users/akash009/vidura/docs/CTO_ROADMAP.md`

Do not redo the provider migration. The app is macOS-first, OpenAI-backed, and Pythia-focused. The old CLI direction is dropped. Do not print `.env` or API keys. Do not revert uncommitted changes unless I explicitly ask.

Your task: implement the next slice, Smoke-gated Reproducible Runs.

Context: the previous thread implemented Run Evidence / Provenance. Build and launch passed, but no fresh GUI Pythia smoke was run after that slice. Before adding more features, prove the new run evidence path works on a fresh run.

Stage 1: Fresh smoke and fix fallout.
1. Build/launch if needed with `./script/build_and_run.sh --verify`.
2. Run a fresh app smoke with:
   `pp collisions at 13 TeV, 10,000 minimum-bias events, measuring charged-particle multiplicity, pT spectrum`
   If GUI automation is impractical, ask me to submit that prompt in the running app, then inspect the DB and artifacts afterward.
3. Verify the new run has completed status, multiple chart messages, evidence artifacts for `run.cc`, `simulation_spec.json`, `summary.json`, `summary_lines.txt`, `compile.log`, `run.log`, and plot/table outputs.
4. Verify the evidence panel can inspect/copy/reveal those artifacts.
5. Fix any direct fallout before moving on.

Stage 2: Exact rerun.
If Stage 1 is clean, add a `Rerun Exact` action for completed simulation runs:
1. Load the existing run's `simulation_spec.json` and `run.cc` from persisted evidence.
2. Create a new sibling run in the same thread.
3. Execute the same generated source through `RunnerService` without using OpenAI guide/intent/codegen.
4. Persist result messages, chart messages, summary, and all evidence artifacts for the new run.
5. Keep the rerun deterministic and evidence-driven.
6. Build with `./script/build_and_run.sh build`.
7. Verify launch with `./script/build_and_run.sh --verify`.

Acceptance criteria:
- Fresh smoke proves multi-chart and evidence persistence on a new run.
- `Rerun Exact` creates a new run with its own run ID, messages, artifacts, and run folder.
- Exact rerun bypasses OpenAI planning/codegen and uses the audited source/spec.
- Historical runs still render.
- No secrets are printed.

Be the driver. If the smoke exposes a more important direct blocker, fix that before implementing rerun.
```

