import 'dart:convert';
import 'dart:developer' as developer;
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../models/farm.dart' as models;
import 'package:mushpi_hub/core/constants/ble_constants.dart';

class FarmRepository {
  final AppDatabase _database;
  FarmRepository(this._database);

  // ── FARM CRUD ──────────────────────────────────────────────────────────────

  Future<List<models.Farm>> getAllFarms() async {
    final rows = await _database.farmsDao.getAllFarms();
    return rows.map(_farmFromDrift).toList();
  }

  Future<List<models.Farm>> getActiveFarms() async {
    final rows = await _database.farmsDao.getActiveFarms();
    return rows.map(_farmFromDrift).toList();
  }

  Future<models.Farm?> getFarmById(String id) async {
    final row = await _database.farmsDao.getFarmById(id);
    return row != null ? _farmFromDrift(row) : null;
  }

  Future<models.Farm?> getFarmByChannelId(String channelId) async {
    final row = await _database.farmsDao.getFarmByChannelId(channelId);
    return row != null ? _farmFromDrift(row) : null;
  }

  /// Create a new farm linked to a ThingSpeak channel.
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
    Map<String, dynamic>? metadata,
  }) async {
    final companion = FarmsCompanion(
      id: Value(id),
      name: Value(name),
      thingSpeakChannelId: Value(thingSpeakChannelId),
      thingSpeakReadApiKey: Value(thingSpeakReadApiKey),
      thingSpeakFieldMap: Value(
        thingSpeakFieldMap != null ? jsonEncode(thingSpeakFieldMap) : null,
      ),
      location: Value(location),
      notes: Value(notes),
      createdAt: Value(DateTime.now()),
      totalHarvests: const Value(0),
      totalYieldKg: const Value(0.0),
      primarySpecies: Value(primarySpecies?.id),
      imageUrl: Value(imageUrl),
      isActive: const Value(true),
      metadata: Value(metadata != null ? jsonEncode(metadata) : null),
    );

    await _database.farmsDao.insertFarm(companion);
    developer.log('Farm created: $name (channel: $thingSpeakChannelId)',
        name: 'FarmRepository');
    return id;
  }

  Future<void> updateFarm({
    required String id,
    String? name,
    String? thingSpeakReadApiKey,
    Map<String, String>? thingSpeakFieldMap,
    String? location,
    String? notes,
    Species? primarySpecies,
    String? imageUrl,
    bool? isActive,
    Map<String, dynamic>? metadata,
  }) async {
    final companion = FarmsCompanion(
      id: Value(id),
      name: name != null ? Value(name) : const Value.absent(),
      thingSpeakReadApiKey: thingSpeakReadApiKey != null
          ? Value(thingSpeakReadApiKey)
          : const Value.absent(),
      thingSpeakFieldMap: thingSpeakFieldMap != null
          ? Value(jsonEncode(thingSpeakFieldMap))
          : const Value.absent(),
      location: location != null ? Value(location) : const Value.absent(),
      notes: notes != null ? Value(notes) : const Value.absent(),
      primarySpecies: primarySpecies != null
          ? Value(primarySpecies.id)
          : const Value.absent(),
      imageUrl: imageUrl != null ? Value(imageUrl) : const Value.absent(),
      isActive: isActive != null ? Value(isActive) : const Value.absent(),
      metadata:
          metadata != null ? Value(jsonEncode(metadata)) : const Value.absent(),
    );
    await _database.farmsDao.updateFarm(companion);
  }

  Future<void> deleteFarm(String id) async {
    await _database.farmsDao.deleteFarm(id);
  }

  Future<void> archiveFarm(String farmId) async {
    await _database.farmsDao.setFarmActive(farmId, false);
  }

  Future<void> restoreFarm(String farmId) async {
    await _database.farmsDao.setFarmActive(farmId, true);
  }

  // Mark farm as recently fetched (replaces BLE lastActive)
  Future<void> updateLastActive(String farmId) async {
    await _database.farmsDao.updateLastActive(farmId, DateTime.now());
  }

  Future<void> clearLastActive(String farmId) async {
    await _database.farmsDao.clearLastActive(farmId);
  }

  // ── HARVESTS ───────────────────────────────────────────────────────────────

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
    Map<String, dynamic>? metadata,
  }) async {
    final companion = HarvestsCompanion(
      id: Value(id),
      farmId: Value(farmId),
      harvestDate: Value(harvestDate),
      species: Value(species.id),
      stage: Value(stage.id),
      yieldKg: Value(yieldKg),
      flushNumber: Value(flushNumber),
      qualityScore: Value(qualityScore),
      notes: Value(notes),
      photoUrls: Value(photoUrls != null ? jsonEncode(photoUrls) : null),
      metadata: Value(metadata != null ? jsonEncode(metadata) : null),
    );
    await _database.harvestsDao.insertHarvest(companion);
    await recalculateProductionMetrics(farmId);
    return id;
  }

  Future<List<models.HarvestRecord>> getHarvestsForFarm(String farmId) async {
    final rows = await _database.harvestsDao.getHarvestsByFarmId(farmId);
    return rows.map(_harvestFromDrift).toList();
  }

  Future<List<models.HarvestRecord>> getHarvestsForPeriod(
    String farmId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final rows = await _database.harvestsDao
        .getHarvestsByFarmAndPeriod(farmId, startDate, endDate);
    return rows.map(_harvestFromDrift).toList();
  }

  // ── PRODUCTION METRICS ─────────────────────────────────────────────────────

  Future<void> recalculateProductionMetrics(String farmId) async {
    final count = await _database.harvestsDao.getHarvestCountByFarm(farmId);
    final yield_ = await _database.harvestsDao.getTotalYieldByFarm(farmId);
    await _database.farmsDao.updateProductionMetrics(farmId, count, yield_);
  }

  Future<FarmStats?> getFarmStats(String farmId) async {
    final farm = await _database.farmsDao.getFarmById(farmId);
    if (farm == null) return null;

    final count = await _database.harvestsDao.getHarvestCountByFarm(farmId);
    final totalYield = await _database.harvestsDao.getTotalYieldByFarm(farmId);
    final avgYield = await _database.harvestsDao.getAverageYieldByFarm(farmId);
    final latest = await _database.readingsDao.getLatestReadingByFarm(farmId);
    final days = DateTime.now().difference(farm.createdAt).inDays;

    return FarmStats(
      farmId: farmId,
      farmName: farm.name,
      harvestCount: count,
      totalYieldKg: totalYield,
      averageYieldKg: avgYield,
      daysActive: days,
      yieldPerDay: days > 0 ? totalYield / days : 0.0,
      lastConnection: farm.lastActive,
      currentTemperature: latest?.temperatureC,
      currentHumidity: latest?.relativeHumidity,
      currentCO2: latest?.co2Ppm,
    );
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────

  models.Farm _farmFromDrift(Farm farm) {
    Map<String, String>? fieldMap;
    if (farm.thingSpeakFieldMap != null) {
      try {
        final decoded = jsonDecode(farm.thingSpeakFieldMap!) as Map;
        fieldMap = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      } catch (_) {}
    }

    return models.Farm(
      id: farm.id,
      name: farm.name,
      thingSpeakChannelId: farm.thingSpeakChannelId,
      thingSpeakReadApiKey: farm.thingSpeakReadApiKey,
      thingSpeakFieldMap: fieldMap,
      location: farm.location,
      notes: farm.notes,
      createdAt: farm.createdAt,
      lastActive: farm.lastActive,
      totalHarvests: farm.totalHarvests,
      totalYieldKg: farm.totalYieldKg,
      primarySpecies: farm.primarySpecies != null
          ? Species.fromId(farm.primarySpecies!)
          : null,
      imageUrl: farm.imageUrl,
      isActive: farm.isActive,
      metadata: farm.metadata != null
          ? jsonDecode(farm.metadata!) as Map<String, dynamic>
          : null,
    );
  }

  models.HarvestRecord _harvestFromDrift(Harvest harvest) {
    List<String>? photos;
    if (harvest.photoUrls != null) {
      try {
        photos = (jsonDecode(harvest.photoUrls!) as List).cast<String>();
      } catch (_) {}
    }

    return models.HarvestRecord(
      id: harvest.id,
      farmId: harvest.farmId,
      harvestDate: harvest.harvestDate,
      species: Species.fromId(harvest.species),
      stage: GrowthStage.fromId(harvest.stage),
      yieldKg: harvest.yieldKg,
      flushNumber: harvest.flushNumber,
      qualityScore: harvest.qualityScore,
      notes: harvest.notes,
      photoUrls: photos,
      metadata: harvest.metadata != null
          ? jsonDecode(harvest.metadata!) as Map<String, dynamic>
          : null,
    );
  }
}

// ── Supporting classes ────────────────────────────────────────────────────────

class FarmStats {
  final String farmId;
  final String farmName;
  final int harvestCount;
  final double totalYieldKg;
  final double averageYieldKg;
  final int daysActive;
  final double yieldPerDay;
  final DateTime? lastConnection;
  final double? currentTemperature;
  final double? currentHumidity;
  final int? currentCO2;

  FarmStats({
    required this.farmId,
    required this.farmName,
    required this.harvestCount,
    required this.totalYieldKg,
    required this.averageYieldKg,
    required this.daysActive,
    required this.yieldPerDay,
    this.lastConnection,
    this.currentTemperature,
    this.currentHumidity,
    this.currentCO2,
  });
}

class FarmRepositoryException implements Exception {
  final String message;
  FarmRepositoryException(this.message);
  @override
  String toString() => 'FarmRepositoryException: $message';
}

class FarmValidationException implements Exception {
  final String message;
  FarmValidationException(this.message);
  @override
  String toString() => 'FarmValidationException: $message';
}
