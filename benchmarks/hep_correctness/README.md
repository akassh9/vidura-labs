# HEP Correctness Benchmark

This directory contains deterministic, offline fixtures for Vidura's HEP
correctness benchmark. The benchmark exercises existing pure correctness
surfaces:

- `RunQualityAnalyzer` for artifact, statistics, cut, log, and output checks.
- `PhysicsReviewerAgent` parsing/fallback helpers for reviewer findings and
  reference ID sanitization.
- `HEPReferencePack` models for persisted citation/reference context.

Run it from the repository root:

```sh
./script/hep_correctness_benchmark.sh
```

Generated reports are written to ignored paths:

```text
benchmark-results/hep_correctness/report.json
benchmark-results/hep_correctness/report.md
```

## Task Schema

Each task in `tasks/*.json` is a small synthetic completed-run fixture:

```json
{
  "id": "low_statistics_minbias",
  "title": "Low-statistics charged multiplicity claim",
  "category": "low_statistics",
  "prompt": "User-facing task or analysis request.",
  "fixtures": {
    "run_metadata": {
      "id": "run id",
      "title": "run title",
      "status": "completed",
      "event_count": 200,
      "configuration": {}
    },
    "simulation_spec": {
      "event_count": 200,
      "analysis_family": "charged_multiplicity",
      "output_files": ["hist_primary.txt"],
      "process_settings": ["SoftQCD:nonDiffractive = on"],
      "cuts_settings": []
    },
    "summary_metrics": {
      "generated_events": "200"
    },
    "artifacts": [
      {
        "label": "summary.json",
        "kind": "evidence",
        "path": "summary.json",
        "byte_size": 128
      }
    ],
    "compile_log": "",
    "run_log": "",
    "chart_payloads": [],
    "reference_pack": null,
    "assistant_interpretation": "Final result text to review.",
    "offline_reviewer_response": {
      "findings": []
    }
  },
  "expected_findings": [
    {
      "category": "low_statistics",
      "severity": "warning",
      "must_include": ["low event count"],
      "evidence_refs": ["event_count=200"],
      "reference_ids": []
    }
  ],
  "competitor_outputs": [
    {
      "label": "general_ai_baseline",
      "interpretation": "Placeholder for later head-to-head model output.",
      "known_failures": ["misses low event count"]
    }
  ],
  "notes": "Why this task matters."
}
```

The fixture may omit `offline_reviewer_response`. In that case the runner uses
the deterministic reviewer fallback only. When `offline_reviewer_response` is
present, the runner parses it through `PhysicsReviewerAgent.parseResponseJSON`
with the supplied reference pack so reference IDs are sanitized exactly as they
are in the app.

## Scoring

For each expected finding, the runner requires:

- benchmark category match;
- severity match;
- all required message substrings;
- all required evidence references;
- all required reference IDs.

The report also includes false-positive counts and fails the command if any
expected finding is missed or any emitted reviewer reference ID is not present
in the fixture reference pack.
