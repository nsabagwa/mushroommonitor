import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mushpi_hub/providers/thingspeak_provider.dart';
import 'dart:developer' as developer;

import '../providers/current_farm_provider.dart';
import '../data/models/farm.dart';
import '../providers/farms_provider.dart';

/// Farm detail screen showing single farm monitoring.
///
/// Displays:
/// - Real-time environmental data
/// - Control settings
/// - Stage information
/// - Historical charts
/// - Harvest records
class FarmDetailScreen extends ConsumerStatefulWidget {
  const FarmDetailScreen({required this.farmId, super.key});

  final String farmId;

  @override
  ConsumerState<FarmDetailScreen> createState() => _FarmDetailScreenState();
}

class _FarmDetailScreenState extends ConsumerState<FarmDetailScreen> {
  @override
  void initState() {
    super.initState();
    
    developer.log(
      '📱 [FarmDetailScreen] Initializing with farm ID: ${widget.farmId}',
      name: 'mushpi.screens.farm_detail',
    );
    
    // Select this farm as current when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      developer.log(
        '🎯 [FarmDetailScreen] Selecting farm: ${widget.farmId}',
        name: 'mushpi.screens.farm_detail',
      );
      ref.read(currentFarmIdProvider.notifier).selectFarm(widget.farmId);
    });
  }

  @override
  Widget build(BuildContext context) {
    developer.log(
      '🎨 [FarmDetailScreen] Building screen for farm: ${widget.farmId}',
      name: 'mushpi.screens.farm_detail',
    );
    
    // Fetch farm directly by ID instead of using currentFarmProvider
    // This avoids timing issues with the currentFarmIdProvider
    final farmAsync = ref.watch(farmByIdProvider(widget.farmId));

    return Scaffold(
      appBar: AppBar(
        title: farmAsync.when(
          data: (farm) {
            final title = farm?.name ?? 'Farm Not Found';
            developer.log(
              '📋 [FarmDetailScreen] AppBar title: $title',
              name: 'mushpi.screens.farm_detail',
            );
            return Text(title);
          },
          loading: () {
            developer.log(
              '⏳ [FarmDetailScreen] AppBar: Loading...',
              name: 'mushpi.screens.farm_detail',
            );
            return const Text('Loading...');
          },
          error: (error, _) {
            developer.log(
              '❌ [FarmDetailScreen] AppBar error: $error',
              name: 'mushpi.screens.farm_detail',
              error: error,
              level: 1000,
            );
            return const Text('Error');
          },
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            developer.log(
              '⬅️ [FarmDetailScreen] Navigating back to home',
              name: 'mushpi.screens.farm_detail',
            );
            context.pop();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              developer.log(
                '⚙️ [FarmDetailScreen] Opening farm options menu',
                name: 'mushpi.screens.farm_detail',
              );
              // TODO: Show farm options menu
            },
          ),
        ],
      ),
      body: farmAsync.when(
        data: (farm) {
          if (farm == null) {
            developer.log(
              '❌ [FarmDetailScreen] Farm not found in database: ${widget.farmId}',
              name: 'mushpi.screens.farm_detail',
              level: 900,
            );
            return _buildNotFoundState(context);
          }

          developer.log(
            '✅ [FarmDetailScreen] Rendering farm: ${farm.name}',
            name: 'mushpi.screens.farm_detail',
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Farm info card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          farm.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (farm.primarySpecies != null) ...[
                          const SizedBox(height: 8),
                          Text('Species: ${farm.primarySpecies!.displayName}'),
                        ],
                        if (farm.location != null) ...[
                          const SizedBox(height: 4),
                          Text('Location: ${farm.location}'),
                        ],
                        const SizedBox(height: 8),
                        Text('Device ID: ${farm.deviceId}'),
                        const SizedBox(height: 4),
                        Text('Total Harvests: ${farm.totalHarvests}'),
                        Text('Total Yield: ${farm.totalYieldKg.toStringAsFixed(1)} kg'),
                        const SizedBox(height: 8),
                        Text(
                          'Created: ${_formatDate(farm.createdAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (farm.lastActive != null)
                          Text(
                            'Last Active: ${_formatDate(farm.lastActive!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                _ThingSpeakCard(farm: farm, farmId: widget.farmId),

                // TODO: Add environmental data cards
                // TODO: Add control panels
                // TODO: Add charts
                // TODO: Add harvest list

                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text(
                      'Farm monitoring interface coming soon...',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () {
          developer.log(
            '⏳ [FarmDetailScreen] Loading farm data...',
            name: 'mushpi.screens.farm_detail',
          );
          return const Center(child: CircularProgressIndicator());
        },
        error: (error, stack) {
          developer.log(
            '❌ [FarmDetailScreen] Error loading farm',
            name: 'mushpi.screens.farm_detail',
            error: error,
            stackTrace: stack,
            level: 1000,
          );
          return _buildErrorState(context, error);
        },
      ),
    );
  }

  /// Build not found state
  Widget _buildNotFoundState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 120,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Farm Not Found',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'The farm you\'re looking for doesn\'t exist or has been deleted.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Farm ID: ${widget.farmId}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.go('/farms'),
              icon: const Icon(Icons.home),
              label: const Text('Go to Home'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                developer.log(
                  '🔄 [FarmDetailScreen] Retrying farm fetch',
                  name: 'mushpi.screens.farm_detail',
                );
                ref.invalidate(farmByIdProvider(widget.farmId));
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build error state
  Widget _buildErrorState(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 120,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              'Error Loading Farm',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                developer.log(
                  '🔄 [FarmDetailScreen] Retrying after error',
                  name: 'mushpi.screens.farm_detail',
                );
                ref.invalidate(farmByIdProvider(widget.farmId));
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.go('/farms'),
              icon: const Icon(Icons.home),
              label: const Text('Go to Home'),
            ),
          ],
        ),
      ),
    );
  }

  /// Format date for display
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

