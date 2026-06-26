import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
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

  // drift_flutter automatically uses:
  //   SQLite (via sqlite3_flutter_libs) on Android/iOS
  //   IndexedDB                         on Web
  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'mushpi_hub',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
      native: DriftNativeOptions(
        databaseDirectory: getApplicationDocumentsDirectory,
      ),
    );
  }
}
