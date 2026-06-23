import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mushpi_hub/data/config/thingspeak_config.dart';
import 'package:mushpi_hub/data/database/app_database.dart';

class ThingSpeakRepository {
  const ThingSpeakRepository();

  static const _baseUrl = 'https://api.thingspeak.com/channels';

  Future<List<Reading>> fetchReadingsForPeriod({
    required ThingSpeakConfig config,
    required String farmId,
    required DateTime start,
    required DateTime end,
  }) async {
    if (!config.hasRequiredCredentials) return const [];

    try {
      final uri = Uri.parse('$_baseUrl/${config.channelId}/feeds.json')
          .replace(queryParameters: {
        'api_key': config.readApiKey,
        'start': _fmt(start),
        'end': _fmt(end),
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const [];

      return _parseFeeds(body: response.body, farmId: farmId, config: config);
    } catch (e) {
      print('[ThingSpeak] fetchReadingsForPeriod failed: $e');
      return const [];
    }
  }

  Future<Reading?> fetchLatestReading({
    required ThingSpeakConfig config,
    required String farmId,
  }) async {
    if (!config.hasRequiredCredentials) {
      print(
          '[ThingSpeak] missing credentials — channelId="${config.channelId}" apiKey="${config.readApiKey}"');
      return null;
    }

    try {
      final uri = Uri.parse('$_baseUrl/${config.channelId}/feeds.json')
          .replace(queryParameters: {
        'api_key': config.readApiKey,
        'results': '1',
      });

      print('[ThingSpeak] GET $uri');

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      print('[ThingSpeak] status=${response.statusCode} body=${response.body}');

      if (response.statusCode != 200) return null;

      final readings =
          _parseFeeds(body: response.body, farmId: farmId, config: config);

      print('[ThingSpeak] parsed ${readings.length} readings');

      return readings.isNotEmpty ? readings.first : null;
    } catch (e, st) {
      print('[ThingSpeak] fetchLatestReading failed: $e\n$st');
      return null;
    }
  }

  List<Reading> _parseFeeds({
    required String body,
    required String farmId,
    required ThingSpeakConfig config,
  }) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final feeds = decoded['feeds'];
    if (feeds is! List) return const [];

    final results = <Reading>[];

    for (final feed in feeds) {
      if (feed is! Map<String, dynamic>) continue;

      final createdAtRaw = feed['created_at'] as String?;
      if (createdAtRaw == null) continue;

      DateTime timestamp;
      try {
        timestamp = DateTime.parse(createdAtRaw).toLocal();
      } catch (_) {
        continue;
      }

      final temp = _parseDouble(feed[config.fieldTemperature]);
      final rh = _parseDouble(feed[config.fieldHumidity]);
      final co2 = _parseIntFromField(feed[config.fieldCo2]);
      // FIX 1: light is optional — sensor may send 0.0 or be absent entirely.
      // FIX 2: _parseIntFromField handles decimal strings like "0.00000"
      //         by truncating the decimal part before parsing.
      final light = _parseIntFromField(feed[config.fieldLight]);

      print('[ThingSpeak] temp=$temp rh=$rh co2=$co2 light=$light');

      // FIX 3: only temp and rh are required; co2 and light are optional.
      if (temp == null || rh == null) {
        print('[ThingSpeak] skipping — missing required field (temp or rh)');
        continue;
      }

      results.add(Reading(
        id: 0,
        farmId: farmId,
        timestamp: timestamp,
        // FIX 4: co2 and light default to 0 if absent rather than aborting.
        co2Ppm: co2 ?? 0,
        temperatureC: temp,
        relativeHumidity: rh,
        lightRaw: light ?? 0,
      ));
    }

    return results;
  }

  String _fmt(DateTime dt) =>
      DateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'").format(dt.toUtc());

  double? _parseDouble(dynamic v) =>
      v == null ? null : double.tryParse(v.toString());

  // FIX: ThingSpeak sends integers as decimal strings e.g. "1114" or "0.00000".
  // int.tryParse("0.00000") returns null, so we parse as double first then
  // truncate to int. This handles both "1114" and "0.00000" correctly.
  int? _parseIntFromField(dynamic v) {
    if (v == null) return null;
    final d = double.tryParse(v.toString());
    return d?.truncate();
  }
}
