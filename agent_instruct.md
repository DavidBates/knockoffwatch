

# Claude Instructions: LaxasFit Watch Companion

## Goal

Build a small iOS app that connects to my LaxasFit Watch Ultra over Bluetooth Low Energy and starts with the simplest useful proof of concept:

Scan → Connect → Read Battery Level → Display Battery %

Long-term goals may include basic health sync to Apple Health, periodic best-effort sync, and optional measurement triggers, but do not build those until the battery proof of concept works.

## Current Known Device Details

The watch exposes the standard BLE Battery Service:

- Battery Service UUID: `0x180F`
- Battery Level Characteristic UUID: `0x2A19`

Battery level should be parsed from the first byte of the characteristic value as an integer percentage.

```swift
let batteryServiceUUID = CBUUID(string: "180F")
let batteryLevelUUID = CBUUID(string: "2A19")

func parseBatteryLevel(_ data: Data) -> Int? {
    guard let firstByte = data.first else { return nil }
    return Int(firstByte)
}
```

## Platform

Build a native iOS app using:

- Swift
- SwiftUI
- CoreBluetooth
- Minimum iOS version: choose a reasonable modern default
- No third-party dependencies unless absolutely necessary

## App Requirements: Phase 1

Create a simple SwiftUI app with:

1. A main screen showing:
   - Bluetooth permission/status
   - Scan button
   - List of discovered peripherals
   - Connect button or tappable peripheral row
   - Connection state
   - Battery level when available
   - Error/status messages

2. BLE behavior:
   - Initialize `CBCentralManager`
   - Scan for BLE peripherals
   - Display discovered peripherals, including name and identifier
   - Prefer peripherals with a visible name, but do not require one
   - Allow connecting to a selected peripheral
   - Discover Battery Service `180F`
   - Discover Battery Level Characteristic `2A19`
   - Read Battery Level
   - If Battery Level supports notify, subscribe to updates
   - Safely handle disconnects

3. Architecture:
   - Keep BLE logic outside the SwiftUI view
   - Use an observable view model or manager class
   - Use clear types for peripheral state
   - Keep code readable and beginner-debuggable

## Do Not Overbuild Yet

Do not implement Apple Health sync yet.

Do not implement watch face setting yet.

Do not implement background sync yet.

Do not reverse engineer custom services yet.

Do not assume heart rate, steps, or sleep are available until we inspect the device further.

## Nice-to-Have Debug Info

Add a debug detail view or console logging that prints:

- Peripheral name
- Peripheral identifier
- Advertisement data
- RSSI
- Discovered service UUIDs
- Discovered characteristic UUIDs
- Characteristic properties: read, write, notify, indicate

This will help us inspect the watch for future health sync features.

## iOS Permissions

Make sure the project includes any required Bluetooth usage description in `Info.plist`.

Use clear permission copy, for example:

“This app uses Bluetooth to connect to your LaxasFit watch and read battery and health data.”

## Acceptance Criteria

The first version is successful when I can:

1. Open the app on my iPhone
2. Scan for nearby BLE devices
3. See the LaxasFit Watch Ultra in the list
4. Connect to it
5. Read and display the battery percentage
6. See useful debug output for discovered services and characteristics

## Future Phases, Not Yet

After Phase 1 works, we may add:

- Heart Rate Service detection: `0x180D`
- Heart Rate Measurement: `0x2A37`
- HealthKit write support
- Best-effort background sync
- Manual “Sync Now”
- Triggering measurements if supported by custom characteristics