import SwiftUI
import CoreBluetooth

struct HomeView: View {
    @Environment(BluetoothManager.self) private var bluetooth

    private var isConnected: Bool {
        if case .connected = bluetooth.connectionState { return true }
        return false
    }

    var body: some View {
        List {
            connectionSection
            if bluetooth.batteryLevel != nil || isConnected {
                batteryRow
            }
            readingsSection
            syncSection
        }
        .navigationTitle("LaxasFit Watch")
        .listStyle(.insetGrouped)
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(connectionColor.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "applewatch")
                        .font(.title2)
                        .foregroundStyle(connectionColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(watchDisplayName)
                        .font(.headline)
                    Text(connectionStatusLabel)
                        .font(.caption)
                        .foregroundStyle(connectionColor)
                }
                Spacer()
                if case .connecting = bluetooth.connectionState {
                    ProgressView()
                } else if bluetooth.isScanning {
                    ProgressView()
                } else if !isConnected {
                    Button("Connect") {
                        bluetooth.startScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(bluetooth.centralState != .poweredOn)
                }
            }
            .padding(.vertical, 4)

            // Show nearby devices while scanning so user can pick one
            if bluetooth.isScanning || (!isConnected && !bluetooth.peripherals.isEmpty) {
                ForEach(bluetooth.peripherals.prefix(5)) { entry in
                    PeripheralRow(entry: entry, isConnectable: !isConnected) {
                        bluetooth.connect(to: entry)
                    }
                }
                if bluetooth.isScanning {
                    Button("Stop Scanning", action: bluetooth.stopScan)
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
        }
    }

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
        case .disconnected:    return bluetooth.savedWatchName != nil ? "Tap Connect to reconnect" : "Not connected"
        }
    }

    // MARK: - Battery

    private var batteryRow: some View {
        Section {
            if let level = bluetooth.batteryLevel {
                HStack(spacing: 12) {
                    Image(systemName: batteryIcon(level))
                        .foregroundStyle(level > 20 ? .green : .red)
                    Text("\(level)%")
                        .font(.body.monospacedDigit())
                    Spacer()
                    Text("Watch Battery")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Reading battery…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Latest Readings

    private var readingsSection: some View {
        Section("Latest Readings") {
            readingRow(
                label: "Heart Rate",
                icon: "heart.fill",
                iconColor: .red,
                value: bluetooth.lastHeartRate.map { "\($0) bpm" },
                date: bluetooth.lastHeartRateDate
            )
            readingRow(
                label: "Blood Pressure",
                icon: "waveform.path.ecg",
                iconColor: .orange,
                value: {
                    if let sys = bluetooth.lastSystolic, let dia = bluetooth.lastDiastolic {
                        return "\(sys)/\(dia) mmHg"
                    }
                    return nil
                }(),
                date: bluetooth.lastBPDate
            )
            readingRow(
                label: "Blood Oxygen",
                icon: "lungs.fill",
                iconColor: .blue,
                value: bluetooth.lastSpO2.map { "\($0)%" },
                date: bluetooth.lastSpO2Date
            )
        }
    }

    private func readingRow(label: String, icon: String, iconColor: Color,
                            value: String?, date: Date?) -> some View {
        LabeledContent {
            if let v = value {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(v).font(.headline)
                    if let d = date {
                        Text(d, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        } label: {
            Label(label, systemImage: icon).foregroundStyle(iconColor)
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        Section {
            if bluetooth.autoSyncEnabled {
                Button {
                    bluetooth.triggerAutoSync()
                } label: {
                    HStack {
                        Label("Sync All", systemImage: "arrow.triangle.2.circlepath")
                        if bluetooth.isSyncSessionActive {
                            Spacer()
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                }
                .disabled(!isConnected || bluetooth.isSyncSessionActive)
            }

            measureButton(
                label: "Sync Heart Rate",
                icon: "heart.fill",
                isActive: bluetooth.measurementState.isActive,
                disabled: !isConnected || bluetooth.measurementState.isActive
            ) {
                bluetooth.startHeartRateMeasurement()
            }

            measureButton(
                label: "Sync Blood Pressure",
                icon: "waveform.path.ecg",
                isActive: bluetooth.bpMeasurementState.isActive,
                disabled: !isConnected || bluetooth.bpMeasurementState.isActive
            ) {
                bluetooth.startBPMeasurement()
            }

            measureButton(
                label: "Sync Blood Oxygen",
                icon: "lungs.fill",
                isActive: bluetooth.spo2MeasurementState.isActive,
                disabled: !isConnected || bluetooth.spo2MeasurementState.isActive
            ) {
                bluetooth.startSpO2Measurement()
            }

            if bluetooth.isSyncSessionActive {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text(bluetooth.syncSessionState.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let last = bluetooth.lastSyncTime {
                LabeledContent("Last sync") {
                    Text(last, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Sync")
        }
    }

    private func measureButton(label: String, icon: String,
                               isActive: Bool, disabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: icon)
                if isActive {
                    Spacer()
                    ProgressView().scaleEffect(0.75)
                }
            }
        }
        .disabled(disabled)
    }

    // MARK: - Helpers

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
