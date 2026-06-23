import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/ble_constants.dart';
import '../data/config/thingspeak_config.dart';
import '../data/repositories/thingspeak_repository.dart';
import '../providers/farms_provider.dart';

const _uuid = Uuid();

class AddFarmScreen extends ConsumerStatefulWidget {
  const AddFarmScreen({super.key});

  @override
  ConsumerState<AddFarmScreen> createState() => _AddFarmScreenState();
}

class _AddFarmScreenState extends ConsumerState<AddFarmScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _channelCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final _fieldTempCtrl = TextEditingController(text: 'field1');
  final _fieldHumCtrl = TextEditingController(text: 'field2');
  final _fieldCo2Ctrl = TextEditingController(text: 'field3');
  final _fieldLightCtrl = TextEditingController(text: 'field4');

  Species? _selectedSpecies;
  bool _showAdvanced = false;
  bool _isVerifying = false;
  bool _isSaving = false;
  String? _verifyError;
  bool _verified = false;

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _channelCtrl,
      _apiKeyCtrl,
      _locationCtrl,
      _notesCtrl,
      _fieldTempCtrl,
      _fieldHumCtrl,
      _fieldCo2Ctrl,
      _fieldLightCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _verifyChannel() async {
    if (_channelCtrl.text.trim().isEmpty || _apiKeyCtrl.text.trim().isEmpty) {
      setState(() => _verifyError = 'Enter channel ID and API key first.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _verifyError = null;
      _verified = false;
    });

    try {
      final config = ThingSpeakConfig.fromFarm(
        channelId: _channelCtrl.text.trim(),
        readApiKey: _apiKeyCtrl.text.trim(),
        fieldMap: _buildFieldMap(),
      );

      final repo = const ThingSpeakRepository();
      final latest = await repo.fetchLatestReading(
        config: config,
        farmId: 'verify',
      );

      if (mounted) {
        if (latest != null) {
          setState(() {
            _verified = true;
            _verifyError = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Connected! Latest reading: '
                '${latest.temperatureC.toStringAsFixed(1)}°C  '
                '${latest.relativeHumidity.toStringAsFixed(0)}% RH  '
                '${latest.co2Ppm} ppm CO₂',
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          setState(() {
            _verified = false;
            _verifyError =
                'Could not fetch data. Check your Channel ID and API key.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _verified = false;
          _verifyError = 'Error: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _saveFarm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final farmOps = ref.read(farmOperationsProvider);
      final farmId = _uuid.v4();

      await farmOps.createFarm(
        id: farmId,
        name: _nameCtrl.text.trim(),
        thingSpeakChannelId: _channelCtrl.text.trim(),
        thingSpeakReadApiKey: _apiKeyCtrl.text.trim(),
        thingSpeakFieldMap: _buildFieldMap(),
        location: _locationCtrl.text.trim().isEmpty
            ? null
            : _locationCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        primarySpecies: _selectedSpecies,
      );

      developer.log('Farm added: ${_nameCtrl.text.trim()}',
          name: 'AddFarmScreen');

      // Mirror to Firestore so the backend out-of-range email alert
      // function can see this farm even when the app is closed.
      final createdFarm = await ref.read(farmByIdProvider(farmId).future);
      if (createdFarm != null) {
        await ref.read(alertSyncRepositoryProvider).syncFarm(createdFarm);
      }

      // FIX: Invalidate the farms cache so HomeScreen re-fetches from the DB
      // and sees the newly created farm immediately on return.
      ref.invalidate(activeFarmsProvider);

      if (mounted) context.go('/farms');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save farm: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Map<String, String> _buildFieldMap() => {
        'temperature': _fieldTempCtrl.text.trim().isEmpty
            ? 'field1'
            : _fieldTempCtrl.text.trim(),
        'humidity': _fieldHumCtrl.text.trim().isEmpty
            ? 'field2'
            : _fieldHumCtrl.text.trim(),
        'co2': _fieldCo2Ctrl.text.trim().isEmpty
            ? 'field3'
            : _fieldCo2Ctrl.text.trim(),
        'light': _fieldLightCtrl.text.trim().isEmpty
            ? 'field4'
            : _fieldLightCtrl.text.trim(),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Farm')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Farm Details',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),

            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Farm Name *',
                hintText: 'e.g. Greenhouse A',
                prefixIcon: Icon(Icons.eco),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<Species?>(
              value: _selectedSpecies,
              decoration: const InputDecoration(
                labelText: 'Primary Species',
                prefixIcon: Icon(Icons.grass),
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('— None —')),
                ...Species.values.map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text('${s.displayName} 🍄'),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _selectedSpecies = v),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                prefixIcon: Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 24),
            const Divider(),

            Text('ThingSpeak Connection',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Find your Channel ID and Read API Key on your ThingSpeak channel page under API Keys.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _channelCtrl,
              decoration: const InputDecoration(
                labelText: 'Channel ID *',
                hintText: 'e.g. 2345678',
                prefixIcon: Icon(Icons.tag),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Channel ID is required'
                  : null,
              onChanged: (_) => setState(() {
                _verified = false;
                _verifyError = null;
              }),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _apiKeyCtrl,
              decoration: const InputDecoration(
                labelText: 'Read API Key *',
                hintText: 'e.g. ABCDEF1234567890',
                prefixIcon: Icon(Icons.key),
                border: OutlineInputBorder(),
              ),
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'API key is required' : null,
              onChanged: (_) => setState(() {
                _verified = false;
                _verifyError = null;
              }),
            ),
            const SizedBox(height: 16),

            OutlinedButton.icon(
              onPressed: _isVerifying ? null : _verifyChannel,
              icon: _isVerifying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_verified ? Icons.check_circle : Icons.wifi_tethering),
              label: Text(_isVerifying
                  ? 'Checking…'
                  : _verified
                      ? 'Connection verified ✓'
                      : 'Test Connection'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _verified ? Colors.green : null,
                side: _verified ? const BorderSide(color: Colors.green) : null,
              ),
            ),

            if (_verifyError != null) ...[
              const SizedBox(height: 8),
              Text(
                _verifyError!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 13),
              ),
            ],

            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              child: Row(
                children: [
                  Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more),
                  const SizedBox(width: 4),
                  Text(
                    'Advanced: Custom Field Mapping',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),

            if (_showAdvanced) ...[
              const SizedBox(height: 12),
              Text(
                'If your MushPi sends data to different ThingSpeak fields, set them here.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child:
                        _FieldInput(ctrl: _fieldTempCtrl, label: 'Temperature'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _FieldInput(ctrl: _fieldHumCtrl, label: 'Humidity'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _FieldInput(ctrl: _fieldCo2Ctrl, label: 'CO₂'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _FieldInput(ctrl: _fieldLightCtrl, label: 'Light'),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),

            FilledButton.icon(
              onPressed: _isSaving ? null : _saveFarm,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              label: Text(_isSaving ? 'Saving…' : 'Add Farm'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _FieldInput extends StatelessWidget {
  const _FieldInput({required this.ctrl, required this.label});
  final TextEditingController ctrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'field1',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}