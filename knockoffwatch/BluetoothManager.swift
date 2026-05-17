import Foundation
import CoreBluetooth
import BackgroundTasks

// MARK: - Supporting Types

struct BLEEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String

    var timeString: String { BLEEvent.timeFormatter.string(from: timestamp) }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.S"
        return f
    }()
}

struct CharacteristicInfo: Identifiable {
    let id: String
    let characteristic: CBCharacteristic
    let serviceUUID: CBUUID
    var lastValue: Data? = nil
    var lastUpdatedAt: Date? = nil
    var isNotifying: Bool = false

    var charUUID: CBUUID { characteristic.uuid }

    var hexString: String { lastValue.map { CharacteristicInfo.toHex($0) } ?? "—" }

    var utf8Value: String? {
        guard let data = lastValue, !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func toHex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func makeID(service: CBUUID, char: CBUUID) -> String { "\(service)/\(char)" }
}

struct ProtocolEvent: Identifiable {
    enum Kind {
        case sessionStart, write, writeAck, notification, read

        var label: String {
            switch self {
            case .sessionStart:  return "SESSION"
            case .write:         return "WRITE"
            case .writeAck:      return "ACK"
            case .notification:  return "NOTIFY"
            case .read:          return "READ"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let timestamp: Date
    let sessionRelativeMS: Int
    var writeRelativeMS: Int?
    let charUUID: String
    let hexBytes: String
    let byteCount: Int
    var writeType: String?
    var pairedWriteUUID: String?
}

struct ChannelPair: Identifiable {
    let id: String
    let label: String
    let writeUUIDPrefix: String
    let notifyUUIDPrefix: String
    var lastCommand: String?
    var lastCommandTime: Date?
    var lastResponse: String?
    var lastResponseTime: Date?
    var writeCharDiscovered = false
    var notifyCharDiscovered = false

    var responseLatencyMS: Int? {
        guard let ct = lastCommandTime, let rt = lastResponseTime, rt >= ct else { return nil }
        return Int(rt.timeIntervalSince(ct) * 1000)
    }
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

enum KeepAliveMode: Equatable {
    case none
    case batteryRead
    case uartPing

    var label: String {
        switch self {
        case .none:        return "none"
        case .batteryRead: return "batteryRead"
        case .uartPing:    return "uartPing"
        }
    }
}

enum ForegroundSyncInterval: Int, CaseIterable, Identifiable {
    case fiveMinutes    = 300
    case fifteenMinutes = 900

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var label: String {
        switch self {
        case .fiveMinutes:    return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        }
    }
}

enum BackgroundSyncInterval: Int, CaseIterable, Identifiable {
    case thirtyMinutes = 1800
    case sixtyMinutes  = 3600

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var label: String {
        switch self {
        case .thirtyMinutes: return "30 minutes"
        case .sixtyMinutes:  return "60 minutes"
        }
    }
}

enum SyncSessionState: Equatable {
    case idle
    case connecting
    case subscribing
    case syncingHeartRate
    case syncingBloodPressurePrep
    case syncingBloodPressure
    case syncingSpO2
    case disconnecting
    case complete
    case failed(String)

    var isActive: Bool {
        switch self {
        case .idle, .complete, .failed: return false
        default: return true
        }
    }

    var label: String {
        switch self {
        case .idle:                     return "Idle"
        case .connecting:               return "Connecting…"
        case .subscribing:              return "Preparing…"
        case .syncingHeartRate:         return "Measuring heart rate…"
        case .syncingBloodPressurePrep: return "Preparing blood pressure…"
        case .syncingBloodPressure:     return "Measuring blood pressure…"
        case .syncingSpO2:              return "Measuring blood oxygen…"
        case .disconnecting:            return "Finishing…"
        case .complete:                 return "Complete"
        case .failed(let reason):       return "Failed: \(reason)"
        }
    }
}

// Lifecycle of an active heart rate measurement triggered by the app.
enum HRMeasurementState: Equatable {
    case idle                // no measurement running
    case starting            // about to send the start command
    case measuring           // command sent, waiting for first packet
    case receivedLiveStatus  // 0x0C packets arriving (sensor active), ACKed, waiting for 0x04
    case receivedResult      // 0x04 result received and ACKed, transitioning to complete
    case complete            // measurement finished with a valid BPM
    case timeout             // 30s elapsed with no 0x04 result packet

    var isActive: Bool {
        switch self {
        case .starting, .measuring, .receivedLiveStatus, .receivedResult: return true
        default: return false
        }
    }
}

enum BPMeasurementState: Equatable {
    case idle
    case sendingStart    // start command sent; expecting FD 00 05 1D 02 0E 00 0A 01
    case measuring       // start ACKed; waiting for DF 00 11 result packet
    case receivedResult  // result received and ACKed, transitioning to complete
    case complete
    case timeout         // see bpTimeoutReason for detail

    var isActive: Bool {
        switch self {
        case .idle, .complete, .timeout: return false
        default: return true
        }
    }
}

struct BPLivePoint: Identifiable {
    let id = UUID()
    let index: Int
    let rawValue: UInt8
}

enum SpO2MeasurementState: Equatable {
    case idle, starting, measuring, complete, timeout

    var isActive: Bool {
        switch self {
        case .starting, .measuring: return true
        default: return false
        }
    }
}

// Classification of a received DF 00 11 UART notification by byte[6].
private enum UARTPacketKind {
    case heartRateResult(bpm: Int)
    case invalidHeartRateResult(bpm: Int)
    case hrLiveSensorOrStatus
    case bpResult(systolic: Int, diastolic: Int)
    case bpLiveData
    case spo2Result(percentage: Int)
    case invalidSpO2Result(percentage: Int)
    case unknownHealthPacket(typeByte: UInt8?)
}

// MARK: - BluetoothManager

@Observable
final class BluetoothManager: NSObject {

    // MARK: Observable state

    let healthKit = HealthKitManager()

    private(set) var centralState: CBManagerState = .unknown
    private(set) var peripherals: [DiscoveredPeripheral] = []
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var batteryLevel: Int? = nil
    private(set) var statusMessage = "Tap Scan to start."
    private(set) var discoveredServices: [CBService] = []
    private(set) var discoveredCharacteristics: [CBCharacteristic] = []
    private(set) var characteristicInfos: [CharacteristicInfo] = []
    private(set) var eventLog: [BLEEvent] = []
    private(set) var lastDisconnectDuration: TimeInterval? = nil
    private(set) var lastDisconnectReason: String? = nil
    private(set) var isKeepAliveRunning = false
    private(set) var protocolSessionLog: [ProtocolEvent] = []
    private(set) var channelPairs: [ChannelPair] = [
        ChannelPair(id: "FF13",      label: "FF Command Channel",
                    writeUUIDPrefix: "FF13",      notifyUUIDPrefix: "FF14"),
        ChannelPair(id: "6E400002",  label: "Nordic UART",
                    writeUUIDPrefix: "6E400002",  notifyUUIDPrefix: "6E400003"),
        ChannelPair(id: "FF02",      label: "FF02 Channel",
                    writeUUIDPrefix: "FF02",      notifyUUIDPrefix: "FF01"),
    ]

    // Heart rate state — persisted across disconnects, cleared on new scan
    private(set) var lastHeartRate: Int? = nil          // set only by 0x04 result packets
    private(set) var lastHeartRateDate: Date? = nil
    private(set) var lastHeartRatePacket: String? = nil // hex of last valid 0x04 result
    private(set) var lastHRRawPacket: String? = nil     // hex of most recent HR packet (any type)
    private(set) var lastHRPacketTypeDesc: String? = nil // e.g. "0x04 = HR result"

    // Blood pressure state — resets on disconnect
    private(set) var lastSystolic: Int? = nil
    private(set) var lastDiastolic: Int? = nil
    private(set) var lastBPDate: Date? = nil
    private(set) var lastBPRawPacket: String? = nil
    private(set) var bpMeasurementState: BPMeasurementState = .idle
    private(set) var bpTimeoutReason: String? = nil
    private(set) var bpLivePoints: [BPLivePoint] = []

    // Blood oxygen state — resets on disconnect
    private(set) var lastSpO2: Int? = nil
    private(set) var lastSpO2Date: Date? = nil
    private(set) var lastSpO2RawPacket: String? = nil
    private(set) var spo2MeasurementState: SpO2MeasurementState = .idle

    // Active measurement state — resets on disconnect
    private(set) var measurementState: HRMeasurementState = .idle
    private(set) var isHRWriteCharAvailable = false

    // Connected watch identity — persisted across disconnects, cleared on new scan
    private(set) var connectedDeviceName: String? = nil

    // Auto-connect
    private(set) var isAutoConnecting: Bool = false
    private(set) var savedWatchName: String? = nil

    // Auto Health Sync
    private(set) var autoSyncEnabled: Bool = false
    private(set) var foregroundSyncInterval: ForegroundSyncInterval = .fiveMinutes
    private(set) var backgroundSyncInterval: BackgroundSyncInterval = .thirtyMinutes
    private(set) var syncSessionState: SyncSessionState = .idle
    private(set) var lastSyncTime: Date? = nil
    private(set) var lastSyncError: String? = nil
    private(set) var nextSyncTime: Date? = nil

    private(set) var keepAliveMode: KeepAliveMode = .none
    var keepAliveIntervalSeconds: Double = 5.0
    var customKeepAliveHex: String = ""
    var isRecordingInteraction = false

    // MARK: Private

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var batteryLevelChar: CBCharacteristic?
    private var heartRateNotifyChar: CBCharacteristic?
    private var hrWriteChar: CBCharacteristic?
    private var connectAttemptTime: Date?
    private var connectedAt: Date?
    private var keepAliveTask: Task<Void, Never>?
    private var measurementTask: Task<Void, Never>?
    private var bpMeasurementTask: Task<Void, Never>?
    private var spo2MeasurementTask: Task<Void, Never>?
    private var schedulerTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var sessionStartTime: Date?
    private var lastWriteByPair: [String: (time: Date, hex: String)] = [:]

    private let batteryLevelUUID    = CBUUID(string: "2A19")
    private let heartRateNotifyUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9F")
    private let hrWriteUUID         = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9F")

    private static let hrStartCommand = Data([0xDF, 0x00, 0x06, 0xF7, 0x02, 0x01, 0x0D, 0x00, 0x01, 0x01])
    private static let hrStopCommand  = Data([0xDF, 0x00, 0x06, 0xF6, 0x02, 0x01, 0x0D, 0x00, 0x01, 0x00])
    private static let hrCommandAck   = Data([0xFD, 0x00, 0x05, 0x1C, 0x02, 0x0D, 0x00, 0x0A, 0x01])

    private static let bpStartCommand = Data([0xDF, 0x00, 0x06, 0xF8, 0x02, 0x01, 0x0E, 0x00, 0x01, 0x01])
    private static let bpStopCommand  = Data([0xDF, 0x00, 0x06, 0xFB, 0x13, 0x01, 0x01, 0x00, 0x01, 0x00])
    private static let bpStartAck     = Data([0xFD, 0x00, 0x05, 0x1D, 0x02, 0x0E, 0x00, 0x0A, 0x01])
    private static let bpAckResult    = Data([0xFD, 0x00, 0x05, 0x22, 0x05, 0x05, 0x00, 0x15, 0x01])
    private static let bpAckLiveData  = Data([0xFD, 0x00, 0x05, 0xD5, 0x05, 0x02, 0x00, 0xCB, 0x01])

    private static let spo2StartCommand = Data([0xDF, 0x00, 0x06, 0x06, 0x02, 0x01, 0x1C, 0x00, 0x01, 0x01])
    private static let spo2StopCommand  = Data([0xDF, 0x00, 0x06, 0x05, 0x02, 0x01, 0x1C, 0x00, 0x01, 0x00])
    private static let spo2CmdAck       = Data([0xFD, 0x00, 0x05, 0x2B, 0x02, 0x1C, 0x00, 0x0A, 0x01])
    private static let spo2AckResult    = Data([0xFD, 0x00, 0x05, 0x2B, 0x05, 0x0E, 0x00, 0x15, 0x01])

    private static let savedWatchUUIDKey          = "knockoff.savedWatchUUID"
    private static let savedWatchNameKey          = "knockoff.savedWatchName"
    private static let autoSyncEnabledKey         = "knockoff.autoSyncEnabled"
    private static let foregroundSyncIntervalKey  = "knockoff.foregroundSyncInterval"
    private static let backgroundSyncIntervalKey  = "knockoff.backgroundSyncInterval"

    static let bgSyncTaskIdentifier = "com.magician.knockoffwatch.healthsync"
    static weak var shared: BluetoothManager?

    var isScanning: Bool { central?.isScanning ?? false }

    // MARK: - Config validation

    @discardableResult
    static func validateBackgroundConfig() -> Bool {
        let modes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] ?? []
        let hasBluetooth = modes.contains("bluetooth-central")
        let hasFetch    = modes.contains("fetch")
        print("[BLE] UIBackgroundModes: \(modes.isEmpty ? "(none)" : modes.joined(separator: ", "))")
        print("[BLE] bluetooth-central: \(hasBluetooth ? "PRESENT ✓" : "MISSING ✗")")
        print("[BLE] fetch: \(hasFetch ? "PRESENT ✓" : "MISSING ✗")")
        if !hasBluetooth {
            print("[BLE] ⚠️ State restoration requires bluetooth-central background mode")
        }
        return hasBluetooth
    }

    override init() {
        super.init()
        Self.shared = self

        let hasBackground = Self.validateBackgroundConfig()
        #if DEBUG
        if hasBackground {
            print("[BLE] State restoration: ENABLED (identifier: com.magician.knockoffwatch.central)")
            central = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionRestoreIdentifierKey: "com.magician.knockoffwatch.central"]
            )
        } else {
            print("[BLE] ⚠️ DEBUG: bluetooth-central missing — state restoration DISABLED to avoid crash")
            central = CBCentralManager(delegate: self, queue: .main)
        }
        #else
        print("[BLE] State restoration: ENABLED (identifier: com.magician.knockoffwatch.central)")
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "com.magician.knockoffwatch.central"]
        )
        #endif

