//
//  ChartModels.swift
//  Physics Companion
//
//  Data models for structured chart data produced by PlottingAgent.
//

import Foundation

// MARK: - Chart Type

enum ChartType: String, Codable, Sendable {
    case bar
    case line
    case summaryCard = "summary_card"
}

// MARK: - Chart Point

/// A single data point in a chart series.
struct ChartPoint: Codable, Sendable, Identifiable {
    var id: String { "\(x)_\(y)_\(label ?? "")" }
    let x: Double
    let y: Double
    let xLow: Double?
    let xHigh: Double?
    let label: String?

    init(x: Double, y: Double, xLow: Double? = nil,
         xHigh: Double? = nil, label: String? = nil) {
        self.x = x
        self.y = y
        self.xLow = xLow
        self.xHigh = xHigh
        self.label = label
    }

    enum CodingKeys: String, CodingKey {
        case x, y
        case xLow = "x_low"
        case xHigh = "x_high"
        case label
    }
}

// MARK: - Chart Series

/// A named series of data points.
struct ChartSeries: Codable, Sendable, Identifiable {
    var id: String { label }
    let label: String
    let points: [ChartPoint]
}

// MARK: - Chart Metric

/// A key-value metric for summary cards (event_scalars family).
struct ChartMetric: Codable, Sendable, Identifiable {
    var id: String { label }
    let label: String
    let value: String
    let unit: String?

    init(label: String, value: String, unit: String? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
    }
}

// MARK: - Chart Payload

/// Complete chart data produced by PlottingAgent, attached to a ChatMessage.
struct ChartPayload: Codable, Sendable {
    let chartType: ChartType
    let title: String
    let xLabel: String
    let yLabel: String
    let series: [ChartSeries]
    let metrics: [ChartMetric]

    init(chartType: ChartType, title: String,
         xLabel: String, yLabel: String,
         series: [ChartSeries], metrics: [ChartMetric] = []) {
        self.chartType = chartType
        self.title = title
        self.xLabel = xLabel
        self.yLabel = yLabel
        self.series = series
        self.metrics = metrics
    }

    enum CodingKeys: String, CodingKey {
        case chartType = "chart_type"
        case title
        case xLabel = "x_label"
        case yLabel = "y_label"
        case series
        case metrics
    }
}
