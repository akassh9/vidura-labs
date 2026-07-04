//
//  ChartBubbleContent.swift
//  Physics Companion
//
//  Renders a ChartPayload inline in the chat using Swift Charts.
//

import SwiftUI
import Charts

struct ChartBubbleContent: View {
    let payload: ChartPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(payload.title)
                .font(.subheadline)
                .fontWeight(.semibold)

            switch payload.chartType {
            case .bar:
                barChart
            case .line:
                lineChart
            case .summaryCard:
                summaryCard
            }
        }
    }

    // MARK: - Bar Chart

    @ViewBuilder
    private var barChart: some View {
        if let series = payload.series.first {
            let useCategorical = series.points.contains(where: { $0.label != nil })

            if useCategorical {
                Chart(series.points) { point in
                    BarMark(
                        x: .value(payload.xLabel, point.label ?? ""),
                        y: .value(payload.yLabel, point.y)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
                .chartXAxisLabel(payload.xLabel)
                .chartYAxisLabel(payload.yLabel)
                .frame(height: 200)
            } else {
                Chart(series.points) { point in
                    BarMark(
                        x: .value(payload.xLabel, point.x),
                        y: .value(payload.yLabel, point.y)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
                .chartXAxisLabel(payload.xLabel)
                .chartYAxisLabel(payload.yLabel)
                .frame(height: 200)
            }
        }
    }

    // MARK: - Line Chart

    @ViewBuilder
    private var lineChart: some View {
        if let series = payload.series.first {
            Chart(series.points) { point in
                LineMark(
                    x: .value(payload.xLabel, point.x),
                    y: .value(payload.yLabel, point.y)
                )
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value(payload.xLabel, point.x),
                    y: .value(payload.yLabel, point.y)
                )
                .foregroundStyle(
                    Color.accentColor.opacity(0.1).gradient
                )
            }
            .chartXAxisLabel(payload.xLabel)
            .chartYAxisLabel(payload.yLabel)
            .frame(height: 200)
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(payload.metrics) { metric in
                HStack {
                    Text(metric.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 2) {
                        Text(metric.value)
                            .font(.system(.callout, design: .monospaced))
                            .fontWeight(.medium)
                        if let unit = metric.unit, !unit.isEmpty {
                            Text(unit)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                )
            }
        }
    }
}
