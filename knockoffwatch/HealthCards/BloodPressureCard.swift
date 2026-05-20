import SwiftUI

struct BloodPressureCard: View {
    let bluetooth: BluetoothManager

    private var history: HealthHistoryStore { bluetooth.healthHistory }
    private var isActive: Bool { bluetooth.bpMeasurementState.isActive }
    private var pair: (latest: HealthReading?, previous: HealthReading?) {
        history.latestTwo(ofType: .bloodPressure)
    }
    private var weekReadings: [HealthReading] { history.recent(ofType: .bloodPressure) }
    private var sysValues: [Int] { weekReadings.compactMap(\.systolic) }
    private var diaValues: [Int] { weekReadings.compactMap(\.diastolic) }

    private var prevDisplay: String? {
        guard let sys = pair.previous?.systolic, let dia = pair.previous?.diastolic else { return nil }
        return "\(sys)/\(dia)"
    }
    private var avgDisplay: String? {
        guard !sysValues.isEmpty, !diaValues.isEmpty else { return nil }
        return "\(sysValues.reduce(0, +) / sysValues.count)/\(diaValues.reduce(0, +) / diaValues.count)"
    }

    var body: some View {
        MetricReadingCard(
            title: "Blood Pressure",
            icon: "waveform.path.ecg",
            color: .orange,
            isMeasuring: isActive,
            prevValue: prevDisplay,
            updatedAt: pair.latest?.date,
            avgValue: avgDisplay,
            minValue: sysValues.min().map { "\($0)" },
            maxValue: sysValues.max().map { "\($0)" },
            syncLabel: isActive ? "Measuring…" : "Sync BP",
            syncDisabled: bluetooth.isSyncSessionActive,
            onSync: { bluetooth.syncBPNow() },
            hero: {
                BloodPressureHeroVisual(
                    sys: isActive ? nil : pair.latest?.systolic.map { "\($0)" },
                    dia: isActive ? nil : pair.latest?.diastolic.map { "\($0)" },
                    isMeasuring: isActive,
                    latestHR: bluetooth.lastHeartRate
                )
            },
            chart: {
                WeeklyBPChart(readings: weekReadings)
            }
        )
    }
}

#if DEBUG
#Preview("Blood Pressure Card") {
    ScrollView {
        BloodPressureCard(bluetooth: .preview)
            .padding(.horizontal, 16)
    }
    .background(Color(.systemGroupedBackground))
}
#endif
