import 'dart:async';

import '../../core/constants/ble_constants.dart';
import '../../core/utils/ble_serializer.dart';

/// Transport-agnostic connection lifecycle state.
///
/// Every concrete [DeviceRepository] (BLE, Wi-Fi, ...) maps its own
/// transport-specific connection state onto this enum so the UI never
/// needs to know which transport is active.
enum DeviceConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

/// Identifies *which* physical device to connect to, without leaking
/// transport-specific types (like flutter_blue_plus's `BluetoothDevice`)
/// into shared providers/screens.
///
/// Each concrete [DeviceRepository] only knows how to handle its own
/// target subtype. In practice the app never hands the wrong target to
/// the wrong repository, because the provider layer picks the repository
/// based on `Farm.communicationType` before it ever builds a target.
sealed class DeviceTarget {
  const DeviceTarget();
}

/// Target for a BLE-connected MushPi controller.
///
/// [deviceId] is the flutter_blue_plus `remoteId` string, the same value
/// already persisted as `Farm.deviceId`.
///
/// [resolvedDevice] is an optional, already-live `BluetoothDevice` from a
/// scan the caller just performed (e.g. the pairing flow in
/// device_scan_screen.dart). When present, the BLE repository connects to
/// it directly. When absent (e.g. reconnecting to a previously-linked farm
/// after an app relaunch, when no live scan object exists yet), the BLE
/// repository re-scans and matches by [deviceId] — the same strategy
/// auto_reconnect_provider.dart already uses today.
///
/// Typed as `Object?` here (rather than `BluetoothDevice?`) so this shared
/// file doesn't need to import flutter_blue_plus. The BLE repository casts
/// it back internally.
class BleDeviceTarget extends DeviceTarget {
  final String deviceId;
  final Object? resolvedDevice;

  const BleDeviceTarget(this.deviceId, {this.resolvedDevice});
}

/// Target for a Wi-Fi / LAN HTTP-connected MushPi controller.
///
/// [host] is an IP address (e.g. "192.168.4.1") or mDNS hostname
/// (e.g. "mushpi.local").
class WifiDeviceTarget extends DeviceTarget {
  final String host;
  final int port;

  const WifiDeviceTarget(this.host, {this.port = 80});
}

/// The single interface the rest of the app (providers, screens) talks to.
///
/// [BleDeviceRepository] and [WifiDeviceRepository] both implement this.
/// Nothing above this layer should import flutter_blue_plus or the http
/// package directly — screens ask for "the environment" or "set the fan
/// speed", never "read this GATT characteristic" or "POST to this URL".
///
/// This mirrors the method surface `BLEOperations` (in ble_provider.dart)
/// already exposes today, since that class turned out to already be
/// ~90% of a transport-agnostic API — it just needed the interface pulled
/// out and a second implementation added alongside it.
abstract class DeviceRepository {
  // ---- Connection lifecycle ----
  Future<void> connect(DeviceTarget target);
  Future<void> disconnect();
  bool get isConnected;
  Stream<DeviceConnectionState> get connectionStateStream;

  // ---- Live data streams ----
  Stream<EnvironmentalReading> get environmentalDataStream;
  Stream<int> get statusFlagsStream;
  Stream<ActuatorStatusData> get actuatorStatusStream;

  // ---- Reads ----
  Future<EnvironmentalReading> readEnvironmentalData();
  Future<ControlTargetsData> readControlTargets();
  Future<StageStateData> readStageState();
  Future<int> readStatusFlags();
  Future<ActuatorStatusData?> readActuatorStatus();
  Future<StageThresholdsData?> readStageThresholds(
    Species species,
    GrowthStage stage,
  );

  // ---- Writes ----
  Future<void> writeControlTargets(ControlTargetsData targets);
  Future<void> writeStageState(StageStateData state);
  Future<void> writeOverrideBits(int bits);
  Future<bool> writeStageThresholds(StageThresholdsData thresholds);

  // ---- Lifecycle ----
  void dispose();

  // ----Settings and toggles----
  Future<void> toggleManualMode();
  Future<void> toggleTec();
  Future<void> toggleHumidifier();
  Future<void> setFanPwm(int value);
  Future<void> setLightPwm(int value);
}

/// Thrown by any [DeviceRepository] implementation on communication
/// failure, so callers can catch one type regardless of transport.
class DeviceRepositoryException implements Exception {
  final String message;
  final Object? cause;

  DeviceRepositoryException(this.message, {this.cause});

  @override
  String toString() => 'DeviceRepositoryException: $message';
}