import SwiftUI
import CoreBluetooth

// MARK: - ProtocolView

struct ProtocolView: View {
    let bluetooth: BluetoothManager
    @State private var showExport = false

    private var isConnected: Bool {
        if case .connected = bluetooth.connectionState { return true }
        return false
    }

    var body: some View {
        List {
            recordSection
            pairsSection
            if !bluetooth.protocolSessionLog.isEmpty {
                logSection
            } else {
                emptyLogState
            }
        }
        .navigationTitle("Protocol Discovery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showExport) {
            ExportSheet(report: bluetooth.exportProtocolJSON(), title: "Protocol JSON")
        }
    }

    // MARK: - Record section

    private var recordSection: some View {
        Section {
            if bluetooth.isRecordingInteraction {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recording interaction…")
                            .font(.subheadline.bold())
                            .foregroundStyle(.red)
                        Text("\(bluetooth.protocolSessionLog.count) events captured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Stop") { bluetooth.stopRecording() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                }
                .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Record Interaction")
                        .font(.subheadline.bold())
                    Text("Subscribes to all notify characteristics and logs every emission. Trigger a health measurement on the watch to capture which channel carries health data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Start Recording") { bluetooth.startRecording() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!isConnected)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Interaction Recording")
        } footer: {
            if !bluetooth.isRecordingInteraction {
                Text("Writes and paired responses are always logged, even without recording.")
                    .font(.caption2)
            }
        }
    }

    // MARK: - Channel pairs section

    private var pairsSection: some View {
        Section("Channel Pairs") {
            ForEach(bluetooth.channelPairs) { pair in
                PairCard(pair: pair)
            }
        }
    }

    // MARK: - Log section

    @ViewBuilder
    private var logSection: some View {
        Section {
            ForEach(bluetooth.protocolSessionLog.suffix(60).reversed()) { event in
                ProtocolEventRow(event: event)
            }
            if bluetooth.protocolSessionLog.count > 60 {
                Text("… \(bluetooth.protocolSessionLog.count - 60) earlier events. Export JSON for the full log.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            }
        } header: {
            HStack {
                Text("Protocol Log (\(bluetooth.protocolSessionLog.count))")
                Spacer()
                Button("Clear") { bluetooth.clearProtocolLog() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
            }
        }
    }

    private var emptyLogState: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No events yet")
                    .font(.headline)
                Text("Connect to a device, then write to a characteristic or start recording to capture events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showExport = true
            } label: {
                Image(systemName: "arrow.down.doc")
            }
            .disabled(bluetooth.protocolSessionLog.isEmpty)
        }
    }
}

// MARK: - PairCard

struct PairCard: View {
    let pair: ChannelPair

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pair.label)
                    .font(.subheadline.bold())
                Spacer()
                HStack(spacing: 4) {
                    discoveryChip("W", discovered: pair.writeCharDiscovered)
                    discoveryChip("N", discovered: pair.notifyCharDiscovered)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                uuidRow(prefix: "W", uuid: pair.writeUUIDPrefix, discovered: pair.writeCharDiscovered)
                uuidRow(prefix: "N", uuid: pair.notifyUUIDPrefix, discovered: pair.notifyCharDiscovered)
            }

            if pair.lastCommand != nil || pair.lastResponse != nil {
                Divider()
                if let cmd = pair.lastCommand {
                    HStack {
                        Text("CMD")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                        Text(cmd)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                        if let t = pair.lastCommandTime {
                            Spacer()
                            Text(BLEEvent.timeFormatter.string(from: t))
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                if let resp = pair.lastResponse {
                    HStack {
                        Text("RSP")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                        Text(resp)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        if let ms = pair.responseLatencyMS {
                            Text("+\(ms)ms")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let t = pair.lastResponseTime {
                        Text(BLEEvent.timeFormatter.string(from: t))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func discoveryChip(_ label: String, discovered: Bool) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(discovered ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
            .foregroundStyle(discovered ? Color.green : Color.gray)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func uuidRow(prefix: String, uuid: String, discovered: Bool) -> some View {
        HStack(spacing: 5) {
            Text(prefix)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(prefix == "W" ? Color.orange : Color.blue)
                .frame(width: 10)
            Text(uuid)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(discovered ? Color.primary : Color.secondary)
            if !discovered {
                Text("not found")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - ProtocolEventRow

struct ProtocolEventRow: View {
    let event: ProtocolEvent

    private var kindColor: Color {
        switch event.kind {
        case .sessionStart: return .gray
        case .write:        return .orange
        case .writeAck:     return .yellow
        case .notification: return .green
        case .read:         return .blue
        }
    }

    private var shortUUID: String {
        event.charUUID.count > 8 ? String(event.charUUID.prefix(8)) + "…" : event.charUUID
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(event.kind.label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(kindColor.opacity(0.15))
                .foregroundStyle(kindColor)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .fixedSize()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(shortUUID)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("+\(event.sessionRelativeMS)ms")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                if !event.hexBytes.isEmpty && event.hexBytes != "OK" {
                    Text(event.hexBytes)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(2)
                }
                if let ms = event.writeRelativeMS {
                    Text("↳ +\(ms)ms after write")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
