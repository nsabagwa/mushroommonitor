import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/constants/ble_constants.dart';
import '../../core/utils/ble_serializer.dart';
import 'ble_repository.dart';
import 'device_repository.dart';

/// Adapts the existing [BLERepository] to the transport-agnostic
/// [DeviceRepository] interface.
///
/// This is a thin wrapper, not a rewrite: it holds a [BLERepository]
/// instance and delegates to it. `ble_repository.dart` itself is
/// untouched, which matters right now because that file is large and
/// under active work elsewhere in the redo-merge — keeping this adapter
/// additive keeps the merge surface small.
///
/// Device discovery/pairing (scanning, `startScan`/`stopScan`,
/// `scanResultsStream`) is deliberately *not* part of this adapter or the
/// [DeviceRepository] interface — BLE scanning and Wi-Fi discovery (SoftAP
/// join, subnet scan, mDNS) work too differently to share one shape.
/// Screens that need to *find* a device (device_scan_screen.dart) keep
/// talking to `BLERepository`/`bleRepositoryProvider` directly. Only the
/// "device is already linked, now operate it" surface goes through this
/// adapter.
class BleDeviceRepository implements DeviceRepository {
  final BLERepository _repository;

  BleDeviceRepository(this._repository);

  // ---- Connection lifecycle ----

  @override
  Future<void> connect(DeviceTarget target) => _guard(() async {
        if (target is! BleDeviceTarget) {
          throw ArgumentError(
            'BleDeviceRepository received a ${target.runtimeType}; '
            'expected BleDeviceTarget',
          );
        }

        var device = target.resolvedDevice as BluetoothDevice?;

        // No live scan object was handed in (e.g. reconnecting to a
        // previously-linked farm after an app relaunch) — scan and match
        // by ID, the same strategy auto_reconnect_provider.dart already
        // uses today.
        device ??= await _findDeviceById(target.deviceId);

        if (device == null) {
          throw DeviceRepositoryException(
            'Could not find BLE device ${target.deviceId} during scan',
          );
        }

        await _repository.connect(device);
      });

  @override
  Future<void> disconnect() => _guard(() => _repository.disconnect());

  @override
  bool get isConnected => _repository.isConnected;

  @override
  Stream<DeviceConnectionState> get connectionStateStream =>
      _repository.connectionStateStream.map(_mapConnectionState);

  DeviceConnectionState _mapConnectionState(BluetoothConnectionState state) {
    // flutter_blue_plus only distinguishes connected/disconnected today;
    // there's no interim "connecting" event from the platform layer.
    return state == BluetoothConnectionState.connected
        ? DeviceConnectionState.connected
        : DeviceConnectionState.disconnected;
  }

  /// Scans and matches by remoteId string, mirroring
  /// auto_reconnect_provider.dart's `_scanAndConnect`.
  Future<BluetoothDevice?> _findDeviceById(
    String deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final completer = Completer<BluetoothDevice?>();
    final subscription = _repository.scanResultsStream.listen((results) {
      for (final result in results) {
        if (result.device.remoteId.toString() == deviceId) {
          if (!completer.isCompleted) completer.complete(result.device);
          break;
        }
      }
    });

    await _repository.startScan(timeout: timeout);

    final found = await completer.future.timeout(
      timeout + const Duration(seconds: 1),
      onTimeout: () => null,
    );

    await subscription.cancel();
    await _repository.stopScan();

    return found;
  }

  // ---- Live data streams ----

  @override
  Stream<EnvironmentalReading> get environmentalDataStream =>
      _repository.environmentalDataStream;

  @override
  Stream<int> get statusFlagsStream => _repository.statusFlagsStream;

  @override
  Stream<ActuatorStatusData> get actuatorStatusStream =>
      _repository.actuatorStatusStream;

  // ---- Reads ----

  @override
  Future<EnvironmentalReading> readEnvironmentalData() =>
      _guard(() => _repository.readEnvironmentalData());

  @override
  Future<ControlTargetsData> readControlTargets() =>
      _guard(() => _repository.readControlTargets());

  @override
  Future<StageStateData> readStageState() =>
      _guard(() => _repository.readStageState());

  @override
  Future<int> readStatusFlags() => _guard(() => _repository.readStatusFlags());

  @override
  Future<ActuatorStatusData?> readActuatorStatus() =>
      _guard(() => _repository.readActuatorStatus());

  @override
  Future<StageThresholdsData?> readStageThresholds(
    Species species,
    GrowthStage stage,
  ) =>
      _guard(() => _repository.readStageThresholds(species, stage));

  // ---- Writes ----

  @override
  Future<void> writeControlTargets(ControlTargetsData targets) =>
      _guard(() => _repository.writeControlTargets(targets));

  @override
  Future<void> writeStageState(StageStateData state) =>
      _guard(() => _repository.writeStageState(state));

  @override
  Future<void> writeOverrideBits(int bits) =>
      _guard(() => _repository.writeOverrideBits(bits));

  @override
  Future<bool> writeStageThresholds(StageThresholdsData thresholds) =>
      _guard(() => _repository.writeStageThresholds(thresholds));

  // ---- Lifecycle ----

  @override
  void dispose() => _repository.dispose();

  /// Wraps BLE-specific failures (BLEException and friends) into
  /// [DeviceRepositoryException] so callers above this layer can catch
  /// one exception type regardless of which transport is active.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DeviceRepositoryException {
      rethrow;
    } catch (e) {
      throw DeviceRepositoryException('BLE operation failed', cause: e);
    }
  }
}