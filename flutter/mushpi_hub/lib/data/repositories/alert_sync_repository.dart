// lib/data/repositories/alert_sync_repository.dart
//
// Mirrors the data the backend alert Cloud Function needs into Firestore:
// the farm's ThingSpeak credentials, its current growth stage, and the
// per-stage thresholds. Local Drift storage stays the source of truth for
// the app's own UI; this is purely a one-way sync so the out-of-range email
// checker (functions/index.js) has something to read even when the app
// isn't running.
//
// Call `syncFarm` after a farm is created/edited, and `syncThresholds`
// whenever the user saves stage thresholds (e.g. in StageWizardScreen).

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mushpi_hub/core/constants/ble_constants.dart';
import 'package:mushpi_hub/data/models/farm.dart';
import 'dart:developer' as developer;

class AlertSyncRepository {
  AlertSyncRepository({FirebaseDatabase? database, FirebaseAuth? auth})
      : _database = database ?? FirebaseDatabase.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseDatabase _database;
  final FirebaseAuth _auth;

  User? get _user => _auth.currentUser;

  /// Push core farm + ThingSpeak info. Safe to call any time the farm
  /// record changes (create, edit, field-map update).
  Future<void> syncFarm(Farm farm) async {
    final user = _user;
    if (user == null) {
      developer.log('No signed-in user — skipping farm alert sync',
          name: 'alert_sync');
      return;
    }

    try {
      await _database.ref('farms/${farm.id}').update({
        'ownerUid': user.uid,
        'ownerEmail': user.email,
        'name': farm.name,
        'thingSpeakChannelId': farm.thingSpeakChannelId,
        'thingSpeakReadApiKey': farm.thingSpeakReadApiKey,
        if (farm.thingSpeakFieldMap != null)
          'thingSpeakFieldMap': farm.thingSpeakFieldMap,
        'alertsEnabled': true,
      });
    } catch (e, st) {
      developer.log('Failed to sync farm for alerts',
          error: e, stackTrace: st, name: 'alert_sync');
    }
  }

  /// Push the per-stage thresholds plus which stage is currently active.
  /// [stageConfigs] keys are GrowthStage, values must contain
  /// tempMin/tempMax/rhMin/co2Max (matches the maps built in
  /// StageWizardScreen).
  Future<void> syncThresholds({
    required String farmId,
    required Map<GrowthStage, Map<String, dynamic>> stageConfigs,
    required GrowthStage currentStage,
  }) async {
    final user = _user;
    if (user == null) {
      developer.log('No signed-in user — skipping threshold alert sync',
          name: 'alert_sync');
      return;
    }

    final thresholds = <String, dynamic>{};
    for (final entry in stageConfigs.entries) {
      thresholds[entry.key.name] = {
        'tempMin': entry.value['tempMin'],
        'tempMax': entry.value['tempMax'],
        'rhMin': entry.value['rhMin'],
        'co2Max': entry.value['co2Max'],
      };
    }

    try {
      await _database.ref('farms/$farmId').update({
        'ownerUid': user.uid,
        'ownerEmail': user.email,
        'currentStage': currentStage.name,
        'thresholds': thresholds,
      });
    } catch (e, st) {
      developer.log('Failed to sync thresholds for alerts',
          error: e, stackTrace: st, name: 'alert_sync');
    }
  }

  /// Lets the user mute/unmute email alerts for a farm (wire this up to a
  /// toggle in SettingsScreen or FarmDetailScreen).
  Future<void> setAlertsEnabled(String farmId, bool enabled) async {
    try {
      await _database.ref('farms/$farmId').update({'alertsEnabled': enabled});
    } catch (e, st) {
      developer.log('Failed to update alertsEnabled',
          error: e, stackTrace: st, name: 'alert_sync');
    }
  }
}