        autoSyncEnabled = UserDefaults.standard.bool(forKey: Self.autoSyncEnabledKey)
        let rawFg = UserDefaults.standard.integer(forKey: Self.foregroundSyncIntervalKey)
        foregroundSyncInterval = ForegroundSyncInterval(rawValue: rawFg) ?? .fiveMinutes
        let rawBg = UserDefaults.standard.integer(forKey: Self.backgroundSyncIntervalKey)
        backgroundSyncInterval = BackgroundSyncInterval(rawValue: rawBg) ?? .thirtyMinutes
        savedWatchName = UserDefaults.standard.string(forKey: Self.savedWatchNameKey)
    }

    // MARK: - Public API

    func startScan() {
        guard central.state == .poweredOn else { return }
        peripherals.removeAll()
        batteryLevel = nil
        discoveredServices.removeAll()
        discoveredCharacteristics.removeAll()
        characteristicInfos.removeAll()
        connectedDeviceName = nil
        lastHRRawPacket = nil
        lastHRPacketTypeDesc = nil
        resetChannelPairs()
        protocolSessionLog.removeAll()
        lastWriteByPair.removeAll()
        isAutoConnecting = false
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
        heartRateNotifyChar = nil
        hrWriteChar = nil
        isHRWriteCharAvailable = false
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

    func setKeepAliveMode(_ mode: KeepAliveMode) {
        keepAliveMode = mode
        if mode == .none { stopKeepAlive() } else { startKeepAlive() }
    }

    func cancelAutoConnect() {
        isAutoConnecting = false
        if central.isScanning { central.stopScan() }
        statusMessage = "Auto-connect cancelled."
        logEvent("Auto-connect: cancelled by user")
    }

    func forgetWatch() {
        isAutoConnecting = false
        if central.isScanning { central.stopScan() }
        UserDefaults.standard.removeObject(forKey: Self.savedWatchUUIDKey)
        UserDefaults.standard.removeObject(forKey: Self.savedWatchNameKey)
        savedWatchName = nil
        stopForegroundScheduler()
        statusMessage = "Watch forgotten. Tap Scan to find a new device."
        logEvent("Saved watch forgotten")
    }

    var isSyncSessionActive: Bool { syncSessionState.isActive }

    func setAutoSyncEnabled(_ enabled: Bool) {
        autoSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.autoSyncEnabledKey)
        if enabled {
            startForegroundScheduler(runImmediately: true)
            scheduleBackgroundSync()
        } else {
            stopForegroundScheduler()
        }
    }

