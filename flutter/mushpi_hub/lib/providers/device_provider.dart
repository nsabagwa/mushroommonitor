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
  await repository.connect(target);

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