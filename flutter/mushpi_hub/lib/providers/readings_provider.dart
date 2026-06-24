// lib/providers/readings_provider.dart

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mushpi_hub/data/database/app_database.dart';
import 'package:mushpi_hub/providers/database_provider.dart';
import 'package:mushpi_hub/providers/current_farm_provider.dart';
import 'package:mushpi_hub/providers/farms_provider.dart';
import 'package:mushpi_hub/data/database/daos/readings_dao.dart';
import 'dart:developer' as developer;

/// Provider for fetching readings from the last 24 hours for the selected farm.
///
/// Fetches from local DB first, then backfills from ThingSpeak if credentials
/// are configured. Remote readings are persisted locally for offline access.
final last24HoursReadingsProvider = FutureProvider<List<Reading>>((ref) async {
  final readingsDao = ref.watch(readingsDaoProvider);
  final selectedFarmId = ref.watch(selectedMonitoringFarmIdProvider);

  if (selectedFarmId == null) {
    developer.log(
      'No farm selected - returning empty readings list',
      name: 'mushpi.providers.readings',
    );
    return [];
  }

  try {
    final now = DateTime.now();
    final twentyFourHoursAgo = now.subtract(const Duration(hours: 24));

    developer.log(
      'Fetching readings for farm $selectedFarmId from last 24 hours (local DB)',
      name: 'mushpi.providers.readings',
    );

    final localReadings = await readingsDao.getReadingsByFarmAndPeriod(
      selectedFarmId,
      twentyFourHoursAgo,
      now,
    );

    developer.log(
      'Fetched ${localReadings.length} readings from local DB for last 24 hours',
      name: 'mushpi.providers.readings',
    );

    // Check if this farm has ThingSpeak credentials
    final farm = await ref.watch(farmByIdProvider(selectedFarmId).future);

    if (farm?.thingSpeakChannelId == null ||
        farm?.thingSpeakReadApiKey == null) {
      developer.log(
        'No ThingSpeak credentials for farm $selectedFarmId — returning local only',
        name: 'mushpi.providers.readings',
      );
      return localReadings;
    }

    developer.log(
      'Fetching ThingSpeak data for farm $selectedFarmId (last 24 hours)',
      name: 'mushpi.providers.readings',
    );

    List<Reading> remoteReadings = [];
    try {
      remoteReadings = await _fetchThingSpeakReadings(
        channelId: farm!.thingSpeakChannelId!,
        readApiKey: farm.thingSpeakReadApiKey!,
        start: twentyFourHoursAgo,
        end: now,
        farmId: selectedFarmId,
        readingsDao: readingsDao,
      );
    } catch (e) {
      developer.log(
        'ThingSpeak fetch failed, returning local only: $e',
        name: 'mushpi.providers.readings',
        level: 900,
      );
      return localReadings;
    }

    if (remoteReadings.isEmpty) {
      developer.log(
        'No ThingSpeak readings available for backfill',
        name: 'mushpi.providers.readings',
      );
      return localReadings;
    }

    // If no local data, return remote directly
    if (localReadings.isEmpty) {
      developer.log(
        'No local readings - returning ThingSpeak-only data (${remoteReadings.length} readings)',
        name: 'mushpi.providers.readings',
      );
      return remoteReadings;
    }

    // Merge: keep remote readings only where local has gaps (±2.5 minutes)
    final merged = <Reading>[];
    merged.addAll(localReadings);

    for (final remote in remoteReadings) {
      final hasNearbyLocal = localReadings.any((local) {
        final diff = local.timestamp.difference(remote.timestamp).abs();
        return diff <= const Duration(minutes: 2, seconds: 30);
      });
      if (!hasNearbyLocal) {
        merged.add(remote);
      }
    }

    merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    developer.log(
      'After ThingSpeak backfill: ${merged.length} total '
      '(local: ${localReadings.length}, remote added: ${merged.length - localReadings.length})',
      name: 'mushpi.providers.readings',
    );

    return merged;
  } catch (e, stackTrace) {
    developer.log(
      'Error fetching 24-hour readings',
      name: 'mushpi.providers.readings',
      error: e,
      stackTrace: stackTrace,
      level: 1000,
    );
    return [];
  }
});

