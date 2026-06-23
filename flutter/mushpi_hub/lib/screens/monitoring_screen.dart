import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/farms_provider.dart';
import '../providers/current_farm_provider.dart';
import '../data/models/farm.dart';

class MonitoringScreen extends ConsumerStatefulWidget {
  const MonitoringScreen({super.key});

  @override
  ConsumerState<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends ConsumerState<MonitoringScreen> {
  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    super.dispose();
  }

  void _startAutoRefresh() {
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        ref.invalidate(selectedMonitoringFarmLatestReadingProvider);
        _startAutoRefresh();
      }
    });
  }

  void _stopAutoRefresh() {}

  @override
  Widget build(BuildContext context) {
    final farmsAsync = ref.watch(activeFarmsProvider);
    final selectedFarmId = ref.watch(selectedMonitoringFarmIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring'),
        actions: [
          farmsAsync.when(
            data: (farms) {
              if (selectedFarmId == null || farms.isEmpty) {
                return const SizedBox.shrink();
              }
              final selectedFarm =
                  farms.where((f) => f.id == selectedFarmId).firstOrNull;
              if (selectedFarm == null) return const SizedBox.shrink();

              final isLive = selectedFarm.lastActive != null &&
                  DateTime.now()
                          .difference(selectedFarm.lastActive!)
                          .inMinutes <
                      1;

              return Padding(
                padding: const EdgeInsets.only(right: 4.0),
                child: Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Row(
                          children: [
                            Icon(
                              isLive ? Icons.check_circle : Icons.cloud_off,
                              color: isLive ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(isLive ? 'Live Data' : 'Stale Data'),
                          ],
                        ),
                        content: Text(
                          isLive
                              ? '${selectedFarm.name} is actively sending data to ThingSpeak.'
                              : '${selectedFarm.name} has not reported recently.\n\n'
                                  'Check that your MushPi device is powered on and '
                                  'connected to the internet.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isLive ? Colors.green : Colors.grey,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLive ? Icons.cloud_done : Icons.cloud_off,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isLive ? 'Live' : 'Stale',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(selectedMonitoringFarmLatestReadingProvider);
              ref.refresh(activeFarmsProvider.future);
            },
          ),
        ],
      ),
      body: farmsAsync.when(
        data: (farms) {
          if (farms.isEmpty) {
            return _EmptyMonitoringView(
              onAddFarm: () => context.push('/farms/add'),
            );
          }

          if (farms.length > 1 && selectedFarmId == null) {
            return _FarmSelectorView(
              farms: farms,
              onSelectFarm: (farmId) {
                ref.read(selectedMonitoringFarmIdProvider.notifier).state =
                    farmId;
              },
            );
          }

          if (farms.length == 1 && selectedFarmId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(selectedMonitoringFarmIdProvider.notifier).state =
                  farms.first.id;
            });
          }

          final selectedFarm = selectedFarmId != null
              ? farms.firstWhere(
                  (f) => f.id == selectedFarmId,
                  orElse: () => farms.first,
                )
              : farms.first;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(selectedMonitoringFarmLatestReadingProvider);
              await ref.refresh(activeFarmsProvider.future);
            },
            child: CustomScrollView(
              slivers: [
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
                          ref.invalidate(
                              selectedMonitoringFarmLatestReadingProvider);
                        },
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _FarmStatusCard(farm: selectedFarm),
                  ),
                ),
                if (selectedFarm.lastActive == null ||
                    DateTime.now()
                            .difference(selectedFarm.lastActive!)
                            .inMinutes >=
                        30)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Card(
                        color: Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Icon(Icons.cloud_off,
                                  color: Colors.orange.shade700),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Data may be stale',
                                      style: TextStyle(
                                        color: Colors.orange.shade900,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Last update was more than 30 minutes ago. '
                                      'Check your ThingSpeak channel is receiving data.',
                                      style: TextStyle(
                                          color: Colors.orange.shade900,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _EnvironmentalOverviewCard(farm: selectedFarm),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _ThingSpeakInfoCard(farm: selectedFarm),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(
                      'Farm Details',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _FarmInfoCard(
                      farm: selectedFarm,
                      onViewDetails: () =>
                          context.push('/farm/${selectedFarm.id}'),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 64, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text('Error loading monitoring data',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(error.toString(),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center),
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

// ── Farm selector (multi-farm) ────────────────────────────────────────────────

class _FarmSelectorView extends StatelessWidget {
  const _FarmSelectorView({required this.farms, required this.onSelectFarm});
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
            Icon(Icons.monitor_heart_outlined,
                size: 80,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.5)),
            const SizedBox(height: 24),
            Text('Select a Farm to Monitor',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text('Choose which farm you want to monitor',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center),
            const SizedBox(height: 32),
            ...farms.map((farm) => Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => onSelectFarm(farm.id),
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(farm.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                if (farm.location != null) ...[
                                  const SizedBox(height: 4),
                                  Text(farm.location!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
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

// ── Farm dropdown (multi-farm toolbar) ───────────────────────────────────────

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
            Icon(Icons.agriculture,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                value: selectedFarmId,
                isExpanded: true,
                underline: const SizedBox(),
                hint: const Text('Select a farm'),
                items: farms
                    .map((farm) => DropdownMenuItem<String>(
                          value: farm.id,
                          child: Text(farm.name),
                        ))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Farm status card (redesigned stats) ──────────────────────────────────────

class _FarmStatusCard extends StatelessWidget {
  const _FarmStatusCard({required this.farm});
  final Farm farm;

  bool get _isLive {
    if (farm.lastActive == null) return false;
    return DateTime.now().difference(farm.lastActive!).inMinutes < 1;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLive = _isLive;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Text('Farm Status',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isLive
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isLive ? Colors.green : Colors.grey,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pulsing dot
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isLive ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isLive ? 'Live' : 'Offline',
                        style: TextStyle(
                          color: isLive ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Stats row — redesigned
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.eco_rounded,
                    label: 'Total Harvests',
                    value: farm.totalHarvests.toString(),
                    gradient: LinearGradient(
                      colors: [
                        cs.primary.withValues(alpha: 0.15),
                        cs.primary.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    iconColor: cs.primary,
                    valueColor: cs.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    icon: Icons.scale_rounded,
                    label: 'Total Yield',
                    value: '${farm.totalYieldKg.toStringAsFixed(1)} kg',
                    gradient: LinearGradient(
                      colors: [
                        cs.tertiary.withValues(alpha: 0.15),
                        cs.tertiary.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    iconColor: cs.tertiary,
                    valueColor: cs.tertiary,
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

/// Attractive gradient stat tile
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
    required this.iconColor,
    required this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final LinearGradient gradient;
  final Color iconColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: iconColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: valueColor,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// ── ThingSpeak channel info ───────────────────────────────────────────────────

class _ThingSpeakInfoCard extends StatelessWidget {
  const _ThingSpeakInfoCard({required this.farm});
  final Farm farm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud, color: cs.primary),
                const SizedBox(width: 8),
                Text('ThingSpeak Channel',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        )),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'Channel ID', value: farm.thingSpeakChannelId),
            const SizedBox(height: 6),
            _InfoRow(
              label: 'Field map',
              value: farm.thingSpeakFieldMap != null
                  ? farm.thingSpeakFieldMap!.entries
                      .map((e) => '${e.key}: ${e.value}')
                      .join('  •  ')
                  : 'Default (field1–field4)',
            ),
            if (farm.lastActive != null) ...[
              const SizedBox(height: 6),
              _InfoRow(label: 'Last fetch', value: _timeAgo(farm.lastActive!)),
            ],
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ── Environmental overview (live ThingSpeak data) ─────────────────────────────

class _EnvironmentalOverviewCard extends ConsumerWidget {
  const _EnvironmentalOverviewCard({required this.farm});
  final Farm farm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingAsync = ref.watch(selectedMonitoringFarmLatestReadingProvider);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: title + badges on separate lines if needed ────────
            // FIX: wrap the header row to prevent overflow
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Environmental Data',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // ThingSpeak badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue, width: 1.2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud, size: 14, color: Colors.blue),
                          const SizedBox(width: 5),
                          Text(
                            'ThingSpeak',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Timestamp chip (if data available)
                    readingAsync.when(
                      data: (r) => r != null
                          ? _TimestampChip(timestamp: r.timestamp)
                          : const SizedBox.shrink(),
                      loading: () => const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Sensor readings ───────────────────────────────────────────
            readingAsync.when(
              data: (reading) {
                if (reading == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          Icon(Icons.sensors_off,
                              size: 48,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text(
                            'No sensor data available.\nCheck your ThingSpeak channel.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    // Row 1: Temperature + Humidity
                    Row(
                      children: [
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.thermostat_rounded,
                            label: 'Temperature',
                            value:
                                '${reading.temperatureC.toStringAsFixed(1)}°C',
                            color: _tempColor(reading.temperatureC),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.water_drop_rounded,
                            label: 'Humidity',
                            value:
                                '${reading.relativeHumidity.toStringAsFixed(0)}%',
                            color: _rhColor(reading.relativeHumidity),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Row 2: CO₂ + Light
                    Row(
                      children: [
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.air_rounded,
                            label: 'CO₂',
                            value: '${reading.co2Ppm} ppm',
                            color: _co2Color(reading.co2Ppm),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.light_mode_rounded,
                            label: 'Light',
                            value: reading.lightRaw.toString(),
                            color: Colors.amber.shade700,
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
              error: (_, __) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Error loading sensor data',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  context.push('/monitoring/charts');
                  developer.log('Navigating to charts',
                      name: 'MonitoringScreen');
                },
                icon: const Icon(Icons.show_chart),
                label: const Text('View Charts & Trends'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _tempColor(double t) {
    if (t < 15) return Colors.blue;
    if (t > 28) return Colors.red;
    return Colors.orange;
  }

  Color _rhColor(double rh) {
    if (rh < 60) return Colors.orange;
    if (rh > 95) return Colors.red;
    return Colors.blue;
  }

  Color _co2Color(int co2) {
    if (co2 > 2000) return Colors.red;
    if (co2 > 1000) return Colors.orange;
    return Colors.green;
  }
}

/// Attractive card-style metric tile (replaces the old inline row widget)
class _MetricTile extends StatelessWidget {
  const _MetricTile({
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Farm info card ────────────────────────────────────────────────────────────

class _FarmInfoCard extends StatelessWidget {
  const _FarmInfoCard({required this.farm, required this.onViewDetails});
  final Farm farm;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(farm.name, style: Theme.of(context).textTheme.titleLarge),
            if (farm.location != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(farm.location!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),
            ],
            if (farm.notes != null && farm.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(farm.notes!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onViewDetails,
                icon: const Icon(Icons.visibility),
                label: const Text('View Full Details'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

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
            Icon(Icons.monitor_outlined,
                size: 120,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.5)),
            const SizedBox(height: 24),
            Text('No Active Monitoring',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small reusable widgets ────────────────────────────────────────────────────

class _TimestampChip extends StatelessWidget {
  const _TimestampChip({required this.timestamp});
  final DateTime timestamp;

  String _timeAgo() {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final isRecent = DateTime.now().difference(timestamp).inMinutes < 5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isRecent
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule,
              size: 13, color: isRecent ? Colors.green : Colors.grey),
          const SizedBox(width: 4),
          Text(
            _timeAgo(),
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
