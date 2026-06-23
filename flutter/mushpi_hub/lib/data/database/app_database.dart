import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'tables/tables.dart';
import 'daos/farms_dao.dart';
import 'daos/harvests_dao.dart';
import 'daos/readings_dao.dart';
import 'daos/settings_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Farms, Harvests, Readings, Settings],
  daos: [FarmsDao, HarvestsDao, ReadingsDao, SettingsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(farms, farms.thingSpeakChannelId);
            await m.addColumn(farms, farms.thingSpeakReadApiKey);
            await m.addColumn(farms, farms.thingSpeakFieldMap);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'mushpi.db'));
      return NativeDatabase(file);
    });
  }
}
