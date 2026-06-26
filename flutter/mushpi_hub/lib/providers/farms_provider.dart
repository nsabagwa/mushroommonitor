import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mushpi_hub/data/repositories/farm_repository.dart';
import 'package:mushpi_hub/data/repositories/alert_sync_repository.dart';
import 'package:mushpi_hub/data/models/farm.dart';
import 'package:mushpi_hub/core/constants/ble_constants.dart';
import 'dart:developer' as developer;

/// Firebase-backed now -- no longer needs the local Drift database.
final farmRepositoryProvider = Provider<FarmRepository>((ref) {
  return FarmRepository();
});

/// Mirrors farm/threshold data to Firestore so the backend email-alert
/// Cloud Function can check readings even while the app is closed.
final alertSyncRepositoryProvider = Provider<AlertSyncRepository>((ref) {
  return AlertSyncRepository();
});

final allFarmsProvider = FutureProvider<List<Farm>>((ref) async {
  return await ref.watch(farmRepositoryProvider).getAllFarms();
});

final activeFarmsProvider = FutureProvider<List<Farm>>((ref) async {
  return await ref.watch(farmRepositoryProvider).getActiveFarms();
});

final archivedFarmsProvider = FutureProvider<List<Farm>>((ref) async {
  final all = await ref.watch(allFarmsProvider.future);
  return all.where((f) => !f.isActive).toList();
});

final farmByIdProvider =
    FutureProvider.family<Farm?, String>((ref, farmId) async {
  return await ref.watch(farmRepositoryProvider).getFarmById(farmId);
});

final farmOperationsProvider = Provider<FarmOperations>((ref) {
  return FarmOperations(
    repository: ref.watch(farmRepositoryProvider),
    ref: ref,
  );
});

class FarmOperations {
  FarmOperations({required this.repository, required this.ref});

  final FarmRepository repository;
  final Ref ref;

  Future<String> createFarm({
    required String id,
    required String name,
    required String thingSpeakChannelId,
    required String thingSpeakReadApiKey,
    Map<String, String>? thingSpeakFieldMap,
    String? location,
    String? notes,
    Species? primarySpecies,
    String? imageUrl,
  }) async {
    try {
      final farmId = await repository.createFarm(
        id: id,
        name: name,
        thingSpeakChannelId: thingSpeakChannelId,
        thingSpeakReadApiKey: thingSpeakReadApiKey,
        thingSpeakFieldMap: thingSpeakFieldMap,
        location: location,
        notes: notes,
        primarySpecies: primarySpecies,
        imageUrl: imageUrl,
      );
      _refreshFarms();
      return farmId;
    } catch (e, st) {
      developer.log('Failed to create farm',
          error: e, stackTrace: st, name: 'FarmOperations');
      rethrow;
    }
  }

  Future<void> updateFarm({
    required String id,
    String? name,
    String? location,
    String? notes,
    Species? primarySpecies,
    String? imageUrl,
  }) async {
    await repository.updateFarm(
      id: id,
      name: name,
      location: location,
      notes: notes,
      primarySpecies: primarySpecies,
      imageUrl: imageUrl,
    );
    _refreshFarms();
  }

  Future<void> deleteFarm(String farmId) async {
    await repository.deleteFarm(farmId);
    _refreshFarms();
  }

  Future<void> archiveFarm(String farmId) async {
    await repository.archiveFarm(farmId);
    _refreshFarms();
  }

  Future<void> restoreFarm(String farmId) async {
    await repository.restoreFarm(farmId);
    _refreshFarms();
  }

  Future<void> updateLastActive(String farmId) async {
    await repository.updateLastActive(farmId);
    _refreshFarms();
  }

  Future<String> recordHarvest({
    required String id,
    required String farmId,
    required DateTime harvestDate,
    required Species species,
    required GrowthStage stage,
    required double yieldKg,
    int? flushNumber,
    double? qualityScore,
    String? notes,
    List<String>? photoUrls,
  }) async {
    final harvestId = await repository.recordHarvest(
      id: id,
      farmId: farmId,
      harvestDate: harvestDate,
      species: species,
      stage: stage,
      yieldKg: yieldKg,
      flushNumber: flushNumber,
      qualityScore: qualityScore,
      notes: notes,
      photoUrls: photoUrls,
    );
    _refreshFarms();
    return harvestId;
  }

  Future<List<HarvestRecord>> getHarvestsForFarm(String farmId) =>
      repository.getHarvestsForFarm(farmId);

  Future<List<HarvestRecord>> getHarvestsForPeriod({
    required String farmId,
    required DateTime startDate,
    required DateTime endDate,
  }) =>
      repository.getHarvestsForPeriod(farmId, startDate, endDate);

  Future<FarmStats?> getFarmStats(String farmId) =>
      repository.getFarmStats(farmId);

  Future<void> recalculateProductionMetrics(String farmId) async {
    await repository.recalculateProductionMetrics(farmId);
    _refreshFarms();
  }

  void _refreshFarms() {
    ref.invalidate(allFarmsProvider);
    ref.invalidate(activeFarmsProvider);
    ref.invalidate(archivedFarmsProvider);
  }
}

final harvestsForFarmProvider =
    FutureProvider.family<List<HarvestRecord>, String>((ref, farmId) async {
  return await ref.watch(farmOperationsProvider).getHarvestsForFarm(farmId);
});

final farmStatsProvider =
    FutureProvider.family<FarmStats?, String>((ref, farmId) async {
  return await ref.watch(farmOperationsProvider).getFarmStats(farmId);
});
