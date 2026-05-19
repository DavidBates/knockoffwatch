import SwiftUI
import CoreBluetooth

struct SettingsView: View {
    @Environment(BluetoothManager.self) private var bluetooth
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private var isConnected: Bool {
        if case .connected = bluetooth.connectionState { return true }
        return false
    }

    var body: some View {
        List {
            watchSection
            healthSection
            autoSyncSection
            advancedSection
        }
        .navigationTitle("Settings")
        .listStyle(.insetGrouped)
    }

    // MARK: - Watch

    private var watchSection: some View {
        Section("Watch") {
            // Watch identity card
            HStack(spacing: 12) {
                Image(systemName: "applewatch")
                    .font(.title2)
                    .foregroundStyle(isConnected ? .green : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(bluetooth.connectedDeviceName ?? bluetooth.savedWatchName ?? "No Watch Paired")
                        .font(.headline)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isConnected ? Color.green : Color.gray)
                            .frame(width: 7, height: 7)
                        Text(isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                            .foregroundStyle(isConnected ? .green : .secondary)
                    }
                }
            }
            .padding(.vertical, 4)

            // Scan results while scanning
            if bluetooth.isScanning || (!isConnected && !bluetooth.peripherals.isEmpty) {
                ForEach(bluetooth.peripherals.prefix(5)) { entry in
                    PeripheralRow(entry: entry, isConnectable: !isConnected) {
                        bluetooth.connect(to: entry)
                    }
                }
            }

            // Connection controls
            if case .connecting = bluetooth.connectionState {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.85)
                    Text("Connecting…").foregroundStyle(.secondary)
                }
            } else if bluetooth.isScanning {
                Button("Stop Scanning", action: bluetooth.stopScan)
                    .foregroundStyle(.orange)
            } else if isConnected {
                Button(role: .destructive, action: bluetooth.disconnect) {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    bluetooth.startScan()
                } label: {
                    Label("Reconnect", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(bluetooth.centralState != .poweredOn)
            }

            if bluetooth.savedWatchName != nil || bluetooth.savedTrustedWatch != nil {
                Button(role: .destructive, action: bluetooth.forgetWatch) {
                    Label("Forget Watch", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Apple Health

    private var healthSection: some View {
        let hk = bluetooth.healthKit
        return Section("Apple Health") {
            HStack(spacing: 10) {
                Circle()
                    .fill(healthStatusColor(hk.authorizationStatus))
                    .frame(width: 10, height: 10)
                Text(hk.authorizationStatus.label)
                    .font(.subheadline)
            }

            if hk.isAvailable && hk.authorizationStatus != .authorized {
                Button("Connect Apple Health") {
                    Task { await hk.requestAuthorization() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.pink)
            }

            if hk.authorizationStatus == .authorized {
                Toggle("Save Heart Rate", isOn: Binding(
                    get: { hk.saveHR },
                    set: { hk.setSaveHR($0) }
                ))
                Toggle("Save Blood Pressure", isOn: Binding(
                    get: { hk.saveBP },
                    set: { hk.setSaveBP($0) }
                ))
                Toggle("Save Blood Oxygen (SpO2)", isOn: Binding(
                    get: { hk.saveSpO2 },
                    set: { hk.setSaveSpO2($0) }
                ))
            }

            Text("These readings come from an unsupported third-party watch integration and should not be used for medical decisions.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func healthStatusColor(_ status: HealthKitManager.AuthStatus) -> Color {
        switch status {
        case .authorized:    return .green
        case .denied:        return .red
        case .notDetermined: return .gray
        case .unavailable:   return .gray
        }
    }

    // MARK: - Auto Sync

    private var autoSyncSection: some View {
        Section {
            Toggle("Auto Health Sync", isOn: Binding(
                get: { bluetooth.autoSyncEnabled },
                set: { bluetooth.setAutoSyncEnabled($0) }
            ))

            if bluetooth.autoSyncEnabled {
                Picker("Foreground interval", selection: Binding(
                    get: { bluetooth.foregroundSyncInterval },
                    set: { bluetooth.setForegroundSyncInterval($0) }
                )) {
                    ForEach(ForegroundSyncInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }

                Picker("Background interval", selection: Binding(
                    get: { bluetooth.backgroundSyncInterval },
                    set: { bluetooth.setBackgroundSyncInterval($0) }
                )) {
                    ForEach(BackgroundSyncInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }

                if let last = bluetooth.lastSyncTime {
                    LabeledContent("Last sync") {
                        Text(last, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let next = bluetooth.nextSyncTime {
                    LabeledContent("Next sync") {
                        HStack(spacing: 3) {
                            Text(next, style: .relative)
                            Text("from now")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Auto Sync")
        } footer: {
            if bluetooth.autoSyncEnabled {
                Text("Foreground syncs run while the app is open. Background syncs are system-managed and may run later than configured.")
                    .font(.caption2)
            }
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        Section("Advanced") {
            NavigationLink {
                InspectorView(bluetooth: bluetooth)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BLE Services")
                        Text("\(bluetooth.discoveredServices.count) services · \(bluetooth.discoveredCharacteristics.count) chars")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "magnifyingglass.circle")
                        .foregroundStyle(.blue)
                }
            }

            NavigationLink {
                ProtocolView(bluetooth: bluetooth)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Protocol Discovery")
                        Text(bluetooth.isRecordingInteraction
                             ? "Recording…"
                             : "\(bluetooth.protocolSessionLog.count) events logged")
                            .font(.caption)
                            .foregroundStyle(bluetooth.isRecordingInteraction ? .red : .secondary)
                    }
                } icon: {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(.purple)
                }
            }

            NavigationLink {
                KeepAliveTestView(bluetooth: bluetooth)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep Alive Test")
                        Text(bluetooth.isKeepAliveRunning
                             ? "Running [\(bluetooth.keepAliveMode.label)]"
                             : "Mode: \(bluetooth.keepAliveMode.label)")
                            .font(.caption)
                            .foregroundStyle(bluetooth.isKeepAliveRunning ? .green : .secondary)
                    }
                } icon: {
                    Image(systemName: "bolt.heart")
                        .foregroundStyle(.green)
                }
            }

            NavigationLink {
                IdleMonitorView(bluetooth: bluetooth)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Idle BLE Monitor")
                        Text(bluetooth.idleMonitorActive
                             ? "Monitoring — \(bluetooth.idleMonitorTotalNotifications) packets"
                             : "Passive packet logger")
                            .font(.caption)
                            .foregroundStyle(bluetooth.idleMonitorActive ? .green : .secondary)
                    }
                } icon: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.orange)
                }
            }

            NavigationLink {
                AdvertisementMonitorView(bluetooth: bluetooth)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Advertisement Monitor")
                        Text("\(bluetooth.peripherals.count) device(s) seen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.cyan)
                }
            }

            ShareLink(
                item: bluetooth.exportReport(),
                subject: Text("LaxasFit BLE Report"),
                message: Text("Exported from LaxasFit Watch app")
            ) {
                Label("Export Logs", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                hasCompletedOnboarding = false
            } label: {
                Label("Reset Onboarding", systemImage: "arrow.counterclockwise")
            }
        }
    }
}
