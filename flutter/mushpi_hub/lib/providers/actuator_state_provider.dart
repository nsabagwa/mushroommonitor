import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';

import '../core/utils/ble_serializer.dart';
import '../core/constants/ble_constants.dart';
import 'device_provider.dart';
import 'database_provider.dart';


/// Exposes current control targets from the device for showing actuator
/// modes on the monitoring screen (e.g., Light mode and cycle timings).
///
/// Works for either transport — it goes through [farmDeviceRepositoryProvider]
/// rather than talking to BLE directly.
final farmControlTargetsProvider = FutureProvider.autoDispose
    .family<ControlTargetsData?, String>((ref, farmId) async {
  final settingsDao = ref.read(settingsDaoProvider);

  try {
    final repository =
        await ref.watch(farmDeviceRepositoryProvider(farmId).future);
    return await repository.readControlTargets();
  } catch (_) {
    // Not connected, or the read failed. Fall back to the last cached
    // targets if that debug flag is on — same behavior as before.
    final useCache =
        dotenv.env['MUSHPI_BLE_OFFLINE_USE_CACHE']?.toLowerCase() == 'true';
    if (!useCache) return null;

    try {
      final cached = await settingsDao.getValue('last_control_targets_json');
      if (cached == null || cached.isEmpty) return null;
      final map = jsonDecode(cached) as Map<String, dynamic>;
      return ControlTargetsData(
        tempMin: (map['tempMin'] as num).toDouble(),
        tempMax: (map['tempMax'] as num).toDouble(),
        rhMin: (map['rhMin'] as num).toDouble(),
        co2Max: map['co2Max'] as int,
        lightMode: LightMode.fromValue(map['lightMode'] as int),
        onMinutes: map['onMinutes'] as int,
        offMinutes: map['offMinutes'] as int,
      );
    } catch (_) {
      return null;
    }
  }
});