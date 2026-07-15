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
/// instance and delegates to it.
class BleDeviceRepository implements DeviceRepository {
  final BLERepository _repository;

  BleDeviceRepository(this._repository);

  // ---- Manual Override State ----
  int _overrideBits = 0;

  Future<void> _writeOverrideBit(int bitmask, bool enabled) => _guard(() {
    _overrideBits = enabled ? (_overrideBits | bitmask) : (_overrideBits & ~bitmask);
    return _repository.writeOverrideBits(_overrideBits);
  });

  Future<void> _toggleOverrideBit(int bitmask) => _writeOverrideBit(bitmask, (_overrideBits & bitmask) == 0);

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
    // previously-linked farm after an app relaunch) - scan and match
    // by ID, same strategy auto_reconnect_provider.dart already uses.
    device ??= await _findDeviceById(target.deviceId);

    if (device == null) {
      throw DeviceRepositoryException('Device ${target.deviceId} not found');
    }

    await _repository.connect(device);
  });

  @override
  Future<void> disconnect() => _guard(() => _repository.disconnect());

  @override
  bool get isConnected => _repository.isConnected;

  @override
  Stream<DeviceConnectionState> get connectionStateStream => _repository.connectionStateStream.map(_mapConnectionState);

  DeviceConnectionState _mapConnectionState(BluetoothConnectionState state) {
    // flutter_blue_plus only distinguishes connected/disconnected today;
    // there's no interim "connecting" event from the platform layer.
    return state == BluetoothConnectionState.connected ? DeviceConnectionState.connected : DeviceConnectionState.disconnected;
  }

  /// Scans and matches by remoteId string, mirroring
  /// auto_reconnect_provider.dart's '_scanAndConnect'.
  Future<BluetoothDevice?> _findDeviceById(
    String deviceId, {
      Duration timeout = const Duration(seconds: 10),
    }
  ) async {
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
  Stream<EnvironmentalReading> get environmentalDataStream => _repository.environmentalDataStream;

  @override
  Stream<int> get statusFlagsStream => _repository.statusFlagsStream;

  @override
  Stream<ActuatorStatusData> get actuatorStatusStream => _repository.actuatorStatusStream;

  // ---- Reads ----

  @override
  Future<EnvironmentalReading> readEnvironmentalData() => _guard(() => _repository.readEnvironmentalData());

  @override
  Future<ControlTargetsData> readControlTargets() => _guard(() => _repository.readControlTargets());

  @override
  Future<StageStateData> readStageState() => _guard(() => _repository.readStageState());

  @override
  Future<int> readStatusFlags() => _guard(() => _repository.readStatusFlags());

  @override
  Future<ActuatorStatusData?> readActuatorStatus() => _guard(() => _repository.readActuatorStatus());

  @override
  Future<StageThresholdsData?> readStageThresholds(
    Species species, 
    GrowthStage stage
    ) => _guard(() => _repository.readStageThresholds(species, stage));


  // ---- Writes ----

  @override
  Future<void> writeControlTargets(ControlTargetsData targets) => _guard(() => _repository.writeControlTargets(targets));

  @override
  Future<void> writeOverrideBits(int bits) => _guard(() => _repository.writeOverrideBits(bits));

  @override
  Future<void> writeStageState(StageStateData state) => _guard(() => _repository.writeStageState(state));

  @override
  Future<bool> writeStageThresholds(StageThresholdsData thresholds) => _guard(() => _repository.writeStageThresholds(thresholds));

  // ---- Manual Controls ----

  @override
  Future<void> toggleManualMode() => _toggleOverrideBit(OverrideBits.disableAuto);

  @override
  Future<void> toggleTec() => _toggleOverrideBit(OverrideBits.heater);

  @override
  Future<void> toggleHumidifier() => _toggleOverrideBit(OverrideBits.mist);

  @override
  Future<void> setFanPwm(int value) => _writeOverrideBit(OverrideBits.fan, value > 0);

  @override
  Future<void> setLightPwm(int value) => _writeOverrideBit(OverrideBits.light, value > 0);

  // ---- Lifecycle ----

  @override
  void dispose() => _repository.dispose();

  /// Wraps BLE-specific failures into [DeviceRepositoryException] so
  /// callers above this layer can catch one exception type regardless of
  /// which transport is active.
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