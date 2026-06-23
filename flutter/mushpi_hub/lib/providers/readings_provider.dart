// lib/providers/readings_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mushpi_hub/data/config/thingspeak_config.dart';
import 'package:mushpi_hub/data/database/app_database.dart';
import 'package:mushpi_hub/data/repositories/thingspeak_repository.dart';
import 'package:mushpi_hub/providers/current_farm_provider.dart';
import 'package:mushpi_hub/providers/database_provider.dart';
import 'dart:developer' as developer;

/// Build a ThingSpeakConfig from a farm row, or return null if unconfigured.
ThingSpeakConfig? _configFromFarm(dynamic farmDao, String farmId) {
  // farmDao is the Drift Farm row — access channelId/apiKey directly
  return null; // resolved below via farmsDao lookup
}

List<Reading> _mergeReadings(List<Reading> local, List<Reading> remote) {
  if (remote.isEmpty) return local;
  if (local.isEmpty) return remote;

  final merged = <Reading>[...local];
  for (final r in remote) {
    final hasNearby = local.any((l) =>
        l.timestamp.difference(r.timestamp).abs() <=
        const Duration(minutes: 2, seconds: 30));
    if (!hasNearby) merged.add(r);
  }
  merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return merged;
}

Future<ThingSpeakConfig?> _getConfig(dynamic farmsDao, String farmId) async {
  try {
    final row = await farmsDao.getFarmById(farmId);
    if (row == null) return null;
    if (row.thingSpeakChannelId.isEmpty || row.thingSpeakReadApiKey.isEmpty) {
      return null;
    }
    return ThingSpeakConfig.fromFarm(
      channelId: row.thingSpeakChannelId,
      readApiKey: row.thingSpeakReadApiKey,
      fieldMap: row.thingSpeakFieldMap != null
          ? Map<String, String>.from(row.thingSpeakFieldMap as Map)
          : null,
    );
  } catch (_) {
    return null;
  }
}

final last24HoursReadingsProvider = FutureProvider<List<Reading>>((ref) async {
  final readingsDao = ref.watch(readingsDaoProvider);
  final farmsDao = ref.watch(farmsDaoProvider);
  final selectedFarmId = ref.watch(selectedMonitoringFarmIdProvider);

  if (selectedFarmId == null) {
    developer.log('No farm selected - returning empty readings list',
        name: 'mushpi.providers.readings');
    return [];
  }

  try {
    final now = DateTime.now();
    final start = now.subtract(const Duration(hours: 24));

    final localReadings = await readingsDao.getReadingsByFarmAndPeriod(
        selectedFarmId, start, now);

    developer.log(
        'Fetched ${localReadings.length} local readings for last 24 hours',
        name: 'mushpi.providers.readings');

    final config = await _getConfig(farmsDao, selectedFarmId);
    if (config == null) return localReadings;

    final tsRepo = const ThingSpeakRepository();
    List<Reading> remoteReadings = [];
    try {
      remoteReadings = await tsRepo.fetchReadingsForPeriod(
        config: config,
        farmId: selectedFarmId,
        start: start,
        end: now,
      );
    } catch (_) {
      return localReadings;
    }

    final merged = _mergeReadings(localReadings, remoteReadings);
    developer.log('After ThingSpeak backfill: ${merged.length} total readings',
        name: 'mushpi.providers.readings');
    return merged;
  } catch (e, stackTrace) {
    developer.log('Error fetching 24-hour readings',
        name: 'mushpi.providers.readings',
        error: e,
        stackTrace: stackTrace,
        level: 1000);
    return [];
  }
});

final readingsByPeriodProvider = FutureProvider.family<List<Reading>,
    ({String farmId, DateTime start, DateTime end})>((ref, params) async {
  final readingsDao = ref.watch(readingsDaoProvider);
  final farmsDao = ref.watch(farmsDaoProvider);

  try {
    final localReadings = await readingsDao.getReadingsByFarmAndPeriod(
        params.farmId, params.start, params.end);

    developer.log(
        'Fetched ${localReadings.length} local readings for custom period',
        name: 'mushpi.providers.readings');

    final config = await _getConfig(farmsDao, params.farmId);
    if (config == null) return localReadings;

    final tsRepo = const ThingSpeakRepository();
    List<Reading> remoteReadings = [];
    try {
      remoteReadings = await tsRepo.fetchReadingsForPeriod(
        config: config,
        farmId: params.farmId,
        start: params.start,
        end: params.end,
      );
    } catch (_) {
      return localReadings;
    }

    final merged = _mergeReadings(localReadings, remoteReadings);
    developer.log('After ThingSpeak backfill: ${merged.length} total readings',
        name: 'mushpi.providers.readings');
    return merged;
  } catch (e, stackTrace) {
    developer.log('Error fetching readings for custom period',
        name: 'mushpi.providers.readings',
        error: e,
        stackTrace: stackTrace,
        level: 1000);
    return [];
  }
});

final recentReadingsProvider =
    FutureProvider.family<List<Reading>, ({String farmId, int limit})>(
        (ref, params) async {
  final readingsDao = ref.watch(readingsDaoProvider);

  try {
    final readings =
        await readingsDao.getRecentReadingsByFarm(params.farmId, params.limit);
    developer.log('Fetched ${readings.length} recent readings',
        name: 'mushpi.providers.readings');
    return readings;
  } catch (e, stackTrace) {
    developer.log('Error fetching recent readings',
        name: 'mushpi.providers.readings',
        error: e,
        stackTrace: stackTrace,
        level: 1000);
    rethrow;
  }
});
