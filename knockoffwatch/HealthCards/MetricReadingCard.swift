import SwiftUI

// MARK: - Outer card shell

struct MetricReadingCard<Hero: View, ChartContent: View>: View {
    let title: String
    let icon: String
    let color: Color
    let isMeasuring: Bool
    let prevValue: String?
    let updatedAt: Date?
    let avgValue: String?
    let minValue: String?
    let maxValue: String?
    let syncLabel: String
    let syncDisabled: Bool
    let onSync: () -> Void
    @ViewBuilder let hero: () -> Hero
    @ViewBuilder let chart: () -> ChartContent

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            contentRow
            Divider()
            MetricBottomBar(
                isMeasuring: isMeasuring,
                prevValue: prevValue,
                updatedAt: updatedAt,
                avgValue: avgValue,
                minValue: minValue,
                maxValue: maxValue,
                syncLabel: syncLabel,
                syncDisabled: syncDisabled,
                color: color,
                onSync: onSync
            )
        }
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)
            Text(title)
                .font(.headline)
                .foregroundStyle(color)
            Spacer()
            if isMeasuring {
                ProgressView().scaleEffect(0.7)
                    .padding(.trailing, 4)
            }
            Text("Last 7 Days")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var contentRow: some View {
        HStack(alignment: .center, spacing: 0) {
            hero()
                .padding(.leading, 12)
                .frame(maxWidth: 155, alignment: .center)

            chart()
                .frame(maxWidth: .infinity)
                .padding(.trailing, 12)
                .padding(.vertical, 10)
        }
        .frame(height: 158)
    }
}

// MARK: - Bottom bar

struct MetricBottomBar: View {
    let isMeasuring: Bool
    let prevValue: String?
    let updatedAt: Date?
    let avgValue: String?
    let minValue: String?
    let maxValue: String?
    let syncLabel: String
    let syncDisabled: Bool
    let color: Color
    let onSync: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            prevColumn
            Spacer(minLength: 4)
            if !isMeasuring {
                statsRow
                Spacer(minLength: 4)
            }
            syncButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var prevColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isMeasuring {
                Text("Measuring…")
                    .font(.caption.bold())
                    .foregroundStyle(color)
            } else if let prev = prevValue {
                Text(prev)
                    .font(.caption.bold())
            } else {
                Text("No previous")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let date = updatedAt, !isMeasuring {
                (Text(date, style: .relative) + Text(" ago"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 130, alignment: .leading)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statColumn(avgValue, label: "avg")
            statColumn(minValue, label: "min")
            statColumn(maxValue, label: "max")
        }
    }

    @ViewBuilder
    private func statColumn(_ value: String?, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value ?? "—")
                .font(.caption.bold())
                .monospacedDigit()
                .foregroundStyle(value != nil ? .primary : .tertiary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var syncButton: some View {
        Button(action: onSync) {
            HStack(spacing: 5) {
                Image(systemName: isMeasuring ? "waveform" : "arrow.clockwise")
                    .font(.caption.bold())
                Text(syncLabel)
                    .font(.caption.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .disabled(syncDisabled)
        .opacity(syncDisabled ? 0.55 : 1.0)
    }
}
