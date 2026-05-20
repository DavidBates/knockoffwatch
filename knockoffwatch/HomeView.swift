import SwiftUI
import CoreBluetooth

struct HomeView: View {
    @Environment(BluetoothManager.self) private var bluetooth

    private var isConnected: Bool {
        if case .connected = bluetooth.connectionState { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                topRow
                healthHeader
                HeartRateCard(bluetooth: bluetooth)
                BloodPressureCard(bluetooth: bluetooth)
                BloodOxygenCard(bluetooth: bluetooth)
                syncCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("LaxasFit Watch")
    }

    // MARK: - Top row: connection + battery tiles

    private var topRow: some View {
        HStack(spacing: 12) {
            connectionTile
            batteryTile
        }
    }

    private var connectionTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "applewatch")
                    .font(.title3)
                    .foregroundStyle(connectionColor)
                Spacer()
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
            }

            Text(watchDisplayName)
                .font(.caption.bold())
                .lineLimit(1)

            Text(connectionStatusLabel)
                .font(.caption2)
                .foregroundStyle(connectionColor)

            if !isConnected {
                if case .connecting = bluetooth.connectionState {
                    ProgressView().scaleEffect(0.7)
                } else if bluetooth.isScanning {
                    Button("Stop", action: bluetooth.stopScan)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Button("Connect") { bluetooth.startScan() }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .controlSize(.mini)
                        .disabled(bluetooth.centralState != .poweredOn)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }

    private var batteryTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: batteryIcon(bluetooth.batteryLevel ?? 100))
                    .font(.title3)
                    .foregroundStyle(batteryColor)
                Spacer()
            }

            if let level = bluetooth.batteryLevel {
                Text("\(level)%")
                    .font(.title2.bold().monospacedDigit())
            } else {
                Text("—")
                    .font(.title2.bold())
                    .foregroundStyle(.tertiary)
            }

            Text("Watch Battery")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }

    // MARK: - Health section header

    private var healthHeader: some View {
        HStack {
            Text("Health")
                .font(.headline)
            Spacer()
            if let last = latestHealthDate {
                Text("Updated \(last, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }

    private var latestHealthDate: Date? {
        let h = bluetooth.healthHistory
        let dates = [
            h.lastUpdated(ofType: .heartRate),
            h.lastUpdated(ofType: .bloodPressure),
            h.lastUpdated(ofType: .bloodOxygen)
        ].compactMap { $0 }
        return dates.max()
    }

    // MARK: - Scan list (shown while scanning)

    private var scanResultsSection: some View {
        Group {
            if bluetooth.isScanning || (!isConnected && !bluetooth.peripherals.isEmpty) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nearby Devices")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                    ForEach(bluetooth.peripherals.prefix(5)) { entry in
                        PeripheralRow(entry: entry, isConnectable: !isConnected) {
                            bluetooth.connect(to: entry)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemGroupedBackground))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Compact sync card

    private var syncCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.blue)
                Text("Sync")
                    .font(.subheadline.bold())
                Spacer()
                if bluetooth.isSyncSessionActive {
                    ProgressView().scaleEffect(0.65)
                    Text(bluetooth.syncSessionState.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 16)

            HStack(spacing: 10) {
                Button {
                    bluetooth.syncAll()
                } label: {
                    Label("Sync All", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
                .disabled(bluetooth.isSyncSessionActive)

                Spacer()

                if let last = bluetooth.lastSyncTime {
                    Text("Last: \(last, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }

    // MARK: - Helpers

    private var watchDisplayName: String {
        bluetooth.connectedDeviceName
            ?? bluetooth.savedWatchName
            ?? "LaxasFit Watch Ultra"
    }

    private var connectionColor: Color {
        if case .connected = bluetooth.connectionState { return .green }
        if case .connecting = bluetooth.connectionState { return .yellow }
        if bluetooth.isScanning { return .blue }
        return .gray
    }

    private var connectionStatusLabel: String {
        if bluetooth.isScanning { return "Scanning…" }
        switch bluetooth.connectionState {
        case .connected:       return "Connected"
        case .connecting:      return "Connecting…"
        case .failed(let msg): return "Error: \(msg)"
        case .disconnected:    return bluetooth.savedWatchName != nil ? "Tap Connect" : "Not paired"
        }
    }

    private var batteryColor: Color {
        guard let level = bluetooth.batteryLevel else { return .secondary }
        return level > 20 ? .green : .red
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case 88...:   return "battery.100"
        case 63...87: return "battery.75"
        case 38...62: return "battery.50"
        case 13...37: return "battery.25"
        default:      return "battery.0"
        }
    }
}

#if DEBUG
#Preview("Home — Connected") {
    NavigationStack {
        HomeView()
    }
    .environment(BluetoothManager.preview)
}

#Preview("Home — Disconnected") {
    NavigationStack {
        HomeView()
    }
    .environment(BluetoothManager())
}
#endif
