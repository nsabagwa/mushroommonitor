import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/thingspeak_provider.dart';
import 'data/models/farm.dart';

class TestRemoteView extends ConsumerWidget {
  const TestRemoteView({super.key, required this.farm});
  final Farm farm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasThingSpeak = farm.thingSpeakChannelId != null && farm.thingSpeakReadApiKey != null;
    final thingSpeakAsync = hasThingSpeak ? ref.watch(thingSpeakProvider((
      channelId: farm.thingSpeakChannelId!,
      readApiKey: farm.thingSpeakReadApiKey!,
    ))) : const AsyncValue<ThingSpeakReading>.loading();

    return Scaffold(
      appBar: AppBar(title: const Text('ThingSpeak Test')),
      body: Center(
        child: thingSpeakAsync.when(
          data: (reading) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Time: ${reading.time.toLocal()}'),
              Text('Temp: ${reading.temperature ?? "--"}°C'),
              Text('Humidity: ${reading.humidity ?? "--"}%'),
              Text('CO2: ${reading.co2 ?? "--"} ppm'),
              Text('Light: ${reading.light ?? "--"} lx'),
            ],
          ),
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
        ),
      ),
    );
  }
}
