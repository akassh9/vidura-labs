//
//  PlottingAgent.swift
//  Physics Companion
//
//  Deterministic plotting stage: parses simulation artifacts and produces
//  structured chart data for inline rendering in the chat.
//

import Foundation

enum PlottingAgent {

    // MARK: - Main Entry Point

    /// Reads artifact files from the attempt directory and produces the
    /// primary ChartPayload suitable for inline chart rendering.
    ///
    /// Returns nil if no plottable artifacts are found.
    static func run(
        family: AnalysisFamily,
        attemptDir: URL,
        summaryDict: [String: Any] = [:]
    ) -> ChartPayload? {
        runAll(family: family, attemptDir: attemptDir, summaryDict: summaryDict).first
    }

    /// Reads all known plottable artifacts from the attempt directory.
    ///
    /// Each returned payload is intended to be stored as its own chart message.
    static func runAll(
        family: AnalysisFamily,
        attemptDir: URL,
        summaryDict: [String: Any] = [:]
    ) -> [ChartPayload] {
        var payloads: [ChartPayload] = []
        var consumed = Set<String>()

        if let descriptor = primaryHistogramDescriptor(for: family),
           let payload = parseHistogram(attemptDir: attemptDir, descriptor: descriptor) {
            payloads.append(payload)
            consumed.insert(descriptor.filename)
        }

        for descriptor in secondaryHistogramDescriptors(for: family) {
            guard !consumed.contains(descriptor.filename) else { continue }
            if let payload = parseHistogram(attemptDir: attemptDir, descriptor: descriptor) {
                payloads.append(payload)
                consumed.insert(descriptor.filename)
            }
        }

        switch family {
        case .pidYields:
            if let payload = parsePidCounts(attemptDir: attemptDir) {
                payloads.append(payload)
                consumed.insert("pid_counts.txt")
            }
        case .eventScalars:
            if let payload = parseEventScalars(attemptDir: attemptDir, summaryDict: summaryDict) {
                payloads.append(payload)
                consumed.insert("event_scalars.txt")
            }
        default:
            break
        }

        payloads.append(contentsOf: parseGenericSecondaryHistograms(
            attemptDir: attemptDir,
            consumed: consumed
        ))

        return payloads
    }

    // MARK: - Histogram Parser

    private struct HistogramDescriptor {
        let filename: String
        let title: String
        let xLabel: String
        let yLabel: String
        let chartType: ChartType
    }

    private static func primaryHistogramDescriptor(for family: AnalysisFamily) -> HistogramDescriptor? {
        switch family {
        case .chargedMultiplicity:
            return HistogramDescriptor(
                filename: "hist_primary.txt",
                title: "Charged Multiplicity",
                xLabel: "N_ch",
                yLabel: "Events",
                chartType: .bar
            )
        case .ptSpectrum:
            return HistogramDescriptor(
                filename: "hist_primary.txt",
                title: "Transverse Momentum Spectrum",
                xLabel: "pT (GeV)",
                yLabel: "Charged particles",
                chartType: .line
            )
        case .etaRapidity:
            return HistogramDescriptor(
                filename: "hist_primary.txt",
                title: "Pseudorapidity Distribution",
                xLabel: "\u{03B7}",
                yLabel: "dN/d\u{03B7}",
                chartType: .line
            )
        case .invariantMass:
            return HistogramDescriptor(
                filename: "hist_primary.txt",
                title: "Dimuon Invariant Mass",
                xLabel: "M (GeV)",
                yLabel: "Events",
                chartType: .line
            )
        case .pidYields, .eventScalars:
            return nil
        }
    }

    private static func secondaryHistogramDescriptors(for family: AnalysisFamily) -> [HistogramDescriptor] {
        var descriptors: [HistogramDescriptor] = [
            HistogramDescriptor(
                filename: "hist_pt.txt",
                title: "Transverse Momentum Spectrum",
                xLabel: "pT (GeV)",
                yLabel: "Charged particles",
                chartType: .line
            ),
            HistogramDescriptor(
                filename: "hist_eta.txt",
                title: "Pseudorapidity Distribution",
                xLabel: "\u{03B7}",
                yLabel: "dN/d\u{03B7}",
                chartType: .line
            ),
            HistogramDescriptor(
                filename: "hist_mass.txt",
                title: "Invariant Mass",
                xLabel: "M (GeV)",
                yLabel: "Events",
                chartType: .line
            )
        ]

        if family == .ptSpectrum {
            descriptors.removeAll { $0.filename == "hist_pt.txt" }
        }

        return descriptors
    }

