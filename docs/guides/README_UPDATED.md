# MushPi Hub — Change Documentation
### Contributor: Alvin Kenneth Mayega
### Branch: `alvin` · Repository: `nsabagwa/mushroommonitor`
### Period covered: 2026-07-22 → 2026-08-11 (commits `84869fb` → `87a225a`, 13 commits)

---

## Scope

This document covers all commits authored by Alvin Kenneth Mayega between the previously reviewed commit (`7f28096`) and the current branch head (`87a225a`). Every entry below was verified against the actual diff, not inferred from commit messages. Files outside `flutter/mushpi_hub/` (the Raspberry Pi/Python backend in `mushpi/`) were not touched in this period and are out of scope.

**Files changed:** 11
**Lines changed:** +1435 / −65

---

## 1. WiFi Farms: Manual Control Panel

**Files:** `lib/screens/control_screen.dart`
**Commits:** `a416b45`, `9637186`, `077fe9a`, `7f39812`, `de4476a`, `726e4e6`, `e21cf44`

The Control screen now branches on farm transport type. WiFi-connected farms (`farm.wifiHost != null`) render a new `_buildManualControlPanel()` instead of the existing BLE automatic-mode panel.

**New UI elements:**
- "Manual Mode" `SwitchListTile` — gates all actuator controls via `_wifiManualModeEnabled`. Nothing else in the panel is interactive until this is on.
- Fan speed slider (0–255) + "Set fan speed" button → `setFanPwm()`
- Grow light brightness slider (0–255) + "Set light brightness level" button → `setLightPwm()`
- TEC (cooler) toggle, live state from `farmActuatorStatusProvider`
- Humidifier toggle, live state from `farmActuatorStatusProvider`

**Design constraint (documented in code comment):** the ESP32's current HTTP API only exposes manual overrides — no stage, threshold, or control-target endpoints over WiFi yet. This panel is a deliberate architectural fork, not a stopgap; it should be removed once firmware adds HTTP equivalents of `readStageState()` / `readControlTargets()`.

**Known limitation:** fan/light slider values reflect the last value sent by the app, not a firmware readback — WiFi mode cannot read PWM state back from the device yet.

---

## 2. WiFi Transport Reliability Fixes

**Files:** `lib/data/repositories/wifi_device_repository.dart`
**Commits:** `d454951`, `de4476a`

### 2.1 HTTP 400s on manual commands — root cause fixed
The ESP32 sends `Connection: close` on every HTTP response. Reusing the shared `http.Client` (`_client`) for repeated requests was breaking pooled connections and producing HTTP 400 responses on manual actuator commands. Fixed by switching `_get()` and `_post()` to issue a fresh `http.get()` / `http.post()` call per request instead of reusing `_client`.

This is a separate, additional root cause to the earlier "manual mode not enabled before sending actuator commands" fix — both bugs were real and both are now fixed.

### 2.2 Overlapping poll requests
Added a `_pollInFlight` boolean guard inside `_startPolling()`'s `Timer.periodic` callback. If the previous poll to `/api/data` hasn't returned yet, the next tick is skipped rather than firing a second concurrent request.

### 2.3 Actuator JSON boolean coercion
Added an `_asBool()` helper (`bool → bool`, `int → value != 0`, `String → 'true'/'1'`, else throws `FormatException`) and applied it to `lightRunning`, `fanRunning`, `humidifierOn`, and `tecOn` in `_actuatorStatusFromApiData()`. The firmware sends these fields as JSON integers (`0`/`1`), not booleans — direct `as bool` casts were throwing at runtime.

### 2.4 Plain-text response parsing
`setFanPwm()` and `setLightPwm()` now use a new `_getText()` helper instead of `_get()`. These two endpoints return plain-text `"OK"`, not JSON — `jsonDecode()` was throwing `FormatException` on every call.

---

## 3. WiFi Environmental Readings: Persisted to Local DB

**Files:** `lib/providers/device_provider.dart`
**Commits:** `a888d48`, `84869fb`, `87a225a`

**Problem:** `SensorDataListener` is hardwired to the BLE singleton stream and has no visibility into WiFi farms, so WiFi sensor readings were never written to Drift. This was the root cause of WiFi-connected farms showing "No Data Available" on the Environmental Data charts.

**Fix:** `farmDeviceRepositoryProvider` now owns a scoped `StreamSubscription<EnvironmentalReading>`, created only when the target is a `WifiDeviceTarget`. Each reading is written via `readingsDao.insertReading()`, debounced to one write per 5 seconds (matching the existing BLE `SensorDataListener` pattern) to avoid hammering the DB at the underlying ~2s poll rate. The subscription is cancelled in `ref.onDispose`. No schema changes were required.

