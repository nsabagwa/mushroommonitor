import '../../core/constants/ble_constants.dart';

/// Reads the (min, max) ideal range for a sensor from the farm's
/// colorRanges metadata (written by the Stage wizard). Returns null
/// when no range has been saved.
({double min, double max})? colorRangeFor(
  Map<String, dynamic>? metadata,
  String sensorKey, // 'temp' | 'humidity' | 'co2' | 'light'
) {
  final currentStageId = metadata?['currentGrowthStage'] as int?;
  if (currentStageId == null) return null;
  final stage = GrowthStage.fromId(currentStageId);
  final colorRanges = metadata?['colorRanges'] as Map<String, dynamic>?;
  final stageRanges = colorRanges?[stage.name] as Map<String, dynamic>?;
  final sensorRange = stageRanges?[sensorKey] as Map<String, dynamic>?;
  final min = (sensorRange?['min'] as num?)?.toDouble();
  final max = (sensorRange?['max'] as num?)?.toDouble();
  if (min == null || max == null) return null;
  return (min: min, max: max);
}

/// true = in range (green), false = out of range (red),
/// null = no saved range (use your default).
bool? isValueInRange(
  Map<String, dynamic>? metadata,
  String sensorKey,
  double value,
) {
  final range = colorRangeFor(metadata, sensorKey);
  if (range == null) return null;
  return value >= range.min && value <= range.max;
}