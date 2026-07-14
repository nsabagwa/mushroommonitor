// lib/providers/readings_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mushpi_hub/data/config/thingspeak_config.dart';
import 'package:mushpi_hub/data/database/app_database.dart' show Reading;
import 'package:mushpi_hub/data/models/farm.dart';
import 'package:mushpi_hub/data/repositories/thingspeak_repository.dart';
import 'package:mushpi_hub/providers/current_farm_provider.dart';
import 'package:mushpi_hub/providers/database_provider.dart';
import 'package:mushpi_hub/providers/farms_provider.dart';
import 'dart:developer' as developer;

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

/// Build a ThingSpeakConfig from the farm's Firebase record.
/// (Previously this read from the local Drift farmsDao, which is no longer
/// the source of truth for farm data now that farms live in Firebase.)
ThingSpeakConfig? _configFromFarm(Farm? farm) {
  if (farm == null) return null;
  if (farm.thingSpeakChannelId.isEmpty || farm.thingSpeakReadApiKey.isEmpty) {
    return null;
  }
  return ThingSpeakConfig.fromFarm(
    channelId: farm.thingSpeakChannelId,
    readApiKey: farm.thingSpeakReadApiKey,
    fieldMap: farm.thingSpeakFieldMap,
  );
}

/// Attempts to backfill [localReadings] with remote ThingSpeak data for the
/// given farm/period. This requires looking up the farm's config from
/// Firebase (via [farmByIdProvider]), which is a network call and can fail
/// or time out independently of the local DB read that already succeeded.
///
/// IMPORTANT: any failure here (farm lookup OR ThingSpeak fetch) must fall
/// back to [localReadings] rather than propagating - otherwise a transient
/// Firebase hiccup would discard readings we already have, which is what
/// caused the intermittent "No Data Available" screen even though local
/// data existed.
Future<List<Reading>> _withThingSpeakBackfill({
  required Ref ref,
  required String farmId,
  required DateTime start,
  required DateTime end,
  required List<Reading> localReadings,
}) async {
  try {
    final farm = await ref.watch(farmByIdProvider(farmId).future);
    final config = _configFromFarm(farm);
    if (config == null) return localReadings;

    final tsRepo = const ThingSpeakRepository();
    final remoteReadings = await tsRepo.fetchReadingsForPeriod(
      config: config,
      farmId: farmId,
      start: start,
      end: end,
    );

    final merged = _mergeReadings(localReadings, remoteReadings);
    developer.log('After ThingSpeak backfill: ${merged.length} total readings',
        name: 'mushpi.providers.readings');
    return merged;
  } catch (e, stackTrace) {
    developer.log(
        'Farm lookup or ThingSpeak backfill failed - falling back to '
        '${localReadings.length} local readings',
        name: 'mushpi.providers.readings',
        error: e,
        stackTrace: stackTrace,
        level: 1000);
    return localReadings;
  }
}

final last24HoursReadingsProvider = FutureProvider<List<Reading>>((ref) async {
  final readingsDao = ref.watch(readingsDaoProvider);
  final selectedFarmId = ref.watch(selectedMonitoringFarmIdProvider);

  if (selectedFarmId == null) {
    developer.log('No farm selected - returning empty readings list',
        name: 'mushpi.providers.readings');
    return [];
  }

  final now = DateTime.now();
  final start = now.subtract(const Duration(hours: 24));

  List<Reading> localReadings;
  try {
    localReadings = await readingsDao.getReadingsByFarmAndPeriod(
        selectedFarmId, start, now);

    developer.log(
        'Fetched ${localReadings.length} local readings for last 24 hours',
        name: 'mushpi.providers.readings');
  } catch (e, stackTrace) {
    developer.log('Error fetching local 24-hour readings',
        name: 'mushpi.providers.readings',
        error: e,
        stackTrace: stackTrace,
        level: 1000);
    return [];
  }

  // From here on, any failure (Firebase farm lookup or ThingSpeak fetch)
  // just skips the backfill - it never discards localReadings.
  return _withThingSpeakBackfill(
    ref: ref,
    farmId: selectedFarmId,
    start: start,
    end: now,
    localReadings: localReadings,
  );
});

final readingsByPeriodProvider = FutureProvider.family<List<Reading>,
    ({String farmId, DateTime start, DateTime end})>((ref, params) async {
  final readingsDao = ref.watch(readingsDaoProvider);

  List<Reading> localReadings;
  try {
    localReadings = await readingsDao.getReadingsByFarmAndPeriod(
        params.farmId, params.start, params.end);

    developer.log(
        'Fetched ${localReadings.length} local readings for custom period',
        name: 'mushpi.providers.readings');
  } catch (e, stackTrace) {
    developer.log('Error fetching local readings for custom period',
        name: 'mushpi.providers.readings',
        error: e,
        stackTrace: stackTrace,
        level: 1000);
    return [];
  }

  // From here on, any failure (Firebase farm lookup or ThingSpeak fetch)
  // just skips the backfill - it never discards localReadings.
  return _withThingSpeakBackfill(
    ref: ref,
    farmId: params.farmId,
    start: params.start,
    end: params.end,
    localReadings: localReadings,
  );
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
