import Foundation
import CoreBluetooth

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

@Observable
final class BluetoothManager: NSObject {
    private(set) var centralState: CBManagerState = .unknown
    private(set) var peripherals: [DiscoveredPeripheral] = []
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var batteryLevel: Int? = nil
    private(set) var statusMessage = "Tap Scan to start."
    private(set) var discoveredServices: [CBService] = []
    private(set) var discoveredCharacteristics: [CBCharacteristic] = []

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?

    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelUUID = CBUUID(string: "2A19")
    // Ready for Phase 2 health data inspection
    private let heartRateServiceUUID = CBUUID(string: "180D")

    var isScanning: Bool { central?.isScanning ?? false }

    override init() {
        super.init()
        // queue: .main ensures all delegate callbacks fire on the main thread,
        // which is required for @MainActor-isolated property mutations below.
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        peripherals.removeAll()
        batteryLevel = nil
        discoveredServices.removeAll()
        discoveredCharacteristics.removeAll()
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
        peripheral.delegate = self
        connectionState = .connecting
        statusMessage = "Connecting to \(entry.name)..."
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let p = connectedPeripheral else { return }
        central.cancelPeripheralConnection(p)
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
                    id: id,
                    peripheral: peripheral,
                    name: name,
                    rssi: rssiValue,
                    advertisementSummary: summary
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
            connectionState = .connected
            discoveredServices.removeAll()
            discoveredCharacteristics.removeAll()
            statusMessage = "Connected. Discovering services..."
            // Discover all services so the debug view shows everything the watch exposes
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let msg = error?.localizedDescription ?? "Unknown error"
        Task { @MainActor [weak self] in
            guard let self else { return }
            connectionState = .failed(msg)
            statusMessage = "Failed to connect: \(msg)"
            connectedPeripheral = nil
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let msg = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            connectionState = .disconnected
            batteryLevel = nil
            connectedPeripheral = nil
            statusMessage = msg.map { "Disconnected: \($0)" } ?? "Disconnected."
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
                statusMessage = "Service discovery failed: \(msg)"
                return
            }
            discoveredServices = services
            for service in services {
                print("[BLE] Service: \(service.uuid)")
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
        let errMsg = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let msg = errMsg {
                statusMessage = "Characteristic discovery failed: \(msg)"
                return
            }
            for char in chars {
                if !discoveredCharacteristics.contains(where: { $0.uuid == char.uuid }) {
                    discoveredCharacteristics.append(char)
                }
                print("[BLE] Characteristic: \(char.uuid) | \(Self.describeProperties(char.properties))")
                if char.uuid == batteryLevelUUID {
                    statusMessage = "Reading battery level..."
                    if char.properties.contains(.read) { peripheral.readValue(for: char) }
                    if char.properties.contains(.notify) { peripheral.setNotifyValue(true, for: char) }
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
                statusMessage = "Read failed: \(msg)"
                return
            }
            if uuid == batteryLevelUUID, let d = data, let level = d.first.map({ Int($0) }) {
                batteryLevel = level
                statusMessage = "Battery updated."
            }
        }
    }
}

// MARK: - Static helpers (nonisolated, safe to call from any context)

private extension BluetoothManager {
    static func describeProperties(_ props: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if props.contains(.read)                { parts.append("read") }
        if props.contains(.write)               { parts.append("write") }
        if props.contains(.notify)              { parts.append("notify") }
        if props.contains(.indicate)            { parts.append("indicate") }
        if props.contains(.writeWithoutResponse){ parts.append("writeNoResp") }
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
}
