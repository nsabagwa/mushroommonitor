import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mushpi_hub/data/models/farm.dart';
import 'package:mushpi_hub/core/constants/ble_constants.dart';
import 'package:mushpi_hub/providers/database_provider.dart';
import 'package:mushpi_hub/providers/farms_provider.dart';
import 'package:mushpi_hub/data/repositories/thingspeak_repository.dart';
import 'package:mushpi_hub/data/config/thingspeak_config.dart';
import 'dart:developer' as developer;

/// Which farm is selected on the Monitoring screen.
final selectedMonitoringFarmIdProvider = StateProvider<String?>((ref) => null);

/// Latest environmental reading for the selected farm.
///
/// Always fetches from ThingSpeak using the farm's own channel credentials.
/// Falls back to the local cached reading if ThingSpeak is unreachable.
final selectedMonitoringFarmLatestReadingProvider =
    FutureProvider<EnvironmentalReading?>((ref) async {
  final farmId = ref.watch(selectedMonitoringFarmIdProvider);
  if (farmId == null) return null;

  final farm = await ref.watch(farmByIdProvider(farmId).future);
  if (farm == null) return null;

  final config = ThingSpeakConfig.fromFarm(
    channelId: farm.thingSpeakChannelId,
    readApiKey: farm.thingSpeakReadApiKey,
    fieldMap: farm.thingSpeakFieldMap,
  );

  const tsRepo = ThingSpeakRepository();

  try {
    final tsReading = await tsRepo.fetchLatestReading(
      config: config,
      farmId: farmId,
    );

    if (tsReading != null) {
      // Update lastActive so farm card shows "Live"
      ref.read(farmOperationsProvider).updateLastActive(farmId);

      return EnvironmentalReading(
        co2Ppm: tsReading.co2Ppm,
        temperatureC: tsReading.temperatureC,
        relativeHumidity: tsReading.relativeHumidity,
        lightRaw: tsReading.lightRaw,
        timestamp: tsReading.timestamp,
      );
    }
  } catch (e, st) {
    developer.log('ThingSpeak fetch failed for farm $farmId',
        error: e, stackTrace: st, name: 'current_farm_provider');
  }

  // Fallback: last cached reading in local DB
  try {
    final readingsDao = ref.watch(readingsDaoProvider);
    final local = await readingsDao.getLatestReadingByFarm(farmId);
    if (local != null) {
      return EnvironmentalReading(
        co2Ppm: local.co2Ppm,
        temperatureC: local.temperatureC,
        relativeHumidity: local.relativeHumidity,
        lightRaw: local.lightRaw,
        timestamp: local.timestamp,
      );
    }
  } catch (e) {
    developer.log('Local DB fallback failed',
        error: e, name: 'current_farm_provider');
  }

  return null;
});

/// The farm currently selected for detail/operations (separate from monitoring).
final currentFarmIdProvider = StateProvider<String?>((ref) => null);

final currentFarmProvider = FutureProvider<Farm?>((ref) async {
  final farmId = ref.watch(currentFarmIdProvider);
  if (farmId == null) return null;
  return await ref.watch(farmByIdProvider(farmId).future);
});

final currentFarmOperationsProvider = Provider<CurrentFarmOperations>((ref) {
  return CurrentFarmOperations(
    farmOperations: ref.watch(farmOperationsProvider),
    currentFarmId: ref.watch(currentFarmIdProvider),
  );
});

class CurrentFarmOperations {
  CurrentFarmOperations({
    required this.farmOperations,
    required this.currentFarmId,
  });

  final FarmOperations farmOperations;
  final String? currentFarmId;

  Future<String?> recordHarvest({
    required String id,
    required DateTime harvestDate,
    required Species species,
    required GrowthStage stage,
    required double yieldKg,
    int? flushNumber,
    double? qualityScore,
    String? notes,
    List<String>? photoUrls,
  }) async {
    if (currentFarmId == null) return null;
    return await farmOperations.recordHarvest(
      id: id,
      farmId: currentFarmId!,
      harvestDate: harvestDate,
      species: species,
      stage: stage,
      yieldKg: yieldKg,
      flushNumber: flushNumber,
      qualityScore: qualityScore,
      notes: notes,
      photoUrls: photoUrls,
    );
  }

  Future<void> updateFarm({
    String? name,
    String? location,
    String? notes,
    Species? primarySpecies,
    String? imageUrl,
  }) async {
    if (currentFarmId == null) return;
    await farmOperations.updateFarm(
      id: currentFarmId!,
      name: name,
      location: location,
      notes: notes,
      primarySpecies: primarySpecies,
      imageUrl: imageUrl,
    );
  }

  Future<void> archiveCurrentFarm() async {
    if (currentFarmId == null) return;
    await farmOperations.archiveFarm(currentFarmId!);
  }

  Future<void> deleteCurrentFarm() async {
    if (currentFarmId == null) return;
    await farmOperations.deleteFarm(currentFarmId!);
  }
}

/// Environmental reading value object
class EnvironmentalReading {
  final int co2Ppm;
  final double temperatureC;
  final double relativeHumidity;
  final int lightRaw;
  final DateTime timestamp;

  const EnvironmentalReading({
    required this.co2Ppm,
    required this.temperatureC,
    required this.relativeHumidity,
    required this.lightRaw,
    required this.timestamp,
  });
}
