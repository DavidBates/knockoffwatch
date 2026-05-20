import SwiftUI

struct HeartRateCard: View {
    let bluetooth: BluetoothManager

    private var history: HealthHistoryStore { bluetooth.healthHistory }
    private var isActive: Bool { bluetooth.measurementState.isActive }
    private var pair: (latest: HealthReading?, previous: HealthReading?) {
        history.latestTwo(ofType: .heartRate)
    }
    private var weekReadings: [HealthReading] { history.recent(ofType: .heartRate) }
    private var bpmValues: [Int] { weekReadings.compactMap(\.heartRate) }

    var body: some View {
        MetricReadingCard(
            title: "Heart Rate",
            icon: "heart.fill",
            color: .red,
            isMeasuring: isActive,
            prevValue: pair.previous.flatMap { $0.heartRate.map { "\($0) bpm" } },
            updatedAt: pair.latest?.date,
            avgValue: bpmValues.isEmpty ? nil : "\(bpmValues.reduce(0, +) / bpmValues.count)",
            minValue: bpmValues.min().map { "\($0)" },
            maxValue: bpmValues.max().map { "\($0)" },
            syncLabel: isActive ? "Measuring…" : "Sync HR",
            syncDisabled: bluetooth.isSyncSessionActive,
            onSync: { bluetooth.syncHeartRateNow() },
            hero: {
                HeartRateHeroVisual(
                    bpm: isActive ? nil : pair.latest.flatMap { $0.heartRate.map { "\($0)" } },
                    isMeasuring: isActive
                )
            },
            chart: {
                WeeklyHRChart(readings: weekReadings)
            }
        )
    }
}

#if DEBUG
#Preview("Heart Rate Card") {
    ScrollView {
        HeartRateCard(bluetooth: .preview)
            .padding(.horizontal, 16)
    }
    .background(Color(.systemGroupedBackground))
}
#endif