    func setForegroundSyncInterval(_ interval: ForegroundSyncInterval) {
        foregroundSyncInterval = interval
        UserDefaults.standard.set(interval.rawValue, forKey: Self.foregroundSyncIntervalKey)
        if autoSyncEnabled { startForegroundScheduler() }
    }

    func setBackgroundSyncInterval(_ interval: BackgroundSyncInterval) {
        backgroundSyncInterval = interval
        UserDefaults.standard.set(interval.rawValue, forKey: Self.backgroundSyncIntervalKey)
        if autoSyncEnabled { scheduleBackgroundSync() }
    }

    func triggerAutoSync() {
        guard autoSyncEnabled else { return }
        logEvent("Auto Health Sync: manual trigger")
        syncTask?.cancel()
        syncTask = Task { @MainActor [weak self] in
            await self?.runSyncSession()
        }
    }

    func refreshBattery() {
        guard let peripheral = connectedPeripheral,
              let char = batteryLevelChar,
              char.properties.contains(.read) else { return }
        logEvent("Battery: manual refresh")
        peripheral.readValue(for: char)
    }

    // MARK: Heart rate measurement

    func startHeartRateMeasurement() {
        guard case .connected = connectionState,
              let peripheral = connectedPeripheral,
              let writeChar = hrWriteChar else {
            logEvent("HR measurement: cannot start — not connected or write char unavailable")
            return
        }
        if let notifyChar = heartRateNotifyChar, !notifyChar.isNotifying {
            peripheral.setNotifyValue(true, for: notifyChar)
        }
        measurementState = .starting
        let hex = CharacteristicInfo.toHex(Self.hrStartCommand)
        peripheral.writeValue(Self.hrStartCommand, for: writeChar, type: .withoutResponse)
        logEvent("HR measurement: command sent [\(hex)] to \(writeChar.uuid.uuidString)")
        appendProtocolEvent(kind: .write, charUUID: writeChar.uuid.uuidString,
                            hexBytes: hex, byteCount: Self.hrStartCommand.count,
                            writeType: "withoutResponse")
        measurementState = .measuring

        measurementTask?.cancel()
        measurementTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled else { return }
            if self.measurementState.isActive {
                self.measurementState = .timeout
                self.logEvent("HR measurement: timed out — no result packet in 30s")
            }
        }
    }

    func stopHeartRateMeasurement() {
        measurementTask?.cancel()
        measurementTask = nil
        if measurementState.isActive {
            if let peripheral = connectedPeripheral, let writeChar = hrWriteChar {
                let hex = CharacteristicInfo.toHex(Self.hrStopCommand)
                peripheral.writeValue(Self.hrStopCommand, for: writeChar, type: .withoutResponse)
                logEvent("HR measurement: stop command sent [\(hex)]")
            }
            measurementState = .idle
            logEvent("HR measurement: stopped by user")
        }
    }

    func startBPMeasurement() {
        guard case .connected = connectionState,
              let peripheral = connectedPeripheral,
              let writeChar = hrWriteChar else {
            logEvent("BP measurement: cannot start — not connected or write char unavailable")
            return
        }
        if let notifyChar = heartRateNotifyChar, !notifyChar.isNotifying {
            peripheral.setNotifyValue(true, for: notifyChar)
        }
        bpLivePoints.removeAll()
        bpTimeoutReason = nil

        let startHex = CharacteristicInfo.toHex(Self.bpStartCommand)
        peripheral.writeValue(Self.bpStartCommand, for: writeChar, type: .withoutResponse)
        logEvent("BP measurement: start command sent [\(startHex)]")
        appendProtocolEvent(kind: .write, charUUID: writeChar.uuid.uuidString,
                            hexBytes: startHex, byteCount: Self.bpStartCommand.count,
                            writeType: "withoutResponse")
        bpMeasurementState = .sendingStart

        bpMeasurementTask?.cancel()
        bpMeasurementTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            if self.bpMeasurementState == .sendingStart {
                self.bpMeasurementState = .timeout
                self.bpTimeoutReason = "Watch did not acknowledge BP start command"
                self.logEvent("BP measurement: start ACK timed out")
            }
        }
    }

    private func bpStartAckReceived() {
        logEvent("BP measurement: start acknowledged — measuring")
        bpMeasurementState = .measuring

        bpMeasurementTask?.cancel()
        bpMeasurementTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard let self, !Task.isCancelled else { return }
            if self.bpMeasurementState == .measuring {
                self.bpMeasurementState = .timeout
                self.bpTimeoutReason = "No BP result received within 45 seconds"
                self.logEvent("BP measurement: timed out — no result packet in 45s")
            }
        }
    }

    func stopBPMeasurement() {
        bpMeasurementTask?.cancel()
        bpMeasurementTask = nil
        bpTimeoutReason = nil
        if bpMeasurementState.isActive {
            if let peripheral = connectedPeripheral, let writeChar = hrWriteChar {
                let hex = CharacteristicInfo.toHex(Self.bpStopCommand)
                peripheral.writeValue(Self.bpStopCommand, for: writeChar, type: .withoutResponse)
                logEvent("BP measurement: stop command sent [\(hex)]")
            }
            bpMeasurementState = .idle
            logEvent("BP measurement: stopped by user")
        }
    }

    func startSpO2Measurement() {
        guard case .connected = connectionState,
              let peripheral = connectedPeripheral,
              let writeChar = hrWriteChar else {
            logEvent("SpO2 measurement: cannot start — not connected or write char unavailable")
            return
        }
        if let notifyChar = heartRateNotifyChar, !notifyChar.isNotifying {
            peripheral.setNotifyValue(true, for: notifyChar)
        }
        spo2MeasurementState = .starting
        let hex = CharacteristicInfo.toHex(Self.spo2StartCommand)
        peripheral.writeValue(Self.spo2StartCommand, for: writeChar, type: .withoutResponse)
        logEvent("SpO2 measurement: start command sent [\(hex)]")
        appendProtocolEvent(kind: .write, charUUID: writeChar.uuid.uuidString,
                            hexBytes: hex, byteCount: Self.spo2StartCommand.count,
                            writeType: "withoutResponse")
        spo2MeasurementState = .measuring

        spo2MeasurementTask?.cancel()
        spo2MeasurementTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled else { return }
            if self.spo2MeasurementState.isActive {
                self.spo2MeasurementState = .timeout
                self.logEvent("SpO2 measurement: timed out — no result packet in 30s")
            }
        }
    }

    func stopSpO2Measurement() {
        spo2MeasurementTask?.cancel()
        spo2MeasurementTask = nil
        if spo2MeasurementState.isActive {
            if let peripheral = connectedPeripheral, let writeChar = hrWriteChar {
                let hex = CharacteristicInfo.toHex(Self.spo2StopCommand)
                peripheral.writeValue(Self.spo2StopCommand, for: writeChar, type: .withoutResponse)
                logEvent("SpO2 measurement: stop command sent [\(hex)]")
            }
            spo2MeasurementState = .idle
            logEvent("SpO2 measurement: stopped by user")
        }
    }

    // MARK: Per-characteristic actions

    func readCharacteristic(_ char: CBCharacteristic) {
        guard let peripheral = connectedPeripheral,
              char.properties.contains(.read) else { return }
        logEvent("Read → \(char.uuid)")
        peripheral.readValue(for: char)
    }

    func setNotify(_ enabled: Bool, for char: CBCharacteristic) {
        guard let peripheral = connectedPeripheral else { return }
        peripheral.setNotifyValue(enabled, for: char)
        logEvent("Notify \(enabled ? "subscribe" : "unsubscribe") → \(char.uuid)")
    }

    func readAllReadable() {
        guard let peripheral = connectedPeripheral else { return }
        let targets = discoveredCharacteristics.filter { $0.properties.contains(.read) }
        logEvent("Read All: requesting \(targets.count) readable chars")
        targets.forEach { peripheral.readValue(for: $0) }
    }

    func subscribeAll() {
        guard let peripheral = connectedPeripheral else { return }
        let targets = discoveredCharacteristics.filter {
            ($0.properties.contains(.notify) || $0.properties.contains(.indicate)) && !$0.isNotifying
        }
        logEvent("Subscribe All: subscribing to \(targets.count) chars")
        targets.forEach { peripheral.setNotifyValue(true, for: $0) }
    }

    func unsubscribeAll() {
        guard let peripheral = connectedPeripheral else { return }
        let targets = discoveredCharacteristics.filter { $0.isNotifying }
        logEvent("Unsubscribe All: unsubscribing from \(targets.count) chars")
        targets.forEach { peripheral.setNotifyValue(false, for: $0) }
    }

    @discardableResult
    func writeCharacteristic(_ char: CBCharacteristic, hexInput: String) -> Bool {
        guard let peripheral = connectedPeripheral,
              let data = BluetoothManager.parseHex(hexInput) else { return false }
        let type: CBCharacteristicWriteType
        if char.properties.contains(.write) {
            type = .withResponse
        } else if char.properties.contains(.writeWithoutResponse) {
            type = .withoutResponse
        } else {
            logEvent("Write FAILED (\(char.uuid)): not writable")
            return false
        }
        peripheral.writeValue(data, for: char, type: type)
        let label = type == .withResponse ? "withResp" : "noResp"
        logEvent("Write [\(label)] → \(char.uuid): \(CharacteristicInfo.toHex(data))")
        recordWrite(char: char, data: data, type: type)
        return true
    }

    // MARK: Protocol discovery

    func startRecording() {
        guard case .connected = connectionState else { return }
        isRecordingInteraction = true
        subscribeAll()
        logEvent("--- Interaction recording started ---")
        appendProtocolEvent(kind: .sessionStart, charUUID: "recording-start", hexBytes: "", byteCount: 0)
    }

    func stopRecording() {
        isRecordingInteraction = false
        logEvent("--- Interaction recording stopped ---")
    }

    func clearProtocolLog() {
        protocolSessionLog.removeAll()
        lastWriteByPair.removeAll()
        logEvent("Protocol log cleared")
    }

    func exportProtocolJSON() -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let events = protocolSessionLog.map { e -> [String: Any] in
            var dict: [String: Any] = [
                "time": iso.string(from: e.timestamp),
                "sessionRelativeMS": e.sessionRelativeMS,
                "kind": e.kind.label,
                "charUUID": e.charUUID,
                "hexBytes": e.hexBytes,
                "byteCount": e.byteCount,
            ]
            if let v = e.writeRelativeMS { dict["writeRelativeMS"] = v }
            if let v = e.writeType       { dict["writeType"] = v }
            if let v = e.pairedWriteUUID { dict["pairedWriteUUID"] = v }
            return dict
        }

        let subscribedChars = characteristicInfos.filter(\.isNotifying).map(\.charUUID.uuidString)

        let root: [String: Any] = [
            "device": connectedPeripheral?.name ?? connectedDeviceName ?? "unknown",
            "sessionStart": sessionStartTime.map { iso.string(from: $0) } ?? "—",
            "subscribedChars": subscribedChars,
            "eventCount": events.count,
            "events": events,
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: root,
                                                  options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\": \"\(error.localizedDescription)\"}"
        }
    }

    // MARK: Export (BLE Inspector)

    func exportReport() -> String {
        var lines = [
            "LaxasFit BLE Inspection Report",
            "Generated: \(Date().formatted(date: .long, time: .complete))",
            "",
            "=== Services & Characteristics ===",
        ]
        for service in discoveredServices {
            lines.append("\nService: \(service.uuid.uuidString)")
            for info in characteristicInfos where info.serviceUUID == service.uuid {
                lines.append("  Char: \(info.charUUID.uuidString)")
                lines.append("    Properties: \(Self.describeProperties(info.characteristic.properties))")
                lines.append("    Last value: \(info.hexString)")
                if let utf8 = info.utf8Value   { lines.append("    UTF-8: \(utf8)") }
                if let ts = info.lastUpdatedAt { lines.append("    Updated: \(BLEEvent.timeFormatter.string(from: ts))") }
                lines.append("    Notifying: \(info.isNotifying)")
            }
        }
        lines.append("\n=== Event Log ===")
        for event in eventLog { lines.append("[\(event.timeString)] \(event.message)") }
        return lines.joined(separator: "\n")
    }

    // MARK: Hex parsing (internal — used by WriteConsoleView for validation)

    static func parseHex(_ input: String) -> Data? {
        let cleaned = input.replacingOccurrences(of: " ", with: "")
        guard cleaned.count % 2 == 0, !cleaned.isEmpty else { return nil }
        var data = Data()
        var i = cleaned.startIndex
        while i < cleaned.endIndex {
            let j = cleaned.index(i, offsetBy: 2)
            guard let byte = UInt8(cleaned[i..<j], radix: 16) else { return nil }
            data.append(byte)
            i = j
        }
        return data
    }

    // MARK: - Private helpers

    private func logEvent(_ message: String) {
        let event = BLEEvent(timestamp: Date(), message: message)
        eventLog.append(event)
        print("[BLE \(event.timeString)] \(message)")
        if eventLog.count > 200 { eventLog.removeFirst(eventLog.count - 200) }
    }

    private func resetChannelPairs() {
        for i in channelPairs.indices {
            channelPairs[i].writeCharDiscovered = false
            channelPairs[i].notifyCharDiscovered = false
            channelPairs[i].lastCommand = nil
            channelPairs[i].lastCommandTime = nil
            channelPairs[i].lastResponse = nil
            channelPairs[i].lastResponseTime = nil
        }
    }

    // Classify a DF 00 11 UART notification by byte[6] (the packet-type discriminator).
    private func classifyUARTPacket(_ data: Data) -> UARTPacketKind {
        guard data.count == 21,
              data[0] == 0xDF, data[1] == 0x00, data[2] == 0x11,
              data[4] == 0x05, data[5] == 0x01 else {
            return .unknownHealthPacket(typeByte: nil)
        }
        switch data[6] {
        case 0x04:
            let bpm = Int(data[20])
            return (30...220).contains(bpm)
                ? .heartRateResult(bpm: bpm)
                : .invalidHeartRateResult(bpm: bpm)
        case 0x0C:
            return .hrLiveSensorOrStatus
        case 0x05:
            return .bpResult(systolic: Int(data[19]), diastolic: Int(data[20]))
        case 0x02:
            return .bpLiveData
        case 0x0E:
            let pct = Int(data[20])
            return (70...100).contains(pct)
                ? .spo2Result(percentage: pct)
                : .invalidSpO2Result(percentage: pct)
        default:
            return .unknownHealthPacket(typeByte: data[6])
        }
    }

    private func decodeUARTNotification(_ data: Data) {
        let hex = CharacteristicInfo.toHex(data)
        lastHRRawPacket = hex

        // FD-prefix packets are watch responses/ACKs — not health data.
        if data.first == 0xFD {
            if data == Self.hrCommandAck {
                lastHRPacketTypeDesc = "HR command ACK"
                logEvent("HR command acknowledged: \(hex)")
            } else if data == Self.bpStartAck {
                lastHRPacketTypeDesc = "BP start ACK"
                if bpMeasurementState == .sendingStart {
                    bpStartAckReceived()
                } else {
                    logEvent("BP start ACK received (unexpected state: \(bpMeasurementState))")
                }
            } else if data == Self.spo2CmdAck {
                lastHRPacketTypeDesc = "SpO2 command ACK"
                logEvent("SpO2 command acknowledged: \(hex)")
            } else {
                lastHRPacketTypeDesc = "watch response"
                logEvent("Watch response (\(data.count)B): \(hex)")
            }
            return
        }

        // DF packets that aren't the 21-byte DF 00 11 health format are status/info packets.
        guard data.count == 21, data.first == 0xDF,
              data.count > 2, data[2] == 0x11 else {
            let typeDesc = data.count >= 3 ? String(format: "DF 00 %02X", data[2]) : "short"
            lastHRPacketTypeDesc = "status packet"
            logEvent("Watch status [\(typeDesc), \(data.count)B]: \(hex)")
            return
        }

        let kind = classifyUARTPacket(data)

        switch kind {
        case .heartRateResult(let bpm):
            lastHRPacketTypeDesc = "0x04 = HR result"
            let isFirst = lastHeartRate == nil
            lastHeartRate = bpm
            let hrDate = Date()
            lastHeartRateDate = hrDate
            lastHeartRatePacket = hex
            logEvent("Heart rate: \(bpm) bpm [type=0x04]\(isFirst ? " — first result" : "") [\(hex)]")
            if measurementState.isActive {
                measurementState = .complete
                measurementTask?.cancel()
                measurementTask = nil
                logEvent("HR measurement: complete — BPM \(bpm)")
                if let peripheral = connectedPeripheral, let writeChar = hrWriteChar {
                    peripheral.writeValue(Self.hrStopCommand, for: writeChar, type: .withoutResponse)
                    logEvent("HR measurement: stop command sent after result")
                }
            }
            let hk = healthKit
            Task { await hk.saveHeartRate(bpm: bpm, date: hrDate, rawPacketHex: hex) }

        case .hrLiveSensorOrStatus:
            lastHRPacketTypeDesc = "0x0C = live sensor/status, ignored for dashboard"
            logEvent("HR packet: live/status [type=0x0C] — not updating dashboard [\(hex)]")
            if measurementState == .measuring || measurementState == .starting {
                measurementState = .receivedLiveStatus
                logEvent("HR measurement: receivedLiveStatus — sensor active, waiting for result")
            }

        case .invalidHeartRateResult(let bpm):
            lastHRPacketTypeDesc = "0x04 = HR result (BPM \(bpm) invalid, outside 30–220)"
            logEvent("HR packet: BPM \(bpm) out of valid range (30–220) [type=0x04] [\(hex)]")

        case .bpResult(let sys, let dia):
            lastHRPacketTypeDesc = "0x05 = BP result"
            let bpIsValid = (70...220).contains(sys) && (40...140).contains(dia) && sys > dia
            if bpIsValid {
                lastSystolic = sys
                lastDiastolic = dia
                let bpDate = Date()
                lastBPDate = bpDate
                lastBPRawPacket = hex
                logEvent("Blood pressure: \(sys)/\(dia) mmHg [type=0x05] [\(hex)]")
                if bpMeasurementState.isActive {
                    bpMeasurementState = .receivedResult
                    bpMeasurementTask?.cancel()
                    bpMeasurementTask = nil
                }
                if let peripheral = connectedPeripheral, let writeChar = hrWriteChar {
                    peripheral.writeValue(Self.bpAckResult, for: writeChar, type: .withoutResponse)
                    logEvent("BP result ACK sent")
                }
                bpMeasurementState = .complete
                logEvent("BP measurement: complete — \(sys)/\(dia) mmHg")
                let hk = healthKit
                Task { await hk.saveBloodPressure(systolic: sys, diastolic: dia, date: bpDate, rawPacketHex: hex) }
            } else {
                logEvent("BP result rejected: \(sys)/\(dia) mmHg — outside valid range [sys:70-220, dia:40-140, sys>dia] [\(hex)]")
                if let peripheral = connectedPeripheral, let writeChar = hrWriteChar {
                    peripheral.writeValue(Self.bpAckResult, for: writeChar, type: .withoutResponse)
                    logEvent("BP result ACK sent")
                }
            }

        case .bpLiveData:
            lastHRPacketTypeDesc = "0x02 = BP live data"
            let point = BPLivePoint(index: bpLivePoints.count, rawValue: data[20])
            bpLivePoints.append(point)
            logEvent("BP live data [type=0x02] byte[20]=\(data[20]) [\(hex)]")
            if let peripheral = connectedPeripheral, let writeChar = hrWriteChar {
                peripheral.writeValue(Self.bpAckLiveData, for: writeChar, type: .withoutResponse)
            }

        case .spo2Result(let pct):
            lastHRPacketTypeDesc = "0x0E = SpO2 result"
            lastSpO2 = pct
            let spo2Date = Date()
            lastSpO2Date = spo2Date
            lastSpO2RawPacket = hex
            logEvent("SpO2: \(pct)% [type=0x0E] [\(hex)]")
            if spo2MeasurementState.isActive {
                spo2MeasurementState = .complete
                spo2MeasurementTask?.cancel()
                spo2MeasurementTask = nil
                logEvent("SpO2 measurement: complete — \(pct)%")
            }
            if let peripheral = connectedPeripheral, let writeChar = hrWriteChar {
                peripheral.writeValue(Self.spo2AckResult, for: writeChar, type: .withoutResponse)
                logEvent("SpO2 result ACK sent")
            }
            let hk = healthKit
            Task { await hk.saveSpO2(percentage: pct, date: spo2Date, rawPacketHex: hex) }

        case .invalidSpO2Result(let pct):
            lastHRPacketTypeDesc = "0x0E = SpO2 result (invalid: \(pct)%)"
            logEvent("SpO2 packet: \(pct)% out of valid range (70–100) [type=0x0E] [\(hex)]")

        case .unknownHealthPacket(let typeByte):
            let typeStr = typeByte.map { String(format: "byte[6]=0x%02X", $0) } ?? "unknown"
            lastHRPacketTypeDesc = "unknown (\(typeStr))"
            logEvent("DF 00 11 packet: unknown type — \(typeStr) [\(hex)]")
        }
    }

    private func appendProtocolEvent(kind: ProtocolEvent.Kind, charUUID: String, hexBytes: String,
                                     byteCount: Int, writeRelativeMS: Int? = nil,
                                     writeType: String? = nil, pairedWriteUUID: String? = nil) {
        let now = Date()
        let relMS = sessionStartTime.map { Int(now.timeIntervalSince($0) * 1000) } ?? 0
        let event = ProtocolEvent(
            kind: kind, timestamp: now, sessionRelativeMS: relMS,
            writeRelativeMS: writeRelativeMS, charUUID: charUUID,
            hexBytes: hexBytes, byteCount: byteCount,
            writeType: writeType, pairedWriteUUID: pairedWriteUUID
        )
        protocolSessionLog.append(event)
        if protocolSessionLog.count > 500 { protocolSessionLog.removeFirst(protocolSessionLog.count - 500) }
    }

    private func recordWrite(char: CBCharacteristic, data: Data, type: CBCharacteristicWriteType) {
        let hex = CharacteristicInfo.toHex(data)
        let now = Date()
        let writeTypeStr = type == .withResponse ? "withResponse" : "withoutResponse"
        appendProtocolEvent(kind: .write, charUUID: char.uuid.uuidString,
                            hexBytes: hex, byteCount: data.count, writeType: writeTypeStr)
        let uuidStr = char.uuid.uuidString.uppercased()
        for i in channelPairs.indices {
            if uuidStr.hasPrefix(channelPairs[i].writeUUIDPrefix.uppercased()) {
                channelPairs[i].lastCommand = hex
                channelPairs[i].lastCommandTime = now
                lastWriteByPair[channelPairs[i].id] = (now, hex)
            }
        }
    }

    private func recordValueUpdate(uuid: CBUUID, data: Data, isNotifying: Bool) {
        let hex = CharacteristicInfo.toHex(data)
        let uuidStr = uuid.uuidString.uppercased()
        let now = Date()
        var writeRelMS: Int? = nil
        var pairedWriteUUID: String? = nil

        for i in channelPairs.indices {
            if uuidStr.hasPrefix(channelPairs[i].notifyUUIDPrefix.uppercased()) {
                channelPairs[i].lastResponse = hex
                channelPairs[i].lastResponseTime = now
                if let writeInfo = lastWriteByPair[channelPairs[i].id] {
                    let elapsed = now.timeIntervalSince(writeInfo.time)
                    if elapsed <= 5.0 {
                        writeRelMS = Int(elapsed * 1000)
                        pairedWriteUUID = channelPairs[i].writeUUIDPrefix
                    }
                }
            }
        }

        if isRecordingInteraction || writeRelMS != nil {
            let kind: ProtocolEvent.Kind = isNotifying ? .notification : .read
            appendProtocolEvent(kind: kind, charUUID: uuid.uuidString, hexBytes: hex,
                                byteCount: data.count, writeRelativeMS: writeRelMS,
                                pairedWriteUUID: pairedWriteUUID)
        }
    }

    private func startKeepAlive() {
        guard keepAliveMode != .none, case .connected = connectionState else { return }
        stopKeepAlive()
        isKeepAliveRunning = true
        logEvent("Keep-alive: starting [\(keepAliveMode.label)] every \(Int(keepAliveIntervalSeconds))s")

        keepAliveTask = Task { @MainActor [weak self] in
            var count = 0
            while !Task.isCancelled {
                guard self?.keepAliveMode != .none,
                      case .connected? = self?.connectionState else { break }
                let interval = self?.keepAliveIntervalSeconds ?? 5.0
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                guard self?.keepAliveMode != .none,
                      case .connected? = self?.connectionState else {
                    self?.logEvent("Keep-alive: stopping (disconnected or disabled)")
                    break
                }
                count += 1
                self?.performKeepAliveTick(count: count)
            }
            self?.isKeepAliveRunning = false
            if let s = self, !Task.isCancelled {
                s.logEvent("Keep-alive: stopped after \(count) ticks")
            }
        }
    }

    private func performKeepAliveTick(count: Int) {
        switch keepAliveMode {
        case .none:
            break
        case .batteryRead:
            guard let peripheral = connectedPeripheral, let char = batteryLevelChar else {
                logEvent("Keep-alive [batteryRead] #\(count): battery char unavailable")
                return
            }
            logEvent("Keep-alive [batteryRead] #\(count): reading battery")
            peripheral.readValue(for: char)
        case .uartPing:
            guard let peripheral = connectedPeripheral, let writeChar = hrWriteChar else {
                logEvent("Keep-alive [uartPing] #\(count): write char unavailable")
                return
            }
            if measurementState.isActive {
                let hex = CharacteristicInfo.toHex(Self.hrStartCommand)
                peripheral.writeValue(Self.hrStartCommand, for: writeChar, type: .withoutResponse)
                logEvent("Keep-alive [uartPing] #\(count): sent HR ping [\(hex)] (measurement active)")
            } else if !customKeepAliveHex.isEmpty, let data = BluetoothManager.parseHex(customKeepAliveHex) {
                let hex = CharacteristicInfo.toHex(data)
                peripheral.writeValue(data, for: writeChar, type: .withoutResponse)
                logEvent("Keep-alive [uartPing] #\(count): sent custom ping [\(hex)]")
            } else {
                logEvent("Keep-alive [uartPing] #\(count): idle — no command configured")
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

    // MARK: - Auto-connect

    private var savedWatchUUID: UUID? {
        UserDefaults.standard.string(forKey: Self.savedWatchUUIDKey)
            .flatMap { UUID(uuidString: $0) }
    }

    private func attemptAutoConnect() {
        guard let savedUUID = savedWatchUUID else {
            statusMessage = "Bluetooth ready. Tap Scan."
            return
        }
        isAutoConnecting = true
        statusMessage = "Auto-connecting\(savedWatchName.map { " to \($0)" } ?? "")…"
        logEvent("Auto-connect: looking for saved peripheral")
        let found = central.retrievePeripherals(withIdentifiers: [savedUUID])
        if let peripheral = found.first {
            logEvent("Auto-connect: retrieved from cache, connecting")
            autoConnectTo(peripheral)
        } else {
            logEvent("Auto-connect: not cached, starting scan")
            startAutoConnectScan()
        }
    }

    private func autoConnectTo(_ peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        batteryLevelChar = nil
        heartRateNotifyChar = nil
        hrWriteChar = nil
        isHRWriteCharAvailable = false
        peripheral.delegate = self
        connectionState = .connecting
        connectAttemptTime = Date()
        logEvent("Auto-connect: connecting to \(peripheral.name ?? peripheral.identifier.uuidString.prefix(8).description)")
        central.connect(peripheral, options: nil)
    }

    private func startAutoConnectScan() {
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    // MARK: - Foreground scheduler

    private func startForegroundScheduler(runImmediately: Bool = false) {
        guard autoSyncEnabled else { return }
        stopForegroundScheduler()
        logEvent("Auto Health Sync: foreground scheduler started — \(foregroundSyncInterval.label) interval")

        schedulerTask = Task { @MainActor [weak self] in
            if runImmediately, let this = self, this.autoSyncEnabled, !Task.isCancelled {
                this.nextSyncTime = nil
                this.logEvent("Auto Health Sync: running immediately on enable")
                await this.runSyncSession()
            }
            while !Task.isCancelled, let this = self, this.autoSyncEnabled {
                let interval = this.foregroundSyncInterval.seconds
                this.nextSyncTime = Date().addingTimeInterval(interval)
                this.logEvent("Auto Health Sync: next sync in \(this.foregroundSyncInterval.label)")

                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }

                guard let this2 = self, this2.autoSyncEnabled, !Task.isCancelled else { break }
                this2.nextSyncTime = nil
                this2.logEvent("Auto Health Sync: running scheduled sync")
                await this2.runSyncSession()
            }
            self?.nextSyncTime = nil
        }
    }

    private func stopForegroundScheduler() {
        guard schedulerTask != nil else { return }
        schedulerTask?.cancel()
        schedulerTask = nil
        nextSyncTime = nil
        logEvent("Auto Health Sync: foreground scheduler stopped")
    }

    // MARK: - Sync session

    private func runSyncSession() async {
        guard autoSyncEnabled else { return }
        logEvent("Sync session: starting")
        syncSessionState = .connecting
        lastSyncError = nil

        guard await connectForSync(), !Task.isCancelled else {
            if !Task.isCancelled {
                let msg = "Could not connect to watch"
                syncSessionState = .failed(msg)
                lastSyncError = msg
                logEvent("Sync session: failed — \(msg)")
            }
            return
        }

        syncSessionState = .subscribing
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        await syncMeasureHR(timeout: 45)
        guard !Task.isCancelled else { return }

        await syncMeasureBP(timeout: 60)
        guard !Task.isCancelled else { return }

        await syncMeasureSpO2(timeout: 45)
        guard !Task.isCancelled else { return }

        syncSessionState = .disconnecting
        logEvent("Sync session: complete, disconnecting")
        disconnect()
        try? await Task.sleep(for: .seconds(2))

        lastSyncTime = Date()
        syncSessionState = .complete
        logEvent("Sync session: done — HR:\(lastHeartRate.map { "\($0)" } ?? "-") BP:\(lastSystolic.map { "\($0)" } ?? "-")/\(lastDiastolic.map { "\($0)" } ?? "-") SpO2:\(lastSpO2.map { "\($0)" } ?? "-%")")
    }

    private func connectForSync() async -> Bool {
        if case .connected = connectionState, isHRWriteCharAvailable { return true }
        guard centralState == .poweredOn else {
            logEvent("Sync: cannot connect — Bluetooth not powered on")
            return false
        }
        if case .connected = connectionState {
            // Connected but UART not yet ready — just wait below
        } else {
            attemptAutoConnect()
        }
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, !Task.isCancelled {
            if case .connected = connectionState, isHRWriteCharAvailable { return true }
            if case .failed = connectionState { return false }
            try? await Task.sleep(for: .milliseconds(500))
        }
        logEvent("Sync: connection timed out")
        return false
    }

    private func syncMeasureHR(timeout: TimeInterval) async {
        syncSessionState = .syncingHeartRate
        guard case .connected = connectionState, isHRWriteCharAvailable,
              !measurementState.isActive else {
            logEvent("Sync: HR skipped — not ready")
            return
        }
        startHeartRateMeasurement()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !Task.isCancelled {
            switch measurementState {
            case .complete:
                logEvent("Sync: HR done — \(lastHeartRate.map { "\($0) bpm" } ?? "?")")
                return
            case .timeout, .idle:
                logEvent("Sync: HR ended (state: \(measurementState))")
                return
            default: break
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        logEvent("Sync: HR deadline exceeded")
        stopHeartRateMeasurement()
    }

    private func syncMeasureBP(timeout: TimeInterval) async {
        syncSessionState = .syncingBloodPressurePrep
        guard case .connected = connectionState, isHRWriteCharAvailable,
              !bpMeasurementState.isActive else {
            logEvent("Sync: BP skipped — not ready")
            return
        }
        startBPMeasurement()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !Task.isCancelled {
            switch bpMeasurementState {
            case .complete:
                logEvent("Sync: BP done — \(lastSystolic.map { "\($0)" } ?? "-")/\(lastDiastolic.map { "\($0)" } ?? "-") mmHg")
                return
            case .timeout, .idle:
                logEvent("Sync: BP ended (state: \(bpMeasurementState))")
                return
            case .measuring:
                syncSessionState = .syncingBloodPressure
            default: break
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        logEvent("Sync: BP deadline exceeded")
        stopBPMeasurement()
    }

    private func syncMeasureSpO2(timeout: TimeInterval) async {
        syncSessionState = .syncingSpO2
        guard case .connected = connectionState, isHRWriteCharAvailable,
              !spo2MeasurementState.isActive else {
            logEvent("Sync: SpO2 skipped — not ready")
            return
        }
        startSpO2Measurement()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !Task.isCancelled {
            switch spo2MeasurementState {
            case .complete:
                logEvent("Sync: SpO2 done — \(lastSpO2.map { "\($0)%" } ?? "?")")
                return
            case .timeout, .idle:
                logEvent("Sync: SpO2 ended (state: \(spo2MeasurementState))")
                return
            default: break
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        logEvent("Sync: SpO2 deadline exceeded")
        stopSpO2Measurement()
    }

    // MARK: - Background sync

    func scheduleBackgroundSync() {
        guard autoSyncEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.bgSyncTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: backgroundSyncInterval.seconds)
        do {
            try BGTaskScheduler.shared.submit(request)
            logEvent("Background sync: scheduled in \(backgroundSyncInterval.label)")
        } catch {
            logEvent("Background sync: scheduling failed — \(error.localizedDescription)")
        }
    }

    func handleBackgroundSync(task: BGAppRefreshTask) {
        logEvent("Background sync: task received")
        scheduleBackgroundSync()

        let bgSyncTask = Task { @MainActor [weak self] in
            await self?.runSyncSession()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            bgSyncTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            logEvent("CoreBluetooth: state restored")
            if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
                for p in peripherals {
                    p.delegate = self
                    connectedPeripheral = p
                    logEvent("Restored peripheral: \(p.name ?? String(p.identifier.uuidString.prefix(8)))")
                }
            }
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor [weak self] in
            guard let self else { return }
            centralState = state
            switch state {
            case .poweredOn:
                print("[BLE] Bluetooth powered on")
                logEvent("Bluetooth powered on")
                attemptAutoConnect()
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
            if isAutoConnecting, let savedUUID = savedWatchUUID, id == savedUUID {
                logEvent("Auto-connect: found target via scan")
                central.stopScan()
                autoConnectTo(peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let elapsed = connectAttemptTime.map { Date().timeIntervalSince($0) }
            let now = Date()
            connectedAt = now
            sessionStartTime = now
            connectedDeviceName = peripheral.name
            connectionState = .connected
            measurementState = .idle
            bpMeasurementState = .idle
            bpTimeoutReason = nil
            bpLivePoints.removeAll()
            spo2MeasurementState = .idle
            isAutoConnecting = false
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.savedWatchUUIDKey)
            if let name = peripheral.name {
                UserDefaults.standard.set(name, forKey: Self.savedWatchNameKey)
                savedWatchName = name
            }
            discoveredServices.removeAll()
            discoveredCharacteristics.removeAll()
            characteristicInfos.removeAll()
            resetChannelPairs()
            protocolSessionLog.removeAll()
            lastWriteByPair.removeAll()
            statusMessage = "Connected. Discovering services..."
            logEvent("Connected\(elapsed.map { String(format: " in %.2fs", $0) } ?? "") — discovering services")
            appendProtocolEvent(kind: .sessionStart,
                                charUUID: peripheral.name ?? peripheral.identifier.uuidString,
                                hexBytes: "", byteCount: 0)
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
            measurementTask?.cancel()
            measurementTask = nil
            measurementState = .idle
            bpMeasurementTask?.cancel()
            bpMeasurementTask = nil
            bpMeasurementState = .idle
            bpTimeoutReason = nil
            spo2MeasurementTask?.cancel()
            spo2MeasurementTask = nil
            spo2MeasurementState = .idle
            if isRecordingInteraction { isRecordingInteraction = false }
            let duration = connectedAt.map { Date().timeIntervalSince($0) }
            lastDisconnectDuration = duration
            lastDisconnectReason = hasError ? reason : nil
            let durationStr = duration.map { Self.formatDuration($0) } ?? "?"
            logEvent("Disconnected after \(durationStr)\(hasError ? " — \(reason)" : " (clean)")")
            connectionState = .disconnected
            batteryLevel = nil
            connectedPeripheral = nil
            batteryLevelChar = nil
            heartRateNotifyChar = nil
            hrWriteChar = nil
            isHRWriteCharAvailable = false
            connectedAt = nil
            connectAttemptTime = nil
            // lastHeartRate*, connectedDeviceName, characteristicInfos intentionally preserved
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
            logEvent("Services (\(services.count)): \(services.map(\.uuid.uuidString).joined(separator: ", "))")
            for service in services { peripheral.discoverCharacteristics(nil, for: service) }
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
                let infoID = CharacteristicInfo.makeID(service: serviceUUID, char: char.uuid)
                if !characteristicInfos.contains(where: { $0.id == infoID }) {
                    characteristicInfos.append(CharacteristicInfo(
                        id: infoID, characteristic: char, serviceUUID: serviceUUID
                    ))
                }
                logEvent("  \(serviceUUID)/\(char.uuid) [\(Self.describeProperties(char.properties))]")

                // Update channel pair discovery state
                let uuidStr = char.uuid.uuidString.uppercased()
                for i in channelPairs.indices {
                    if uuidStr.hasPrefix(channelPairs[i].writeUUIDPrefix.uppercased()) {
                        channelPairs[i].writeCharDiscovered = true
                    }
                    if uuidStr.hasPrefix(channelPairs[i].notifyUUIDPrefix.uppercased()) {
                        channelPairs[i].notifyCharDiscovered = true
                    }
                }

                // Battery characteristic
                if char.uuid == batteryLevelUUID {
                    batteryLevelChar = char
                    statusMessage = "Reading battery level..."
                    if char.properties.contains(.read) {
                        logEvent("Battery: requesting read")
                        peripheral.readValue(for: char)
                    }
                    if char.properties.contains(.notify) { peripheral.setNotifyValue(true, for: char) }
                }

                // Heart rate notify characteristic — auto-subscribe
                if char.uuid == heartRateNotifyUUID {
                    heartRateNotifyChar = char
                    if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                        peripheral.setNotifyValue(true, for: char)
                        logEvent("Heart rate notify: auto-subscribing (\(char.uuid.uuidString))")
                    }
                }

                // Heart rate write characteristic
                if char.uuid == hrWriteUUID {
                    hrWriteChar = char
                    isHRWriteCharAvailable = true
                    logEvent("Heart rate write: found (\(char.uuid.uuidString))")
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
        let isNotifying = characteristic.isNotifying
        let errMsg = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let msg = errMsg {
                logEvent("Read FAILED (\(uuid)): \(msg)")
                statusMessage = "Read failed: \(msg)"
                return
            }
            if let idx = characteristicInfos.firstIndex(where: { $0.charUUID == uuid }) {
                characteristicInfos[idx].lastValue = data
                characteristicInfos[idx].lastUpdatedAt = Date()
            }
            if let d = data {
                if uuid == heartRateNotifyUUID {
                    decodeUARTNotification(d)
                } else if uuid == batteryLevelUUID, let level = d.first.map({ Int($0) }) {
                    let hex = CharacteristicInfo.toHex(d)
                    let isFirst = batteryLevel == nil
                    batteryLevel = level
                    logEvent("Battery: \(level)% [0x\(hex)]\(isFirst ? " — first read" : "")")
                    if isFirst {
                        statusMessage = "Battery: \(level)%"
                        startKeepAlive()
                    }
                } else {
                    let hex = CharacteristicInfo.toHex(d)
                    let utf8 = String(data: d, encoding: .utf8).map { " → \"\($0)\"" } ?? ""
                    logEvent("Value (\(uuid)): \(hex)\(utf8)")
                }
                recordValueUpdate(uuid: uuid, data: d, isNotifying: isNotifying)
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
                if let idx = characteristicInfos.firstIndex(where: { $0.charUUID == uuid }) {
                    characteristicInfos[idx].isNotifying = isNotifying
                }
                logEvent("Notify \(isNotifying ? "ENABLED" : "disabled") for \(uuid)")
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let uuid = characteristic.uuid
        let errMsg = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let msg = errMsg {
                logEvent("Write response FAILED (\(uuid)): \(msg)")
                appendProtocolEvent(kind: .writeAck, charUUID: uuid.uuidString,
                                    hexBytes: "FAILED: \(msg)", byteCount: 0)
            } else {
                logEvent("Write response OK (\(uuid))")
                appendProtocolEvent(kind: .writeAck, charUUID: uuid.uuidString,
                                    hexBytes: "OK", byteCount: 0)
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
        t < 60 ? String(format: "%.1fs", t) : "\(Int(t) / 60)m \(Int(t) % 60)s"
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
