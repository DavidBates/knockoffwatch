import SwiftUI
import UIKit
import CoreBluetooth

struct IdleMonitorView: View {
    @Bindable var bluetooth: BluetoothManager

    var body: some View {
        List {
            statusSection
            controlsSection
            optionsSection
            if !bluetooth.idleMonitorEvents.isEmpty || bluetooth.idleMonitorActive {
                summarySection
            }
            if !bluetooth.idleMonitorSignatures.isEmpty {
                signaturesSection
            }
            if !bluetooth.idleMonitorEvents.isEmpty {
                eventsSection
            }
        }
        .navigationTitle("Idle BLE Monitor")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .onChange(of: bluetooth.keepScreenAwake) { _, enabled in
            UIApplication.shared.isIdleTimerDisabled = enabled
        }
        .onDisappear {
            if !bluetooth.keepScreenAwake {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section("Status") {
            HStack(spacing: 12) {
                Circle()
                    .fill(bluetooth.idleMonitorActive ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                if bluetooth.idleMonitorActive {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Monitoring")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                        Text(formatDuration(bluetooth.idleMonitorDuration))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Inactive")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if bluetooth.idleMonitorTotalNotifications > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(bluetooth.idleMonitorTotalNotifications)")
                            .font(.title2.bold())
                        Text("packets")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        Section("Controls") {
            if bluetooth.idleMonitorActive {
                Button(role: .destructive) { bluetooth.stopIdleMonitor() } label: {
                    Label("Stop Monitor", systemImage: "stop.circle.fill")
                }
            } else {
                Button { bluetooth.startIdleMonitor() } label: {
                    Label("Start Monitor", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(bluetooth.centralState != .poweredOn)
            }

            Button { bluetooth.clearIdleMonitorLog() } label: {
                Label("Clear Log", systemImage: "trash")
            }
            .disabled(bluetooth.idleMonitorEvents.isEmpty)

            ShareLink(
                item: bluetooth.exportIdleMonitorJSON(),
                subject: Text("Idle BLE Monitor Log"),
                message: Text("Exported from LaxasFit app")
            ) {
                Label("Export JSON", systemImage: "square.and.arrow.up")
            }
            .disabled(bluetooth.idleMonitorEvents.isEmpty)
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        Section("Options") {
            Toggle("Keep Screen Awake", isOn: Binding(
                get: { bluetooth.keepScreenAwake },
                set: { bluetooth.setKeepScreenAwake($0) }
            ))

            Toggle("Battery Read Keepalive", isOn: Binding(
                get: { bluetooth.idleMonitorKeepAlive },
                set: { bluetooth.setIdleMonitorKeepAlive($0) }
            ))

            if bluetooth.idleMonitorKeepAlive {
                Text("Reads battery level every 60s. These reads are app-generated and labeled separately from watch notifications.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section("Summary") {
            LabeledContent("Duration") {
                Text(formatDuration(bluetooth.idleMonitorDuration)).foregroundStyle(.secondary)
            }
            LabeledContent("Total notifications") {
                Text("\(bluetooth.idleMonitorTotalNotifications)").foregroundStyle(.secondary)
            }
            LabeledContent("Disconnects / Reconnects") {
                Text("\(bluetooth.idleMonitorDisconnectCount) / \(bluetooth.idleMonitorReconnectCount)")
                    .foregroundStyle(.secondary)
            }
            if let t = bluetooth.idleMonitorTimeSinceLastPacket {
                LabeledContent("Last packet") {
                    Text(String(format: "%.1fs ago", t)).foregroundStyle(.secondary)
                }
            }

            let byChar = bluetooth.notificationsByCharacteristic()
            if !byChar.isEmpty {
                DisclosureGroup("By Characteristic (\(byChar.count))") {
                    ForEach(byChar, id: \.0) { charUUID, count in
                        LabeledContent {
                            Text("\(count)").foregroundStyle(.secondary)
                        } label: {
                            Text(charUUID.count > 10 ? String(charUUID.prefix(8)) + "…" : charUUID)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Signatures

    private var signaturesSection: some View {
        let sorted = bluetooth.idleMonitorSignatures.sorted { $0.count > $1.count }
        return Section {
            ForEach(sorted) { sig in
                VStack(alignment: .leading, spacing: 3) {
                    Text(sig.id)
                        .font(.system(size: 11, design: .monospaced))
                    HStack(spacing: 8) {
                        Text("\(sig.count)×")
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                        if let avg = sig.averageIntervalSeconds {
                            Text("avg \(String(format: "%.0f", avg))s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let last = sig.lastSeen {
                            Text(BLEEvent.timeFormatter.string(from: last))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        } header: {
            Text("Recurring Packet Signatures (\(sorted.count))")
        } footer: {
            Text("Grouped by first 8 bytes. Average interval computed across all observed occurrences.")
                .font(.caption2)
        }
    }

    // MARK: - Events

    private var eventsSection: some View {
        let events = bluetooth.idleMonitorEvents.suffix(100)
        return Section {
            ForEach(events.reversed()) { event in
                IdleMonitorEventRow(event: event)
            }
        } header: {
            Text("Recent Events (last \(min(100, bluetooth.idleMonitorEvents.count)) of \(bluetooth.idleMonitorEvents.count))")
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Event Row

struct IdleMonitorEventRow: View {
    let event: IdleMonitorEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(BLEEvent.timeFormatter.string(from: event.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("+\(event.elapsedMS)ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                if let tag = decodedTag {
                    Text(tag)
                        .font(.system(size: 9, design: .monospaced))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(tagColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(tagColor)
                }
            }
            Text(event.label)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(2)
            if case .notification(let p) = event.kind {
                if let detail = p.decodedDetail {
                    Text(detail)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                }
                if let utf8 = p.utf8String {
                    Text("\"\(utf8)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 1)
    }

    private var decodedTag: String? {
        guard case .notification(let p) = event.kind else { return nil }
        return p.decodedLabel
    }

    private var tagColor: Color {
        guard case .notification(let p) = event.kind, let label = p.decodedLabel else { return .secondary }
        switch label {
        case "heartRateResult":       return .red
        case "bloodPressureResult":   return .orange
        case "spO2Result":            return .blue
        case "bloodPressureLiveData": return .yellow
        case "hrLiveSensor":          return .pink
        case "ack/status":            return .gray
        default:                      return .purple
        }
    }
}
