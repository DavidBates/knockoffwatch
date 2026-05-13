import SwiftUI

struct KeepAliveTestView: View {
    @Bindable var bluetooth: BluetoothManager

    private var isConnected: Bool {
        if case .connected = bluetooth.connectionState { return true }
        return false
    }

    var body: some View {
        List {
            presetsSection
            commandSection
            statusSection
            logSection
        }
        .navigationTitle("Keep Alive Test")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Presets

    private var presetsSection: some View {
        Section {
            presetRow(
                title: "No Keep-Alive",
                subtitle: "Connection may drop after ~30s",
                active: bluetooth.keepAliveMode == .none
            ) {
                bluetooth.setKeepAliveMode(.none)
            }
            presetRow(
                title: "Battery Read every 5s",
                subtitle: "Reads battery level to keep GATT alive",
                active: bluetooth.keepAliveMode == .batteryRead
            ) {
                bluetooth.keepAliveIntervalSeconds = 5
                bluetooth.setKeepAliveMode(.batteryRead)
            }
            presetRow(
                title: "Custom UART every 5s",
                subtitle: bluetooth.customKeepAliveHex.isEmpty
                    ? "Set a custom command below first"
                    : "Sends: \(bluetooth.customKeepAliveHex)",
                active: bluetooth.keepAliveMode == .uartPing
            ) {
                bluetooth.keepAliveIntervalSeconds = 5
                bluetooth.setKeepAliveMode(.uartPing)
            }
        } header: {
            Text("Presets")
        } footer: {
            if !isConnected {
                Text("Connect to a device to start testing.")
            }
        }
    }

    private func presetRow(title: String, subtitle: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if active {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .font(.caption.bold())
                }
            }
        }
        .disabled(!isConnected)
    }

    // MARK: - Custom command

    private var commandSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Hex bytes (e.g. DF 00 06 F7 02 01 0D 00 01 01)", text: $bluetooth.customKeepAliveHex)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                if !bluetooth.customKeepAliveHex.isEmpty {
                    if let data = BluetoothManager.parseHex(bluetooth.customKeepAliveHex) {
                        Text("\(data.count) bytes — \(CharacteristicInfo.toHex(data))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.green)
                    } else {
                        Text("Invalid hex — enter pairs like: DF 00 06 F7 02")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        } header: {
            Text("Custom Command (UART Ping / idle)")
        } footer: {
            Text("Sent each tick when UART Ping mode is active and no HR measurement is running. Leave empty to skip the tick.")
                .font(.caption2)
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Mode", value: bluetooth.keepAliveMode.label)
            if bluetooth.keepAliveMode != .none {
                Stepper(
                    "Interval: \(Int(bluetooth.keepAliveIntervalSeconds))s",
                    value: Binding(
                        get: { bluetooth.keepAliveIntervalSeconds },
                        set: { bluetooth.keepAliveIntervalSeconds = $0 }
                    ),
                    in: 1...60, step: 1
                )
                .font(.caption)
            }
            if bluetooth.isKeepAliveRunning {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.75)
                    Text("Running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let d = bluetooth.lastDisconnectDuration {
                LabeledContent("Last session", value: formatDuration(d))
            }
            if let r = bluetooth.lastDisconnectReason {
                LabeledContent("Last disconnect") {
                    Text(r)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    // MARK: - Log

    private var logSection: some View {
        let events = Array(bluetooth.eventLog
            .filter { e in
                e.message.hasPrefix("Keep-alive") ||
                e.message.hasPrefix("Disconnect") ||
                e.message.hasPrefix("Connected") ||
                e.message.hasPrefix("HR command acknowledged")
            }
            .suffix(50)
            .reversed())

        return Section("Keep-Alive Log (\(events.count))") {
            if events.isEmpty {
                Text("No events yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events) { event in
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
