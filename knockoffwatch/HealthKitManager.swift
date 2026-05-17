import Foundation
import HealthKit

@Observable
final class HealthKitManager {

    // MARK: Observable state

    private(set) var isAvailable: Bool = HKHealthStore.isHealthDataAvailable()
    private(set) var authorizationStatus: AuthStatus = .notDetermined
    private(set) var saveHR: Bool = false
    private(set) var saveSpO2: Bool = false
    private(set) var saveBP: Bool = false
    private(set) var lastSaveResult: String? = nil
    private(set) var lastSaveError: String? = nil

    enum AuthStatus {
        case notDetermined
        case authorized
        case denied
        case unavailable

        var label: String {
            switch self {
            case .notDetermined: return "Not connected"
            case .authorized:    return "Connected"
            case .denied:        return "Permission denied"
            case .unavailable:   return "Not available on this device"
            }
        }
    }

    // MARK: Private

    private let store = HKHealthStore()

    private static let hrType    = HKQuantityType(.heartRate)
    private static let spo2Type  = HKQuantityType(.oxygenSaturation)
    private static let bpSysType = HKQuantityType(.bloodPressureSystolic)
    private static let bpDiaType = HKQuantityType(.bloodPressureDiastolic)
    private static let writeTypes: Set<HKSampleType> = [hrType, spo2Type, bpSysType, bpDiaType]

    private static let saveHRKey   = "knockoff.healthkit.saveHR"
    private static let saveSpO2Key = "knockoff.healthkit.saveSpO2"
    private static let saveBPKey   = "knockoff.healthkit.saveBP"

    init() {
        guard isAvailable else {
            authorizationStatus = .unavailable
            return
        }
        refreshAuthStatus()
        saveHR   = UserDefaults.standard.bool(forKey: Self.saveHRKey)
        saveSpO2 = UserDefaults.standard.bool(forKey: Self.saveSpO2Key)
        saveBP   = UserDefaults.standard.bool(forKey: Self.saveBPKey)
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: Self.writeTypes, read: [])
            refreshAuthStatus()
            if authorizationStatus == .authorized {
                if !UserDefaults.standard.bool(forKey: "knockoff.healthkit.firstAuthDone") {
                    saveHR   = true
                    saveSpO2 = true
                    saveBP   = true
                    UserDefaults.standard.set(true, forKey: Self.saveHRKey)
                    UserDefaults.standard.set(true, forKey: Self.saveSpO2Key)
                    UserDefaults.standard.set(true, forKey: Self.saveBPKey)
                    UserDefaults.standard.set(true, forKey: "knockoff.healthkit.firstAuthDone")
                }
            }
        } catch {
            lastSaveError = "Authorization failed: \(error.localizedDescription)"
        }
    }

    func setSaveHR(_ enabled: Bool) {
        saveHR = enabled
        UserDefaults.standard.set(enabled, forKey: Self.saveHRKey)
    }

    func setSaveSpO2(_ enabled: Bool) {
        saveSpO2 = enabled
        UserDefaults.standard.set(enabled, forKey: Self.saveSpO2Key)
    }

    func setSaveBP(_ enabled: Bool) {
        saveBP = enabled
        UserDefaults.standard.set(enabled, forKey: Self.saveBPKey)
    }

    private func refreshAuthStatus() {
        let statuses = [
            store.authorizationStatus(for: Self.hrType),
            store.authorizationStatus(for: Self.spo2Type),
            store.authorizationStatus(for: Self.bpSysType),
            store.authorizationStatus(for: Self.bpDiaType),
        ]
        if statuses.contains(.sharingAuthorized) {
            authorizationStatus = .authorized
        } else if statuses.allSatisfy({ $0 == .sharingDenied }) {
            authorizationStatus = .denied
        } else {
            authorizationStatus = .notDetermined
        }
    }

    // MARK: - Save

    func saveHeartRate(bpm: Int, date: Date, rawPacketHex: String) async {
        guard isAvailable, saveHR else { return }
        let quantity = HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: Double(bpm))
        let sample = HKQuantitySample(
            type: Self.hrType,
            quantity: quantity,
            start: date,
            end: date,
            metadata: makeMetadata(rawPacketHex: rawPacketHex)
        )
        await saveSample(sample, label: "HR \(bpm) bpm")
    }

    func saveSpO2(percentage: Int, date: Date, rawPacketHex: String) async {
        guard isAvailable, saveSpO2 else { return }
        let ratio = Double(percentage) / 100.0
        let quantity = HKQuantity(unit: .percent(), doubleValue: ratio)
        let sample = HKQuantitySample(
            type: Self.spo2Type,
            quantity: quantity,
            start: date,
            end: date,
            metadata: makeMetadata(rawPacketHex: rawPacketHex)
        )
        await saveSample(sample, label: "SpO2 \(percentage)%")
    }

    func saveBloodPressure(systolic: Int, diastolic: Int, date: Date, rawPacketHex: String) async {
        guard isAvailable, saveBP else { return }
        let mmHg = HKUnit.millimeterOfMercury()
        let metadata = makeMetadata(rawPacketHex: rawPacketHex)
        let sysSample = HKQuantitySample(
            type: Self.bpSysType,
            quantity: HKQuantity(unit: mmHg, doubleValue: Double(systolic)),
            start: date, end: date, metadata: metadata
        )
        let diaSample = HKQuantitySample(
            type: Self.bpDiaType,
            quantity: HKQuantity(unit: mmHg, doubleValue: Double(diastolic)),
            start: date, end: date, metadata: metadata
        )
        do {
            try await store.save([sysSample, diaSample])
            await MainActor.run {
                lastSaveResult = "BP \(systolic)/\(diastolic) mmHg saved at \(BLEEvent.timeFormatter.string(from: Date()))"
                lastSaveError = nil
            }
        } catch {
            await MainActor.run {
                lastSaveError = "BP failed: \(error.localizedDescription)"
            }
        }
    }

    private func saveSample(_ sample: HKSample, label: String) async {
        do {
            try await store.save(sample)
            await MainActor.run {
                lastSaveResult = "\(label) saved at \(BLEEvent.timeFormatter.string(from: Date()))"
                lastSaveError = nil
            }
        } catch {
            await MainActor.run {
                lastSaveError = "\(label) failed: \(error.localizedDescription)"
            }
        }
    }

    private func makeMetadata(rawPacketHex: String) -> [String: Any] {
        [
            HKMetadataKeyExternalUUID: UUID().uuidString,
            "source": "LaxasFit Watch Ultra",
            "rawPacketHex": rawPacketHex,
            "app": "KnockoffWatch",
        ]
    }
}
