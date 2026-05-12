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
                    debugSection
                }
            }
            .navigationTitle("LaxasFit Watch")
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Sections

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
        Section("Nearby Devices (\(bluetooth.peripherals.count))") {
            ForEach(bluetooth.peripherals) { entry in
                PeripheralRow(entry: entry) {
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
                        Text("\(level)%")
                            .font(.title.bold())
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

    private var debugSection: some View {
        Section {
            DisclosureGroup("Debug: Services & Characteristics") {
                if bluetooth.discoveredServices.isEmpty {
                    Text("Discovering…")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(bluetooth.discoveredServices, id: \.uuid) { service in
                        ServiceRow(
                            service: service,
                            allCharacteristics: bluetooth.discoveredCharacteristics
                        )
                    }
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
        case 88...: return "battery.100"
        case 63...87: return "battery.75"
        case 38...62: return "battery.50"
        case 13...37: return "battery.25"
        default:      return "battery.0"
        }
    }

    private func batteryColor(_ level: Int) -> Color {
        level > 20 ? .green : .red
    }
}

// MARK: - PeripheralRow

struct PeripheralRow: View {
    let entry: DiscoveredPeripheral
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
        if props.contains(.read)   { parts.append("R") }
        if props.contains(.write)  { parts.append("W") }
        if props.contains(.notify) { parts.append("N") }
        if props.contains(.indicate) { parts.append("I") }
        return parts.isEmpty ? "—" : parts.joined(separator: "|")
    }
}

#Preview {
    ContentView()
}
