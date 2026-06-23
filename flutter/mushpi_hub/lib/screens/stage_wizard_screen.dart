import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:developer' as developer;

import '../core/constants/ble_constants.dart';
import '../providers/current_farm_provider.dart';
import '../providers/farms_provider.dart';
import '../app.dart' show routeObserver;

/// Stage Configuration Wizard
///
/// Multi-step form that configures the complete grow cycle:
/// - Step 0: Species, Date Planted, Automation Mode, Current Stage
/// - Step 1: Incubation stage settings
/// - Step 2: Pinning stage settings
/// - Step 3: Fruiting stage settings
/// - Step 4: Review & Submit all settings
///
/// BLE connectivity removed. Re-wire bleOps calls when BLE is restored.
class StageWizardScreen extends ConsumerStatefulWidget {
  const StageWizardScreen({super.key});

  @override
  ConsumerState<StageWizardScreen> createState() => _StageWizardScreenState();
}

class _StageWizardScreenState extends ConsumerState<StageWizardScreen>
    with RouteAware, WidgetsBindingObserver {
  int _currentStep = 0;
  static const int _totalSteps = 5;

  // Step 0: Basic Information
  Species _species = Species.oyster;
  DateTime _datePlanted = DateTime.now();
  ControlMode _mode = ControlMode.semi;
  GrowthStage _currentStage = GrowthStage.incubation;

  final Map<GrowthStage, Map<String, dynamic>> _stageConfigs = {
    GrowthStage.incubation: {},
    GrowthStage.pinning: {},
    GrowthStage.fruiting: {},
  };

  final Map<GrowthStage, Map<String, TextEditingController>> _controllers = {
    GrowthStage.incubation: {},
    GrowthStage.pinning: {},
    GrowthStage.fruiting: {},
  };

  bool _isLoading = false;
  // ignore: unused_field
  bool _hasChanges = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    for (var stage in GrowthStage.values) {
      _controllers[stage] = {
        'expectedDays': TextEditingController(),
        'tempMin': TextEditingController(),
        'tempMax': TextEditingController(),
        'rhMin': TextEditingController(),
        'co2Max': TextEditingController(),
        'lightOnTime': TextEditingController(text: '08:00'),
        'lightOffTime': TextEditingController(text: '20:00'),
      };
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExistingData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    developer.log('Refreshing data on navigation return',
        name: 'mushpi.stage_wizard');
    _loadExistingData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadExistingData();
    }
  }

  void _loadDefaultValues() {
    final defaults = _getSpeciesDefaults(_species);

    setState(() {
      for (var stage in [
        GrowthStage.incubation,
        GrowthStage.pinning,
        GrowthStage.fruiting
      ]) {
        final stageDefaults = defaults[stage]!;
        _stageConfigs[stage] = Map.from(stageDefaults);

        _controllers[stage]!['expectedDays']!.text =
            stageDefaults['expectedDays'].toString();
        _controllers[stage]!['tempMin']!.text =
            stageDefaults['tempMin'].toString();
        _controllers[stage]!['tempMax']!.text =
            stageDefaults['tempMax'].toString();
        _controllers[stage]!['rhMin']!.text = stageDefaults['rhMin'].toString();
        _controllers[stage]!['co2Max']!.text =
            stageDefaults['co2Max'].toString();
      }
    });
  }

  void _loadDefaultValuesForStage(GrowthStage stage) {
    final defaults = _getSpeciesDefaults(_species);
    final stageDefaults = defaults[stage]!;

    setState(() {
      _stageConfigs[stage] = Map.from(stageDefaults);

      _controllers[stage]!['expectedDays']!.text =
          stageDefaults['expectedDays'].toString();
      _controllers[stage]!['tempMin']!.text =
          stageDefaults['tempMin'].toString();
      _controllers[stage]!['tempMax']!.text =
          stageDefaults['tempMax'].toString();
      _controllers[stage]!['rhMin']!.text = stageDefaults['rhMin'].toString();
      _controllers[stage]!['co2Max']!.text = stageDefaults['co2Max'].toString();
    });
  }

  Future<void> _loadExistingData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // BLE removed — load defaults only.
      developer.log(
        'BLE not available — loading species defaults',
        name: 'mushpi.stage_wizard',
      );
      _loadDefaultValues();
    } catch (e) {
      developer.log('Failed to load data: $e', name: 'mushpi.stage_wizard');
      setState(() {
        _errorMessage = 'Could not load data. Using defaults.';
      });
      _loadDefaultValues();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _submitAllSettings() async {
    final validationError = _validateAllStages();
    if (validationError != null) {
      setState(() {
        _errorMessage = validationError;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // BLE removed — settings cannot be written to device yet.
      // TODO: re-wire bleOps.writeStageState / writeStageThresholds when BLE restored.
      developer.log(
        'BLE not available — settings saved locally only',
        name: 'mushpi.stage_wizard',
      );

      final selectedFarmId = ref.read(selectedMonitoringFarmIdProvider);
      if (selectedFarmId != null) {
        await ref.read(alertSyncRepositoryProvider).syncThresholds(
              farmId: selectedFarmId,
              stageConfigs: _stageConfigs,
              currentStage: _currentStage,
            );
      }

      setState(() {
        _hasChanges = false;
        _successMessage = 'Settings saved (device not connected, alerts synced)';
        _currentStep = 0;
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _successMessage = null;
          });
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save settings: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String? _validateAllStages() {
    if (_datePlanted.isAfter(DateTime.now())) {
      return 'Date planted cannot be in the future';
    }

    for (var stage in [
      GrowthStage.incubation,
      GrowthStage.pinning,
      GrowthStage.fruiting
    ]) {
      final error = _validateStageConfig(stage);
      if (error != null) {
        return '${stage.displayName}: $error';
      }
    }

    return null;
  }

  String? _validateStageConfig(GrowthStage stage) {
    final config = _stageConfigs[stage]!;
    final controllers = _controllers[stage]!;

    final expectedDays = int.tryParse(controllers['expectedDays']!.text);
    if (expectedDays == null || expectedDays < 1 || expectedDays > 365) {
      return 'Expected days must be between 1 and 365';
    }

    final tempMin = double.tryParse(controllers['tempMin']!.text);
    final tempMax = double.tryParse(controllers['tempMax']!.text);
    if (tempMin == null || tempMax == null) {
      return 'Temperature values must be valid numbers';
    }
    if (tempMin < 5 || tempMin > 35 || tempMax < 5 || tempMax > 35) {
      return 'Temperature must be between 5°C and 35°C';
    }
    if (tempMin >= tempMax) {
      return 'Temperature minimum must be less than maximum';
    }

    final rhMin = double.tryParse(controllers['rhMin']!.text);
    if (rhMin != null && (rhMin < 40 || rhMin > 100)) {
      return 'Humidity must be between 40% and 100%';
    }

    final co2Max = int.tryParse(controllers['co2Max']!.text);
    if (co2Max != null && (co2Max < 400 || co2Max > 5000)) {
      return 'CO₂ must be between 400 ppm and 5000 ppm';
    }

    final lightMode = config['lightMode'] as LightMode;
    if (lightMode == LightMode.cycle) {
      final onParts = controllers['lightOnTime']!.text.split(':');
      final offParts = controllers['lightOffTime']!.text.split(':');
      if (onParts.length != 2 || offParts.length != 2) {
        return 'Light times must be in HH:MM format';
      }
      final onHours = int.tryParse(onParts[0]);
      final onMins = int.tryParse(onParts[1]);
      final offHours = int.tryParse(offParts[0]);
      final offMins = int.tryParse(offParts[1]);
      if (onHours == null ||
          onMins == null ||
          offHours == null ||
          offMins == null) {
        return 'Light times must be valid numbers';
      }
      if (onHours < 0 ||
          onHours > 23 ||
          offHours < 0 ||
          offHours > 23 ||
          onMins < 0 ||
          onMins > 59 ||
          offMins < 0 ||
          offMins > 59) {
        return 'Light times must be valid 24-hour times';
      }
    }

    _stageConfigs[stage] = {
      'expectedDays': expectedDays,
      'tempMin': tempMin,
      'tempMax': tempMax,
      'rhMin': rhMin,
      'co2Max': co2Max,
      'lightMode': lightMode,
    };

    return null;
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() {
        _currentStep++;
        _hasChanges = true;
      });
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  void _jumpToStep(int step) {
    setState(() {
      _currentStep = step;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedFarmId = ref.watch(selectedMonitoringFarmIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stage Configuration'),
      ),
      body: selectedFarmId == null
          ? _buildFarmSelector()
          : _buildWizard(false), // isConnected = false until BLE restored
    );
  }

  Widget _buildFarmSelector() {
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
                Text('No Farms Available',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 12),
                Text('Add a farm to configure stages',
                    style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          );
        }

        if (farms.length == 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(selectedMonitoringFarmIdProvider.notifier).state =
                farms.first.id;
          });
          return const Center(child: CircularProgressIndicator());
        }

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
      error: (error, _) => Center(child: Text('Error loading farms: $error')),
    );
  }

  Widget _buildWizard(bool isConnected) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _buildStepIndicator(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_errorMessage != null) ...[
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.error,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_successMessage != null) ...[
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _successMessage!,
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _buildStepContent(),
              ],
            ),
          ),
        ),
        _buildNavigationButtons(isConnected),
      ],
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: List.generate(_totalSteps, (index) {
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _jumpToStep(index),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: isCompleted || isActive
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                if (index < _totalSteps - 1) const SizedBox(width: 8),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep0BasicInfo();
      case 1:
        return _buildStageConfigStep(GrowthStage.incubation);
      case 2:
        return _buildStageConfigStep(GrowthStage.pinning);
      case 3:
        return _buildStageConfigStep(GrowthStage.fruiting);
      case 4:
        return _buildStep4Review();
      default:
        return const SizedBox();
    }
  }

  Widget _buildStep0BasicInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Basic Information',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Configure the basic details for your grow cycle',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        Text('Species', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SegmentedButton<Species>(
          segments: const [
            ButtonSegment(
                value: Species.oyster,
                label: Text('Oyster'),
                icon: Icon(Icons.eco)),
            ButtonSegment(
                value: Species.shiitake,
                label: Text('Shiitake'),
                icon: Icon(Icons.eco)),
            ButtonSegment(
                value: Species.lionsMane,
                label: Text("Lion's Mane"),
                icon: Icon(Icons.eco)),
          ],
          selected: {_species},
          onSelectionChanged: (Set<Species> selection) {
            setState(() {
              _species = selection.first;
              _hasChanges = true;
              _loadDefaultValues();
            });
          },
          showSelectedIcon: true,
        ),
        const SizedBox(height: 24),
        Text('Date Planted', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.event),
            title: Text(_formatDate(_datePlanted)),
            subtitle: const Text('When was this batch started?'),
            trailing: const Icon(Icons.edit),
            onTap: _pickDatePlanted,
          ),
        ),
        const SizedBox(height: 24),
        Text('Current Growth Stage',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Which stage is your grow currently in?',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<GrowthStage>(
          segments: const [
            ButtonSegment(
                value: GrowthStage.incubation, label: Text('Incubation')),
            ButtonSegment(value: GrowthStage.pinning, label: Text('Pinning')),
            ButtonSegment(value: GrowthStage.fruiting, label: Text('Fruiting')),
          ],
          selected: {_currentStage},
          onSelectionChanged: (Set<GrowthStage> selection) {
            setState(() {
              _currentStage = selection.first;
              _hasChanges = true;
            });
          },
        ),
        const SizedBox(height: 24),
        Text('Automation Mode', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        RadioListTile<ControlMode>(
          title: const Text('Full Auto'),
          subtitle:
              const Text('Automatic control + automatic stage advancement'),
          value: ControlMode.full,
          groupValue: _mode,
          onChanged: (value) {
            if (value != null) setState(() => _mode = value);
          },
        ),
        RadioListTile<ControlMode>(
          title: const Text('Semi Auto'),
          subtitle: const Text('Automatic control + manual stage confirmation'),
          value: ControlMode.semi,
          groupValue: _mode,
          onChanged: (value) {
            if (value != null) setState(() => _mode = value);
          },
        ),
        RadioListTile<ControlMode>(
          title: const Text('Manual'),
          subtitle: const Text('Full manual control for experimental grows'),
          value: ControlMode.manual,
          groupValue: _mode,
          onChanged: (value) {
            if (value != null) setState(() => _mode = value);
          },
        ),
      ],
    );
  }

  Widget _buildStageConfigStep(GrowthStage stage) {
    final controllers = _controllers[stage]!;
    final config = _stageConfigs[stage]!;
    final lightMode = config['lightMode'] as LightMode? ?? LightMode.off;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${stage.displayName} Stage',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          _getStageDescription(stage),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.event),
            title: Text(
              _getStageStartDate(stage) != null
                  ? _formatDate(_getStageStartDate(stage)!)
                  : 'Not set (will use current time when stage starts)',
            ),
            subtitle: Text(stage == GrowthStage.incubation
                ? 'When was this batch started?'
                : 'When did this stage begin?'),
            trailing: const Icon(Icons.edit),
            onTap: () => _pickStageStartDate(stage),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: controllers['expectedDays'],
          decoration: const InputDecoration(
            labelText: 'Expected Duration (days)',
            border: OutlineInputBorder(),
            helperText: 'How long does this stage typically last?',
            prefixIcon: Icon(Icons.schedule),
          ),
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() => _hasChanges = true),
        ),
        const SizedBox(height: 24),
        Text('Temperature Range (°C)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controllers['tempMin'],
                decoration: const InputDecoration(
                    labelText: 'Minimum',
                    border: OutlineInputBorder(),
                    helperText: '5-35°C'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() => _hasChanges = true),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: controllers['tempMax'],
                decoration: const InputDecoration(
                    labelText: 'Maximum',
                    border: OutlineInputBorder(),
                    helperText: '5-35°C'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() => _hasChanges = true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        TextField(
          controller: controllers['rhMin'],
          decoration: const InputDecoration(
            labelText: 'Humidity Minimum (%)',
            border: OutlineInputBorder(),
            helperText: '40-100%',
            prefixIcon: Icon(Icons.water_drop),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() => _hasChanges = true),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: controllers['co2Max'],
          decoration: const InputDecoration(
            labelText: 'CO₂ Maximum (ppm)',
            border: OutlineInputBorder(),
            helperText: '400-5000 ppm',
            prefixIcon: Icon(Icons.air),
          ),
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() => _hasChanges = true),
        ),
        const SizedBox(height: 24),
        Text('Light Mode', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SegmentedButton<LightMode>(
          segments: const [
            ButtonSegment(
                value: LightMode.off,
                label: Text('OFF'),
                icon: Icon(Icons.light_mode_outlined)),
            ButtonSegment(
                value: LightMode.on,
                label: Text('ON'),
                icon: Icon(Icons.light_mode)),
            ButtonSegment(
                value: LightMode.cycle,
                label: Text('CYCLE'),
                icon: Icon(Icons.schedule)),
          ],
          selected: {lightMode},
          onSelectionChanged: (Set<LightMode> selection) {
            setState(() {
              _stageConfigs[stage]!['lightMode'] = selection.first;
              _hasChanges = true;
            });
          },
        ),
        if (lightMode == LightMode.cycle) ...[
          const SizedBox(height: 24),
          Text('Light Timing (24-hour format)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controllers['lightOnTime'],
                  decoration: const InputDecoration(
                      labelText: 'On Time (HH:MM)',
                      border: OutlineInputBorder(),
                      helperText: 'e.g. 08:00'),
                  keyboardType: TextInputType.datetime,
                  onChanged: (_) => setState(() => _hasChanges = true),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: controllers['lightOffTime'],
                  decoration: const InputDecoration(
                      labelText: 'Off Time (HH:MM)',
                      border: OutlineInputBorder(),
                      helperText: 'e.g. 20:00'),
                  keyboardType: TextInputType.datetime,
                  onChanged: (_) => setState(() => _hasChanges = true),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStep4Review() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Review & Confirm',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Please review all settings before submitting',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        _buildReviewSection('Basic Information', Icons.info_outline, [
          _buildReviewItem(
              'Species', _species.displayName, () => _jumpToStep(0)),
          _buildReviewItem(
              'Date Planted', _formatDate(_datePlanted), () => _jumpToStep(0)),
          _buildReviewItem(
              'Current Stage', _currentStage.displayName, () => _jumpToStep(0)),
          _buildReviewItem(
              'Automation Mode', _mode.displayName, () => _jumpToStep(0)),
        ]),
        const SizedBox(height: 16),
        _buildReviewStageSection(GrowthStage.incubation, 1),
        const SizedBox(height: 16),
        _buildReviewStageSection(GrowthStage.pinning, 2),
        const SizedBox(height: 16),
        _buildReviewStageSection(GrowthStage.fruiting, 3),
      ],
    );
  }

  Widget _buildReviewSection(String title, IconData icon, List<Widget> items) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 16),
            ...items,
          ],
        ),
      ),
    );
  }

  Widget _buildReviewStageSection(GrowthStage stage, int stepIndex) {
    final config = _stageConfigs[stage]!;
    final controllers = _controllers[stage]!;
    final lightMode = config['lightMode'] as LightMode? ?? LightMode.off;

    String lightInfo = lightMode.name.toUpperCase();
    if (lightMode == LightMode.cycle) {
      lightInfo +=
          ' (${controllers['lightOnTime']!.text} - ${controllers['lightOffTime']!.text})';
    }

    return _buildReviewSection('${stage.displayName} Stage', Icons.timeline, [
      if (_getStageStartDate(stage) != null)
        _buildReviewItem('Start Date', _formatDate(_getStageStartDate(stage)!),
            () => _jumpToStep(stepIndex)),
      _buildReviewItem(
          'Expected Duration',
          '${controllers['expectedDays']!.text} days',
          () => _jumpToStep(stepIndex)),
      _buildReviewItem(
          'Temperature',
          '${controllers['tempMin']!.text}°C - ${controllers['tempMax']!.text}°C',
          () => _jumpToStep(stepIndex)),
      _buildReviewItem('Humidity Min', '${controllers['rhMin']!.text}%',
          () => _jumpToStep(stepIndex)),
      _buildReviewItem('CO₂ Max', '${controllers['co2Max']!.text} ppm',
          () => _jumpToStep(stepIndex)),
      _buildReviewItem('Light', lightInfo, () => _jumpToStep(stepIndex)),
    ]);
  }

  Widget _buildReviewItem(String label, String value, VoidCallback onEdit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons(bool isConnected) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (_currentStep > 0)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _previousStep,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Previous'),
                ),
              ),
            if (_currentStep > 0) const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _isLoading
                    ? null
                    : (_currentStep == _totalSteps - 1
                        ? _submitAllSettings
                        : _nextStep),
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_currentStep == _totalSteps - 1
                        ? Icons.check
                        : Icons.arrow_forward),
                label: Text(
                  _isLoading
                      ? 'Saving...'
                      : (_currentStep == _totalSteps - 1
                          ? 'Submit All Settings'
                          : 'Next Step'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDatePlanted() async {
    final now = DateTime.now();
    final firstDate = now.subtract(const Duration(days: 365));

    DateTime initialDate = _datePlanted;
    if (initialDate.isBefore(firstDate) || initialDate.isAfter(now)) {
      initialDate = now;
    }

    if (!mounted) return;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: now,
    );

    if (date == null || !mounted) return;

    final timeOfDay = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_datePlanted),
    );

    if (timeOfDay == null || !mounted) return;

    setState(() {
      _datePlanted = DateTime(
          date.year, date.month, date.day, timeOfDay.hour, timeOfDay.minute);

      if (_stageConfigs.containsKey(GrowthStage.incubation)) {
        _stageConfigs[GrowthStage.incubation]!['start_time'] =
            _datePlanted.toIso8601String();
      }

      _hasChanges = true;
    });
  }

  DateTime? _getStageStartDate(GrowthStage stage) {
    final startTimeStr = _stageConfigs[stage]?['start_time'] as String?;
    if (startTimeStr != null) {
      try {
        return DateTime.parse(startTimeStr);
      } catch (_) {}
    }
    return null;
  }

  Future<void> _pickStageStartDate(GrowthStage stage) async {
    final now = DateTime.now();
    final firstDate = now.subtract(const Duration(days: 365));

    DateTime initialDate = _getStageStartDate(stage) ?? now;
    if (initialDate.isBefore(firstDate) || initialDate.isAfter(now)) {
      initialDate = now;
    }

    if (!mounted) return;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: now,
    );

    if (date == null || !mounted) return;

    final timeOfDay = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );

    if (timeOfDay == null || !mounted) return;

    setState(() {
      final selectedDate = DateTime(
          date.year, date.month, date.day, timeOfDay.hour, timeOfDay.minute);
      _stageConfigs[stage]!['start_time'] = selectedDate.toIso8601String();
      _hasChanges = true;
    });
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _getStageDescription(GrowthStage stage) {
    switch (stage) {
      case GrowthStage.incubation:
        return 'Colonization period where mycelium spreads through substrate. Keep dark, warm, and humid.';
      case GrowthStage.pinning:
        return 'Initiation of mushroom primordia (pins). Introduce light cycles and fresh air exchange.';
      case GrowthStage.fruiting:
        return 'Active mushroom growth and maturation. Maintain optimal conditions until harvest.';
    }
  }

  int _getDefaultExpectedDays(Species species, GrowthStage stage) {
    switch (species) {
      case Species.oyster:
        switch (stage) {
          case GrowthStage.incubation:
            return 14;
          case GrowthStage.pinning:
            return 5;
          case GrowthStage.fruiting:
            return 7;
        }
      case Species.shiitake:
        switch (stage) {
          case GrowthStage.incubation:
            return 21;
          case GrowthStage.pinning:
            return 7;
          case GrowthStage.fruiting:
            return 10;
        }
      case Species.lionsMane:
        switch (stage) {
          case GrowthStage.incubation:
            return 18;
          case GrowthStage.pinning:
            return 6;
          case GrowthStage.fruiting:
            return 8;
        }
      case Species.custom:
        return 14;
    }
  }

  Map<GrowthStage, Map<String, dynamic>> _getSpeciesDefaults(Species species) {
    switch (species) {
      case Species.oyster:
        return {
          GrowthStage.incubation: {
            'expectedDays': 14,
            'tempMin': 20.0,
            'tempMax': 24.0,
            'rhMin': 90.0,
            'co2Max': 2000,
            'lightMode': LightMode.off
          },
          GrowthStage.pinning: {
            'expectedDays': 5,
            'tempMin': 18.0,
            'tempMax': 22.0,
            'rhMin': 95.0,
            'co2Max': 1000,
            'lightMode': LightMode.cycle
          },
          GrowthStage.fruiting: {
            'expectedDays': 7,
            'tempMin': 16.0,
            'tempMax': 20.0,
            'rhMin': 90.0,
            'co2Max': 800,
            'lightMode': LightMode.cycle
          },
        };
      case Species.shiitake:
        return {
          GrowthStage.incubation: {
            'expectedDays': 21,
            'tempMin': 18.0,
            'tempMax': 22.0,
            'rhMin': 85.0,
            'co2Max': 2500,
            'lightMode': LightMode.off
          },
          GrowthStage.pinning: {
            'expectedDays': 7,
            'tempMin': 16.0,
            'tempMax': 20.0,
            'rhMin': 90.0,
            'co2Max': 1000,
            'lightMode': LightMode.cycle
          },
          GrowthStage.fruiting: {
            'expectedDays': 10,
            'tempMin': 14.0,
            'tempMax': 18.0,
            'rhMin': 85.0,
            'co2Max': 800,
            'lightMode': LightMode.cycle
          },
        };
      case Species.lionsMane:
        return {
          GrowthStage.incubation: {
            'expectedDays': 18,
            'tempMin': 20.0,
            'tempMax': 24.0,
            'rhMin': 85.0,
            'co2Max': 2000,
            'lightMode': LightMode.off
          },
          GrowthStage.pinning: {
            'expectedDays': 6,
            'tempMin': 18.0,
            'tempMax': 22.0,
            'rhMin': 90.0,
            'co2Max': 1000,
            'lightMode': LightMode.cycle
          },
          GrowthStage.fruiting: {
            'expectedDays': 8,
            'tempMin': 16.0,
            'tempMax': 20.0,
            'rhMin': 85.0,
            'co2Max': 800,
            'lightMode': LightMode.cycle
          },
        };
      case Species.custom:
        return {
          GrowthStage.incubation: {
            'expectedDays': 14,
            'tempMin': 20.0,
            'tempMax': 24.0,
            'rhMin': 90.0,
            'co2Max': 2000,
            'lightMode': LightMode.off
          },
          GrowthStage.pinning: {
            'expectedDays': 5,
            'tempMin': 18.0,
            'tempMax': 22.0,
            'rhMin': 95.0,
            'co2Max': 1000,
            'lightMode': LightMode.cycle
          },
          GrowthStage.fruiting: {
            'expectedDays': 7,
            'tempMin': 16.0,
            'tempMax': 20.0,
            'rhMin': 90.0,
            'co2Max': 800,
            'lightMode': LightMode.cycle
          },
        };
    }
  }

  @override
  void dispose() {
    try {
      routeObserver.unsubscribe(this);
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}

    for (var stageControllers in _controllers.values) {
      for (var controller in stageControllers.values) {
        controller.dispose();
      }
    }

    super.dispose();
  }
}
