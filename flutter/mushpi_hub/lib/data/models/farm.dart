import 'package:freezed_annotation/freezed_annotation.dart';
import '../../core/constants/ble_constants.dart';

part 'farm.freezed.dart';
part 'farm.g.dart';

/// Farm entity representing a mushroom cultivation farm
@freezed
class Farm with _$Farm {
  const factory Farm({
    required String id, // Unique farm ID (UUID)
    required String name, // User-defined name
    required String thingSpeakChannelId, // ThingSpeak channel ID
    required String thingSpeakReadApiKey, // ThingSpeak read API key
    Map<String, String>?
        thingSpeakFieldMap, // e.g. {"temperature":"field1","humidity":"field2","co2":"field3","light":"field4"}
    String? location,
    String? notes,
    required DateTime createdAt,
    DateTime? lastActive, // Last successful ThingSpeak fetch
    @Default(0) int totalHarvests,
    @Default(0.0) double totalYieldKg,
    Species? primarySpecies,
    String? imageUrl,
    @Default(true) bool isActive,
    Map<String, dynamic>? metadata,
  }) = _Farm;

  factory Farm.fromJson(Map<String, dynamic> json) => _$FarmFromJson(json);
}

/// Farm analytics data
@freezed
class FarmAnalytics with _$FarmAnalytics {
  const factory FarmAnalytics({
    required String farmId,
    required String farmName,
    required double avgTemperature,
    required double avgHumidity,
    required double avgCO2,
    required double tempCompliancePercent,
    required double humidityCompliancePercent,
    required double co2CompliancePercent,
    required int harvestCount,
    required double totalYieldKg,
    required double avgYieldPerHarvest,
    required int daysInProduction,
    required double yieldPerDay,
    GrowthStage? currentStage,
    required int daysInCurrentStage,
    required int stageTransitions,
    required int totalAlerts,
    required int criticalAlerts,
    required double uptimePercent,
    DateTime? lastConnection,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) = _FarmAnalytics;

  factory FarmAnalytics.fromJson(Map<String, dynamic> json) =>
      _$FarmAnalyticsFromJson(json);
}

/// Harvest record for production tracking
@freezed
class HarvestRecord with _$HarvestRecord {
  const factory HarvestRecord({
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
  }) = _HarvestRecord;

  factory HarvestRecord.fromJson(Map<String, dynamic> json) =>
      _$HarvestRecordFromJson(json);
}

/// Cross-farm comparison data
@freezed
class CrossFarmComparison with _$CrossFarmComparison {
  const factory CrossFarmComparison({
    required List<FarmAnalytics> farms,
    required FarmAnalytics averages,
    required FarmAnalytics topPerformer,
    required FarmAnalytics bottomPerformer,
    required Map<String, double> speciesBreakdown,
    required Map<String, int> stageDistribution,
  }) = _CrossFarmComparison;

  factory CrossFarmComparison.fromJson(Map<String, dynamic> json) =>
      _$CrossFarmComparisonFromJson(json);
}
