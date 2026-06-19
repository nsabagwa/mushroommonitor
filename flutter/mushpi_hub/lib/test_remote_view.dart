import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/thingspeak_provider.dart';

class TestRemoteView extends ConsumerWidget {
  const TestRemoteView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(thingSpeakProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('ThingSpeak Test')),
      body: Center(
        child: asyncData.when(
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
