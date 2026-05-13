import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @State private var bluetooth = BluetoothManager()

    private var isConnected: Bool {
        if case .connected = bluetooth.connectionState { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                bluetoothStatusSection
                if bluetooth.centralState == .poweredOn {
                    scanControlSection
                }
                if !bluetooth.peripherals.isEmpty && !isConnected {
                    peripheralsSection
                }
                if let name = bluetooth.connectedDeviceName {
                    selectedWatchSection(name)
                }
                if bluetooth.batteryLevel != nil || isConnected {
                    batterySection
                }
                heartRateSection
                toolsSection
                BLEDebugSection(bluetooth: bluetooth)
            }
            .navigationTitle("LaxasFit Watch")
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Bluetooth status

    private var bluetoothStatusSection: some View {
        Section("Bluetooth") {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 10, height: 10)
                Text(bluetooth.statusMessage)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Scan controls

    private var scanControlSection: some View {
        Section {
            if bluetooth.isScanning {
                HStack {
                    ProgressView().padding(.trailing, 4)
                    Button("Stop Scanning", action: bluetooth.stopScan)
                        .foregroundStyle(.orange)
                }
            } else if case .connected = bluetooth.connectionState {
                Button("Disconnect", role: .destructive, action: bluetooth.disconnect)
            } else if case .connecting = bluetooth.connectionState {
                HStack {
                    ProgressView().padding(.trailing, 4)
                    Text("Connecting…").foregroundStyle(.secondary)
                }
            } else {
                Button("Scan for Devices", action: bluetooth.startScan)
            }
        }
    }

    // MARK: - Nearby devices

    private var peripheralsSection: some View {
        let isConnectable: Bool = {
            switch bluetooth.connectionState {
            case .disconnected, .failed: return true
            default: return false
            }
        }()
        return Section("Nearby Devices (\(bluetooth.peripherals.count))") {
            ForEach(bluetooth.peripherals) { entry in
                PeripheralRow(entry: entry, isConnectable: isConnectable) {
                    bluetooth.connect(to: entry)
                }
            }
        }
    }

    // MARK: - Selected watch

    private func selectedWatchSection(_ name: String) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "applewatch")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.headline)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isConnected ? Color.green : Color.gray)
                            .frame(width: 7, height: 7)
                        Text(isConnected ? "Connected" : "Last connected")
                            .font(.caption)
                            .foregroundStyle(isConnected ? .green : .secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Battery card

    private var batterySection: some View {
        Section("Battery") {
            if let level = bluetooth.batteryLevel {
                HStack(spacing: 12) {
                    Image(systemName: batteryIcon(level))
                        .font(.title2)
                        .foregroundStyle(batteryColor(level))
                    VStack(alignment: .leading) {
                        Text("\(level)%").font(.title.bold())
                        Text("LaxasFit Watch Ultra")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else if isConnected {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("Reading battery level…").foregroundStyle(.secondary)
                }
            }
            if isConnected {
                Button(action: bluetooth.refreshBattery) {
                    Label("Refresh Battery", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: - Heart Rate card

    private var heartRateSection: some View {
        Section("❤️ Heart Rate") {
            // BPM display
            if let bpm = bluetooth.lastHeartRate {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.title2)
                        .foregroundStyle(bluetooth.measurementState.isActive ? .red : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(bpm) bpm")
                            .font(.title.bold())
                        if let date = bluetooth.lastHeartRateDate {
                            HStack(spacing: 2) {
                                Text("Last updated")
                                Text(date, style: .relative)
                                Text("ago")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No heart rate data yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if isConnected {
                        Text("Tap Start Measurement to begin.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            // Measurement controls — only when connected
            if isConnected {
                measurementControls
            }
        }
    }

    @ViewBuilder
    private var measurementControls: some View {
        switch bluetooth.measurementState {

        case .idle:
            Button(action: bluetooth.startHeartRateMeasurement) {
                Label("Start Measurement", systemImage: "heart.circle.fill")
            }
            .disabled(!bluetooth.isHRWriteCharAvailable)

        case .starting:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("Starting…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .measuring:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("Measuring…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Stop") { bluetooth.stopHeartRateMeasurement() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

        case .receivedLiveStatus:
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("Sensor active…")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
                Spacer()
                Button("Stop") { bluetooth.stopHeartRateMeasurement() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

        case .receivedResult:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("Processing result…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .complete:
            VStack(alignment: .leading, spacing: 6) {
                Label("Measurement complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
                Button(action: bluetooth.startHeartRateMeasurement) {
                    Label("Measure Again", systemImage: "heart.circle")
                }
                .disabled(!bluetooth.isHRWriteCharAvailable)
            }

        case .timeout:
            VStack(alignment: .leading, spacing: 6) {
                Text("No response from watch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("No heart rate received in 30s. Start a measurement on the watch, then try again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: bluetooth.startHeartRateMeasurement) {
                    Label("Start Measurement", systemImage: "heart.circle.fill")
                }
                .disabled(!bluetooth.isHRWriteCharAvailable)
            }
        }
    }

    // MARK: - Tools

    private var toolsSection: some View {
        Section {
            NavigationLink {
                InspectorView(bluetooth: bluetooth)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BLE Inspector")
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
        }
    }

    // MARK: - Helpers

    private var statusDotColor: Color {
        switch bluetooth.centralState {
        case .poweredOn:
            switch bluetooth.connectionState {
            case .connected:  return .green
            case .connecting: return .yellow
            default:          return .blue
            }
        case .poweredOff, .unauthorized, .unsupported: return .red
        default: return .gray
        }
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

    private func batteryColor(_ level: Int) -> Color { level > 20 ? .green : .red }
}

// MARK: - BLEDebugSection

struct BLEDebugSection: View {
    @Bindable var bluetooth: BluetoothManager

    var body: some View {
        Section {
            DisclosureGroup("BLE Debug") {
                sessionStatsRows
                keepAliveRows
                heartRateDebugRows
                eventLogGroup
            }
        }
    }

    @ViewBuilder private var sessionStatsRows: some View {
        if let d = bluetooth.lastDisconnectDuration {
            LabeledContent("Last session", value: formatDuration(d))
        }
        if let r = bluetooth.lastDisconnectReason {
            LabeledContent("Disconnect reason") {
                Text(r).font(.caption).foregroundStyle(.red).multilineTextAlignment(.trailing)
            }
        }
    }

    @ViewBuilder private var keepAliveRows: some View {
        Picker("Keep-Alive", selection: Binding(
            get: { bluetooth.keepAliveMode },
            set: { bluetooth.setKeepAliveMode($0) }
        )) {
            Text("None").tag(KeepAliveMode.none)
            Text("Battery").tag(KeepAliveMode.batteryRead)
            Text("UART Ping").tag(KeepAliveMode.uartPing)
        }
        if bluetooth.keepAliveMode != .none {
            Stepper(
                "Interval: \(Int(bluetooth.keepAliveIntervalSeconds))s",
                value: Binding(get: { bluetooth.keepAliveIntervalSeconds },
                               set: { bluetooth.keepAliveIntervalSeconds = $0 }),
                in: 1...60, step: 1
            )
            .font(.caption)
        }
        if bluetooth.isKeepAliveRunning {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.75)
                Text("Running [\(bluetooth.keepAliveMode.label)] every \(Int(bluetooth.keepAliveIntervalSeconds))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var heartRateDebugRows: some View {
        if let raw = bluetooth.lastHRRawPacket {
            LabeledContent("HR BPM", value: bluetooth.lastHeartRate.map { "\($0) bpm" } ?? "—")
            if let date = bluetooth.lastHeartRateDate {
                LabeledContent("HR timestamp", value: BLEEvent.timeFormatter.string(from: date))
            }
            if let typeDesc = bluetooth.lastHRPacketTypeDesc {
                LabeledContent("HR packet type") {
                    Text(typeDesc)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            LabeledContent("HR raw packet (\(raw.split(separator: " ").count)B)") {
                Text(raw)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        let stateLabel: String = {
            switch bluetooth.measurementState {
            case .idle:               return "idle"
            case .starting:           return "starting"
            case .measuring:          return "measuring"
            case .receivedLiveStatus: return "receivedLiveStatus"
            case .receivedResult:     return "receivedResult"
            case .complete:           return "complete"
            case .timeout:            return "timeout"
            }
        }()
        LabeledContent("HR measurement", value: stateLabel)
        LabeledContent("HR write char", value: bluetooth.isHRWriteCharAvailable ? "found" : "not found")
    }

    private var eventLogGroup: some View {
        DisclosureGroup("Event Log (\(bluetooth.eventLog.count))") {
            if bluetooth.eventLog.isEmpty {
                Text("No events yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(bluetooth.eventLog.suffix(30).reversed()) { event in
                    HStack(alignment: .top, spacing: 6) {
                        Text(event.timeString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Text(event.message)
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        t < 60 ? String(format: "%.1fs", t) : "\(Int(t) / 60)m \(Int(t) % 60)s"
    }
}

// MARK: - PeripheralRow

struct PeripheralRow: View {
    let entry: DiscoveredPeripheral
    let isConnectable: Bool
    let onConnect: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.headline)
                Text(entry.id.uuidString)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                if entry.advertisementSummary != "—" {
                    Text(entry.advertisementSummary)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(entry.rssi) dBm").font(.caption2).foregroundStyle(.secondary)
                Button("Connect", action: onConnect)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!isConnectable)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ContentView()
}
