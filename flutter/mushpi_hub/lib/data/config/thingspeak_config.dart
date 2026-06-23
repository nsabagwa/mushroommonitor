/// ThingSpeak configuration built from a farm's stored credentials.
///
/// Each farm has its own channel ID, read API key, and optional field map.
/// Default field assignments follow ThingSpeak's field1–field4 convention.
class ThingSpeakConfig {
  final String channelId;
  final String readApiKey;
  final String baseUrl;
  final String fieldTemperature;
  final String fieldHumidity;
  final String fieldCo2;
  final String fieldLight;

  const ThingSpeakConfig({
    required this.channelId,
    required this.readApiKey,
    this.baseUrl = 'https://api.thingspeak.com/channels',
    this.fieldTemperature = 'field1',
    this.fieldHumidity = 'field2',
    this.fieldCo2 = 'field3',
    this.fieldLight = 'field4',
  });

  /// Build config from a farm's stored ThingSpeak credentials.
  ///
  /// [fieldMap] is optional — if the farmer didn't customise field numbers
  /// the defaults (field1–field4) are used.
  factory ThingSpeakConfig.fromFarm({
    required String channelId,
    required String readApiKey,
    Map<String, String>? fieldMap,
  }) {
    return ThingSpeakConfig(
      channelId: channelId,
      readApiKey: readApiKey,
      fieldTemperature: fieldMap?['temperature'] ?? 'field1',
      fieldHumidity: fieldMap?['humidity'] ?? 'field2',
      fieldCo2: fieldMap?['co2'] ?? 'field3',
      fieldLight: fieldMap?['light'] ?? 'field4',
    );
  }

  bool get hasRequiredCredentials =>
      channelId.isNotEmpty && readApiKey.isNotEmpty;
}
