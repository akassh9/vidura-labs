# Run Audit Bug Report: Chart Fidelity and Clean-Run Interpretation

Date: 2026-07-08
Primary audited run: `07C215FF-363B-45C9-B085-D73F230B11CC`
Context: ad hoc CTO audit outside the normal PR implementation workflow.

## Executive Summary

The audited run completed and preserved the expected evidence bundle, but the
visible scientific interpretation is not reliable enough to treat as a clean
result.

The highest priority bug is chart fidelity: the Charged Multiplicity chart
shown in the UI is not plotting event counts from `hist_primary.txt`. For the
primary audited run, the raw histogram peaks at 2,605 events in the first bin,
but the persisted chart payload stores `y` as the bin center (`3.5`, `11.5`,
`19.5`, ...), producing a false monotonically rising bar chart. This is a
product-critical correctness issue because the UI can show a visually plausible
plot that contradicts the saved artifact.

There are also run-quality and interpretation issues:

- The final assistant summary says the run succeeded without acknowledging
  PYTHIA warnings/errors in `run.log`.
- The request/title uses "minimum-bias", but the generated configuration
  includes `PhaseSpace:pTHatMin = 15.`, so the sample is not fully inclusive
  minimum-bias.
- `compile.log` is present but empty. Current Run Quality flags this as an
  error, but an empty compiler stderr log is usually expected for a clean
  compile. This appears to be a Run Quality rule bug or severity bug, not a
  failed compile.

Recommended priority: fix chart parsing first, then adjust the `compile.log`
quality rule, then tighten planner/summary wording around minimum-bias requests
that receive pT-hat cuts.

## Primary Evidence

Run folder:

```text
~/Library/Application Support/com.AL.PhysicsCompanion/simulations/07C215FF-363B-45C9-B085-D73F230B11CC/attempt_1/
```

Persisted run configuration:

```json
{
  "Beams:eCM": "13000.0",
  "Beams:frameType": "pp",
  "Main:numberOfEvents": "10000",
  "PhaseSpace:pTHatMin": "15.",
  "Random:seed": "217174",
  "SoftQCD:all": "on"
}
```

Expected artifacts are present:

```text
run.cc
simulation_spec.json
summary.json
summary_lines.txt
compile.log
run.log
hist_primary.txt
hist_pt.txt
reference_pack.json
physics_reviewer.json
```

Raw summary metrics are internally consistent:

```json
{
  "generated_events": 10000,
  "mean_charged": 71.197,
  "rms_charged": 76.2145,
  "total_charged_particles": 711970,
  "pt_spectrum_entries": 711970
}
```

Artifact checks:

```text
hist_primary.txt count sum: 10000
hist_pt.txt count sum: 711970
summary.generated_events: 10000
summary.total_charged_particles: 711970
```

This means the event loop and raw artifact writes are not the primary failure.
The failure is downstream interpretation and chart parsing.

## Bug 1: Charged Multiplicity Chart Uses the Wrong Y Values

Severity: P0/P1 for scientific correctness.

For the primary run, `hist_primary.txt` starts with:

```text
# charged_multiplicity histogram
# bin_low bin_high bin_center count
-0.5 7.5 3.5 2605
7.5 15.5 11.5 283
15.5 23.5 19.5 300
```

The persisted chart payload for "Charged Multiplicity" starts with:

```json
[
  { "x_low": -0.5, "x": 3.5, "x_high": 7.5, "y": 3.5 },
  { "x_low": 7.5, "x": 11.5, "x_high": 15.5, "y": 11.5 },
  { "x_low": 15.5, "x": 19.5, "x_high": 23.5, "y": 19.5 }
]
```

The chart uses bin centers as y-values. The correct y-values are counts:

```text
2605, 283, 300, ...
```

Observed UI symptom:

- The Charged Multiplicity chart appears as an almost perfectly rising bar
  chart from low to high `N_ch`.
- The raw histogram is not rising. It has a large low-multiplicity bin and then
  a broad distribution with many zero-count high bins.

Likely root cause:

- `Physics Companion/Agents/PlottingAgent.swift` has a generic parser whose
  comments and assumptions do not match all generated histogram formats.
- The parser documents five-column generated tables as:

```text
bin_low bin_center bin_high count probability
```

- Current generated files commonly use:

```text
bin_low bin_high bin_center count [normalized columns...]
```

- Four-column files like the primary run's `hist_primary.txt` fall through to
  the three-column legacy parser:

```text
xLow xHigh content
```

That makes `content = bin_center`, so the chart y-value becomes the bin center.

Files to inspect:

```text
Physics Companion/Agents/PlottingAgent.swift
Physics Companion/Agents/CodegenAgent.swift
Physics Companion/Agents/RunnerService.swift
```

Recommended fix:

1. Make histogram parsing header-aware where possible.
2. Support at least these observed formats:
   - `bin_low bin_high bin_center count`
   - `bin_low bin_high bin_center count probability`
   - `bin_low bin_high bin_center count count_per_event dN_dpt_per_event`
   - `x_mid count`
   - `x_mid count density`
3. For four or more columns with a header containing `bin_low bin_high
   bin_center count`, use `x = bin_center`, `y = count`, `xLow = bin_low`,
   `xHigh = bin_high`.
4. For two or three-column midpoint formats, use `x = column 1`, `y = column
   2`, and treat later columns as normalized or density metadata unless a
   descriptor explicitly requests them.
5. Add regression coverage using the exact formats found in these run folders.
6. Add a chart-payload sanity check: for count histograms, the sum of plotted
   y-values should match the expected event or particle count when the artifact
   has a count column.

## Cross-Run Evidence

Recent completed runs show multiple histogram formats, including at least one
repeat of the exact chart-payload failure.

### Runs with the Same Fake Rising Multiplicity Signature

These persisted chart payloads have first and last y-values equal to bin centers
instead of counts:

```text
07C215FF-363B-45C9-B085-D73F230B11CC
Charged Multiplicity: first y=3.5, last y=795.5

784E16CA-4C9F-4ECC-998F-A76EDE14991D
Charged Multiplicity: first y=3.5, last y=795.5
```

For `784E16CA-4C9F-4ECC-998F-A76EDE14991D`, the raw file starts:

```text
# charged_multiplicity histogram
# bin_low bin_high bin_center count
-0.5 7.5 3.5 0
7.5 15.5 11.5 1
15.5 23.5 19.5 16
```

So the same four-column format reproduces the same parser failure.

### Observed Histogram Formats in Recent Runs

The app currently needs to handle all of these in the wild:

```text
# charged_multiplicity histogram
# bin_low bin_high bin_center count
-0.5 7.5 3.5 2605
```

```text
# charged-particle multiplicity distribution per generated event
# bin_low bin_high bin_center count probability
-0.5 7.5 3.5 2552 0.2552
```

```text
# charged_multiplicity count
# bins=100 min=-0.5 max=799.5
3.5 2481
```

```text
# charged_multiplicity count probability
3.5 1292 0.2584
```

```text
# final_state_charged_particle_pt_spectrum
# bin_low_GeV bin_high_GeV bin_center_GeV count dN_dpt_per_event
0 0.2 0.1 164716 82.358
```

```text
# final-state charged-particle pT spectrum
# bin_low_GeV bin_high_GeV bin_center_GeV count count_per_event dN_dpt_per_event
0 0.5 0.25 461945 46.1945 92.389
```

```text
# pT_GeV charged_particle_count dN_dpT_per_event
# bins=100 min=0 max=20 underflow=0 overflow=0
0.1 167267 83.6335
```

The parser should not infer a universal column order solely from column count.
It needs either explicit header parsing or deterministic file-format contracts
from codegen.

## Bug 2: Run Summary Says "Succeeded" Despite Run Quality Findings

Severity: P1.

The assistant final summary for the primary run says:

```text
The run completed with 10000 generated events.
...
Takeaways: run succeeded; results should be interpreted within Monte Carlo/statistical uncertainty...
```

But `run.log` contains PYTHIA warnings and errors:

```text
12   Error in SimpleSpaceShower::pT2nearThreshold: stuck in loop
2    Warning in MultipartonInteractions::init: maximum increased
3    Warning in MultipartonInteractions::pTnext: weight above unity
1    Warning in Pythia::check: energy-momentum not quite conserved
1    Warning in SimpleSpaceShower::pT2nextQCD: small daughter PDF
72   Warning in SimpleSpaceShower::pT2nextQCD: weight above unity
```

The Physics Reviewer correctly flagged this:

```text
ignored_quality_finding
The final summary does not mention PYTHIA warnings/errors seen in run.log...
```

Recommended fix:

1. Summary generation should consume deterministic Run Quality findings before
   writing the final user-facing interpretation.
2. If Run Quality has warnings/errors, the final summary should say "completed
   with warnings" or similar.
3. Do not use unqualified "run succeeded" language unless deterministic quality
   findings are clean or explicitly acknowledged.
4. Consider moving reviewer execution before the final chat summary, or adding a
   deterministic post-summary correction when reviewer/quality findings are
   severe.

## Bug 3: Minimum-Bias Wording Conflicts With `PhaseSpace:pTHatMin`

Severity: P1 for physics correctness and user trust.

The user request/title:

```text
pp collisions at 13 TeV, 10,000 minimum-bias events, measuring charged-particle multiplicity, pT spectrum
```

The generated configuration:

```text
SoftQCD:all = on
PhaseSpace:pTHatMin = 15.
```

This should not be described as fully inclusive minimum-bias. The pT-hat cut
changes the generated sample. The reviewer correctly flagged this as
`cut_process_wording`.

Likely root cause:

- `Physics Companion/Agents/AnalysisPlannerAgent.swift` appends
  `PhaseSpace:pTHatMin = 15.` whenever requested observables contain `pt`.
- That is too blunt for a minimum-bias prompt. Asking to measure a pT spectrum
  is not the same as asking to impose a hard pT-hat generation cut.

Recommended fix options:

1. If the prompt says minimum-bias, do not auto-add `PhaseSpace:pTHatMin`.
2. If the planner adds a pT-hat cut, the analysis plan and final summary must
   state that the sample is pT-hat filtered.
3. Longer term: add an analysis-plan review step where the user can accept or
   reject cuts before execution.

## Bug 4: Empty `compile.log` Is Probably Misclassified

Severity: P2, because it causes false red/error UI and distracts from real run
warnings.

For the primary run:

```text
compile.log byte size: 0
run binary exists
run completed
summary.json exists
histograms exist
```

Current Run Quality says:

```text
Empty expected evidence
compile.log is present but empty.
```

This is probably not a real run failure. A clean compiler invocation often
writes nothing to stderr/stdout. The presence of the compiled binary and
completed run artifacts is stronger evidence that compilation succeeded.

Recommended fix:

1. Treat empty `compile.log` as acceptable if the run binary exists and the
   compile step succeeded.
2. Keep missing `compile.log` as an evidence warning or error depending on the
   artifact contract.
3. Keep non-empty compile logs with warning/error markers as warnings/errors.
4. Add regression coverage for:
   - empty clean compile log with successful run;
   - non-empty compile warning;
   - non-empty compile error;
   - missing compile log.

## Bug 5: pT Spectrum Is Treated as Secondary Evidence, Not a First-Class Observable

Severity: P2.

The primary request asked for both charged-particle multiplicity and pT
spectrum. The run did generate `hist_pt.txt`, and the raw pT histogram sums to
`711970`, matching `summary.total_charged_particles`.

However, `simulation_spec.json` lists the analysis family as
`charged_multiplicity` and the observables as:

```text
charged_multiplicity
generated_events
```

The pT spectrum appears only through `output_plan.extra_files`, not as a
first-class observable in the spec.

This weakens downstream review and provenance because the requested observable
is visible as an artifact but not fully represented in the analysis plan.

Recommended fix:

1. Allow multiple first-class observables in `analysis_plan.observables`, even
   when one family remains primary for codegen.
2. Ensure Summary and Reviewer stages know that pT was requested, not merely
   opportunistically emitted.
3. Run Compare and Export should distinguish primary family from requested
   secondary observables.

## Suggested Fix Order

1. Fix `PlottingAgent.parseHistogram` with header-aware parsing and regression
   fixtures for the observed formats.
2. Add a deterministic chart sanity check that compares plotted count sums to
   raw artifact count sums for count histograms.
3. Update Run Quality handling for empty `compile.log`.
4. Make final summary wording quality-aware so it cannot call a run clean while
   deterministic warnings/errors are present.
5. Adjust planner behavior for minimum-bias prompts and pT-hat cuts.
6. Promote secondary requested observables to first-class spec/reviewer input.

## Minimal Regression Fixtures to Add

Use these existing runs as fixtures or copy their small artifact files into the
script harness:

```text
07C215FF-363B-45C9-B085-D73F230B11CC
- Four-column multiplicity histogram currently misparsed.
- pT histogram count sum matches summary.
- run.log contains PYTHIA warnings/errors.
- compile.log is empty.

784E16CA-4C9F-4ECC-998F-A76EDE14991D
- Same four-column multiplicity chart failure.

41AD4B83-5611-48CF-8E46-4B104787695D
- Five-column `bin_low bin_high bin_center count probability` format.

A30F6683-43AE-4067-AF07-64065F34D265
- Two-column midpoint/count multiplicity format.

FB51CD04-8C20-47B1-924D-6955311AC15E
- Three-column midpoint/count/probability multiplicity format.

55C18C16-54E4-4A3C-BFFE-DEEE030A7459
- Known smoke fixture with full evidence and two charts.
```

The harness should assert parsed chart points, not just non-empty chart output.
For example:

```text
07C215FF hist_primary first chart point should be:
x = 3.5
y = 2605
xLow = -0.5
xHigh = 7.5
```

## CTO Product Implication

This bug cuts directly against Vidura's stated wedge: verified scientific
work products. The app did the right thing by preserving artifacts and having
the reviewer complain, but the main visible plot was wrong. For a correctness
product, artifact fidelity must outrank visual polish and natural-language
confidence.

The good news is that this appears fixable without a schema migration. The raw
evidence is present, the reviewer path is catching some summary-level failures,
and the issue is mostly in deterministic parsing/quality/wording layers.

## Screenshot Need

No additional screenshots are required to diagnose this specific bug. The
database chart payload and artifact files reproduce the issue directly. A
follow-up screenshot may be useful after a fix, to verify that the corrected
chart no longer shows the false rising multiplicity distribution.
