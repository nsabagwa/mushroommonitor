// lib/data/repositories/farm_repository.dart
//
// Firebase Realtime Database-backed repository. Replaces the old Drift/
// SQLite version so farms and harvests are shared in real time across every
// device a user logs into (web, Android, iOS) instead of being trapped in
// that one device's local database.
//
// Data layout in Firebase:
//   users/{uid}/farms/{farmId}      -> Farm fields (flat map)
//   users/{uid}/harvests/{harvestId} -> Harvest fields (flat map)
//
// Live sensor readings are NOT stored here — they continue to come straight
// from ThingSpeak (see thingspeak_repository.dart / readings_provider.dart),
// which already works the same on every device since it's a cloud API.
// Drift's Readings table remains in place purely as an offline-fallback
// cache and isn't touched by this file.

import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mushpi_hub/core/constants/ble_constants.dart';
import 'package:mushpi_hub/data/models/farm.dart' as models;

class FarmRepository {
  FarmRepository({FirebaseDatabase? database, FirebaseAuth? auth})
      : _database = database ?? FirebaseDatabase.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseDatabase _database;
  final FirebaseAuth _auth;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) {
      throw FarmRepositoryException(
          'No signed-in user — cannot access farm data.');
    }
    return user.uid;
  }

  DatabaseReference get _farmsRef => _database.ref('users/$_uid/farms');
  DatabaseReference get _harvestsRef => _database.ref('users/$_uid/harvests');

  // ── FARM CRUD ──────────────────────────────────────────────────────────────

  Future<List<models.Farm>> getAllFarms() async {
    final snapshot = await _farmsRef.get();
    if (!snapshot.exists || snapshot.value == null) return [];

    final raw = Map<String, dynamic>.from(snapshot.value as Map);
    final farms = raw.values
        .map((v) => _farmFromMap(Map<String, dynamic>.from(v as Map)))
        .toList();
    farms.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return farms;
  }

  Future<List<models.Farm>> getActiveFarms() async {
    final all = await getAllFarms();
    return all.where((f) => f.isActive).toList();
  }

  Future<models.Farm?> getFarmById(String id) async {
    final snapshot = await _farmsRef.child(id).get();
    if (!snapshot.exists || snapshot.value == null) return null;
    return _farmFromMap(Map<String, dynamic>.from(snapshot.value as Map));
  }

  Future<models.Farm?> getFarmByChannelId(String channelId) async {
    final all = await getAllFarms();
    try {
      return all.firstWhere((f) => f.thingSpeakChannelId == channelId);
    } catch (_) {
      return null;
    }
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
    final farm = models.Farm(
      id: id,
      name: name,
      thingSpeakChannelId: thingSpeakChannelId,
      thingSpeakReadApiKey: thingSpeakReadApiKey,
      thingSpeakFieldMap: thingSpeakFieldMap,
      location: location,
      notes: notes,
      createdAt: DateTime.now(),
      totalHarvests: 0,
      totalYieldKg: 0.0,
      primarySpecies: primarySpecies,
      imageUrl: imageUrl,
      isActive: true,
      metadata: metadata,
    );

    await _farmsRef.child(id).set(_farmToMap(farm));
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
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (thingSpeakReadApiKey != null) {
      updates['thingSpeakReadApiKey'] = thingSpeakReadApiKey;
    }
    if (thingSpeakFieldMap != null) {
      updates['thingSpeakFieldMap'] = thingSpeakFieldMap;
    }
    if (location != null) updates['location'] = location;
    if (notes != null) updates['notes'] = notes;
    if (primarySpecies != null) updates['primarySpecies'] = primarySpecies.id;
    if (imageUrl != null) updates['imageUrl'] = imageUrl;
    if (isActive != null) updates['isActive'] = isActive;
    if (metadata != null) updates['metadata'] = metadata;

    if (updates.isEmpty) return;
    await _farmsRef.child(id).update(updates);
  }

  Future<void> deleteFarm(String id) async {
    await _farmsRef.child(id).remove();
    // Clean up any harvests that belonged to this farm.
    final snapshot =
        await _harvestsRef.orderByChild('farmId').equalTo(id).get();
    if (snapshot.exists && snapshot.value != null) {
      final raw = Map<String, dynamic>.from(snapshot.value as Map);
      for (final harvestId in raw.keys) {
        await _harvestsRef.child(harvestId).remove();
      }
    }
  }

  Future<void> archiveFarm(String farmId) async {
    await _farmsRef.child(farmId).update({'isActive': false});
  }

  Future<void> restoreFarm(String farmId) async {
    await _farmsRef.child(farmId).update({'isActive': true});
  }

  // Mark farm as recently fetched (replaces BLE lastActive)
  Future<void> updateLastActive(String farmId) async {
    await _farmsRef
        .child(farmId)
        .update({'lastActive': DateTime.now().toIso8601String()});
  }

  Future<void> clearLastActive(String farmId) async {
    await _farmsRef.child(farmId).update({'lastActive': null});
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
    final harvest = models.HarvestRecord(
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
      metadata: metadata,
    );

    await _harvestsRef.child(id).set(_harvestToMap(harvest));
    await recalculateProductionMetrics(farmId);
    return id;
  }

  Future<List<models.HarvestRecord>> getHarvestsForFarm(String farmId) async {
    final snapshot =
        await _harvestsRef.orderByChild('farmId').equalTo(farmId).get();
    if (!snapshot.exists || snapshot.value == null) return [];

    final raw = Map<String, dynamic>.from(snapshot.value as Map);
    final harvests = raw.values
        .map((v) => _harvestFromMap(Map<String, dynamic>.from(v as Map)))
        .toList();
    harvests.sort((a, b) => b.harvestDate.compareTo(a.harvestDate));
    return harvests;
  }

  Future<List<models.HarvestRecord>> getHarvestsForPeriod(
    String farmId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final all = await getHarvestsForFarm(farmId);
    return all
        .where((h) =>
            h.harvestDate.isAfter(startDate) && h.harvestDate.isBefore(endDate))
        .toList();
  }

  // ── PRODUCTION METRICS ─────────────────────────────────────────────────────

  Future<void> recalculateProductionMetrics(String farmId) async {
    final harvests = await getHarvestsForFarm(farmId);
    final count = harvests.length;
    final totalYield = harvests.fold<double>(0.0, (sum, h) => sum + h.yieldKg);
    await _farmsRef.child(farmId).update({
      'totalHarvests': count,
      'totalYieldKg': totalYield,
    });
  }

  Future<FarmStats?> getFarmStats(String farmId) async {
    final farm = await getFarmById(farmId);
    if (farm == null) return null;

    final harvests = await getHarvestsForFarm(farmId);
    final count = harvests.length;
    final totalYield = harvests.fold<double>(0.0, (sum, h) => sum + h.yieldKg);
    final avgYield = count > 0 ? totalYield / count : 0.0;
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
      // Live readings still come from ThingSpeak via readings_provider /
      // current_farm_provider — not duplicated here.
      currentTemperature: null,
      currentHumidity: null,
      currentCO2: null,
    );
  }

  // ── SERIALIZATION HELPERS ──────────────────────────────────────────────────

  Map<String, dynamic> _farmToMap(models.Farm farm) {
    return {
      'id': farm.id,
      'name': farm.name,
      'thingSpeakChannelId': farm.thingSpeakChannelId,
      'thingSpeakReadApiKey': farm.thingSpeakReadApiKey,
      'thingSpeakFieldMap': farm.thingSpeakFieldMap,
      'location': farm.location,
      'notes': farm.notes,
      'createdAt': farm.createdAt.toIso8601String(),
      'lastActive': farm.lastActive?.toIso8601String(),
      'totalHarvests': farm.totalHarvests,
      'totalYieldKg': farm.totalYieldKg,
      'primarySpecies': farm.primarySpecies?.id,
      'imageUrl': farm.imageUrl,
      'isActive': farm.isActive,
      'metadata': farm.metadata,
    };
  }

  models.Farm _farmFromMap(Map<String, dynamic> map) {
    Map<String, String>? fieldMap;
    final rawFieldMap = map['thingSpeakFieldMap'];
    if (rawFieldMap != null) {
      fieldMap = Map<String, dynamic>.from(rawFieldMap as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    Map<String, dynamic>? metadata;
    final rawMetadata = map['metadata'];
    if (rawMetadata != null) {
      metadata = Map<String, dynamic>.from(rawMetadata as Map);
    }

    return models.Farm(
      id: map['id'] as String,
      name: map['name'] as String,
      thingSpeakChannelId: map['thingSpeakChannelId'] as String,
      thingSpeakReadApiKey: map['thingSpeakReadApiKey'] as String,
      thingSpeakFieldMap: fieldMap,
      location: map['location'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      lastActive: map['lastActive'] != null
          ? DateTime.parse(map['lastActive'] as String)
          : null,
      totalHarvests: (map['totalHarvests'] as num?)?.toInt() ?? 0,
      totalYieldKg: (map['totalYieldKg'] as num?)?.toDouble() ?? 0.0,
      primarySpecies: map['primarySpecies'] != null
          ? Species.fromId(map['primarySpecies'] as int)
          : null,
      imageUrl: map['imageUrl'] as String?,
      isActive: map['isActive'] as bool? ?? true,
      metadata: metadata,
    );
  }

  Map<String, dynamic> _harvestToMap(models.HarvestRecord harvest) {
    return {
      'id': harvest.id,
      'farmId': harvest.farmId,
      'harvestDate': harvest.harvestDate.toIso8601String(),
      'species': harvest.species.id,
      'stage': harvest.stage.id,
      'yieldKg': harvest.yieldKg,
      'flushNumber': harvest.flushNumber,
      'qualityScore': harvest.qualityScore,
      'notes': harvest.notes,
      'photoUrls': harvest.photoUrls,
      'metadata': harvest.metadata,
    };
  }

  models.HarvestRecord _harvestFromMap(Map<String, dynamic> map) {
    List<String>? photos;
    final rawPhotos = map['photoUrls'];
    if (rawPhotos != null) {
      photos = List<dynamic>.from(rawPhotos as List).cast<String>();
    }

    Map<String, dynamic>? metadata;
    final rawMetadata = map['metadata'];
    if (rawMetadata != null) {
      metadata = Map<String, dynamic>.from(rawMetadata as Map);
    }

    return models.HarvestRecord(
      id: map['id'] as String,
      farmId: map['farmId'] as String,
      harvestDate: DateTime.parse(map['harvestDate'] as String),
      species: Species.fromId(map['species'] as int),
      stage: GrowthStage.fromId(map['stage'] as int),
      yieldKg: (map['yieldKg'] as num).toDouble(),
      flushNumber: (map['flushNumber'] as num?)?.toInt(),
      qualityScore: (map['qualityScore'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      photoUrls: photos,
      metadata: metadata,
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
