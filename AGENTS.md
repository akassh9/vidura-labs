# Vidura Labs Codex Notes

## Project Shape

Vidura Labs is a native macOS SwiftUI app in `Vidura Labs.xcodeproj`.
The single runnable scheme is `Vidura Labs`, and the app source lives under
`Physics Companion/`.

The active direction is macOS first. The old sponsored-provider hackathon path
and the separate CLI direction are no longer the product baseline.

## Run Path

Use the project-local entrypoint:

```sh
./script/build_and_run.sh
```

Useful modes:

```sh
./script/build_and_run.sh build
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

The Codex app Run action is wired through `.codex/environments/environment.toml`.

## GitHub Workflow

The source-of-truth repo is:

```text
https://github.com/akassh9/vidura-labs
```

Work from a fresh branch off current `main` using the `codex/` prefix. Do not
push directly to `main`. Open a pull request for every implementation slice,
then report the PR URL, validation commands, smoke run IDs, and any known gaps.
The project CTO/user will verify and merge.

Before pushing, check that no secrets, local databases, DerivedData,
Application Support artifacts, `.codex/backups`, key/cert-like files, or
duplicate generated/vendor folders are included.

## Required Local Config

Use a repository-root `.env` file:

```sh
OPENAI_API_KEY=sk-...
```

`.env` is ignored and must never be committed or printed. The run script exports
`VIDURA_REPO_ROOT` so the app can resolve local config when launched from Codex.

## Important Source Areas

- `Physics Companion/Physics_CompanionApp.swift`: app entrypoint.
- `Physics Companion/AppBootstrapView.swift`: startup checks, Pythia install,
  store creation, and orchestrator creation.
- `Physics Companion/ResearchStore.swift`: GRDB persistence for projects,
  threads, runs, messages, artifacts, and branching.
- `Physics Companion/Agents/OpenAIClient.swift`: minimal Responses API client
  and local credential resolution.
- `Physics Companion/Agents/OrchestratorService.swift`: main multi-stage
  pipeline.
- `Physics Companion/Agents/RunnerService.swift`: writes, compiles, runs, and
  parses generated Pythia C++ attempts.
- `Physics Companion/Agents/AnalysisPlannerAgent.swift`: deterministic intent
  to simulation spec mapping.
- `Physics Companion/Agents/CodegenAgent.swift`: deterministic C++ fallback.
- `Physics Companion/Agents/PolicyCheckAgent.swift` and
  `Physics Companion/Agents/PhysicsCheckAgent.swift`: pre-execution gates for
  generated C++.

## Known Hackathon Debt

- `pythia_dist` and `pythia_dist 2` are duplicate vendored Pythia trees. The
  Xcode project only references `pythia_dist`.
- `AppBootstrap.run` in `Appbootstrap.swift` duplicates most of
  `AppBootstrapView.bootstrap()` and is not the active startup path.
- `SettingsStore` persists `api_key`; the active path now also resolves
  `OPENAI_API_KEY` from local environment files for development.
- `moveThreadToProject` deletes and recreates a thread instead of moving it,
  which drops runs/messages.
- The current OpenAI integration uses a thin local client. If the app grows
  toward heavier tool orchestration, revisit the Agents SDK or a service layer.

## Working Rules

- Do not commit secrets, local databases, DerivedData, or generated simulation
  artifacts.
- Prefer keeping simulation-generated files in app support directories at
  runtime.
- Before changing agent contracts, update persistence and UI assumptions in
  tandem: runs, messages, artifacts, and chart payloads are tightly coupled.
- For build/debug work, use `script/build_and_run.sh` rather than ad hoc Xcode
  commands unless narrowing a specific compiler or signing issue.
