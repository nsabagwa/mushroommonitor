import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mushpi_hub/providers/device_provider.dart';

import '../providers/farms_provider.dart';
import '../providers/current_farm_provider.dart';
import '../providers/actuator_state_provider.dart';
import '../providers/thingspeak_provider.dart'; // ThingSpeak remote data
import '../data/models/relay_reason_code.dart';
import '../providers/ble_provider.dart'; // still used for actuators & stage
import '../core/constants/ble_constants.dart';
import '../core/utils/ble_serializer.dart';
import '../data/models/farm.dart';

/// Monitoring screen showing real‑time environmental data and system status.
///
/// Displays:
/// - Real‑time environmental metrics from ThingSpeak (remote)
/// - System alerts and notifications
/// - Compliance indicators
/// - Quick action buttons
/// - Environmental trend charts
class MonitoringScreen extends ConsumerStatefulWidget {
  const MonitoringScreen({super.key});

  @override
  ConsumerState<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends ConsumerState<MonitoringScreen> {
  // No auto-refresh needed – ThingSpeak stream updates every 30 seconds

  @override
  Widget build(BuildContext context) {
    final farmsAsync = ref.watch(activeFarmsProvider);
    final selectedFarmId = ref.watch(selectedMonitoringFarmIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring'),
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(activeFarmsProvider.future),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: farmsAsync.when(
        data: (farms) {
          if (farms.isEmpty) {
            return _EmptyMonitoringView(
              onAddFarm: () => context.go('/farms'),
            );
          }

          // If multiple farms and no farm selected, show farm selector
          if (farms.length > 1 && selectedFarmId == null) {
            return _FarmSelectorView(
              farms: farms,
              onSelectFarm: (farmId) {
                ref.read(selectedMonitoringFarmIdProvider.notifier).state =
                    farmId;
              },
            );
          }

          // If single farm and no selection, auto-select it
          if (farms.length == 1 && selectedFarmId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(selectedMonitoringFarmIdProvider.notifier).state =
                  farms.first.id;
            });
          }

          // Find the selected farm
          final selectedFarm = selectedFarmId != null
              ? farms.firstWhere(
                  (f) => f.id == selectedFarmId,
                  orElse: () => farms.first,
                )
              : farms.first;

          // Live connectivity, computed once and sharedby the state
          // card and the reconnect banner below
          final lanOnline = selectedFarm.lastActive != null &&
              DateTime.now()
                      .difference(selectedFarm.lastActive!)
                      .inMinutes <
                  1;
          final hasThingSpeak = selectedFarm.thingSpeakChannelId != null &&
              selectedFarm.thingSpeakReadApiKey != null;
          final tsAsync = hasThingSpeak ? ref.watch(thingSpeakProvider((
            channelId: selectedFarm.thingSpeakChannelId!,
            readApiKey: selectedFarm.thingSpeakReadApiKey!,
          ))): null;
          final tsOnline = tsAsync?.hasValue ?? false;
          final anyOnline = lanOnline || tsOnline;

          return RefreshIndicator(
            onRefresh: () => ref.refresh(activeFarmsProvider.future),
            child: CustomScrollView(
              slivers: [
                // Farm selector dropdown (if multiple farms)
                if (farms.length > 1)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _FarmDropdownSelector(
                        farms: farms,
                        selectedFarmId: selectedFarmId,
                        onChanged: (farmId) {
                          ref
                              .read(selectedMonitoringFarmIdProvider.notifier)
                              .state = farmId;
                        },
                      ),
                    ),
                  ),

                // System status for selected farm
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _FarmStatusCard(
                      farm: selectedFarm,
                      lanOnline: lanOnline,
                      tsOnline: tsOnline,),
                  ),
                ),

                // Reconnect banner if farm is offline
                if (!anyOnline)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Card(
                        color: Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning_amber,
                                      color: Colors.orange.shade700),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Not Connected',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: Colors.orange.shade900,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Your MushPi is offline. Real-time updates paused unless you connect to the LAN or ThingSpeak.',
                                style: TextStyle(color: Colors.orange.shade900),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => context
                                      .push('/farm/${selectedFarm.id}/scan'),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Reconnect Device'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange.shade700,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Environmental overview
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: _EnvironmentalOverviewCard(farm: selectedFarm),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                // Stage Progress card
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: _StageProgressCard(),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                // Actuator state/modes
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: _ActuatorStateCard(farmId: selectedFarm.id),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                // Farm details
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'Farm Details',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 8)),

                // Farm info card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: _FarmInfoCard(
                      farm: selectedFarm,
                      onViewDetails: () =>
                          context.push('/farm/${selectedFarm.id}'),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 80), // Bottom padding
                ),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading monitoring data',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(activeFarmsProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Farm selector view shown when no farm is selected
