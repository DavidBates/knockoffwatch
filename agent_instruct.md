# Claude Instructions: LaxasFit Watch Companion

## Project Summary

A native iOS app that reverse-engineers the BLE protocol of a **LaxasFit Watch Ultra** to sync heart rate, blood pressure, and blood oxygen into Apple Health. The app is called "LaxasFit Watch" in the UI; the Xcode project/scheme is `knockoffwatch`.

This is a personal/experimental project, not a commercial product. All BLE protocol knowledge was discovered through active reverse engineering using the debug tools built into the app. Do not assume any BLE protocol details beyond what is documented here.

---

## Platform

- **iOS 26.1 / Xcode 26.1**
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** — all types in the project are implicitly `@MainActor` unless explicitly annotated otherwise. This is a build setting, not a code annotation.
- **Swift Concurrency**: `nonisolated` on CoreBluetooth delegate methods + `Task { @MainActor [weak self] in }` pattern for crossing the actor boundary.
- **`@Observable` macro** on `BluetoothManager: NSObject` — not `ObservableObject`. SwiftUI views consume it via `@Environment(BluetoothManager.self)`.
- No third-party dependencies. Swift Charts, CoreBluetooth, HealthKit, BackgroundTasks are all first-party.
- Bundle ID: `com.magician.knockoffwatch`
- Background task identifier: `com.magician.knockoffwatch.healthsync`
- Use iPhone 17 Pro when requesting a simulator or leave blank to use latest

---

## File Map

| File | Purpose |
|---|---|
| `knockoffwatchApp.swift` | `@main` entry point, BGTaskScheduler registration, `RootView` (onboarding vs main app routing) |
| `BluetoothManager.swift` | All BLE logic, health measurements, auto-sync, state restoration. ~2300 lines. The heart of the app. |
| `HealthKitManager.swift` | `@Observable` wrapper for HealthKit writes (HR, BP, SpO2). `requestAuthorization()`, `saveHeartRate`, `saveBloodPressure`, `saveSpO2`. |
| `HealthHistoryStore.swift` | `@Observable` store for 7-day reading history. Persists to `~/Documents/health_history.json`. Used by health cards. |
| `OnboardingView.swift` | 6-page TabView onboarding flow. Gated by `@AppStorage("hasCompletedOnboarding")`. |
| `MainAppView.swift` | Root TabView with Home and Settings tabs. |
| `HomeView.swift` | ScrollView-based home screen: connection tile, battery tile, health section header, three health cards, sync card. |
| `HealthCards.swift` | `HeartRateCard`, `BloodPressureCard`, `BloodOxygenCard` + shared `HealthCardShell`. Swift Charts mini charts, measurement animations, per-card sync buttons. |
| `SettingsView.swift` | Watch connection, Apple Health toggles, auto-sync config, Advanced section (all debug tools). |
| `ContentView.swift` | `PeripheralRow` shared component. Legacy debug content that lives alongside newer views. |
| `InspectorView.swift` | BLE Services inspector: lists all discovered services and characteristics with live values. |
| `ProtocolView.swift` | Protocol discovery recorder: logs all WRITE/NOTIFY/ACK events with timing. |
| `KeepAliveTestView.swift` | Tests keep-alive modes (battery read, UART ping) to prevent idle disconnects. |
| `IdleMonitorView.swift` | Passive notification logger — records all incoming BLE packets while connected but idle. |
| `AdvertisementMonitorView.swift` | Shows full advertisement data for all scanned peripherals (service UUIDs, manufacturer data, RSSI, confidence scores). |
| `WriteConsoleView.swift` | Manual hex write console for custom UART commands. |

---

## App Structure

### Routing

```
knockoffwatchApp
  └── RootView (reads @AppStorage("hasCompletedOnboarding"))
        ├── OnboardingView  (hasCompletedOnboarding == false)
        └── MainAppView     (hasCompletedOnboarding == true)
              ├── Tab: HomeView
              └── Tab: SettingsView
                    └── Advanced section
                          ├── InspectorView
                          ├── ProtocolView
                          ├── KeepAliveTestView
                          ├── IdleMonitorView
                          └── AdvertisementMonitorView
```

### Onboarding (6 pages)

1. Welcome
2. Pair Your Watch (pre-flight checklist)
3. Enable Bluetooth (live `centralState` status + Open Settings link)
4. Apple Health (requestAuthorization + Skip)
5. Connect Watch (scan + peripheral list + Skip)
6. You're All Set → sets `hasCompletedOnboarding = true`

