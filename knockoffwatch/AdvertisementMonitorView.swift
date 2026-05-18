import SwiftUI
import CoreBluetooth

// MARK: - AdvertisementMonitorView

struct AdvertisementMonitorView: View {
    @Bindable var bluetooth: BluetoothManager

    // MARK: Sorted display list

    private var sortedPeripherals: [DiscoveredPeripheral] {
        bluetooth.peripherals.sorted { a, b in
            let aIsUnknown = a.name == "Unknown BLE Device"
            let bIsUnknown = b.name == "Unknown BLE Device"
            if aIsUnknown != bIsUnknown { return bIsUnknown }
            if a.confidence != b.confidence { return a.confidence > b.confidence }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    // MARK: Body

    var body: some View {
        List {
            headerSection
            ForEach(sortedPeripherals) { entry in
                peripheralSection(entry)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Advertisement Monitor")
    }

    // MARK: - Header

    private var headerSection: some View {
        Section("Status") {
            LabeledContent("Scanning") {
                Text(bluetooth.isScanning ? "Active" : "Idle")
                    .foregroundStyle(bluetooth.isScanning ? .green : .secondary)
            }
            LabeledContent("Devices seen") {
                Text("\(bluetooth.peripherals.count)")
                    .monospacedDigit()
            }
            Button {
                if bluetooth.isScanning {
                    bluetooth.stopScan()
                } else {
                    bluetooth.startScan()
                }
            } label: {
                Label(
                    bluetooth.isScanning ? "Stop Scan" : "Start Scan",
                    systemImage: bluetooth.isScanning ? "stop.circle" : "antenna.radiowaves.left.and.right"
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(bluetooth.centralState != .poweredOn)
        }
    }

    // MARK: - Per-device section

    @ViewBuilder
    private func peripheralSection(_ entry: DiscoveredPeripheral) -> some View {
        Section {
            // Name headline + confidence badge
            HStack(alignment: .firstTextBaseline) {
                Text(entry.name)
                    .font(.headline)
                Spacer()
                confidenceBadge(entry.confidence)
            }

            // UUID
            Text(entry.id.uuidString)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            // Advertised name (only when different from displayed name)
            if let advName = entry.advertisedName, advName != entry.name {
                LabeledContent("Adv name", value: advName)
            }

            // Peripheral name (only when different from displayed name)
            if let periphName = entry.peripheralName, periphName != entry.name {
                LabeledContent("Peripheral name", value: periphName)
            }

            // Advertised service UUIDs
            if !entry.advertisedServiceUUIDs.isEmpty {
                LabeledContent("Services") {
                    Text(entry.advertisedServiceUUIDs.map { shortUUID($0) }.joined(separator: ", "))
                        .font(.caption.monospaced())
                        .multilineTextAlignment(.trailing)
                }
            }

            // Manufacturer data (first 30 hex chars)
            if let hex = entry.manufacturerDataHex {
                LabeledContent("Mfr data") {
                    Text(String(hex.prefix(30)))
                        .font(.caption.monospaced())
                        .multilineTextAlignment(.trailing)
                }
            }

            // TX power
            if let tx = entry.txPower {
                LabeledContent("TX power", value: "\(tx) dBm")
            }

            // Connectable
            LabeledContent("Connectable", value: entry.isConnectable ? "Yes" : "No")

            // Seen count and first seen
            LabeledContent("Seen") {
                Text("\(entry.seenCount)x — first \(BLEEvent.timeFormatter.string(from: entry.firstSeen))")
                    .font(.caption.monospaced())
            }

            // RSSI
            LabeledContent("RSSI", value: "\(entry.rssi) dBm")

            // Last seen
            LabeledContent("Last seen") {
                Text(BLEEvent.timeFormatter.string(from: entry.lastSeen))
                    .font(.caption.monospaced())
            }

            // Connect button
            Button {
                bluetooth.connect(to: entry)
            } label: {
                Label("Connect", systemImage: "cable.connector")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(!entry.isConnectable)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func confidenceBadge(_ confidence: Int) -> some View {
        let color: Color = confidence >= 70 ? .green : confidence >= 40 ? .blue : .gray
        Text("\(confidence)%")
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
    }

    /// Returns a short human-readable UUID string.
    /// 4-char for 16-bit BT SIG UUIDs (e.g. "180D"), 8-char suffix otherwise.
    private func shortUUID(_ uuid: CBUUID) -> String {
        let full = uuid.uuidString
        // 16-bit BT SIG UUIDs are 4 hex digits long in CBUUID.uuidString
        if full.count == 4 {
            return full
        }
        // Standard 128-bit UUID — take the last 8 chars of the UUID string (last segment)
        return String(full.suffix(8))
    }
}