class _ThingSpeakCard extends ConsumerStatefulWidget {
  const _ThingSpeakCard({required this.farm, required this.farmId});

  final Farm farm;
  // final farm_model.Farm farm;
  final String farmId;

  @override
  ConsumerState<_ThingSpeakCard> createState() => _ThingSpeakCardState();
}

class _ThingSpeakCardState extends ConsumerState<_ThingSpeakCard> {
  late final TextEditingController _channelController;
  late final TextEditingController _apiKeyController;
  bool _isTesting = false;
  bool _isSaving = false;
  String? _testResult;
  bool _testPassed = false;
  List<String>? _discoveredSensors;

  @override
  void initState() {
    super.initState();
    _channelController = TextEditingController(
      text: widget.farm.thingSpeakChannelId ?? '',
    );
    _apiKeyController = TextEditingController(
      text: widget.farm.thingSpeakReadApiKey ?? '',
    );
  }

  @override
  void dispose() {
    _channelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final channelId = _channelController.text.trim();
    final readApiKey = _apiKeyController.text.trim();

    if (channelId.isEmpty || readApiKey.isEmpty) {
      setState(() {
        _testResult = 'Please enter both Channel ID and API Key';
        _testPassed = false;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
      _discoveredSensors = null;
    });

    try {
      final reading = await fetchThingSpeakOnce(
        channelId: channelId,
        readApiKey: readApiKey,
      );
      setState(() {
        _testPassed = true;
        _discoveredSensors = reading.availableSensors;
        _testResult =
            'Connected! Found ${_discoveredSensors!.length} sensor(s).';
      });
    } catch (e) {
      setState(() {
        _testPassed = false;
        _testResult = 'Failed: $e';
      });
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _saveCredentials() async {
    setState(() => _isSaving = true);
    try {
      final ops = ref.read(farmOperationsProvider);
      await ops.updateThingSpeak(
        farmId: widget.farmId,
        channelId: _channelController.text.trim().isEmpty
            ? null
            : _channelController.text.trim(),
        readApiKey: _apiKeyController.text.trim().isEmpty
            ? null
            : _apiKeyController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ThingSpeak credentials saved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _unlinkThingSpeak() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink ThingSpeak?'),
        content: const Text(
            'This will remove remote monitoring for this farm.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      final ops = ref.read(farmOperationsProvider);
      await ops.updateThingSpeak(
        farmId: widget.farmId,
        channelId: null,
        readApiKey: null,
      );
      _channelController.clear();
      _apiKeyController.clear();
      setState(() {
        _testResult = null;
        _testPassed = false;
        _discoveredSensors = null;
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLinked = widget.farm.thingSpeakChannelId != null &&
        widget.farm.thingSpeakReadApiKey != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.cloud, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ThingSpeak Remote Monitoring',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isLinked)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Linked',
                      style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Optional. Link a ThingSpeak channel to monitor this farm remotely.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),

            // Channel ID field
            TextField(
              controller: _channelController,
              decoration: const InputDecoration(
                labelText: 'Channel ID',
                hintText: 'e.g. 3386816',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {
                _testResult = null;
                _testPassed = false;
              }),
            ),
            const SizedBox(height: 12),

            // API Key field
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'Read API Key',
                hintText: 'e.g. GR8NEFEZGVW3SG4X',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {
                _testResult = null;
                _testPassed = false;
              }),
            ),
            const SizedBox(height: 16),

            // Test result / discovered sensors
            if (_testResult != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testPassed
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _testPassed ? Colors.green : Colors.red,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _testPassed ? Icons.check_circle : Icons.error,
                          color: _testPassed ? Colors.green : Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _testResult!,
                          style: TextStyle(
                            color: _testPassed ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (_discoveredSensors != null &&
                        _discoveredSensors!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Detected sensors: ${_discoveredSensors!.join(', ')}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering),
                    label:
                        Text(_isTesting ? 'Testing...' : 'Test Connection'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        (_isSaving || (!_testPassed && !isLinked))
                            ? null
                            : _saveCredentials,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isSaving ? 'Saving...' : 'Save'),
                  ),
                ),
              ],
            ),

            // Unlink button (only shown if currently linked)
            if (isLinked) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _isSaving ? null : _unlinkThingSpeak,
                  icon: const Icon(Icons.link_off, color: Colors.red),
                  label: const Text(
                    'Unlink ThingSpeak',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}