`OnboardingPageView` is a non-generic struct using `AnyView` type erasure for the optional extra content slot. Two overloaded inits — one without extra, one with `@ViewBuilder extra: () -> V`. Always pass extra as a closure: `extra: { bluetoothStatusView }`, never as a value.

### Home Screen

`ScrollView` layout, not a `List`. Top row: two equal-width tiles (connection status + battery). Below: health section header with "Updated X ago" timestamp. Then three stacked `HealthCardShell`-based cards (HR, BP, SpO2). Bottom: compact sync card with "Sync All" button.

### Settings

Four sections: Watch (connection controls, scan results, forget watch), Apple Health (auth status, metric toggles), Auto Sync (enable/disable, foreground/background interval pickers, last/next sync times), Advanced (NavigationLinks to all debug tools + Export Logs + Reset Onboarding).

---

## BluetoothManager Architecture

`@Observable final class BluetoothManager: NSObject` — the single source of truth. Injected via `.environment(bluetooth)` at the root and consumed with `@Environment(BluetoothManager.self)`.

**Key observable state** (all `private(set) var`):

```
centralState, peripherals, connectionState
batteryLevel
lastHeartRate, lastHeartRateDate
lastSystolic, lastDiastolic, lastBPDate
lastSpO2, lastSpO2Date
measurementState (HRMeasurementState)
bpMeasurementState (BPMeasurementState)
spo2MeasurementState (SpO2MeasurementState)
isSyncSessionActive, syncSessionState
autoSyncEnabled, foregroundSyncInterval, backgroundSyncInterval
lastSyncTime, nextSyncTime
savedWatchName, savedTrustedWatch
isScanning, isRecordingInteraction, isKeepAliveRunning
idleMonitorActive, idleMonitorTotalNotifications
peripherals [DiscoveredPeripheral]
healthHistory (HealthHistoryStore)
healthKit (HealthKitManager)
```

**Persistence (UserDefaults keys)**:

- `knockoff.savedWatchUUID` — UUID of last paired watch
- `knockoff.savedWatchName` — display name of last paired watch
- `knockoff.trustedWatch` — JSON-encoded `TrustedWatch` (fingerprint for factory-reset recovery)
- `knockoff.autoSyncEnabled`, `knockoff.foregroundSyncInterval`, `knockoff.backgroundSyncInterval`

---

## Discovered BLE Protocol

All health data flows through the **Nordic UART Service (NUS)**:

| Direction | UUID |
|---|---|
| Write (app → watch) | `6E400002-B5A3-F393-E0A9-E50E24DCCA9F` |
| Notify (watch → app) | `6E400003-B5A3-F393-E0A9-E50E24DCCA9F` |

Battery level uses the standard BLE service: `0x180F` / `0x2A19`.

### Notification packet format

Health result packets are 21 bytes starting with `DF 00 11`. The type discriminator is **byte[6]**:

| byte[6] | Metric | Result location |
|---|---|---|
| `0x04` | Heart rate | byte[20] = BPM |
| `0x0C` | HR live status | ignored for dashboard (sensor active signal) |
| `0x05` | Blood pressure | byte[19] = systolic, byte[20] = diastolic |
| `0x02` | BP live data | byte[20] = raw pressure value |
| `0x0E` | SpO2 | byte[20] = percentage |

Valid ranges enforced before saving: HR 30–220 bpm, BP sys 70–220 / dia 40–140 / sys > dia, SpO2 70–100%.

### Write commands (hex)

```
HR start:   DF 00 06 F7 02 01 0D 00 01 01
HR stop:    DF 00 06 F6 02 01 0D 00 01 00
HR ack:     FD 00 05 1C 02 0D 00 0A 01

BP start:   DF 00 06 F8 02 01 0E 00 01 01
BP stop:    DF 00 06 FB 13 01 01 00 01 00
BP startAck: FD 00 05 1D 02 0E 00 0A 01    (sent by watch)
BP ackResult: FD 00 05 22 05 05 00 15 01   (sent by app)
BP ackLive:   FD 00 05 D5 05 02 00 CB 01   (sent by app per live packet)

SpO2 start: DF 00 06 06 02 01 1C 00 01 01
SpO2 stop:  DF 00 06 05 02 01 1C 00 01 00
SpO2 ack:   FD 00 05 2B 02 1C 00 0A 01
SpO2 ackResult: FD 00 05 2B 05 0E 00 15 01
```

