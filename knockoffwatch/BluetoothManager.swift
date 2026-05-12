import Foundation
import CoreBluetooth

// MARK: - Supporting Types

struct BLEEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String

    var timeString: String { BLEEvent.timeFormatter.string(from: timestamp) }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.S"
        return f
    }()
}

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

struct DiscoveredPeripheral: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    var rssi: Int
    var advertisementSummary: String
}

// MARK: - BluetoothManager

@Observable
final class BluetoothManager: NSObject {

    // MARK: Observable state

    private(set) var centralState: CBManagerState = .unknown
    private(set) var peripherals: [DiscoveredPeripheral] = []
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var batteryLevel: Int? = nil
    private(set) var statusMessage = "Tap Scan to start."
    private(set) var discoveredServices: [CBService] = []
    private(set) var discoveredCharacteristics: [CBCharacteristic] = []
    private(set) var eventLog: [BLEEvent] = []
    private(set) var lastDisconnectDuration: TimeInterval? = nil
    private(set) var lastDisconnectReason: String? = nil
    private(set) var isKeepAliveRunning = false
    var keepAliveEnabled = false

    // MARK: Private

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var batteryLevelChar: CBCharacteristic?
    private var connectAttemptTime: Date?
    private var connectedAt: Date?
    private var keepAliveTask: Task<Void, Never>?

    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelUUID = CBUUID(string: "2A19")
    private let heartRateServiceUUID = CBUUID(string: "180D") // Phase 2

    var isScanning: Bool { central?.isScanning ?? false }

    override init() {
        super.init()
        // queue: .main ensures all CBDelegate callbacks fire on the main thread.
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    func startScan() {
        guard central.state == .poweredOn else { return }
        peripherals.removeAll()
        batteryLevel = nil
        discoveredServices.removeAll()
        discoveredCharacteristics.removeAll()
        logEvent("--- Scan started ---")
        statusMessage = "Scanning..."
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
        if statusMessage == "Scanning..." {
            statusMessage = peripherals.isEmpty
                ? "No devices found."
                : "Found \(peripherals.count) device(s)."
        }
    }

    func connect(to entry: DiscoveredPeripheral) {
        stopScan()
        let peripheral = entry.peripheral
        connectedPeripheral = peripheral
        batteryLevelChar = nil
        peripheral.delegate = self
        connectionState = .connecting
        connectAttemptTime = Date()
        statusMessage = "Connecting to \(entry.name)..."
        logEvent("Connect → \(entry.name) [\(entry.id.uuidString.prefix(8))…]")
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let p = connectedPeripheral else { return }
        logEvent("Disconnect requested by user")
        central.cancelPeripheralConnection(p)
    }

    func setKeepAlive(_ enabled: Bool) {
        keepAliveEnabled = enabled
        if enabled {
            startKeepAlive()
        } else {
            stopKeepAlive()
        }
    }

    // MARK: - Private helpers

    private func logEvent(_ message: String) {
        let event = BLEEvent(timestamp: Date(), message: message)
        eventLog.append(event)
        print("[BLE \(event.timeString)] \(message)")
        if eventLog.count > 100 { eventLog.removeFirst(eventLog.count - 100) }
    }

    private func startKeepAlive() {
        guard keepAliveEnabled,
              case .connected = connectionState,
              let peripheral = connectedPeripheral,
              let char = batteryLevelChar else { return }
        stopKeepAlive()
        isKeepAliveRunning = true
        logEvent("Keep-alive: starting — read every 2s for 120s")

        keepAliveTask = Task { @MainActor [weak self] in
            let deadline = ContinuousClock.now.advanced(by: .seconds(120))
            var count = 0
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, self.keepAliveEnabled else { break }
                guard case .connected = self.connectionState else {
                    self.logEvent("Keep-alive: stopping (no longer connected)")
                    break
                }
                count += 1
                self.logEvent("Keep-alive: battery read #\(count)")
                peripheral.readValue(for: char)
            }
            guard let self else { return }
            self.isKeepAliveRunning = false
            if !Task.isCancelled {
                self.logEvent("Keep-alive: finished after \(count) reads")
            }
        }
    }

