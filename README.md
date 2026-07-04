# Vidura Labs

A native macOS app for running and analyzing high-energy physics simulations with [Pythia 8](https://pythia.org/) and OpenAI.

## Product Direction

Vidura Labs is being rebuilt as a physics-first research companion: start with HEP and Pythia, keep the experience native to macOS first, and make the chat surface capable of planning, running, inspecting, and explaining local simulations.

The current app lets a researcher describe a simulation in plain language. The orchestrator decides whether to answer directly or run a simulation, generates Pythia 8 C++ code, compiles and runs it locally, parses output artifacts, then returns charts and a physics summary in the conversation.

## Requirements

- macOS 14+
- Xcode 16+ or newer Xcode command line tools
- An OpenAI API key

## Local Setup

1. Clone the repository.
2. Add a local `.env` file at the repository root:

   ```sh
   OPENAI_API_KEY=sk-...
   ```

3. Build or run the app:

   ```sh
   ./script/build_and_run.sh build
   ./script/build_and_run.sh
   ```

The run script exports `VIDURA_REPO_ROOT` and loads `OPENAI_API_KEY` for local launches. `.env` is gitignored and must not be committed.

## Agent Pipeline

The current pipeline is hybrid:

| Stage | Role |
|---|---|
| **Guide** | Decide whether to answer, propose a simulation, or run one |
| **Intent** | Convert natural language into a structured Pythia simulation intent |
| **Examples** | Retrieve relevant bundled Pythia examples |
| **Planner** | Build a deterministic simulation spec |
| **Codegen** | Generate Pythia 8 C++ analysis code |
| **Policy / Physics Checks** | Validate generated code before execution |
| **Runner** | Compile and run code locally against bundled Pythia |
| **Plotting** | Convert artifacts into Swift Charts payloads |
| **Physics Summary** | Explain results with deterministic fallback support |

## Supported Analysis Families

- Charged multiplicity distributions
- Transverse momentum spectra
- Pseudorapidity / rapidity distributions
- Invariant mass spectra
- Particle-ID yields
- Event-level scalar observables

## Tech Stack

- **SwiftUI** for the native macOS interface
- **GRDB / SQLite** for local persistence
- **OpenAI Responses API** for guide, intent, codegen, naming, and summary stages
- **Pythia 8** for local Monte Carlo event generation
- **Swift Charts** for inline plots

## Development Notes

- The app intentionally targets macOS first.
- The old sponsored-provider hackathon path has been removed from the active target.
- The CLI direction is not part of this repo's near-term direction.
- Generated simulation artifacts live under Application Support at runtime.
- AI-generated C++ is compiled locally, so prompts and generated code should be treated with care.

## License

All rights reserved.