### Auto-connect & fingerprinting

`DiscoveredPeripheral` carries full advertisement data: `advertisedName`, `peripheralName`, `rssi`, `advertisedServiceUUIDs`, `manufacturerData`, `txPower`, `isConnectable`, `confidence`, `seenCount`, `firstSeen`, `lastSeen`.

`TrustedWatch: Codable` is saved on every successful connect: `identifier` (UUID string), `serviceUUIDs`, `manufacturerDataPrefix` (first 4 bytes), `lastKnownName`, `lastConnectedDate`.

Confidence scoring (max 100): +40 for Nordic UART service UUID, +20 for FFxx service UUID, +25 for exact UUID match with saved watch, +20 for manufacturer data prefix match, +10 for name match, +15 for service UUID overlap. Auto-connect fires at ≥ 55 confidence, allowing reconnect after factory reset even when the UUID changes.

---

## Health History

`HealthHistoryStore` (`@Observable`, `@MainActor`) persists readings to `~/Documents/health_history.json`. Prunes to 30 days on every write. Exposes:

- `append(_ reading: HealthReading)` — called automatically after each successful measurement in `decodeUARTNotification`
- `recent(ofType:days:)` — for 7-day chart data
- `latestTwo(ofType:)` — for latest + previous reading display
- `lastUpdated(ofType:)` — for the "Updated X ago" header

`HealthReading: Codable, Identifiable` — one struct for all three types, with optional fields (`heartRate`, `systolic`, `diastolic`, `spo2`). Static factories: `.heartRate(_:date:)`, `.bloodPressure(sys:dia:date:)`, `.bloodOxygen(_:date:)`.

---

## Health Cards

Each card (`HeartRateCard`, `BloodPressureCard`, `BloodOxygenCard`) is backed by `HealthCardShell<Anim, MiniChart>` which takes generic `@ViewBuilder` parameters for the animation and chart slots.

**Layout**: header row (icon + title + activity spinner) → divider → body row (value column + animation + chart+stats) → divider → footer (sync button + status text).

**Animations** (`onChange(of: isActive)`):
- HR: pulsing `scaleEffect` on heart icon, with shadow glow
- BP: rotating arc (`Circle().trim`) + icon overlay
- SpO2: slow breathing `scaleEffect` on lungs icon

**Charts**: 7-day `LineMark` + `PointMark` (HR/SpO2 also has `AreaMark` gradient fill). X domain always spans 7 days (`chartXScale(domain:)`). Both axes hidden on mini chart. BP has dual-color lines (systolic orange, diastolic yellow) using `series:` parameter.

---

## Auto Sync

When `autoSyncEnabled`, `triggerAutoSync()` runs a sequential sync session (`SyncSessionState`): connect → subscribe to UART notify → HR measurement → BP measurement → SpO2 measurement → disconnect.

Foreground scheduler fires every 5 or 15 minutes (configurable). Background sync uses `BGAppRefreshTask` (identifier: `com.magician.knockoffwatch.healthsync`), registered in `knockoffwatchApp.init()`, handled by `BluetoothManager.handleBackgroundSync(task:)`.

---

## Critical Constraints

- **Do NOT modify the packet decoding logic in `decodeUARTNotification` or `classifyUARTPacket` without strong evidence.** The protocol was discovered through extensive reverse engineering and is correct.
- **Do NOT refactor `BluetoothManager` into multiple files or types** — the shared mutable state is intentional and the class boundary matters for CoreBluetooth delegate conformance.
- **Do NOT add forced dark mode or hard-coded colors.** All UI uses adaptive system colors (`Color(.systemGroupedBackground)`, `Color(.secondarySystemGroupedBackground)`, `.primary`, `.secondary`).
- **Do NOT remove the Advanced section from Settings.** The debug tools (Inspector, Protocol, KeepAlive, IdleMonitor, AdvertisementMonitor, WriteConsole) are actively used for protocol research.
- **`@ViewBuilder` cannot be a stored property.** Use `AnyView` type erasure for view storage (see `OnboardingPageView`).
- **Delegate methods are `nonisolated`.** Always dispatch back with `Task { @MainActor [weak self] in }`.

---

## What Is NOT Built Yet

- History / Trends tab (intentionally deferred)
- Steps, sleep, or any data beyond HR/BP/SpO2
- Watch face setting or time sync
- Any UI for viewing per-reading history logs
- iCloud or server sync of any kind
- Per-reading notes or tagging
