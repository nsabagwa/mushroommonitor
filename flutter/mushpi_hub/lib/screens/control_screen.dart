import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:developer' as developer;

import '../core/constants/ble_constants.dart';
import '../core/utils/ble_serializer.dart';
import '../providers/current_farm_provider.dart';
import '../providers/farms_provider.dart';
import '../data/repositories/device_repository.dart';
import '../providers/device_provider.dart';

/// Control screen for managing environmental control parameters.
///
/// Allows users to adjust:
/// - Temperature range (min/max)
/// - Humidity minimum
/// - CO₂ maximum
/// - Light mode and timing
/// - Manual relay overrides
///
/// Uses batch send: changes are applied when "Apply Changes" button is pressed.
class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({super.key});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  // Current stage info
  Species? _currentSpecies;
  GrowthStage? _currentStage;

  // Form state
  double _tempMin = 20.0;
  double _tempMax = 26.0;
  double _rhMin = 60.0;
  int _co2Max = 1000;
  LightMode _lightMode = LightMode.off;
  int _onMinutes = 960; // 16 hours
  int _offMinutes = 480; // 8 hours
  int? _expectedDays; // Track expected days from stage thresholds

  // Override bits
  bool _lightOverride = false;
  bool _fanOverride = false;
  bool _mistOverride = false;
  bool _heaterOverride = false;
  bool _disableAuto = false;

  // Manual-mode state (Wifi farms only)
  double _fanPwm = 0;
  double _lightPwm = 0;
  bool _wifiManualModeEnabled = false; // no readback from firmware - UI-tracked only

  // UI state
  bool _isLoading = false;
  bool _hasChanges = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    // Load current settings when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrentSettings();
    });
  }

  /// Load current control settings from BLE device
  Future<void> _loadCurrentSettings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final farmId = ref.read(selectedMonitoringFarmIdProvider);
      if (farmId == null) {
        throw DeviceRepositoryException('No farm selected');
      }
      final farm = await ref.read(farmByIdProvider(farmId).future);
      if (farm?.wifiHost != null) {
        /// Wifi farms don't support automatic mode settings over HTTP yet=
        /// so theres is nothing to preload here. the manaul panel reads actuator state
        /// live via farmActuatorStatusProvider instead
        return;
      }

      final repository =
          await ref.read(farmDeviceRepositoryProvider(farmId).future);

      // Load current stage first
      final stageState = await repository.readStageState();
      setState(() {
        _currentSpecies = stageState.species;
        _currentStage = stageState.stage;
      });

      developer.log(
        '✅ Loaded current stage: ${stageState.species.displayName} - ${stageState.stage.displayName}',
        name: 'mushpi.control_screen',
      );

      // Load stage thresholds for current stage
      final thresholds = await repository.readStageThresholds(
        stageState.species,
        stageState.stage,
      );

      if (thresholds != null) {
        // Use stage thresholds as initial values
        setState(() {
          if (thresholds.tempMin != null) _tempMin = thresholds.tempMin!;
          if (thresholds.tempMax != null) _tempMax = thresholds.tempMax!;
          if (thresholds.rhMin != null) _rhMin = thresholds.rhMin!;
          if (thresholds.co2Max != null) _co2Max = thresholds.co2Max!;
          if (thresholds.lightMode != null) {
            _lightMode = thresholds.lightMode!;
          }
          if (thresholds.lightOnMinutes != null) {
            _onMinutes = thresholds.lightOnMinutes!;
          }
          if (thresholds.lightOffMinutes != null) {
            _offMinutes = thresholds.lightOffMinutes!;
          }
          if (thresholds.expectedDays != null) {
            _expectedDays = thresholds.expectedDays!;
          }
        });

        developer.log(
          '✅ Loaded stage thresholds for current stage (expectedDays: $_expectedDays)',
          name: 'mushpi.control_screen',
        );
      }

      // Load current control targets (actual applied values)
      final controlTargets = await repository.readControlTargets();

      setState(() {
        _tempMin = controlTargets.tempMin;
        _tempMax = controlTargets.tempMax;
        _rhMin = controlTargets.rhMin;
        _co2Max = controlTargets.co2Max;
        _lightMode = controlTargets.lightMode;
        _onMinutes = controlTargets.onMinutes;
        _offMinutes = controlTargets.offMinutes;
        _hasChanges = false;
      });

      developer.log(
        '✅ Loaded control settings: ${controlTargets.toString()}',
        name: 'mushpi.control_screen',
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load settings: $e';
      });
      developer.log(
        '❌ Failed to load control settings: $e',
        name: 'mushpi.control_screen',
        error: e,
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Apply changes to BLE device
  Future<void> _applyChanges() async {
    // Validate
    if (_tempMin >= _tempMax) {
      setState(() {
        _errorMessage = 'Temperature min must be less than max';
      });
      return;
    }

    if (_lightMode == LightMode.cycle &&
        (_onMinutes <= 0 || _offMinutes <= 0)) {
      setState(() {
        _errorMessage = 'Light cycle times must be greater than 0';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final farmId = ref.read(selectedMonitoringFarmIdProvider);
      if (farmId == null) {
        throw DeviceRepositoryException('No farm selected');
      }
      final repository =
          await ref.read(farmDeviceRepositoryProvider(farmId).future);

      // Write control targets
      final controlTargets = ControlTargetsData(
        tempMin: _tempMin,
        tempMax: _tempMax,
        rhMin: _rhMin,
        co2Max: _co2Max,
        lightMode: _lightMode,
        onMinutes: _onMinutes,
        offMinutes: _offMinutes,
      );

      await repository.writeControlTargets(controlTargets);

      developer.log(
        '✅ Applied control settings: ${controlTargets.toString()}',
        name: 'mushpi.control_screen',
      );

      // Write stage thresholds for current stage (if known)
      if (_currentSpecies != null && _currentStage != null) {
        final thresholds = StageThresholdsData(
          species: _currentSpecies!,
          stage: _currentStage!,
          tempMin: _tempMin,
          tempMax: _tempMax,
          rhMin: _rhMin,
          co2Max: _co2Max,
          lightMode: _lightMode,
          lightOnMinutes: _onMinutes,
          lightOffMinutes: _offMinutes,
          expectedDays: _expectedDays,
        );

        final thresholdSuccess =
            await repository.writeStageThresholds(thresholds);

        if (thresholdSuccess) {
          developer.log(
            '✅ Applied stage thresholds for ${_currentSpecies!.displayName} - ${_currentStage!.displayName}',
            name: 'mushpi.control_screen',
          );
        } else {
          developer.log(
            '⚠️ Failed to write stage thresholds (validation failed)',
            name: 'mushpi.control_screen',
            level: 900,
          );
        }
      }

      // Write override bits if any are set
      if (_lightOverride ||
          _fanOverride ||
          _mistOverride ||
          _heaterOverride ||
          _disableAuto) {
        int overrideBits = 0;
        if (_lightOverride) overrideBits |= 0x01;
        if (_fanOverride) overrideBits |= 0x02;
        if (_mistOverride) overrideBits |= 0x04;
        if (_heaterOverride) overrideBits |= 0x08;
        if (_disableAuto) overrideBits |= 0x80;

        await repository.writeOverrideBits(overrideBits);

        developer.log(
          '✅ Applied override bits: 0x${overrideBits.toRadixString(16)}',
          name: 'mushpi.control_screen',
        );
      }

      setState(() {
        _hasChanges = false;
        _successMessage = 'Settings applied successfully';
      });

      // Clear success message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _successMessage = null;
          });
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to apply settings: $e';
      });
      developer.log(
        '❌ Failed to apply control settings: $e',
        name: 'mushpi.control_screen',
        error: e,
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Mark that changes have been made
  void _markChanged() {
    if (!_hasChanges) {
      setState(() {
        _hasChanges = true;
      });
    }
  }

  Future<void> _setFanPwm(int value) async {
    final farmId = ref.read(selectedMonitoringFarmIdProvider);
    if (farmId == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final repository =
          await ref.read(farmDeviceRepositoryProvider(farmId).future);
      await repository.setFanPwm(value);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to set fan PWM: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setLightPwm(int value) async {
    final farmId = ref.read(selectedMonitoringFarmIdProvider);
    if (farmId == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final repository =
          await ref.read(farmDeviceRepositoryProvider(farmId).future);
      await repository.setLightPwm(value);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to set mist PWM: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleTec() async {
    final farmId = ref.read(selectedMonitoringFarmIdProvider);
    if (farmId == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final repository =
          await ref.read(farmDeviceRepositoryProvider(farmId).future);
      await repository.toggleTec();
    } catch (e) {
      setState(() => _errorMessage = 'Failed to toggle TEC: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleHumidifier() async {
    final farmId = ref.read(selectedMonitoringFarmIdProvider);
    if (farmId == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final repository =
          await ref.read(farmDeviceRepositoryProvider(farmId).future);
      await repository.toggleHumidifier();
    } catch (e) {
      setState(() => _errorMessage = 'Failed to toggle humidifier: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleWifiManualMode(bool enable) async {
    final farmId = ref.read(selectedMonitoringFarmIdProvider);
    if (farmId == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final repository =
          await ref.read(farmDeviceRepositoryProvider(farmId).future);
      await repository.toggleManualMode();
      setState(() => _wifiManualModeEnabled = enable);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to toggle manual mode on Wifi: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedFarmId = ref.watch(selectedMonitoringFarmIdProvider);
    final isConnected = selectedFarmId == null
        ? false
        : ref.watch(farmConnectionStateProvider(selectedFarmId)).maybeWhen(
              data: (state) => state == DeviceConnectionState.connected,
              orElse: () => false,
            );
    final isWifiFarm = selectedFarmId == null
        ? false
        : ref.watch(farmByIdProvider(selectedFarmId)).maybeWhen(
              data: (farm) => farm?.wifiHost != null,
              orElse: () => false,
            );

            ref.listen<String?>(selectedMonitoringFarmIdProvider, (previous, next) {
              if (next != null && next !=previous) {
                _loadCurrentSettings();
              }
            });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Environmental Control'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadCurrentSettings,
            tooltip: 'Reload Settings',
          ),
        ],
      ),
      body: selectedFarmId == null
          ? _buildFarmSelector(context)
          : isWifiFarm
              ? _buildManualControlPanel(context, isConnected, selectedFarmId)
              : _buildControlPanel(context, isConnected),
    );
  }

  /// Build farm selector if no farm selected
  Widget _buildFarmSelector(BuildContext context) {
    final farmsAsync = ref.watch(activeFarmsProvider);

    return farmsAsync.when(
      data: (farms) {
        if (farms.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.agriculture_outlined,
                  size: 120,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.5),
                ),
                const SizedBox(height: 24),
                Text(
                  'No Farms Available',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Add a farm to access control settings',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          );
        }

        if (farms.length == 1) {
          // Auto-select single farm
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(selectedMonitoringFarmIdProvider.notifier).state =
                farms.first.id;
          });
          return const Center(child: CircularProgressIndicator());
        }

        // Show farm selector
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: farms.length,
          itemBuilder: (context, index) {
            final farm = farms[index];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.agriculture),
                title: Text(farm.name),
                subtitle: farm.location != null ? Text(farm.location!) : null,
                trailing: const Icon(Icons.arrow_forward),
                onTap: () {
                  ref.read(selectedMonitoringFarmIdProvider.notifier).state =
                      farm.id;
                },
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('Error loading farms: $error'),
      ),
    );
  }

  /// Build control panel
  Widget _buildControlPanel(BuildContext context, bool isConnected) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding:
              const EdgeInsets.all(16).copyWith(bottom: 88), // Space for FAB
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Connection status
              if (!isConnected)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bluetooth_disabled,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Not connected to device. Connect to a farm to adjust settings.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Current Stage Banner
              if (_currentSpecies != null && _currentStage != null) ...[
                if (!isConnected) const SizedBox(height: 8),
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.eco,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Editing Current Stage',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondaryContainer,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_currentSpecies!.displayName} - ${_currentStage!.displayName}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondaryContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Changes will update thresholds for this stage',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondaryContainer,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Success/Error messages
              if (_successMessage != null) ...[
                const SizedBox(height: 8),
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _successMessage!,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Temperature Control
              _buildSection(
                context,
                title: 'Temperature Range',
                icon: Icons.thermostat,
                child: Column(
                  children: [
                    _buildSlider(
                      label: 'Minimum',
                      value: _tempMin,
                      min: -20,
                      max: 60,
                      divisions: 160,
                      unit: '°C',
                      onChanged: (value) {
                        setState(() {
                          _tempMin = value;
                          _markChanged();
                        });
                      },
                    ),
                    _buildSlider(
                      label: 'Maximum',
                      value: _tempMax,
                      min: -20,
                      max: 60,
                      divisions: 160,
                      unit: '°C',
                      onChanged: (value) {
                        setState(() {
                          _tempMax = value;
                          _markChanged();
                        });
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Humidity Control
              _buildSection(
                context,
                title: 'Humidity',
                icon: Icons.water_drop,
                child: _buildSlider(
                  label: 'Minimum',
                  value: _rhMin,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  unit: '%',
                  onChanged: (value) {
                    setState(() {
                      _rhMin = value;
                      _markChanged();
                    });
                  },
                ),
              ),

              const SizedBox(height: 16),

              // CO₂ Control
              _buildSection(
                context,
                title: 'CO₂ Level',
                icon: Icons.air,
                child: _buildSlider(
                  label: 'Maximum',
                  value: _co2Max.toDouble(),
                  min: 0,
                  max: 10000,
                  divisions: 100,
                  unit: 'ppm',
                  onChanged: (value) {
                    setState(() {
                      _co2Max = value.round();
                      _markChanged();
                    });
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Light Control
              _buildSection(
                context,
                title: 'Light Control',
                icon: Icons.lightbulb,
                child: Column(
                  children: [
                    SegmentedButton<LightMode>(
                      segments: const [
                        ButtonSegment(
                          value: LightMode.off,
                          label: Text('Off'),
                          icon: Icon(Icons.lightbulb_outline),
                        ),
                        ButtonSegment(
                          value: LightMode.on,
                          label: Text('On'),
                          icon: Icon(Icons.lightbulb),
                        ),
                        ButtonSegment(
                          value: LightMode.cycle,
                          label: Text('Cycle'),
                          icon: Icon(Icons.schedule),
                        ),
                      ],
                      selected: {_lightMode},
                      onSelectionChanged: (Set<LightMode> selection) {
                        setState(() {
                          _lightMode = selection.first;
                          _markChanged();
                        });
                      },
                    ),
                    if (_lightMode == LightMode.cycle) ...[
                      const SizedBox(height: 16),
                      _buildTimeControl(
                        label: 'On Duration',
                        minutes: _onMinutes,
                        onChanged: (value) {
                          setState(() {
                            _onMinutes = value;
                            _markChanged();
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildTimeControl(
                        label: 'Off Duration',
                        minutes: _offMinutes,
                        onChanged: (value) {
                          setState(() {
                            _offMinutes = value;
                            _markChanged();
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Manual Overrides
              _buildSection(
                context,
                title: 'Manual Overrides',
                icon: Icons.settings_remote,
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Light Override'),
                      subtitle: const Text('Force light on/off'),
                      value: _lightOverride,
                      onChanged: (value) {
                        setState(() {
                          _lightOverride = value;
                          _markChanged();
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Fan Override'),
                      subtitle: const Text('Force fan on/off'),
                      value: _fanOverride,
                      onChanged: (value) {
                        setState(() {
                          _fanOverride = value;
                          _markChanged();
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Mist Override'),
                      subtitle: const Text('Force mist on/off'),
                      value: _mistOverride,
                      onChanged: (value) {
                        setState(() {
                          _mistOverride = value;
                          _markChanged();
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Heater Override'),
                      subtitle: const Text('Force heater on/off'),
                      value: _heaterOverride,
                      onChanged: (value) {
                        setState(() {
                          _heaterOverride = value;
                          _markChanged();
                        });
                      },
                    ),
                    const Divider(),
                    SwitchListTile(
                      title: const Text('Disable Automation'),
                      subtitle: const Text('Turn off all automatic control'),
                      value: _disableAuto,
                      onChanged: (value) {
                        setState(() {
                          _disableAuto = value;
                          _markChanged();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Apply Changes FAB
        if (_hasChanges && isConnected)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _applyChanges,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isLoading ? 'Applying...' : 'Apply Changes'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
      ],
    );
  }

  /// Manual-only control panel for Wifi farms. The ESP32's HTTP API only
  /// exposes manual overrides right now- no stage/threshold/target support
  /// over Wifi yet - so this deliberately doesn't show the automatic-mode
  /// sliders _buildControlPanel does. Remove this fork once fimeware adds
  /// the missing endpoints (see readStageState/readControlTargets/etc. in
  /// wifi_device_repository.dart).
  Widget _buildManualControlPanel(
      BuildContext context, bool isConnected, String farmId) {
    final actuatorAsync = ref.watch(farmActuatorStatusProvider(farmId));
    final canAct = isConnected && !_isLoading;
    final canControlActuators = canAct && _wifiManualModeEnabled;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isConnected)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.wifi_off,
                        color: Theme.of(context).colorScheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Not Connected to device. Connect to a farm to adjust settings',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "This farm connects over Wifi, which currently only supports manual control."
                " Automatic stage-based control is available over Bluetooth for now.",
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondaryContainer),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              title: const Text('Manual Mode'),
              subtitle: const Text('Enable manual control over Wifi'),
              value: _wifiManualModeEnabled,
              onChanged: canAct ? _toggleWifiManualMode : null,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildSection(
            context,
            title: 'Fan',
            icon: Icons.air,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Level shown reflects your last request not the device current setting. "
                  "Wifi mode can't read it back yet.",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                _buildSlider(
                  label: "Speed",
                  value: _fanPwm,
                  min: 0,
                  max: 255,
                  divisions: 255,
                  unit: '',
                  onChanged: (value) => setState(() => _fanPwm = value),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed:
                        canControlActuators ? () => _setFanPwm(_fanPwm.round()) : null,
                    child: const Text('Set fan speed'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            context,
            title: 'Grow Light',
            icon: Icons.lightbulb,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSlider(
                  label: "Brightness",
                  value: _lightPwm,
                  min: 0,
                  max: 255,
                  divisions: 255,
                  unit: '',
                  onChanged: (value) => setState(() => _lightPwm = value),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed:
                        canControlActuators ? () => _setLightPwm(_lightPwm.round()) : null,
                    child: const Text('Set light brightness level'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            context,
            title: 'TEC (Cooler)',
            icon: Icons.ac_unit_sharp,
            child: actuatorAsync.when(
              data: (status) => SwitchListTile(
                title: const Text('TEC'),
                subtitle: Text(status.heaterOn ? 'ON' : 'OFF'),
                value: status.heaterOn,
                onChanged: canControlActuators ? (_) => _toggleTec() : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text("Status unavailable"),
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            context,
            title: 'Humidifier',
            icon: Icons.water_drop,
            child: actuatorAsync.when(
              data: (status) => SwitchListTile(
                title: const Text('Humidifier'),
                subtitle: Text(status.mistOn ? 'ON' : 'OFF'),
                value: status.mistOn,
                onChanged: canControlActuators ? (_) => _toggleHumidifier() : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text("Status unavailable"),
            ),
          ),
        ],
      ),
    );
  }

  /// Build section card
  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  /// Build slider with label and value
  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(
              '${value.toStringAsFixed(1)} $unit',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: '${value.toStringAsFixed(1)} $unit',
          onChanged: onChanged,
        ),
      ],
    );
  }

  /// Build time control (hours and minutes)
  Widget _buildTimeControl({
    required String label,
    required int minutes,
    required ValueChanged<int> onChanged,
  }) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;

    return Row(
      children: [
        Expanded(child: Text(label)),
        SizedBox(
          width: 100,
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Hours',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            controller: TextEditingController(text: hours.toString()),
            onChanged: (value) {
              final h = int.tryParse(value) ?? 0;
              onChanged(h * 60 + mins);
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Minutes',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            controller: TextEditingController(text: mins.toString()),
            onChanged: (value) {
              final m = int.tryParse(value) ?? 0;
              onChanged(hours * 60 + m);
            },
          ),
        ),
      ],
    );
  }
}