/// Provider for fetching readings from a custom time period for a specific farm.
final readingsByPeriodProvider = FutureProvider.family<List<Reading>,
    ({String farmId, DateTime start, DateTime end})>((ref, params) async {
  final readingsDao = ref.watch(readingsDaoProvider);

  try {
    developer.log(
      'Fetching readings for farm ${params.farmId} '
      'from ${params.start} to ${params.end}',
      name: 'mushpi.providers.readings',
    );

    final localReadings = await readingsDao.getReadingsByFarmAndPeriod(
      params.farmId,
      params.start,
      params.end,
    );

    developer.log(
      'Fetched ${localReadings.length} readings from local DB for custom period',
      name: 'mushpi.providers.readings',
    );

    final farm = await ref.watch(farmByIdProvider(params.farmId).future);

    if (farm?.thingSpeakChannelId == null ||
        farm?.thingSpeakReadApiKey == null) {
      developer.log(
        'No ThingSpeak credentials for farm ${params.farmId} — returning local only',
        name: 'mushpi.providers.readings',
      );
      return localReadings;
    }

    developer.log(
      'Fetching ThingSpeak data for farm ${params.farmId} (custom period)',
      name: 'mushpi.providers.readings',
    );

    List<Reading> remoteReadings = [];
    try {
      remoteReadings = await _fetchThingSpeakReadings(
        channelId: farm!.thingSpeakChannelId!,
        readApiKey: farm.thingSpeakReadApiKey!,
        start: params.start,
        end: params.end,
        farmId: params.farmId,
        readingsDao: readingsDao,
      );
    } catch (e) {
      developer.log(
        'ThingSpeak fetch failed, returning local only: $e',
        name: 'mushpi.providers.readings',
        level: 900,
      );
      return localReadings;
    }

    if (remoteReadings.isEmpty) {
      developer.log(
        'No ThingSpeak readings available for backfill',
        name: 'mushpi.providers.readings',
      );
      return localReadings;
    }

    if (localReadings.isEmpty) {
      developer.log(
        'No local readings - returning ThingSpeak-only data '
        '(${remoteReadings.length} readings)',
        name: 'mushpi.providers.readings',
      );
      return remoteReadings;
    }

    final merged = <Reading>[];
    merged.addAll(localReadings);

    for (final remote in remoteReadings) {
      final hasNearbyLocal = localReadings.any((local) {
        final diff = local.timestamp.difference(remote.timestamp).abs();
        return diff <= const Duration(minutes: 2, seconds: 30);
      });
      if (!hasNearbyLocal) {
        merged.add(remote);
      }
    }

    merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    developer.log(
      'After ThingSpeak backfill: ${merged.length} total '
      '(local: ${localReadings.length}, '
      'remote added: ${merged.length - localReadings.length})',
      name: 'mushpi.providers.readings',
    );

    return merged;
  } catch (e, stackTrace) {
    developer.log(
      'Error fetching readings for custom period',
      name: 'mushpi.providers.readings',
      error: e,
      stackTrace: stackTrace,
      level: 1000,
    );
    return [];
  }
});

/// Provider for fetching recent readings for a farm (limited count).
final recentReadingsProvider =
    FutureProvider.family<List<Reading>, ({String farmId, int limit})>(
        (ref, params) async {
  final readingsDao = ref.watch(readingsDaoProvider);

  try {
    developer.log(
      'Fetching ${params.limit} recent readings for farm ${params.farmId}',
      name: 'mushpi.providers.readings',
    );

    final readings = await readingsDao.getRecentReadingsByFarm(
      params.farmId,
      params.limit,
    );

    developer.log(
      'Fetched ${readings.length} recent readings',
      name: 'mushpi.providers.readings',
    );

    return readings;
  } catch (e, stackTrace) {
    developer.log(
      'Error fetching recent readings',
      name: 'mushpi.providers.readings',
      error: e,
      stackTrace: stackTrace,
      level: 1000,
    );
    rethrow;
  }
});

