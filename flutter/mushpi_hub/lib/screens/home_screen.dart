import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../providers/thingspeak_provider.dart';
import '../providers/farms_provider.dart';
import '../providers/current_farm_provider.dart';
import '../widgets/farm_card.dart';
import '../widgets/theme_selector.dart';
import '../data/models/farm.dart';
import '../core/constants/ble_constants.dart';

const _uuid = Uuid();

/// Home screen showing overview of all farms.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farmsAsync = ref.watch(activeFarmsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Farms'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => const _ThingSpeakTestDialog(),
              );
            },
          ),
          const ThemeToggleButton(),
        ],
      ),
      body: farmsAsync.when(
        data: (farms) {
          if (farms.isEmpty) {
            return _EmptyFarmsView(
              onAddFarm: () => _showCreateFarmDialog(context, ref),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(activeFarmsProvider.future),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _StatsHeader(
                      farmCount: farms.length,
                      farms: farms,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final farm = farms[index];
                        return FarmCard(
                          farm: farm,
                          onTap: () {
                            ref
                                .read(selectedMonitoringFarmIdProvider.notifier)
                                .state = farm.id;
                            context.go('/monitoring');
                          },
                        );
                      },
                      childCount: farms.length,
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
              Icon(Icons.error_outline, size: 64,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text('Error loading farms',
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateFarmDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Farm'),
      ),
    );
  }

  Future<void> _showCreateFarmDialog(
      BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => const _CreateFarmDialog(),
    );
  }
}

// ---------------------------------------------------------------------------
// Farm creation dialog — no BLE required.
// A device can be linked later from the Farm Detail screen.
// ---------------------------------------------------------------------------

class _CreateFarmDialog extends ConsumerStatefulWidget {
  const _CreateFarmDialog();

  @override
  ConsumerState<_CreateFarmDialog> createState() => _CreateFarmDialogState();
}

class _CreateFarmDialogState extends ConsumerState<_CreateFarmDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  Species _selectedSpecies = Species.oyster;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _createFarm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    try {
      final operations = ref.read(farmOperationsProvider);

      await operations.createFarm(
        id: _uuid.v4(),
        name: _nameController.text.trim(),
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        primarySpecies: _selectedSpecies,
        // deviceId intentionally omitted — link a device from Farm Detail
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Farm "${_nameController.text.trim()}" created! Link a device from the farm detail screen.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create farm: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Farm'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Farm Name *',
                  hintText: 'e.g., Basement Farm',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a farm name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text('Mushroom Species *',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: Species.values.map((species) {
                  return FilterChip(
                    label: Text('${species.icon} ${species.displayName}'),
                    selected: _selectedSpecies == species,
                    onSelected: (_) =>
                        setState(() => _selectedSpecies = species),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                  hintText: 'e.g., Basement, Shed',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'You can link a MushPi device to this farm later from the farm detail screen.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isCreating ? null : _createFarm,
          child: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create Farm'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyFarmsView extends StatelessWidget {
  const _EmptyFarmsView({required this.onAddFarm});

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
              Icons.eco_outlined,
              size: 120,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text('No Farms Yet',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'Start your mushroom cultivation journey by adding your first farm.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onAddFarm,
              icon: const Icon(Icons.add),
              label: const Text('Add Your First Farm'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats header
// ---------------------------------------------------------------------------

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({required this.farmCount, required this.farms});

  final int farmCount;
  final List<Farm> farms;

  int _countOnlineFarms(List<Farm> farms) {
    final now = DateTime.now();
    return farms.where((farm) {
      return farm.lastActive != null &&
          now.difference(farm.lastActive!).inMinutes < 1;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final online = _countOnlineFarms(farms);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: _StatItem(
                icon: Icons.agriculture,
                label: 'Active Farms',
                value: farmCount.toString(),
                color: colorScheme.primary,
              ),
            ),
            Container(width: 1, height: 40, color: colorScheme.outlineVariant),
            Expanded(
              child: _StatItem(
                icon: Icons.check_circle_outline,
                label: 'Online',
                value: online.toString(),
                color: online > 0 ? Colors.green : colorScheme.tertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
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
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ThingSpeak test dialog (temporary)
// ---------------------------------------------------------------------------

class _ThingSpeakTestDialog extends ConsumerWidget {
  const _ThingSpeakTestDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(thingSpeakProvider);

    return AlertDialog(
      title: const Text('ThingSpeak Test'),
      content: asyncData.when(
        data: (reading) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Time: ${reading.time}'),
            Text('Temp: ${reading.temperature}°C'),
            Text('Hum: ${reading.humidity}%'),
            Text('CO2: ${reading.co2} ppm'),
            Text('Light: ${reading.light}'),
          ],
        ),
        loading: () => const CircularProgressIndicator(),
        error: (e, _) => Text('Error: $e'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}