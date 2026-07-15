// lib/providers/device_provider.dart
// This file contains the provider for the DeviceRepository, which
// controls the lifecycle of a connection to a physical device.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mushpi_hub/data/repositories/ble_device_repository.dart';
import 'package:mushpi_hub/data/repositories/device_repository.dart';
import 'package:mushpi_hub/data/repositories/wifi_device_repository.dart';
import 'package:mushpi_hub/providers/ble_provider.dart';
import 'package:mushpi_hub/providers/farms_provider.dart';

final farmDeviceRepositoryProvider = FutureProvider.autoDispose
    .family<DeviceRepository, String>((ref, farmId) async {
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
  return repository;
});