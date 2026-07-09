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
    /// - `bin_low bin_high bin_center count`
    /// - `bin_low bin_high bin_center count probability`
    /// - `bin_low bin_high bin_center count count_per_event dN_dpt_per_event`
    /// - `x_mid count`
    /// - `x_mid count density`
    /// Header comments are preferred over column-count inference.
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
        var headerColumns: [String]?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("#") {
                if let parsedHeader = parseHistogramHeader(trimmed) {
                    headerColumns = parsedHeader
                }
                continue
            }

            let firstChar = trimmed.first!
            guard firstChar == "-" || firstChar == "+" || firstChar.isNumber else {
                continue
            }

            let values = trimmed
                .split(whereSeparator: { $0.isWhitespace })
                .compactMap { Double($0) }

            guard let point = histogramPoint(values: values, headerColumns: headerColumns) else {
                continue
            }
            points.append(point)
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

    private static func parseHistogramHeader(_ line: String) -> [String]? {
        let stripped = line
            .drop(while: { $0 == "#" || $0.isWhitespace })
            .lowercased()
        let columns = stripped
            .split(whereSeparator: { $0.isWhitespace })
            .map { normalizeColumnName(String($0)) }
        guard columns.count >= 2 else { return nil }

        let hasColumnMarker = columns.contains { column in
            isBinLowColumn(column)
                || isBinHighColumn(column)
                || isBinCenterColumn(column)
                || isCountColumn(column)
                || column.contains("pt")
                || column == "x"
                || column == "xmid"
        }
        return hasColumnMarker ? columns : nil
    }

    private static func histogramPoint(values: [Double], headerColumns: [String]?) -> ChartPoint? {
        guard values.count >= 2 else { return nil }

        if let headerColumns,
           let headerPoint = histogramPointFromHeader(values: values, headerColumns: headerColumns) {
            return headerPoint
        }

        if values.count >= 4 {
            return histogramPointFromBinnedColumns(values)
        }

        if values.count == 3 || values.count == 2 {
            return ChartPoint(x: values[0], y: values[1])
        }

        return nil
    }

    private static func histogramPointFromHeader(
        values: [Double],
        headerColumns: [String]
    ) -> ChartPoint? {
        let limit = min(values.count, headerColumns.count)
        guard limit >= 2 else { return nil }

        let xLowIndex = firstIndex(in: headerColumns, limit: limit) { isBinLowColumn($0) }
        let xHighIndex = firstIndex(in: headerColumns, limit: limit) { isBinHighColumn($0) }
        let xMidIndex = firstIndex(in: headerColumns, limit: limit) { isBinCenterColumn($0) }
        let yIndex = preferredCountIndex(in: headerColumns, limit: limit)

        guard let yIndex else { return nil }

        if let xMidIndex {
            return ChartPoint(
                x: values[xMidIndex],
                y: values[yIndex],
                xLow: xLowIndex.map { values[$0] },
                xHigh: xHighIndex.map { values[$0] }
            )
        }

        if let xLowIndex, let xHighIndex {
            return ChartPoint(
                x: (values[xLowIndex] + values[xHighIndex]) / 2.0,
                y: values[yIndex],
                xLow: values[xLowIndex],
                xHigh: values[xHighIndex]
            )
        }

        let xIndex = firstXIndex(in: headerColumns, limit: limit, excluding: yIndex) ?? 0
        return ChartPoint(x: values[xIndex], y: values[yIndex])
    }

    private static func histogramPointFromBinnedColumns(_ values: [Double]) -> ChartPoint? {
        guard values.count >= 4 else { return nil }
        let first = values[0]
        let second = values[1]
        let third = values[2]

        if second > third, third >= min(first, second), third <= max(first, second) {
            return ChartPoint(x: third, y: values[3], xLow: first, xHigh: second)
        }

        if second >= min(first, third), second <= max(first, third) {
            return ChartPoint(x: second, y: values[3], xLow: first, xHigh: third)
        }

        return ChartPoint(x: third, y: values[3], xLow: first, xHigh: second)
    }

    private static func normalizeColumnName(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;:()[]{}"))
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
    }

    private static func isBinLowColumn(_ column: String) -> Bool {
        column.contains("bin_low") || column == "x_low" || column == "low"
    }

    private static func isBinHighColumn(_ column: String) -> Bool {
        column.contains("bin_high") || column == "x_high" || column == "high"
    }

    private static func isBinCenterColumn(_ column: String) -> Bool {
        column.contains("bin_center")
            || column == "x_mid"
            || column == "xmid"
            || column == "center"
            || column == "mid"
    }

    private static func isCountColumn(_ column: String) -> Bool {
        column == "count"
            || column == "content"
            || column == "entries"
            || column == "value"
            || column.hasSuffix("_count")
    }

    private static func isNormalizedColumn(_ column: String) -> Bool {
        column.contains("probability")
            || column.contains("density")
            || column.contains("per_event")
            || column.contains("dn_")
            || column.contains("dnd")
            || column.contains("dn_d")
    }

    private static func preferredCountIndex(in columns: [String], limit: Int) -> Int? {
        if let exact = firstIndex(in: columns, limit: limit, matching: { $0 == "count" }) {
            return exact
        }
        return firstIndex(in: columns, limit: limit) { column in
            isCountColumn(column) && !isNormalizedColumn(column)
        }
    }

    private static func firstXIndex(
        in columns: [String],
        limit: Int,
        excluding excludedIndex: Int
    ) -> Int? {
        firstIndex(in: columns, limit: limit) { column in
            column == "x"
                || column == "x_mid"
                || column == "xmid"
                || column.contains("pt")
                || column.contains("gev")
        }.flatMap { $0 == excludedIndex ? nil : $0 }
    }

    private static func firstIndex(
        in columns: [String],
        limit: Int,
        matching predicate: (String) -> Bool
    ) -> Int? {
        let upperBound = min(limit, columns.count)
        for index in 0..<upperBound where predicate(columns[index]) {
            return index
        }
        return nil
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
