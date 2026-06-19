import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class ThingSpeakReading {
  final DateTime time;
  final double? temperature;
  final double? humidity;
  final double? co2;
  final double? light;

  ThingSpeakReading({
    required this.time,
    this.temperature,
    this.humidity,
    this.co2,
    this.light,
  });

  factory ThingSpeakReading.fromJson(Map<String, dynamic> json) {
    final feed = json['feeds']?[0];
    if (feed == null) throw Exception('No data');
    return ThingSpeakReading(
      time: DateTime.parse(feed['created_at']),
      temperature: double.tryParse(feed['field1'] ?? ''),
      humidity: double.tryParse(feed['field2'] ?? ''),
      co2: double.tryParse(feed['field3'] ?? ''),
      light: double.tryParse(feed['field4'] ?? ''),
    );
  }
}

final thingSpeakProvider = StreamProvider.autoDispose<ThingSpeakReading>((ref) {
  const channelId = '3386816';
  const readApiKey = 'GR8NEFEZGVW3SG4X';

  return Stream.periodic(const Duration(seconds: 30), (_) => null)
      .asyncMap((_) async {
    final url = Uri.parse(
      'https://api.thingspeak.com/channels/$channelId/feeds.json'
      '?api_key=$readApiKey&results=1',
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      return ThingSpeakReading.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('HTTP ${response.statusCode}');
    }
  });
});