**Bug fixed on 2026-08-11 (`87a225a`):** the debounce condition was inverted —
```dart
// before (crashes on the first reading — lastReadingSave is null at start,
// so the null-assertion on the right-hand side throws immediately):
if (lastReadingSave == null && now.difference(lastReadingSave!) < minSaveInterval)

// after:
if (lastReadingSave != null && now.difference(lastReadingSave!) < minSaveInterval)
```

---

## 4. Environmental Data Badge Flicker

**Files:** `lib/providers/device_provider.dart`
**Commit:** `84869fb`

Removed `ref.invalidate(farmByIdProvider(farmId))` from both `markOnline()` and `markOffline()`. These ran on every heartbeat tick and were forcing a rebuild of every widget watching `farmByIdProvider`, which was the cause of the visible flicker on the Environmental Data badge.

---

## 5. Farm LAN Setup: Test Now Auto-Saves

**Files:** `lib/screens/farm_detail_screen.dart`
**Commit:** `de4476a`

**Problem:** `_testConnection()` tested a WiFi host but never persisted it. `_saveHost()` was a separate button that users routinely never pressed after a successful test, leaving `farm.wifiHost` `null` — which cascaded into `device_provider.dart` throwing "no device linked" and the app falling back to ThingSpeak (which also failed).

**Fix:** `_testConnection()` now calls `_saveHost(host)` directly on a successful connection test. The standalone "Save" button has been removed — a passing test is now the save action. The `_saveHost()` signature changed from taking no arguments (reading `_hostController.text`) to `_saveHost(String host)`.

**Also in this commit:** `_ThingSpeakCardState` now catches `TimeoutException` specifically and returns a targeted message telling the user to check whether their phone is on the ESP32's own AP-mode network (which has no internet route) rather than a generic `'Failed: $e'` string. This clarifies the error but does not change the underlying 10-second HTTP timeout behavior.

---

## 6. Shorebird OTA Integration

**Files:** `shorebird.yaml` (new), `pubspec.yaml`, `macos/Runner/Release.entitlements`
**Commit:** `86b1bf5`

Added Shorebird Code Push for over-the-air app updates without app-store resubmission.

- `shorebird.yaml`: `app_id: f1144f9b-cd05-45cc-be3c-c39624fef058`, `auto_update` left at its default (enabled).
- `pubspec.yaml`: `shorebird.yaml` added to the `assets` list.
- `macos/Runner/Release.entitlements`: 4 lines added (required for the updater to reach Shorebird's servers from a macOS release build).

---

## 7. Data Layer Hardening

**Commits:** `0d46df2`, `a888d48`, `de4476a`

| File | Change |
|---|---|
| `lib/data/database/daos/farms_dao.dart` | `updateWifiHost()` now throws an `Exception` if the write affects 0 rows, instead of silently returning `0`. |
| `lib/data/repositories/farm_repository.dart` | `wifiHost` and `wifiPort` (defaulting to `80`) are now carried through the farm entity → model conversion — previously dropped in this code path. |
| `lib/data/repositories/device_repository.dart` | `DeviceRepositoryException.toString()` now includes `cause` when present, instead of dropping it. |

---

## Open Issues (unaffected by this change set)

These were flagged previously and confirmed still present by re-checking the current code — no commit in this range touched them:

1. **`lightRaw`/`lux` field mismatch** — `wifi_device_repository.dart` maps `lightRaw: (json['lux'] as num).round()`, i.e. the ambient light sensor reading is stored in the domain model's grow-light PWM field. The actual `lightRaw` (grow-light PWM) and `manualMode` fields from `GET /api/data` are still unparsed.
2. **Connection badges reflect configuration, not live state** — "Online"/"Remote" badges in `home_screen.dart` and `monitoring_screen.dart` are driven by `farm.wifiHost != null` (a farm has WiFi configured) rather than the live `DeviceConnectionState`, so a farm can show "Online" after the poll loop has silently disconnected.
3. **ThingSpeak timeout** — the 10-second HTTP timeout and its underlying cause (phone connected to the ESP32's own AP-mode network, which has no internet route) are unchanged; only the user-facing error message was improved (§5).
4. **`flutter/mushpi_hub/README.md` is stale relative to current architecture** — it documents a single-device, `.env`-driven, BLE-only setup with no concept of farms, WiFi transport, or per-farm ThingSpeak credentials. No commit in this range touched it; it was not in scope for this document.

---

*Compiled from `git log`/`git diff` against `nsabagwa/mushroommonitor`, branch `alvin`, range `7f28096..87a225a`.*