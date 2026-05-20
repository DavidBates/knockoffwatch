import XCTest
@testable import knockoffwatch

final class HealthReadingTests: XCTestCase {

    func testHeartRateFactory() {
        let reading = HealthReading.heartRate(75)
        XCTAssertEqual(reading.type, .heartRate)
        XCTAssertEqual(reading.heartRate, 75)
        XCTAssertNil(reading.systolic)
        XCTAssertNil(reading.diastolic)
        XCTAssertNil(reading.spo2)
    }

    func testBloodPressureFactory() {
        let reading = HealthReading.bloodPressure(sys: 120, dia: 80)
        XCTAssertEqual(reading.type, .bloodPressure)
        XCTAssertEqual(reading.systolic, 120)
        XCTAssertEqual(reading.diastolic, 80)
        XCTAssertNil(reading.heartRate)
        XCTAssertNil(reading.spo2)
    }

    func testBloodOxygenFactory() {
        let reading = HealthReading.bloodOxygen(98)
        XCTAssertEqual(reading.type, .bloodOxygen)
        XCTAssertEqual(reading.spo2, 98)
        XCTAssertNil(reading.heartRate)
        XCTAssertNil(reading.systolic)
        XCTAssertNil(reading.diastolic)
    }

    func testDateIsPreserved() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let reading = HealthReading.heartRate(70, date: date)
        XCTAssertEqual(reading.date, date)
    }

    func testCodableRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let original = HealthReading.bloodPressure(sys: 115, dia: 75, date: date)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HealthReading.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.systolic, original.systolic)
        XCTAssertEqual(decoded.diastolic, original.diastolic)
        XCTAssertEqual(
            decoded.date.timeIntervalSince1970,
            original.date.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testUniqueIDs() {
        let a = HealthReading.heartRate(72)
        let b = HealthReading.heartRate(72)
        XCTAssertNotEqual(a.id, b.id)
    }
}