    /// Parses histogram text output.
    /// Supported formats:
    /// - `bin_low bin_center bin_high count probability`
    /// - `x_low x_high content`
    /// - `x_mid content`
    /// Lines starting with non-numeric characters are skipped.
    private static func parseHistogram(
        attemptDir: URL,
        descriptor: HistogramDescriptor
    ) -> ChartPayload? {
        let path = attemptDir.appendingPathComponent(descriptor.filename)
        guard let content = try? String(contentsOf: path, encoding: .utf8) else {
            return nil
        }

        var points: [ChartPoint] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let firstChar = trimmed.first!
            guard firstChar == "-" || firstChar == "+" || firstChar.isNumber else {
                continue
            }

            let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })

            // Five-column generated table: bin_low bin_center bin_high count probability.
            if tokens.count >= 5,
               let xLow = Double(tokens[0]),
               let xMid = Double(tokens[1]),
               let xHigh = Double(tokens[2]),
               let y = Double(tokens[3]) {
                points.append(ChartPoint(
                    x: xMid, y: y,
                    xLow: xLow, xHigh: xHigh
                ))
            }
            // Three-column legacy format: xLow xHigh content.
            else if tokens.count >= 3,
               let xLow = Double(tokens[0]),
               let xHigh = Double(tokens[1]),
               let y = Double(tokens[2]) {
                let xMid = (xLow + xHigh) / 2.0
                points.append(ChartPoint(
                    x: xMid, y: y,
                    xLow: xLow, xHigh: xHigh
                ))
            }
            // Two-column format: xMid content
            else if tokens.count == 2,
                    let x = Double(tokens[0]),
                    let y = Double(tokens[1]) {
                points.append(ChartPoint(x: x, y: y))
            }
        }

        guard !points.isEmpty else { return nil }

        return ChartPayload(
            chartType: descriptor.chartType,
            title: descriptor.title,
            xLabel: descriptor.xLabel,
            yLabel: descriptor.yLabel,
            series: [ChartSeries(label: descriptor.title, points: points)]
        )
    }

    private static func parseGenericSecondaryHistograms(
        attemptDir: URL,
        consumed: Set<String>
    ) -> [ChartPayload] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: attemptDir,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix("hist_")
                    && name.hasSuffix(".txt")
                    && !consumed.contains(name)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                let stem = url.deletingPathExtension().lastPathComponent
                let label = stem
                    .replacingOccurrences(of: "hist_", with: "")
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
                let descriptor = HistogramDescriptor(
                    filename: url.lastPathComponent,
                    title: label.isEmpty ? "Histogram" : label,
                    xLabel: "Bin",
                    yLabel: "Count",
                    chartType: .line
                )
                return parseHistogram(attemptDir: attemptDir, descriptor: descriptor)
            }
    }

    // MARK: - PID Counts Parser (pid_counts.txt)

    /// Parses CSV file with header "pid,count".
    private static func parsePidCounts(attemptDir: URL) -> ChartPayload? {
        let path = attemptDir.appendingPathComponent("pid_counts.txt")
        guard let content = try? String(contentsOf: path, encoding: .utf8) else {
            return nil
        }

        let pidNames: [Int: String] = [
            211: "\u{03C0}+", -211: "\u{03C0}-",
            321: "K+", -321: "K-",
            2212: "p"
        ]

        let lines = content.components(separatedBy: .newlines)
        var points: [ChartPoint] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if index == 0 && trimmed.lowercased().contains("pid") { continue }

            let parts = trimmed.split(separator: ",")
            guard parts.count >= 2,
                  let pid = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let count = Double(parts[1].trimmingCharacters(in: .whitespaces))
            else { continue }

            let name = pidNames[pid] ?? "PID \(pid)"
            let barIndex = Double(points.count)
            points.append(ChartPoint(x: barIndex, y: count, label: name))
        }

        guard !points.isEmpty else { return nil }

        return ChartPayload(
            chartType: .bar,
            title: "Particle Yields",
            xLabel: "Particle",
            yLabel: "Count",
            series: [ChartSeries(label: "Yields", points: points)]
        )
    }

    // MARK: - Event Scalars Parser (event_scalars.txt)

    /// Parses key=value pairs into a summary card.
    private static func parseEventScalars(
        attemptDir: URL,
        summaryDict: [String: Any]
    ) -> ChartPayload? {
        let path = attemptDir.appendingPathComponent("event_scalars.txt")

        var metrics: [ChartMetric] = []

        if let content = try? String(contentsOf: path, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                let label = key.replacingOccurrences(of: "_", with: " ").capitalized
                metrics.append(ChartMetric(label: label, value: value, unit: "GeV"))
            }
        }

        // Fallback to summary dict
        if metrics.isEmpty {
            if let ve = summaryDict["mean_visible_energy"] {
                metrics.append(ChartMetric(
                    label: "Mean Visible Energy", value: "\(ve)", unit: "GeV"
                ))
            }
            if let ht = summaryDict["mean_ht"] {
                metrics.append(ChartMetric(
                    label: "Mean HT", value: "\(ht)", unit: "GeV"
                ))
            }
        }

        guard !metrics.isEmpty else { return nil }

        return ChartPayload(
            chartType: .summaryCard,
            title: "Event Scalars",
            xLabel: "",
            yLabel: "",
            series: [],
            metrics: metrics
        )
    }
}