class _FarmSelectorView extends StatelessWidget {
  const _FarmSelectorView({
    required this.farms,
    required this.onSelectFarm,
  });

  final List<Farm> farms;
  final ValueChanged<String> onSelectFarm;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.monitor_heart_outlined,
              size: 80,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Select a Farm to Monitor',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Choose which farm you want to monitor',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ...farms.map((farm) => Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => onSelectFarm(farm.id),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  farm.name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                if (farm.location != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    farm.location!,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// Farm dropdown selector
class _FarmDropdownSelector extends StatelessWidget {
  const _FarmDropdownSelector({
    required this.farms,
    required this.selectedFarmId,
    required this.onChanged,
  });

  final List<Farm> farms;
  final String? selectedFarmId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            Icon(
              Icons.agriculture,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                value: selectedFarmId,
                isExpanded: true,
                underline: const SizedBox(),
                hint: const Text('Select a farm'),
                items: farms.map((farm) {
                  return DropdownMenuItem<String>(
                    value: farm.id,
                    child: Text(farm.name),
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Farm status card for single farm
class _FarmStatusCard extends StatelessWidget {
  const _FarmStatusCard({
    required this.farm,
    required this.lanOnline,
    required this.tsOnline,
    });

  final Farm farm;
  final bool lanOnline;
  final bool tsOnline;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOnline = lanOnline || tsOnline;
    final String statusLabel = lanOnline && tsOnline
       ? 'Online (LAN + ThingSpeak)' 
       : lanOnline 
       ? 'Online (LAN)'
       : tsOnline
       ? 'Online (ThingSpeak)'
       : 'Offline';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Status',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statusLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isOnline ? Colors.green : Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatusItem(
                    icon: Icons.eco,
                    label: 'Total Harvests',
                    value: farm.totalHarvests.toString(),
                    color: colorScheme.primary,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: colorScheme.outlineVariant,
                ),
                Expanded(
                  child: _StatusItem(
                    icon: Icons.scale,
                    label: 'Total Yield',
                    value: '${farm.totalYieldKg.toStringAsFixed(1)} kg',
                    color: colorScheme.tertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Farm info card with view details button
class _FarmInfoCard extends StatelessWidget {
  const _FarmInfoCard({
    required this.farm,
    required this.onViewDetails,
  });

  final Farm farm;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              farm.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (farm.location != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    farm.location!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ],
            if (farm.notes != null && farm.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                farm.notes!,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onViewDetails,
                icon: const Icon(Icons.settings),
                label: const Text('Farm Connection Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state when no farms exist
class _EmptyMonitoringView extends StatelessWidget {
  const _EmptyMonitoringView({required this.onAddFarm});

  final VoidCallback onAddFarm;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.monitor_outlined,
              size: 120,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No Active Monitoring',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Add your first farm to start monitoring environmental conditions.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onAddFarm,
              icon: const Icon(Icons.add),
              label: const Text('Add Farm'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Environmental overview card – now always uses ThingSpeak remote data
class _EnvironmentalOverviewCard extends ConsumerWidget {
  const _EnvironmentalOverviewCard({required this.farm});

  final Farm farm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wifiDataAsync = ref.watch(farmEnvironmentalDataProvider(farm.id));
    final hasThingSpeak =farm.thingSpeakChannelId != null && farm.thingSpeakReadApiKey != null;
    final thingSpeakAsync = hasThingSpeak
        ? ref.watch(thingSpeakProvider((
            channelId: farm.thingSpeakChannelId!,
            readApiKey: farm.thingSpeakReadApiKey!,
          )))
        : const AsyncValue<ThingSpeakReading>.loading();
    
    // Prefer whichever transport actually has live data right now, 
    // instead of locking to Wifi just because wifiHost happens to be configured
    final AsyncValue<dynamic> effectiveAsync;
    if (wifiDataAsync.hasValue) {
      effectiveAsync = wifiDataAsync;
    } else if (hasThingSpeak && thingSpeakAsync.hasValue) {
      effectiveAsync = thingSpeakAsync;
    } else {
      effectiveAsync = wifiDataAsync;
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(context, effectiveAsync),
            const SizedBox(height: 16),

            _buildFarmData(context, effectiveAsync),

            const SizedBox(height: 16),
            // Chart navigation button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  context.push('/monitoring/charts');
                  developer.log(
                    'Navigating to environmental charts',
                    name: 'mushpi.monitoring_screen',
                  );
                },
                icon: const Icon(Icons.show_chart),
                label: const Text('View Charts & Trends'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AsyncValue<dynamic> effectiveAsync) {

    return Row(
      children: [
        Expanded(
          child: Text(
            'Environmental Data',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
      
        const SizedBox(width: 8),
        // Timestamp
        effectiveAsync.when(
          data: (reading) => _TimestampChip(
            timestamp: reading is ThingSpeakReading ? reading.time : reading.timestamp,),
          loading: () => const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (_, __) => const SizedBox.shrink()
        )
      ],
    );
  }

// This widget handles all 3 situations: ThingSpeak(Remote), Live data (Wifi/BLE) (Online), and Local data (Offline)
  Widget _buildFarmData(
      BuildContext context, AsyncValue<dynamic> effectiveAsync) {
    return effectiveAsync.when(
      data: (reading) {
        final temp = reading is ThingSpeakReading ? reading.temperature : reading.temperatureC;
        final humidity = reading is ThingSpeakReading ? reading.humidity : reading.relativeHumidity;
        final co2 = reading is ThingSpeakReading ? reading.co2 : reading.co2Ppm;
        final light = reading is ThingSpeakReading ? reading.light : reading.lightRaw;
      
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _EnvironmentalMetric(
                  icon: Icons.thermostat,
                  label: 'Temperature',
                  value: '${temp?.toStringAsFixed(1) ?? "--"}°C',
                  color: _getTemperatureColor(temp ?? 20),
                ),
              ),
              Expanded(
                child: _EnvironmentalMetric(
                  icon: Icons.water_drop,
                  label: 'Humidity',
                  value: '${humidity?.toStringAsFixed(0) ?? "--"}%',
                  color: _getHumidityColor(humidity ?? 70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _EnvironmentalMetric(
                  icon: Icons.air,
                  label: 'CO₂',
                  value: '${co2 ?? "--"} ppm',
                  color: _getCO2Color(co2?.toInt() ?? 0),
                ),
              ),
              Expanded(
                child: _EnvironmentalMetric(
                  icon: Icons.light_mode,
                  label: 'Light',
                  value: '${light ?? "--"} lx',
                  color: Colors.amber,
                ),
              ),
            ],
          ),
        ],
      );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Could not load remote, local or online data',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ),
      ),
    );
  }

  Color _getTemperatureColor(double temp) {
    if (temp < 15) return Colors.blue;
    if (temp > 28) return Colors.red;
    return Colors.orange;
  }

  Color _getHumidityColor(double rh) {
    if (rh < 60) return Colors.orange;
    if (rh > 95) return Colors.red;
    return Colors.blue;
  }

  Color _getCO2Color(int co2) {
    if (co2 > 2000) return Colors.red;
    if (co2 > 1000) return Colors.orange;
    return Colors.green;
  }
}

/// Timestamp chip showing when data was last updated
class _TimestampChip extends StatelessWidget {
  const _TimestampChip({required this.timestamp});

  final DateTime timestamp;

  String _getTimeAgo() {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRecent = DateTime.now().difference(timestamp).inMinutes < 5;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isRecent
            ? Colors.green.withValues(alpha: 0.2)
            : Colors.grey.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: 14,
            color: isRecent ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            _getTimeAgo(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isRecent ? Colors.green : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

/// Individual status item
class _StatusItem extends StatelessWidget {
  const _StatusItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Environmental metric display
class _EnvironmentalMetric extends StatelessWidget {
  const _EnvironmentalMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Actuator modes/state card (unchanged)
class _ActuatorStateCard extends ConsumerWidget {
  const _ActuatorStateCard({required this.farmId});

  final String farmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetsAsync = ref.watch(farmControlTargetsProvider(farmId));
    final actuatorStatusAsync = ref.watch(farmActuatorStatusProvider(farmId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => StatefulNavigationShell.of(context).goBranch(2),
                    child: Row(
                      children: [
                        const Icon(Icons.settings_remote),
                        const SizedBox(width: 12),
                        Text(
                          'Actuator Modes', 
                          style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => StatefulNavigationShell.of(context).goBranch(2),
                  tooltip: 'Open Control Screen',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.refresh(farmControlTargetsProvider(farmId)),
                  tooltip: 'Reload',
                )
              ],
            ),
            const SizedBox(height: 12),
            targetsAsync.when(
              data: (targets) {
                if (targets == null) {
                  return const _ActuatorUnavailable();
                }

                final theme = Theme.of(context);
                final actuatorStatus = actuatorStatusAsync.asData?.value;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _ActuatorChip(
                          icon: Icons.lightbulb,
                          label: 'Light',
                          value: targets.lightMode.displayName,
                          color: Colors.amber,
                          subtitle: targets.lightMode == LightMode.cycle
                              ? 'On ${targets.onMinutes}m / Off ${targets.offMinutes}m'
                              : null,
                          statusValue: actuatorStatus?.lightOn,
                          reasonCode: actuatorStatus?.lightReasonCode,
                        ),
                        _ActuatorChip(
                          icon: Icons.air,
                          label: 'Fan',
                          value: 'Auto',
                          color: theme.colorScheme.primary,
                          statusValue: actuatorStatus?.fanOn,
                          reasonCode: actuatorStatus?.fanReasonCode,
                        ),
                        _ActuatorChip(
                          icon: Icons.grain,
                          label: 'Mist',
                          value: 'Auto',
                          color: theme.colorScheme.tertiary,
                          statusValue: actuatorStatus?.mistOn,
                          reasonCode: actuatorStatus?.mistReasonCode,
                        ),
                        _ActuatorChip(
                          icon: Icons.local_fire_department,
                          label: 'Heater',
                          value: 'Auto',
                          color: Colors.redAccent,
                          statusValue: actuatorStatus?.heaterOn,
                          reasonCode: actuatorStatus?.heaterReasonCode,
                        ),
                      ],
                    ),
                    if (actuatorStatus == null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Note: Real-time relay states not available (older firmware or not connected).',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (_, __) => const _ActuatorUnavailable(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActuatorChip extends StatelessWidget {
  const _ActuatorChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
    this.statusValue,
    this.reasonCode,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? subtitle;
  final bool? statusValue;
  final int? reasonCode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String? statusText;
    Color? statusColor;
    String? reasonText;
    if (statusValue != null) {
      statusText = statusValue! ? 'ON' : 'OFF';
      statusColor = statusValue! ? Colors.green : Colors.grey;

      if (reasonCode != null && reasonCode! > 0) {
        final reason = RelayReasonCode.fromCode(reasonCode!);
        reasonText = reason.shortDisplay;
        if (reason.isWarning) {
          statusColor = Color(reason.displayColor);
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (statusText != null)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor!.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor, width: 1.5),
                  ),
                  child: Text(
                    statusText,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              if (reasonText != null)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    reasonText,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 10,
                        ),
                  ),
                )
              else if (statusText == null && subtitle != null)
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActuatorUnavailable extends StatelessWidget {
  const _ActuatorUnavailable();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tap the arrow to see Actuator Status',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stage Progress card (unchanged)
/// Stage Progress card — reflects the device's live stage state.
/// Rebuilds automatically whenever [stageStateProvider] is invalidated,
/// e.g. right after the Stage wizard successfully pushes new settings
/// to the device (see stage_wizard_screen.dart's _submitAllSettings()).
class _StageProgressCard extends ConsumerWidget {
  const _StageProgressCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final stageStateAsync = ref.watch(stageStateProvider);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => StatefulNavigationShell.of(context).goBranch(3),
                    child: Text(
                      'Stage Progress',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  tooltip: 'Open Stage screen',
                  onPressed: () => StatefulNavigationShell.of(context).goBranch(3),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Reload Stage data',
                  onPressed: () => ref.invalidate(stageStateProvider),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildContent(context, cs, stageStateAsync),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ColorScheme cs,
    AsyncValue<StageStateData?> stageStateAsync,
  ) {
    return stageStateAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: cs.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Failed to load stage data',
                style: TextStyle(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
      data: (stageData) {
        if (stageData == null) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No stage data available. Configure stages to begin.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          );
        }

        final daysElapsed = stageData.daysInStage;
        final expectedDays = stageData.expectedDays;
        final progressPercent = expectedDays > 0
            ? (daysElapsed / expectedDays * 100).clamp(0, 100)
            : 0.0;
        final daysRemaining =
            (expectedDays - daysElapsed).clamp(0, expectedDays);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${stageData.species.displayName} - ${stageData.stage.displayName}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stageData.mode.displayName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: progressPercent >= 100
                        ? cs.tertiaryContainer
                        : cs.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    progressPercent >= 100 ? 'COMPLETE' : 'IN PROGRESS',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: progressPercent >= 100
                              ? cs.onTertiaryContainer
                              : cs.onPrimaryContainer,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Day $daysElapsed of $expectedDays',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    Text(
                      '${progressPercent.toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progressPercent / 100,
                    minHeight: 12,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progressPercent >= 100 ? cs.tertiary : cs.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StageMetric(
                    icon: Icons.calendar_today,
                    label: 'Started',
                    value: _formatDate(stageData.stageStartTime),
                    color: cs.primary,
                  ),
                ),
                Expanded(
                  child: _StageMetric(
                    icon: progressPercent >= 100
                        ? Icons.check_circle
                        : Icons.access_time,
                    label: progressPercent >= 100 ? 'Complete' : 'Days Remaining',
                    value: progressPercent >= 100
                        ? 'Ready to advance'
                        : '$daysRemaining days',
                    color: progressPercent >= 100 ? cs.tertiary : cs.secondary,
                  ),
                ),
              ],
            ),
            if (progressPercent < 100 && stageData.mode != ControlMode.manual)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: cs.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          stageData.mode == ControlMode.full
                              ? 'Will auto-advance to next stage when complete'
                              : 'Manual advancement required when complete',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSecondaryContainer,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

class _StageMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StageMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}
