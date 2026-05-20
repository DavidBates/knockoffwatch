import Foundation
import Observation

enum HealthReadingType: String, Codable {
    case heartRate, bloodPressure, bloodOxygen
}

struct HealthReading: Codable, Identifiable {
    let id: UUID
    let type: HealthReadingType
    let date: Date
    let heartRate: Int?
    let systolic: Int?
    let diastolic: Int?
    let spo2: Int?

    static func heartRate(_ bpm: Int, date: Date = Date()) -> Self {
        .init(id: UUID(), type: .heartRate, date: date,
              heartRate: bpm, systolic: nil, diastolic: nil, spo2: nil)
    }

    static func bloodPressure(sys: Int, dia: Int, date: Date = Date()) -> Self {
        .init(id: UUID(), type: .bloodPressure, date: date,
              heartRate: nil, systolic: sys, diastolic: dia, spo2: nil)
    }

    static func bloodOxygen(_ pct: Int, date: Date = Date()) -> Self {
        .init(id: UUID(), type: .bloodOxygen, date: date,
              heartRate: nil, systolic: nil, diastolic: nil, spo2: pct)
    }
}

@Observable
final class HealthHistoryStore {
    private(set) var readings: [HealthReading] = []

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("health_history.json")
    }

    init() { load() }

    func append(_ reading: HealthReading) {
        readings.append(reading)
        prune()
        save()
    }

    func recent(ofType type: HealthReadingType, days: Int = 7) -> [HealthReading] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return readings
            .filter { $0.type == type && $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    func latestTwo(ofType type: HealthReadingType) -> (latest: HealthReading?, previous: HealthReading?) {
        let all = readings.filter { $0.type == type }.sorted { $0.date > $1.date }
        return (all.first, all.dropFirst().first)
    }

    func lastUpdated(ofType type: HealthReadingType) -> Date? {
        readings.filter { $0.type == type }.max(by: { $0.date < $1.date })?.date
    }

    private func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        readings = readings.filter { $0.date >= cutoff }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([HealthReading].self, from: data)
        else { return }
        readings = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(readings) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    #if DEBUG
    init(previewReadings: [HealthReading]) {
        readings = previewReadings
    }

    static var preview: HealthHistoryStore {
        let calendar = Calendar.current
        let now = Date()
        var r: [HealthReading] = []
        for i in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -i, to: now) else { continue }
            r.append(.heartRate(Int.random(in: 62...88), date: date))
            r.append(.bloodPressure(sys: Int.random(in: 112...132), dia: Int.random(in: 72...86), date: date))
            r.append(.bloodOxygen(Int.random(in: 96...99), date: date))
        }
        return HealthHistoryStore(previewReadings: r)
    }
    #endif
}
