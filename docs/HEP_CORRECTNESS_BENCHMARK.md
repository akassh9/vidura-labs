# HEP Correctness Benchmark

## Purpose

The benchmark exists to prove the product wedge: Vidura is a correctness and
verification layer for computational HEP, not a thin model wrapper.

The v0 benchmark should show whether Vidura catches physics failures that a
general AI workflow can miss: weak statistics, missing evidence, biased cuts,
unsupported agreement claims, invented citations, mismatched figures, ambiguous
units, and untraceable numbers.

## V0 Principles

- Deterministic and offline.
- Fixture-backed, with small text artifacts.
- No live OpenAI calls.
- No live arXiv, INSPIRE, HEPData, PDG, or other network calls.
- Reuse existing pure analyzer and reviewer helpers where practical.
- Generate reports into ignored output paths.
- Fail with a nonzero exit code when expected findings are not detected.

## Current Status

HEP Correctness Benchmark Harness v0 is implemented:

- `./script/hep_correctness_benchmark.sh`
- `benchmarks/hep_correctness/README.md`
- 11 fixtures under `benchmarks/hep_correctness/tasks/`
- generated reports under ignored `benchmark-results/hep_correctness/`

The harness currently proves the offline fixture/scoring shape. The next
milestone is a public-style head-to-head report that compares Vidura findings
against frozen baseline outputs with explicit provenance labels.

## Suggested Layout

```text
benchmarks/hep_correctness/
  README.md
  tasks/
    low_statistics.json
    missing_evidence.json
    event_count_mismatch.json
    histogram_overflow.json
    cut_wording_bias.json
    unsupported_external_claim.json
    missing_citation_coverage.json
    invented_reference_id.json
    figure_summary_mismatch.json
    unit_ambiguity.json

script/hep_correctness_benchmark.sh
script/hep_correctness_benchmark/
  main.swift
```

The exact runner language is flexible. Prefer Swift if app structs can be
reused cleanly; use a smaller aggregation layer only when it reduces harness
fragility.

## Task Schema

Each task should be a checked-in fixture with enough information to run
deterministic checks and score the result.

```json
{
  "id": "low_statistics_minbias",
  "title": "Low-statistics charged multiplicity claim",
  "category": "low_statistics",
  "prompt": "User-facing task or analysis request.",
  "fixtures": {
    "run_metadata": {},
    "simulation_spec": {},
    "summary_json": {},
    "summary_lines": [],
    "artifacts": [],
    "chart_payloads": [],
    "reference_pack": {},
    "assistant_interpretation": ""
  },
  "expected_findings": [
    {
      "category": "statistics",
      "severity": "warning",
      "must_include": ["low event count"],
      "evidence_refs": ["summary.json"],
      "reference_ids": []
    }
  ],
  "competitor_outputs": [
    {
      "label": "general_ai_baseline",
      "interpretation": "",
      "known_failures": []
    }
  ],
  "notes": "Why this task matters."
}
```

The implementation can refine field names, but the benchmark should preserve
these concepts: task identity, synthetic run inputs, expected findings,
optional competitor outputs, and human-readable rationale.

## Initial Categories

V0 should include at least 10 tasks across these categories:

- `low_statistics`
- `missing_evidence`
- `empty_declared_output`
- `event_count_mismatch`
- `histogram_overflow`
- `cut_process_wording`
- `unsupported_external_claim`
- `citation_gap`
- `invented_reference`
- `figure_summary_mismatch`
- `unit_ambiguity`

## Scoring

The first scoring pass should be strict enough to catch regressions but simple
enough to maintain:

- category match;
- severity match;
- required evidence references present;
- required reference IDs present when a reference pack is supplied;
- no invented reference IDs in reviewer findings;
- false-positive count by task;
- aggregate pass/fail summary.

## Reports

Generated reports should live under an ignored path:

```text
benchmark-results/hep_correctness/report.json
benchmark-results/hep_correctness/report.md
```

The JSON report should be machine-readable for future CI and leaderboard work.
The Markdown report should be readable enough to become the seed of a public
benchmark writeup.

## Acceptance Criteria

- `./script/hep_correctness_benchmark.sh` runs offline.
- At least 10 initial fixtures are checked in.
- The runner exits nonzero when expected findings are missed.
- Reports include per-task pass/fail, missing expectations, false positives, and
  aggregate score.
- Existing app validation still passes:
  - `./script/reproducibility_regression.sh`
  - `./script/build_and_run.sh build`
  - `./script/build_and_run.sh --verify`

## Later Milestones

- Add a public benchmark report comparing Vidura against frozen general AI
  output fixtures.
- Replace or augment synthetic baseline outputs with live-captured,
  provenance-labeled model outputs when legally and operationally clean.
- Add HEPData/Rivet/YODA comparisons for published-measurement reproduction.
- Track a growing corpus of verified HEP runs, failures, corrections, and
  reviewer judgments.
- Use the benchmark as the go/no-go proof for whether Vidura has a real
  correctness edge.
