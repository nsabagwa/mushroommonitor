import 'package:flutter_dotenv/flutter_dotenv.dart';

/// ThingSpeak configuration for the Flutter app.
///
/// All values are loaded from the runtime `.env` file via flutter_dotenv.
/// No hard-coded API keys, channel IDs, or field mappings are used.
class ThingSpeakConfig {
  final String readApiKey;
  final String channelId;
  final String baseUrl;
  final String fieldTemperature;
  final String fieldHumidity;
  final String fieldCo2;
  final String fieldLight;

  const ThingSpeakConfig({
    required this.readApiKey,
    required this.channelId,
    required this.baseUrl,
    required this.fieldTemperature,
    required this.fieldHumidity,
    required this.fieldCo2,
    required this.fieldLight,
  });

  bool get hasRequiredCredentials => readApiKey.isNotEmpty && channelId.isNotEmpty;

  /// Load configuration from `.env` using flutter_dotenv.
  ///
  /// This intentionally does not provide default API keys or channel IDs;
  /// if required values are missing, the integration will be considered
  /// "effectively disabled" at runtime.
  static ThingSpeakConfig defaultsFromEnv() {
    final env = dotenv.env;

    String getString(String key, [String defaultValue = '']) => env[key]?.trim() ?? defaultValue;

    return ThingSpeakConfig(
      // Separate read key so backend can use write key; caller may set them equal.
      readApiKey: '',
      channelId: '',
      baseUrl: getString(
        'MUSHPI_THINGSPEAK_BASE_URL',
        'https://api.thingspeak.com/channels',
      ),
      fieldTemperature: getString('MUSHPI_THINGSPEAK_FIELD_TEMPERATURE'),
      fieldHumidity: getString('MUSHPI_THINGSPEAK_FIELD_HUMIDITY'),
      fieldCo2: getString('MUSHPI_THINGSPEAK_FIELD_CO2'),
      fieldLight: getString('MUSHPI_THINGSPEAK_FIELD_LIGHT'),
    );
  }

  ThingSpeakConfig withFarmCredentials ({
    required String channelId,
    required String readApiKey,
  }) {
    return ThingSpeakConfig(
      readApiKey: readApiKey,
      channelId: channelId,
      baseUrl: baseUrl,
      fieldTemperature: fieldTemperature,
      fieldHumidity: fieldHumidity,
      fieldCo2: fieldCo2,
      fieldLight: fieldLight,
    );
  }
}


