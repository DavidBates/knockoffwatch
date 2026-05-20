import SwiftUI
import Charts

// MARK: - Helpers

private func dailyAvg(readings: [HealthReading], keyPath: KeyPath<HealthReading, Int?>) -> [(date: Date, value: Double)] {
    let cal = Calendar.current
    let grouped = Dictionary(grouping: readings) { cal.startOfDay(for: $0.date) }
    return grouped.compactMap { (day, rs) in
        let vals = rs.compactMap { $0[keyPath: keyPath] }
        guard !vals.isEmpty else { return nil }
        return (day, Double(vals.reduce(0, +)) / Double(vals.count))
    }.sorted { $0.date < $1.date }
}

private func sevenDayDomain() -> ClosedRange<Date> {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let weekAgo = cal.date(byAdding: .day, value: -6, to: today) ?? today
    return weekAgo...Date()
}

// MARK: - Heart Rate

struct WeeklyHRChart: View {
    let readings: [HealthReading]

    private var points: [(date: Date, value: Double)] {
        dailyAvg(readings: readings, keyPath: \.heartRate)
    }

    var body: some View {
        if points.isEmpty {
            weeklyChartPlaceholder(color: .red)
        } else {
            Chart {
                ForEach(points, id: \.date) { p in
                    AreaMark(x: .value("Day", p.date), y: .value("BPM", p.value))
                        .foregroundStyle(LinearGradient(
                            colors: [.red.opacity(0.30), .red.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Day", p.date), y: .value("BPM", p.value))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Day", p.date), y: .value("BPM", p.value))
                        .foregroundStyle(.red)
                        .symbolSize(22)
                }
            }
            .chartXScale(domain: sevenDayDomain())
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel()
                }
            }
        }
    }
}

// MARK: - Blood Pressure

struct WeeklyBPChart: View {
    let readings: [HealthReading]

    private var sysPoints: [(date: Date, value: Double)] {
        dailyAvg(readings: readings, keyPath: \.systolic)
    }
    private var diaPoints: [(date: Date, value: Double)] {
        dailyAvg(readings: readings, keyPath: \.diastolic)
    }

    var body: some View {
        if sysPoints.isEmpty && diaPoints.isEmpty {
            weeklyChartPlaceholder(color: .orange)
        } else {
            Chart {
                ForEach(sysPoints, id: \.date) { p in
                    LineMark(x: .value("Day", p.date), y: .value("mmHg", p.value),
                             series: .value("Series", "Systolic"))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Day", p.date), y: .value("mmHg", p.value))
                        .foregroundStyle(.orange)
                        .symbolSize(18)
                }
                ForEach(diaPoints, id: \.date) { p in
                    LineMark(x: .value("Day", p.date), y: .value("mmHg", p.value),
                             series: .value("Series", "Diastolic"))
                        .foregroundStyle(.orange.opacity(0.50))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 2]))
                    PointMark(x: .value("Day", p.date), y: .value("mmHg", p.value))
                        .foregroundStyle(.orange.opacity(0.50))
                        .symbolSize(14)
                }
            }
            .chartXScale(domain: sevenDayDomain())
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel()
                }
            }
            .chartLegend(.hidden)
        }
    }
}

// MARK: - Blood Oxygen

struct WeeklySpO2Chart: View {
    let readings: [HealthReading]

    private var points: [(date: Date, value: Double)] {
        dailyAvg(readings: readings, keyPath: \.spo2)
    }

    var body: some View {
        if points.isEmpty {
            weeklyChartPlaceholder(color: .blue)
        } else {
            Chart {
                ForEach(points, id: \.date) { p in
                    AreaMark(x: .value("Day", p.date), y: .value("%", p.value))
                        .foregroundStyle(LinearGradient(
                            colors: [.blue.opacity(0.28), .blue.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Day", p.date), y: .value("%", p.value))
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Day", p.date), y: .value("%", p.value))
                        .foregroundStyle(.blue)
                        .symbolSize(22)
                }
            }
            .chartXScale(domain: sevenDayDomain())
            .chartYScale(domain: 80...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel()
                }
            }
        }
    }
}

// MARK: - Placeholder

@ViewBuilder
private func weeklyChartPlaceholder(color: Color) -> some View {
    RoundedRectangle(cornerRadius: 8)
        .fill(color.opacity(0.07))
        .overlay(
            Text("No data")
                .font(.system(size: 9))
                .foregroundStyle(color.opacity(0.4))
        )
}