// ---------------------------------------------------------------------------
// Internal helper — fetches ThingSpeak data and persists it locally
// ---------------------------------------------------------------------------

/// Fetches a time-bounded set of readings from ThingSpeak, converts them to
/// [Reading] objects, persists each one to the local database for offline
/// access, and returns the list.
Future<List<Reading>> _fetchThingSpeakReadings({
  required String channelId,
  required String readApiKey,
  required DateTime start,
  required DateTime end,
  required String farmId,
  required ReadingsDao readingsDao,
}) async {
  // ThingSpeak supports up to 8000 results per request.
  // Use one data point per 15-minute interval as a reasonable upper bound.
  final durationMinutes = end.difference(start).inMinutes;
  final results = (durationMinutes / 15).ceil().clamp(1, 8000);

  final url = Uri.parse(
    'https://api.thingspeak.com/channels/$channelId/feeds.json'
    '?api_key=$readApiKey'
    '&start=${Uri.encodeComponent(start.toUtc().toIso8601String())}'
    '&end=${Uri.encodeComponent(end.toUtc().toIso8601String())}'
    '&results=$results',
  );

  developer.log(
    'ThingSpeak request: $url',
    name: 'mushpi.providers.readings',
  );

  final response = await http.get(url).timeout(const Duration(seconds: 15));

  if (response.statusCode != 200) {
    throw Exception('ThingSpeak HTTP ${response.statusCode}');
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final feeds = json['feeds'] as List<dynamic>? ?? [];

  developer.log(
    'ThingSpeak returned ${feeds.length} feed entries',
    name: 'mushpi.providers.readings',
  );

  // Log first entry for debugging field mapping
  if (feeds.isNotEmpty) {
    final sample = feeds.first as Map<String, dynamic>;
    developer.log(
      'Sample feed entry — '
      'field1: "${sample['field1']}" '
      'field2: "${sample['field2']}" '
      'field3: "${sample['field3']}" '
      'field4: "${sample['field4']}"',
      name: 'mushpi.providers.readings',
    );
  }

  final readings = feeds.map((feed) {
    final map = feed as Map<String, dynamic>;

    // Trim whitespace before parsing — ThingSpeak occasionally pads values
    String? clean(String? raw) => raw?.trim().isEmpty == true ? null : raw?.trim();

    return Reading(
      id: 0,
      farmId: farmId,
      timestamp: DateTime.parse(map['created_at'] as String).toLocal(),
      temperatureC: double.tryParse(clean(map['field1'] as String?) ?? '') ?? 0.0,
      relativeHumidity: double.tryParse(clean(map['field2'] as String?) ?? '') ?? 0.0,
      co2Ppm: (double.tryParse(clean(map['field3'] as String?) ?? '') ?? 0.0).toInt(),
      lightRaw: (double.tryParse(clean(map['field4'] as String?) ?? '') ?? 0.0).toInt(),
    );
  }).where((r) =>
    r.temperatureC > 0 ||
    r.relativeHumidity > 0 ||
    r.co2Ppm > 0 ||
    r.lightRaw > 0,
  ).toList();

  developer.log(
    'Parsed ${readings.length} valid readings from ThingSpeak feed',
    name: 'mushpi.providers.readings',
  );

  // Persist each reading to the local database so they are available offline.
  // insertOrIgnore skips duplicates based on (farmId, timestamp).
  int saved = 0;
  for (final reading in readings) {
    try {
      await readingsDao.insertOrIgnoreReading(reading);
      saved++;
    } catch (e) {
      developer.log(
        'Failed to persist reading at ${reading.timestamp}: $e',
        name: 'mushpi.providers.readings',
        level: 900,
      );
    }
  }

  developer.log(
    'Persisted $saved/${readings.length} ThingSpeak readings to local DB',
    name: 'mushpi.providers.readings',
  );

  return readings;
}
