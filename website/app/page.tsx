const pipeline = [
  ["01", "Ask", "Describe a physics question in natural language."],
  ["02", "Plan", "Turn intent into an inspectable simulation spec."],
  ["03", "Run", "Generate, check, compile, and execute Pythia locally."],
  ["04", "Review", "Read plots, logs, quality checks, and references together."],
];

const evidenceFiles = [
  ["simulation_spec.json", "Beams, process settings, cuts, seed"],
  ["run.cc", "Generated source preserved with the run"],
  ["summary.json", "Parsed observables and event-level results"],
  ["hist_primary.txt", "Raw histogram data behind each chart"],
  ["run.log", "Captured execution output and warnings"],
  ["reference_pack.json", "Persisted HEP references and source status"],
];

const analysisFamilies = [
  "Charged multiplicity",
  "Transverse momentum spectra",
  "Pseudorapidity and rapidity",
  "Invariant mass",
  "Particle-ID yields",
  "Event-level scalars",
];

export default function Home() {
  return (
    <main>
      <header className="site-header">
        <a className="wordmark" href="#top" aria-label="Vidura Labs home">
          VIDURA <span>LABS</span>
        </a>
        <nav aria-label="Primary navigation">
          <a href="#workflow">Workflow</a>
          <a href="#evidence">Run record</a>
          <a href="#direction">Direction</a>
        </nav>
        <a className="header-link" href="#evidence">Inspect the loop</a>
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow"><span className="dot" /> HEP RESEARCH COMPANION / MACOS</p>
          <h1>From physics question to <em>verified</em> run record.</h1>
          <p className="hero-intro">
            Vidura Labs is a native research workbench for high-energy physics.
            It runs Pythia 8 locally, then keeps the source, settings, plots,
            logs, quality checks, reviewer notes, and references in one
            reproducible record.
          </p>
          <div className="hero-actions">
            <a className="button primary" href="#evidence">See a run record <span aria-hidden="true">-&gt;</span></a>
            <a className="text-link" href="#workflow">Follow the workflow</a>
          </div>
          <dl className="hero-facts">
            <div><dt>Runtime</dt><dd>Local Pythia 8</dd></div>
            <div><dt>Interface</dt><dd>Native macOS</dd></div>
            <div><dt>Priority</dt><dd>Correctness</dd></div>
          </dl>
        </div>

        <div className="hero-record" aria-label="Example run evidence interface">
          <div className="record-topline">
            <span className="live-status"><i /> COMPLETED</span>
            <span>RUN / 8C1D4F2A</span>
            <span>LOCAL</span>
          </div>
          <div className="record-heading">
            <div>
              <p className="micro-label">ANALYSIS</p>
              <h2>Charged multiplicity</h2>
              <p>pp collisions at 13 TeV</p>
            </div>
            <div className="run-type">ORIGINAL<br /><span>PYTHIA 8</span></div>
          </div>
          <div className="record-grid">
            <section className="plot-panel" aria-label="Illustrative charged multiplicity histogram">
              <div className="panel-label"><span>CHARGED MULTIPLICITY</span><span>EVENTS</span></div>
              <div className="histogram" aria-hidden="true">
                {Array.from({ length: 24 }, (_, index) => (
                  <i key={index} style={{ height: `${Math.max(8, 82 - index * 2.7 + (index % 4) * 7)}%` }} />
                ))}
                <b className="curve" />
              </div>
              <div className="axis"><span>0</span><span>200</span><span>400</span><span>600 N<sub>ch</sub></span></div>
            </section>
            <section className="metrics-panel">
              <p className="micro-label">SUMMARY.JSON</p>
              <dl>
                <div><dt>generated_events</dt><dd>10,000</dd></div>
                <div><dt>mean_charged</dt><dd>71.20</dd></div>
                <div><dt>random_seed</dt><dd>217174</dd></div>
                <div><dt>artifacts</dt><dd>09</dd></div>
              </dl>
              <div className="quality-note">
                <span>RUN QUALITY</span>
                <strong>Review the evidence before calling a result clean.</strong>
              </div>
            </section>
          </div>
          <div className="record-footer">
            <span>SPEC</span><b>PASS</b>
            <span>CODE</span><b>CAPTURED</b>
            <span>LOGS</span><b>ATTACHED</b>
            <span>REFERENCES</span><b>PACKED</b>
          </div>
        </div>
      </section>

      <section className="proof-strip" aria-label="Vidura value proposition">
        <p>Generation is common. <strong>Evidence is the product.</strong></p>
        <span>LOCAL EXECUTION</span>
        <span>TRACEABLE ARTIFACTS</span>
        <span>PHYSICS REVIEW</span>
      </section>

      <section className="workflow section" id="workflow">
        <div className="section-intro">
          <p className="eyebrow">THE RESEARCH LOOP</p>
          <h2>Chat coordinates the work.<br />The run record carries the claim.</h2>
        </div>
        <div className="pipeline-grid">
          {pipeline.map(([number, title, body]) => (
            <article className="pipeline-step" key={number}>
              <p className="step-number">{number}</p>
              <h3>{title}</h3>
              <p>{body}</p>
            </article>
          ))}
        </div>
        <div className="pipeline-detail">
          <p>Vidura routes runnable requests through structured guide and intent stages, retrieves relevant Pythia examples, builds a deterministic simulation spec, and uses policy and physics checks before local execution. Where supported, model-backed stages have deterministic fallback paths.</p>
          <span>OPENAI RESPONSES API + PYTHIA 8 + SWIFTUI + SQLITE</span>
        </div>
      </section>

      <section className="evidence section" id="evidence">
        <div className="evidence-sticky">
          <p className="eyebrow">RUN EVIDENCE</p>
          <h2>A result should survive more than one conversation.</h2>
          <p>Every completed run is preserved locally as an inspectable research object. Review the inputs and artifacts now; replay, branch, compare, or export them later.</p>
          <div className="evidence-actions">
            <a className="button dark" href="#direction">Why correctness matters <span aria-hidden="true">-&gt;</span></a>
          </div>
        </div>
        <div className="evidence-list">
          {evidenceFiles.map(([file, description], index) => (
            <article className="file-row" key={file}>
              <span className="file-index">0{index + 1}</span>
              <div><h3>{file}</h3><p>{description}</p></div>
              <span className="file-state">PERSISTED</span>
            </article>
          ))}
          <article className="review-row">
            <p className="micro-label">PHYSICS REVIEWER</p>
            <h3>Interpretations are checked against available artifacts, deterministic quality findings, charts, logs, and persisted reference packs.</h3>
            <p>References are validated to the run&apos;s saved pack, so a review cannot point to a citation that the record does not contain.</p>
          </article>
        </div>
      </section>

      <section className="capabilities section">
        <div className="capability-head">
          <p className="eyebrow">CURRENT RESEARCH SURFACE</p>
          <h2>Built for the details that make computational physics defensible.</h2>
        </div>
        <div className="capability-columns">
          <article>
            <p className="capability-no">A</p>
            <h3>Reproduce and compare</h3>
            <p>Exact reruns preserve audited source and spec. Controlled variants can change event count, random seed, or pT-hat cut, with lineage and differences kept visible. Compare runs side by side across configuration, summary metrics, artifacts, charts, and exact byte matches.</p>
          </article>
          <article>
            <p className="capability-no">B</p>
            <h3>Audit the scientific claim</h3>
            <p>Run Quality flags missing or empty evidence, weak statistics, event-count mismatches, histogram overflow markers, risky wording, and log warnings. The reviewer then weighs those findings before a summary is treated as reliable.</p>
          </article>
          <article>
            <p className="capability-no">C</p>
            <h3>Carry references with the result</h3>
            <p>Completed simulations include a typed reference pack covering Pythia, arXiv, INSPIRE, HEPData, and PDG sources. Packs can be refreshed explicitly, show source status, and export without relying on a live network call.</p>
          </article>
        </div>
      </section>

      <section className="analysis section">
        <div className="analysis-copy">
          <p className="eyebrow">HEP / PYTHIA FIRST</p>
          <h2>Start with a question that has a calculation behind it.</h2>
          <p>The current native app supports six analysis families and preserves generated source, raw outputs, parsed summaries, and inline Swift Charts payloads for each run.</p>
        </div>
        <ul className="family-list" aria-label="Supported analysis families">
          {analysisFamilies.map((family, index) => <li key={family}><span>0{index + 1}</span>{family}</li>)}
        </ul>
      </section>

      <section className="direction" id="direction">
        <div className="direction-mark" aria-hidden="true">V</div>
        <div className="direction-copy">
          <p className="eyebrow">THE DIRECTION</p>
          <h2>Physics workbench,<br /><em>not</em> a model wrapper.</h2>
          <p>Vidura is building toward an AI workbench where physicists can move from a question to literature, data, simulation, figures, and manuscript-ready artifacts. The core wedge is verification: catch untraceable numbers, weak statistics, biased cuts, unsupported claims, mismatched figures, and invented citations before they become conclusions.</p>
          <a className="button light" href="#top">Back to the top <span aria-hidden="true">-&gt;</span></a>
        </div>
        <aside className="benchmark-note">
          <p className="micro-label">BENCHMARK IN PROGRESS</p>
          <strong>Offline HEP correctness harness</strong>
          <p>Fixture-backed checks for missing evidence, low statistics, event mismatches, overflow, citation gaps, figure-summary disagreement, and unit ambiguity.</p>
          <span>11 INITIAL FIXTURES</span>
        </aside>
      </section>

      <footer>
        <a className="wordmark" href="#top">VIDURA <span>LABS</span></a>
        <p>Native macOS research companion for reproducible high-energy physics simulation.</p>
        <span>LOCAL FIRST / HEP / PYTHIA 8</span>
      </footer>
    </main>
  );
}
