import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/tables.dart';

part 'farms_dao.g.dart';

/// Data Access Object for Farms table
@DriftAccessor(tables: [Farms])
class FarmsDao extends DatabaseAccessor<AppDatabase> with _$FarmsDaoMixin {
  FarmsDao(super.db);

  Future<List<Farm>> getAllFarms() {
    return select(farms).get();
  }

  Future<List<Farm>> getActiveFarms() {
    return (select(farms)..where((f) => f.isActive.equals(true))).get();
  }

  Future<Farm?> getFarmById(String id) {
    return (select(farms)..where((f) => f.id.equals(id))).getSingleOrNull();
  }

  /// Find farm by ThingSpeak channel ID
  Future<Farm?> getFarmByChannelId(String channelId) {
    return (select(farms)
          ..where((f) => f.thingSpeakChannelId.equals(channelId)))
        .getSingleOrNull();
  }

  Future<int> insertFarm(FarmsCompanion farm) {
    return into(farms).insert(farm);
  }

  Future<bool> updateFarm(FarmsCompanion farm) {
    return update(farms).replace(farm);
  }

  Future<int> updateLastActive(String farmId, DateTime timestamp) {
    return (update(farms)..where((f) => f.id.equals(farmId)))
        .write(FarmsCompanion(lastActive: Value(timestamp)));
  }

  Future<int> clearLastActive(String farmId) {
    return (update(farms)..where((f) => f.id.equals(farmId)))
        .write(const FarmsCompanion(lastActive: Value(null)));
  }

  Future<int> updateProductionMetrics(
    String farmId,
    int totalHarvests,
    double totalYieldKg,
  ) {
    return (update(farms)..where((f) => f.id.equals(farmId))).write(
      FarmsCompanion(
        totalHarvests: Value(totalHarvests),
        totalYieldKg: Value(totalYieldKg),
      ),
    );
  }

  Future<int> setFarmActive(String farmId, bool isActive) {
    return (update(farms)..where((f) => f.id.equals(farmId)))
        .write(FarmsCompanion(isActive: Value(isActive)));
  }

  Future<int> deleteFarm(String farmId) {
    return (delete(farms)..where((f) => f.id.equals(farmId))).go();
  }
}
