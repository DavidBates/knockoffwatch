import SwiftUI
import CoreBluetooth

// MARK: - Known BLE names (standard Bluetooth SIG assignments)

private enum BLEKnownNames {
    static func service(_ uuid: CBUUID) -> String? {
        let names: [String: String] = [
            "1800": "Generic Access",
            "1801": "Generic Attribute",
            "180A": "Device Information",
            "180D": "Heart Rate",
            "180F": "Battery Service",
            "1810": "Blood Pressure",
            "1816": "Cycling Speed and Cadence",
            "181A": "Environmental Sensing",
        ]
        return names[uuid.uuidString.uppercased()]
    }

    static func characteristic(_ uuid: CBUUID) -> String? {
        let names: [String: String] = [
            "2A00": "Device Name",
            "2A01": "Appearance",
            "2A04": "Preferred Connection Parameters",
            "2A05": "Service Changed",
            "2A19": "Battery Level",
            "2A24": "Model Number String",
            "2A25": "Serial Number String",
            "2A26": "Firmware Revision String",
            "2A27": "Hardware Revision String",
            "2A28": "Software Revision String",
            "2A29": "Manufacturer Name String",
            "2A37": "Heart Rate Measurement",
            "2A38": "Body Sensor Location",
            "2A50": "PnP ID",
        ]
        return names[uuid.uuidString.uppercased()]
    }
}

// MARK: - InspectorView

struct InspectorView: View {
    let bluetooth: BluetoothManager
    @State private var showExport = false

    private var isConnected: Bool {
        if case .connected = bluetooth.connectionState { return true }
        return false
    }

    var body: some View {
        List {
            if bluetooth.discoveredServices.isEmpty {
                emptyState
            } else {
                ForEach(bluetooth.discoveredServices, id: \.uuid) { service in
                    serviceSection(for: service)
                }
            }
        }
        .navigationTitle("BLE Inspector")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showExport) {
            ExportSheet(report: bluetooth.exportReport())
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No services discovered")
                    .font(.headline)
                Text("Connect to a device from the main screen, then return here to inspect its services and characteristics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Service section

    @ViewBuilder
    private func serviceSection(for service: CBService) -> some View {
        let chars = bluetooth.characteristicInfos.filter { $0.serviceUUID == service.uuid }
        Section(header: serviceSectionHeader(service)) {
            ForEach(chars) { info in
                CharacteristicRow(infoID: info.id, bluetooth: bluetooth)
            }
            if chars.isEmpty {
                Text("No characteristics discovered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func serviceSectionHeader(_ service: CBService) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let name = BLEKnownNames.service(service.uuid) {
                Text(name).font(.caption.bold()).textCase(nil)
            }
            Text(service.uuid.uuidString)
                .font(.system(size: 10, design: .monospaced))
                .textCase(nil)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Read All") { bluetooth.readAllReadable() }
                .disabled(!isConnected)
            Spacer()
            Button("Sub All") { bluetooth.subscribeAll() }
                .disabled(!isConnected)
            Spacer()
            Button("Unsub All") { bluetooth.unsubscribeAll() }
                .disabled(!isConnected)
            Spacer()
            Button {
                showExport = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - CharacteristicRow

struct CharacteristicRow: View {
    let infoID: String
    let bluetooth: BluetoothManager
    @State private var showWriteSheet = false

    private var info: CharacteristicInfo? {
        bluetooth.characteristicInfos.first { $0.id == infoID }
    }

    var body: some View {
        if let info {
            VStack(alignment: .leading, spacing: 6) {
                charHeader(info)
                if let data = info.lastValue { valueDisplay(info, data: data) }
                actionButtons(info)
            }
            .padding(.vertical, 4)
            .sheet(isPresented: $showWriteSheet) {
                WriteConsoleView(info: info, bluetooth: bluetooth)
            }
        }
    }

    @ViewBuilder
    private func charHeader(_ info: CharacteristicInfo) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if let name = BLEKnownNames.characteristic(info.charUUID) {
                    Text(name).font(.subheadline.bold())
                }
                Text(info.charUUID.uuidString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            propsBadges(info.characteristic.properties, isNotifying: info.isNotifying)
        }
    }

    @ViewBuilder
    private func valueDisplay(_ info: CharacteristicInfo, data: Data) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(info.hexString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
            if let utf8 = info.utf8Value {
                Text("\"\(utf8)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let ts = info.lastUpdatedAt {
                Text("Updated \(BLEEvent.timeFormatter.string(from: ts))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(6)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func actionButtons(_ info: CharacteristicInfo) -> some View {
        let props = info.characteristic.properties
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if props.contains(.read) {
                    Button("Read") { bluetooth.readCharacteristic(info.characteristic) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if props.contains(.notify) || props.contains(.indicate) {
                    Button(info.isNotifying ? "Unsubscribe" : "Subscribe") {
                        bluetooth.setNotify(!info.isNotifying, for: info.characteristic)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(info.isNotifying ? .green : .blue)
                }
                if props.contains(.write) || props.contains(.writeWithoutResponse) {
                    Button("Write…") { showWriteSheet = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.orange)
                }
                Button {
                    let text = "\(info.charUUID.uuidString): \(info.hexString)"
                    UIPasteboard.general.string = text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func propsBadges(_ props: CBCharacteristicProperties, isNotifying: Bool) -> some View {
        HStack(spacing: 3) {
            if props.contains(.read)                 { badge("R", .blue) }
            if props.contains(.write)                { badge("W", .orange) }
            if props.contains(.writeWithoutResponse) { badge("W*", .orange) }
            if props.contains(.notify)               { badge("N", isNotifying ? .green : .gray) }
            if props.contains(.indicate)             { badge("I", isNotifying ? .green : .gray) }
        }
    }

    private func badge(_ label: String, _ color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - ExportSheet

struct ExportSheet: View {
    let report: String
    var title: String = "BLE Report"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(report)
                    .font(.system(size: 11, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: report, preview: SharePreview(title))
                }
            }
        }
    }
}
