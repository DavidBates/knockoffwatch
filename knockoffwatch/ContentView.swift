import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @State private var bluetooth = BluetoothManager()

    var body: some View {
        NavigationStack {
            List {
                bluetoothStatusSection
                if bluetooth.centralState == .poweredOn {
                    scanControlSection
                }
                if !bluetooth.peripherals.isEmpty {
                    peripheralsSection
                }
                if case .connected = bluetooth.connectionState {
                    batterySection
                }
                BLEDebugSection(bluetooth: bluetooth)
            }
            .navigationTitle("LaxasFit Watch")
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Main sections

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
            } else {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("Reading battery level…").foregroundStyle(.secondary)
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
                if !bluetooth.discoveredServices.isEmpty {
                    servicesDisclosureGroup
                }
                eventLogDisclosureGroup
            }
        }
    }

    @ViewBuilder private var sessionStatsRows: some View {
        LabeledContent("Services found",
                       value: "\(bluetooth.discoveredServices.count)")
        LabeledContent("Characteristics found",
                       value: "\(bluetooth.discoveredCharacteristics.count)")
        if let d = bluetooth.lastDisconnectDuration {
            LabeledContent("Last session", value: formatDuration(d))
        }
        if let r = bluetooth.lastDisconnectReason {
            LabeledContent("Disconnect reason") {
                Text(r)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    @ViewBuilder private var keepAliveRows: some View {
        Toggle(
            "Keep connection active",
            isOn: Binding(
                get: { bluetooth.keepAliveEnabled },
                set: { bluetooth.setKeepAlive($0) }
            )
        )
        if bluetooth.isKeepAliveRunning {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.75)
                Text("Keep-alive running (reads every 2s, up to 30s)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var servicesDisclosureGroup: some View {
        DisclosureGroup("Services & Characteristics (\(bluetooth.discoveredServices.count))") {
            ForEach(bluetooth.discoveredServices, id: \.uuid) { service in
                ServiceRow(
                    service: service,
                    allCharacteristics: bluetooth.discoveredCharacteristics
                )
            }
        }
    }

    private var eventLogDisclosureGroup: some View {
        DisclosureGroup("Event Log (\(bluetooth.eventLog.count))") {
            if bluetooth.eventLog.isEmpty {
                Text("No events yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Newest first; show last 30 to keep the list manageable
                ForEach(bluetooth.eventLog.suffix(30).reversed()) { event in
                    HStack(alignment: .top, spacing: 6) {
                        Text(event.timeString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Text(event.message)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        t < 60
            ? String(format: "%.1fs", t)
            : "\(Int(t) / 60)m \(Int(t) % 60)s"
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
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(entry.rssi) dBm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Connect", action: onConnect)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!isConnectable)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ServiceRow

struct ServiceRow: View {
    let service: CBService
    let allCharacteristics: [CBCharacteristic]

    private var characteristics: [CBCharacteristic] {
        allCharacteristics.filter { service.characteristics?.contains($0) == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Service: \(service.uuid.uuidString)")
                .font(.caption.monospaced())
            ForEach(characteristics, id: \.uuid) { char in
                HStack(alignment: .top) {
                    Text("↳ \(char.uuid.uuidString)")
                        .font(.caption2.monospaced())
                    Spacer()
                    Text(propertiesLabel(char.properties))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func propertiesLabel(_ props: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if props.contains(.read)    { parts.append("R") }
        if props.contains(.write)   { parts.append("W") }
        if props.contains(.notify)  { parts.append("N") }
        if props.contains(.indicate){ parts.append("I") }
        return parts.isEmpty ? "—" : parts.joined(separator: "|")
    }
}

#Preview {
    ContentView()
}
