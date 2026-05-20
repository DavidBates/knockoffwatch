# knockoffwatch

A reverse-engineered iOS companion app for the **LaxasFit Watch Ultra** (and similar budget BLE smartwatches).

The official app for this watch is abandoned and barely functional. This was built from scratch by reverse-engineering the watch's BLE protocol — enough to pull heart rate, blood pressure, and blood oxygen readings and sync them to Apple Health.

---

## Features

- **Heart Rate** — on-demand measurement synced to Apple Health
- **Blood Pressure** — on-demand measurement synced to Apple Health
- **Blood Oxygen (SpO2)** — on-demand measurement synced to Apple Health
- **7-day history charts** — Swift Charts line/area charts per metric with daily aggregation
- **Auto-sync** — configurable foreground and background sync intervals via `BGTaskScheduler`
- **Onboarding** — guided Bluetooth pairing and Health permissions setup
- **BLE diagnostic tools** included in Settings:
  - Service/characteristic inspector
  - Protocol discovery logger (records raw UART traffic)
  - Idle packet monitor (passive background logger)
  - Advertisement scanner
  - Keep-alive tester

---

## Requirements

| | |
|---|---|
| iOS | 26.1+ |
| Xcode | 26+ |
| Apple Developer account | Required for HealthKit entitlement and device signing |
| Device | Physical iPhone (Bluetooth and HealthKit unavailable in Simulator) |

---

## Getting Started

1. Clone the repo
2. Open `knockoffwatch.xcodeproj`
3. In **Signing & Capabilities**, set your own **Team** and **Bundle Identifier**
4. Build and run on a physical iPhone
5. Follow the onboarding flow to pair your watch and connect Apple Health

> You will need to replace the Development Team IDs in `project.pbxproj` or let Xcode manage signing automatically.

---

## Architecture

Built with SwiftUI (iOS 26, `@Observable`), CoreBluetooth, HealthKit, and Swift Charts. No third-party dependencies.

### Key files

| File | Role |
|---|---|
| `BluetoothManager.swift` | All BLE logic: scanning, pairing, UART protocol, sync orchestration, auto-sync scheduler |
| `HealthKitManager.swift` | HealthKit authorization and write operations |
| `HealthHistoryStore.swift` | Local 30-day reading history, JSON-persisted |
| `HealthCards/` | Home screen metric cards (shell, hero visuals, weekly charts, per-metric cards) |
| `HomeView.swift` | Main health dashboard |
| `SettingsView.swift` | Watch pairing, Health settings, sync config, diagnostic tool links |
| `OnboardingView.swift` | First-run guided setup |

See [`agent_instruct.md`](agent_instruct.md) for a deeper architecture reference including all observable state, UserDefaults keys, and sync flow details.

---

## BLE Protocol

The watch uses the **Nordic UART Service (NUS)**:

| | UUID |
|---|---|
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9F` |
| TX (write commands to watch) | `6E400002-B5A3-F393-E0A9-E50E24DCCA9F` |
| RX (notifications from watch) | `6E400003-B5A3-F393-E0A9-E50E24DCCA9F` |

Measurements are triggered by writing command bytes to TX. The watch responds with **21-byte UART packets** on RX. Byte `[6]` is the packet type discriminator.

### Commands

| Measurement | TX bytes |
|---|---|
| Heart Rate | `0xAB 0x00 0x04 0xFF 0x31 0x09 0x01 0xCF` |
| Blood Pressure | `0xAB 0x00 0x04 0xFF 0x31 0x09 0x03 0xCD` |
| Blood Oxygen | `0xAB 0x00 0x04 0xFF 0x31 0x09 0x04 0xCC` |

### Result packets

| Byte `[6]` | Packet type | Data bytes |
|---|---|---|
| `0x04` | HR result | `[9]` = BPM |
| `0x05` | BP result | `[9]` = systolic, `[10]` = diastolic |
| `0x06` | SpO2 result | `[9]` = SpO2 % |
| `0x01` | Live HR status | `[9]` = HR, `[18]` = status |

Full protocol documentation (live status flow, keep-alive, battery reads, packet format table) is in [`agent_instruct.md`](agent_instruct.md).

---

## Design

UI design specification and card layout reference are in [`.design/`](.design/).

---

## Disclaimer

Personal reverse-engineering project. Not affiliated with or endorsed by the watch manufacturer. Health readings from unsupported third-party devices should not be used for medical decisions.