    private func stopKeepAlive() {
        guard keepAliveTask != nil else { return }
        keepAliveTask?.cancel()
        keepAliveTask = nil
        isKeepAliveRunning = false
        logEvent("Keep-alive: stopped")
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor [weak self] in
            guard let self else { return }
            centralState = state
            switch state {
            case .poweredOn:    statusMessage = "Bluetooth ready. Tap Scan."
            case .poweredOff:   statusMessage = "Bluetooth is off."
            case .unauthorized: statusMessage = "Bluetooth permission denied."
            case .unsupported:  statusMessage = "Bluetooth not supported on this device."
            default:            statusMessage = "Bluetooth unavailable."
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier
        let rssiValue = RSSI.intValue
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Unknown"
        let summary = Self.formatAdvertisementData(advertisementData)

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let idx = peripherals.firstIndex(where: { $0.id == id }) {
                peripherals[idx].rssi = rssiValue
            } else {
                peripherals.append(DiscoveredPeripheral(
                    id: id, peripheral: peripheral,
                    name: name, rssi: rssiValue, advertisementSummary: summary
                ))
                peripherals.sort {
                    if $0.name == "Unknown" { return false }
                    if $1.name == "Unknown" { return true }
                    return $0.name < $1.name
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let elapsed = connectAttemptTime.map { Date().timeIntervalSince($0) }
            connectedAt = Date()
            connectionState = .connected
            discoveredServices.removeAll()
            discoveredCharacteristics.removeAll()
            statusMessage = "Connected. Discovering services..."
            let elapsedStr = elapsed.map { String(format: " in %.2fs", $0) } ?? ""
            logEvent("Connected\(elapsedStr) — discovering all services")
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let msg = error?.localizedDescription ?? "unknown error"
        Task { @MainActor [weak self] in
            guard let self else { return }
            connectionState = .failed(msg)
            statusMessage = "Failed to connect: \(msg)"
            connectedPeripheral = nil
            connectAttemptTime = nil
            logEvent("Connection FAILED: \(msg)")
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let reason = Self.describeDisconnectError(error)
        let hasError = error != nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            stopKeepAlive()

            let duration = connectedAt.map { Date().timeIntervalSince($0) }
            lastDisconnectDuration = duration
            lastDisconnectReason = hasError ? reason : nil

            let durationStr = duration.map { Self.formatDuration($0) } ?? "?"
            let suffix = hasError ? " — \(reason)" : " (clean)"
            logEvent("Disconnected after \(durationStr)\(suffix)")

            connectionState = .disconnected
            batteryLevel = nil
            connectedPeripheral = nil
            batteryLevelChar = nil
            connectedAt = nil
            connectAttemptTime = nil
            statusMessage = hasError
                ? "Disconnected (\(durationStr)): \(reason)"
                : "Disconnected after \(durationStr)."
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        let errMsg = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let msg = errMsg {
                logEvent("Service discovery FAILED: \(msg)")
                statusMessage = "Service discovery failed: \(msg)"
                return
            }
            discoveredServices = services
            let uuids = services.map(\.uuid.uuidString).joined(separator: ", ")
            logEvent("Services (\(services.count)): \(uuids)")
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let chars = service.characteristics ?? []
        let serviceUUID = service.uuid
        let errMsg = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let msg = errMsg {
                logEvent("Char discovery FAILED for \(serviceUUID): \(msg)")
                statusMessage = "Characteristic discovery failed: \(msg)"
                return
            }
            for char in chars {
                if !discoveredCharacteristics.contains(where: { $0.uuid == char.uuid }) {
                    discoveredCharacteristics.append(char)
                }
                let props = Self.describeProperties(char.properties)
                logEvent("  \(serviceUUID)/\(char.uuid) [\(props)]")

                if char.uuid == batteryLevelUUID {
                    batteryLevelChar = char
                    statusMessage = "Reading battery level..."
                    if char.properties.contains(.read) {
                        logEvent("Battery: requesting read")
                        peripheral.readValue(for: char)
                    }
                    if char.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: char)
                    }
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let data = characteristic.value
        let uuid = characteristic.uuid
        let errMsg = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let msg = errMsg {
                logEvent("Read FAILED (\(uuid)): \(msg)")
                statusMessage = "Read failed: \(msg)"
                return
            }
            if uuid == batteryLevelUUID, let d = data, let level = d.first.map({ Int($0) }) {
                let isFirst = batteryLevel == nil
                batteryLevel = level
                logEvent("Battery: \(level)%\(isFirst ? " (first read)" : "")")
                if isFirst {
                    statusMessage = "Battery: \(level)%"
                    startKeepAlive() // no-op if keepAliveEnabled is false
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let uuid = characteristic.uuid
        let isNotifying = characteristic.isNotifying
        let errMsg = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let msg = errMsg {
                logEvent("Notify subscribe FAILED (\(uuid)): \(msg)")
            } else {
                logEvent("Notify \(isNotifying ? "ENABLED" : "disabled") for \(uuid)")
            }
        }
    }
}

// MARK: - Static helpers

private extension BluetoothManager {
    static func describeProperties(_ props: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if props.contains(.read)                 { parts.append("read") }
        if props.contains(.write)                { parts.append("write") }
        if props.contains(.notify)               { parts.append("notify") }
        if props.contains(.indicate)             { parts.append("indicate") }
        if props.contains(.writeWithoutResponse) { parts.append("writeNoResp") }
        return parts.isEmpty ? "none" : parts.joined(separator: ", ")
    }

    static func formatAdvertisementData(_ data: [String: Any]) -> String {
        var parts: [String] = []
        if let uuids = data[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID], !uuids.isEmpty {
            parts.append("services: " + uuids.map(\.uuidString).joined(separator: ", "))
        }
        if let tx = data[CBAdvertisementDataTxPowerLevelKey] as? Int {
            parts.append("tx: \(tx) dBm")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " | ")
    }

    static func describeDisconnectError(_ error: Error?) -> String {
        guard let error else { return "clean" }
        let ns = error as NSError
        if ns.domain == CBErrorDomain, let code = CBError.Code(rawValue: ns.code) {
            return "\(code.debugName) (CBError \(ns.code))"
        }
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }

    static func formatDuration(_ t: TimeInterval) -> String {
        t < 60
            ? String(format: "%.1fs", t)
            : "\(Int(t) / 60)m \(Int(t) % 60)s"
    }
}

// MARK: - CBError.Code debug names

private extension CBError.Code {
    var debugName: String {
        switch self {
        case .unknown:                       return "unknown"
        case .invalidParameters:             return "invalidParameters"
        case .invalidHandle:                 return "invalidHandle"
        case .notConnected:                  return "notConnected"
        case .outOfSpace:                    return "outOfSpace"
        case .operationCancelled:            return "operationCancelled"
        case .connectionTimeout:             return "connectionTimeout"
        case .peripheralDisconnected:        return "peripheralDisconnected"
        case .uuidNotAllowed:                return "uuidNotAllowed"
        case .alreadyAdvertising:            return "alreadyAdvertising"
        case .connectionFailed:              return "connectionFailed"
        case .connectionLimitReached:        return "connectionLimitReached"
        case .unknownDevice:                 return "unknownDevice"
        case .operationNotSupported:         return "operationNotSupported"
        case .peerRemovedPairingInformation: return "peerRemovedPairingInformation"
        case .encryptionTimedOut:            return "encryptionTimedOut"
        case .tooManyLEPairedDevices:        return "tooManyLEPairedDevices"
        @unknown default:                    return "CBError(\(rawValue))"
        }
    }
}
