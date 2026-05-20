import SwiftUI

struct BloodOxygenCard: View {
    let bluetooth: BluetoothManager

    private var history: HealthHistoryStore { bluetooth.healthHistory }
    private var isActive: Bool { bluetooth.spo2MeasurementState.isActive }
    private var pair: (latest: HealthReading?, previous: HealthReading?) {
        history.latestTwo(ofType: .bloodOxygen)
    }
    private var weekReadings: [HealthReading] { history.recent(ofType: .bloodOxygen) }
    private var pctValues: [Int] { weekReadings.compactMap(\.spo2) }

    var body: some View {
        MetricReadingCard(
            title: "Blood Oxygen",
            icon: "lungs.fill",
            color: .blue,
            isMeasuring: isActive,
            prevValue: pair.previous.flatMap { $0.spo2.map { "\($0)%" } },
            updatedAt: pair.latest?.date,
            avgValue: pctValues.isEmpty ? nil : "\(pctValues.reduce(0, +) / pctValues.count)%",
            minValue: pctValues.min().map { "\($0)%" },
            maxValue: pctValues.max().map { "\($0)%" },
            syncLabel: isActive ? "Measuring…" : "Sync SpO2",
            syncDisabled: bluetooth.isSyncSessionActive,
            onSync: { bluetooth.syncSpO2Now() },
            hero: {
                BloodOxygenHeroVisual(
                    pct: isActive ? nil : pair.latest.flatMap { $0.spo2.map { "\($0)" } },
                    isMeasuring: isActive
                )
            },
            chart: {
                WeeklySpO2Chart(readings: weekReadings)
            }
        )
    }
}

#Preview("Blood Oxygen Card") {
    ScrollView {
        BloodOxygenCard(bluetooth: .preview)
            .padding(.horizontal, 16)
    }
    .background(Color(.systemGroupedBackground))
}
