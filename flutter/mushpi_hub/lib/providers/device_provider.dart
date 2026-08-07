// lib/providers/device_provider.dart
// This file contains the provider for the DeviceRepository, which
// controls the lifecycle of a connection to a physical device.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mushpi_hub/data/repositories/ble_device_repository.dart';
import 'package:mushpi_hub/data/repositories/device_repository.dart';
import 'package:mushpi_hub/data/repositories/wifi_device_repository.dart';
import 'package:mushpi_hub/providers/ble_provider.dart';
import 'package:mushpi_hub/providers/farms_provider.dart';
import 'package:mushpi_hub/providers/database_provider.dart';
import 'package:mushpi_hub/data/database/app_database.dart';

import 'package:mushpi_hub/core/utils/ble_serializer.dart';

final farmDeviceRepositoryProvider = FutureProvider.autoDispose.family<DeviceRepository, String>((ref, farmId) async {
  final farm = await ref.watch(farmByIdProvider(farmId).future);

  if (farm == null) {
    throw DeviceRepositoryException('Farm $farmId not found');
  }

  final DeviceRepository repository;
  final DeviceTarget target;

  // If a farm somehow has both set, Wi-Fi wins — that's a deliberate
  // choice, not an accident. Revisit if a farm ever legitimately needs both.
  if (farm.wifiHost != null) {
    repository = WifiDeviceRepository();
    target = WifiDeviceTarget(farm.wifiHost!, port: farm.wifiPort);
  } else if (farm.deviceId != null) {
    // Untested path today — routing a BLE farm through here means a
    // second thing calling .connect() on the same bleRepositoryProvider
    // singleton the existing auto-reconnect flow already manages. Don't
    // exercise this branch until your groupmate's confirmed it won't
    // fight that flow. Flag it to them before anything touches this.
    repository = BleDeviceRepository(ref.watch(bleRepositoryProvider));
    target = BleDeviceTarget(farm.deviceId!);
  } else {
    throw DeviceRepositoryException('Farm $farmId has no device linked');
  }

  ref.onDispose(repository.dispose);
  try {
    await repository.connect(target);
    } catch (e) {
      print('❌ farmDeviceRepositoryProvider: connect() failed for farm $farmId — $e');
      rethrow;
    }

  /// BLE readings are persisted by SensorDataListener (sensor_data_listener.dart),
  /// which is hardwired to the BLE singleton and has no visibility into wifi
  /// farms. This provider is already the one place that owns a live Wifi
  /// connection per farm, so it persists Wifi readings directly- same 5s
  /// debounce SensorDataListener uses for BLE to avoid hammering the DB at the 2s poll rate
  StreamSubscription<EnvironmentalReading>? wifiReadingSubscription;
  if (target is WifiDeviceTarget) {
    DateTime? lastReadingSave;
    const minSaveInterval = Duration(seconds: 5);
    wifiReadingSubscription = repository.environmentalDataStream.listen((reading) async {
      final now = DateTime.now();
      if (lastReadingSave == null && now.difference(lastReadingSave!) < minSaveInterval) {
        return;
      }
      lastReadingSave = now;
      try {
        final readingsDao = ref.read(readingsDaoProvider);
        await readingsDao.insertReading(
          ReadingsCompanion.insert(
            farmId: farmId,
            timestamp: reading.timestamp,
            co2Ppm: reading.co2Ppm,
            temperatureC: reading.temperatureC,
            relativeHumidity: reading.relativeHumidity,
            lightRaw: reading.lightRaw,
            ),
          );
      } catch (e) {
        print('❌ farmDeviceRepositoryProvider: saveReading() failed for farm $farmId — $e');
      }
    });
  }

  // Keep farm.lastActive fresh while this repository has a live
  // connection, so a farm shows 'online' the same way BLE farms already
  // do via BLEConnectionManager. This is a new behaviour for Wi-Fi; BLE
  // farms already get this from BLEConnectionManager, so this is harmless
  // for them.
  final farmOps = ref.watch(farmOperationsProvider);

  Future<void> markOnline() async {
    await farmOps.updateLastActive(farmId);
    ref.invalidate(activeFarmsProvider);
  }

  Future<void> markOffline() async {
    await farmOps.clearLastActive(farmId);
    ref.invalidate(activeFarmsProvider);
  }

  await markOnline();
  final heartbeat = Timer.periodic(const Duration(seconds: 30), (_) => markOnline());

  final connectionSubscription = repository.connectionStateStream.listen((state) {
    if (state == DeviceConnectionState.disconnected) markOffline();
  });

  ref.onDispose(() {
    heartbeat.cancel();
    connectionSubscription.cancel();
    wifiReadingSubscription?.cancel();
    markOffline();
  });

  return repository;
});

/// Connection status for [farmId], regardless of transport (BLE or WiFi).
/// Built on [farmDeviceRepositoryProvider], which already knows how to pick
/// the right transport per farm so screens that watch this don't need to branch
/// on farm.wifiHost/ farm.deviceId themselves

final farmConnectionStateProvider = StreamProvider.autoDispose.family<DeviceConnectionState, String>((ref, farmId) async* {
  final repository = await ref.watch(farmDeviceRepositoryProvider(farmId).future);
  yield repository.isConnected ? DeviceConnectionState.connected : DeviceConnectionState.disconnected;
  yield* repository.connectionStateStream;
});

/// Live actuator status for [farmId] regardless of transport.
final farmActuatorStatusProvider = StreamProvider.autoDispose.family<ActuatorStatusData, String>((ref, farmId) async* {
  final repository = await ref.watch(farmDeviceRepositoryProvider(farmId).future);
  yield* repository.actuatorStatusStream;
});

final farmEnvironmentalDataProvider = StreamProvider.autoDispose.family<EnvironmentalReading, String>((ref, farmId) async* {
  final repository = await ref.watch(farmDeviceRepositoryProvider(farmId).future);
  yield* repository.environmentalDataStream;
});