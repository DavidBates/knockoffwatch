import Foundation
import HealthKit

@Observable
final class HealthKitManager {

    // MARK: Observable state

    private(set) var isAvailable: Bool = HKHealthStore.isHealthDataAvailable()
    private(set) var authorizationStatus: AuthStatus = .notDetermined
    private(set) var saveHR: Bool = false
    private(set) var saveSpO2: Bool = false
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
    private static let writeTypes: Set<HKSampleType> = [hrType, spo2Type]

    private static let saveHRKey   = "knockoff.healthkit.saveHR"
    private static let saveSpO2Key = "knockoff.healthkit.saveSpO2"

    init() {
        guard isAvailable else {
            authorizationStatus = .unavailable
            return
        }
        refreshAuthStatus()
        saveHR   = UserDefaults.standard.bool(forKey: Self.saveHRKey)
        saveSpO2 = UserDefaults.standard.bool(forKey: Self.saveSpO2Key)
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
                    UserDefaults.standard.set(true, forKey: Self.saveHRKey)
                    UserDefaults.standard.set(true, forKey: Self.saveSpO2Key)
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

    private func refreshAuthStatus() {
        let hrStatus   = store.authorizationStatus(for: Self.hrType)
        let spo2Status = store.authorizationStatus(for: Self.spo2Type)
        if hrStatus == .sharingAuthorized || spo2Status == .sharingAuthorized {
            authorizationStatus = .authorized
        } else if hrStatus == .sharingDenied && spo2Status == .sharingDenied {
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
