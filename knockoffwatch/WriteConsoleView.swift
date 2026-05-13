import SwiftUI
import CoreBluetooth

struct WriteConsoleView: View {
    let info: CharacteristicInfo
    let bluetooth: BluetoothManager
    @Environment(\.dismiss) private var dismiss

    @State private var hexInput = ""
    @State private var sendResult: SendResult? = nil

    enum SendResult {
        case sent(String)
        case invalid
    }

    var body: some View {
        NavigationStack {
            Form {
                charInfoSection
                warningSection
                inputSection
                if let result = sendResult { resultSection(result) }
                recentEventsSection
            }
            .navigationTitle("Write Characteristic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var charInfoSection: some View {
        Section("Characteristic") {
            LabeledContent("UUID", value: info.charUUID.uuidString)
            LabeledContent("Service", value: info.serviceUUID.uuidString)
            LabeledContent("Write type", value: writeTypeLabel)
            if let hex = info.lastValue.map({ CharacteristicInfo.toHex($0) }) {
                LabeledContent("Last known value", value: hex)
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }

    private var warningSection: some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.top, 1)
                Text("Writing to unknown characteristics may change watch state, trigger unexpected behavior, or cause instability. Only send bytes you understand.")
                    .font(.caption)
            }
        }
    }

    private var inputSection: some View {
        Section("Hex Bytes") {
            VStack(alignment: .leading, spacing: 6) {
                TextField("e.g.  A1 02 FF  or  A102FF", text: $hexInput)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.send)
                    .onSubmit { attemptSend() }

                if !hexInput.isEmpty {
                    if let data = parsed {
                        Text("\(data.count) byte\(data.count == 1 ? "" : "s") — \(CharacteristicInfo.toHex(data))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.green)
                    } else {
                        Text("Invalid hex — enter pairs like: A1 02 FF")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Button("Send") { attemptSend() }
                .disabled(parsed == nil)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func resultSection(_ result: SendResult) -> some View {
        Section("Last Send") {
            switch result {
            case .sent(let desc):
                Label(desc, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Check the event log in BLE Debug for the write response.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .invalid:
                Label("Invalid hex input — nothing sent.", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private var recentEventsSection: some View {
        let relevant = bluetooth.eventLog
            .suffix(20)
            .filter { $0.message.contains(info.charUUID.uuidString) }
            .reversed()
        return Group {
            if !relevant.isEmpty {
                Section("Recent Events for This Characteristic") {
                    ForEach(Array(relevant)) { event in
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
    }

    // MARK: - Helpers

    private var parsed: Data? { BluetoothManager.parseHex(hexInput) }

    private var writeTypeLabel: String {
        let props = info.characteristic.properties
        if props.contains(.write) && props.contains(.writeWithoutResponse) {
            return "With response (preferred)"
        } else if props.contains(.write) {
            return "With response"
        } else if props.contains(.writeWithoutResponse) {
            return "Without response"
        }
        return "Not writable"
    }

    private func attemptSend() {
        guard parsed != nil else { sendResult = .invalid; return }
        let ok = bluetooth.writeCharacteristic(info.characteristic, hexInput: hexInput)
        if ok {
            let clean = hexInput.replacingOccurrences(of: " ", with: "").uppercased()
            sendResult = .sent("Sent: \(clean)")
        } else {
            sendResult = .invalid
        }
    }
}
