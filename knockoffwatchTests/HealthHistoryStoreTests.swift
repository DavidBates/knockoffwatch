import XCTest
@testable import knockoffwatch

final class HealthHistoryStoreTests: XCTestCase {

    func testAppendHeartRate() {
        let store = HealthHistoryStore(previewReadings: [])
        store.append(.heartRate(72))
        XCTAssertEqual(store.readings.count, 1)
        XCTAssertEqual(store.readings[0].heartRate, 72)
        XCTAssertEqual(store.readings[0].type, .heartRate)
    }

    func testAppendBloodPressure() {
        let store = HealthHistoryStore(previewReadings: [])
        store.append(.bloodPressure(sys: 120, dia: 80))
        XCTAssertEqual(store.readings.count, 1)
        XCTAssertEqual(store.readings[0].systolic, 120)
        XCTAssertEqual(store.readings[0].diastolic, 80)
        XCTAssertEqual(store.readings[0].type, .bloodPressure)
    }

    func testAppendBloodOxygen() {
        let store = HealthHistoryStore(previewReadings: [])
        store.append(.bloodOxygen(98))
        XCTAssertEqual(store.readings.count, 1)
        XCTAssertEqual(store.readings[0].spo2, 98)
        XCTAssertEqual(store.readings[0].type, .bloodOxygen)
    }

    func testRecentReturnsReadingsWithinWindow() {
        let now = Date()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let eightDaysAgo = Calendar.current.date(byAdding: .day, value: -8, to: now)!
        let store = HealthHistoryStore(previewReadings: [
            .heartRate(70, date: twoDaysAgo),
            .heartRate(65, date: eightDaysAgo),
        ])
        let recent = store.recent(ofType: .heartRate)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent[0].heartRate, 70)
    }

    func testRecentFiltersCorrectType() {
        let now = Date()
        let store = HealthHistoryStore(previewReadings: [
            .heartRate(72, date: now),
            .bloodPressure(sys: 120, dia: 80, date: now),
            .bloodOxygen(98, date: now),
        ])
        XCTAssertEqual(store.recent(ofType: .heartRate).count, 1)
        XCTAssertEqual(store.recent(ofType: .bloodPressure).count, 1)
        XCTAssertEqual(store.recent(ofType: .bloodOxygen).count, 1)
    }

    func testLatestTwoReturnsInOrder() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let store = HealthHistoryStore(previewReadings: [
            .heartRate(65, date: yesterday),
            .heartRate(72, date: now),
        ])
        let pair = store.latestTwo(ofType: .heartRate)
        XCTAssertEqual(pair.latest?.heartRate, 72)
        XCTAssertEqual(pair.previous?.heartRate, 65)
    }

    func testLatestTwoWithSingleReading() {
        let store = HealthHistoryStore(previewReadings: [.heartRate(72)])
        let pair = store.latestTwo(ofType: .heartRate)
        XCTAssertNotNil(pair.latest)
        XCTAssertNil(pair.previous)
    }

    func testLatestTwoWithNoReadings() {
        let store = HealthHistoryStore(previewReadings: [])
        let pair = store.latestTwo(ofType: .heartRate)
        XCTAssertNil(pair.latest)
        XCTAssertNil(pair.previous)
    }

    func testLastUpdated() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let store = HealthHistoryStore(previewReadings: [
            .heartRate(65, date: yesterday),
            .heartRate(72, date: now),
        ])
        XCTAssertEqual(
            store.lastUpdated(ofType: .heartRate)?.timeIntervalSince1970 ?? 0,
            now.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    func testLastUpdatedReturnsNilForEmptyStore() {
        let store = HealthHistoryStore(previewReadings: [])
        XCTAssertNil(store.lastUpdated(ofType: .heartRate))
    }

    func testDifferentTypesDontInterfere() {
        let now = Date()
        let store = HealthHistoryStore(previewReadings: [
            .heartRate(72, date: now),
            .bloodPressure(sys: 120, dia: 80, date: now),
        ])
        XCTAssertNil(store.latestTwo(ofType: .heartRate).latest?.systolic)
        XCTAssertNil(store.latestTwo(ofType: .bloodPressure).latest?.heartRate)
    }
}
