import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../../core/constants/ble_constants.dart';
import '../../core/utils/ble_serializer.dart';
import 'device_repository.dart';

/// Wi-Fi / LAN implementation of [DeviceRepository].
///
/// Talks to a MushPi controller's REST API over HTTP, using the same
/// domain models (EnvironmentalReading, ControlTargetsData, etc.) the BLE
/// side already uses. The endpoint shapes below match the API sketched out
/// with ChatGPT; adjust paths/fields here (and only here) once the ESP32
/// firmware side is finalized — nothing outside this file needs to change
/// if the wire format shifts, since screens only ever see the domain
/// models.
///
/// v1 uses polling (a periodic GET) to fill in the same
/// Stream<EnvironmentalReading> / Stream<int> / Stream<ActuatorStatusData>
/// getters the BLE side exposes via GATT notifications. That's a
/// deliberate, contained shortcut: swapping polling for a WebSocket later
/// only touches [_startPolling] — the interface and everything above it
/// stays the same.
class WifiDeviceRepository implements DeviceRepository {
  final http.Client _client;
  final Duration _requestTimeout;
  final Duration _pollInterval;

  String? _host;
  int _port = 80;
  Timer? _pollTimer;
  DeviceConnectionState _state = DeviceConnectionState.disconnected;
  int _consecutivePollFailures = 0;
  static const int _pollFailureThreshold = 3;

  final _connectionStateController =
      StreamController<DeviceConnectionState>.broadcast();
  final _environmentalDataController =
      StreamController<EnvironmentalReading>.broadcast();
  final _statusFlagsController = StreamController<int>.broadcast();
  final _actuatorStatusController =
      StreamController<ActuatorStatusData>.broadcast();

  WifiDeviceRepository({
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(seconds: 2),
  })  : _client = client ?? http.Client(),
        _requestTimeout = requestTimeout,
        _pollInterval = pollInterval;

  // ---- Connection lifecycle ----

  @override
  Future<void> connect(DeviceTarget target) => _guard(() async {
        if (target is! WifiDeviceTarget) {
          throw ArgumentError(
            'WifiDeviceRepository received a ${target.runtimeType}; '
            'expected WifiDeviceTarget',
          );
        }

        _host = target.host;
        _port = target.port;
        _setState(DeviceConnectionState.connecting);

        // Confirm the controller is actually reachable before declaring
        // "connected" — a bad IP/hostname should fail fast here rather
        // than surfacing as a mysterious later read/write error.
        await readEnvironmentalData();

        _setState(DeviceConnectionState.connected);
        _startPolling();
      });

  @override
  Future<void> disconnect() => _guard(() async {
        _pollTimer?.cancel();
        _pollTimer = null;
        _setState(DeviceConnectionState.disconnected);
      });

  @override
  bool get isConnected => _state == DeviceConnectionState.connected;

  @override
  Stream<DeviceConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  void _setState(DeviceConnectionState state) {
    _state = state;
    _connectionStateController.add(state);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) async {
      try {
        _environmentalDataController.add(await readEnvironmentalData());
        _statusFlagsController.add(await readStatusFlags());
        final actuator = await readActuatorStatus();
        if (actuator != null) _actuatorStatusController.add(actuator);
        // Successful poll; reset failure counter.
        _consecutivePollFailures = 0;
      } catch (e, stackTrace) {
        // Swallow poll errors so one flaky cycle doesn't crash the timer.
        // A device that's genuinely gone stays silent on these streams;
        // callers doing an explicit read/write still get a real failure.
        // (a "missed N heartbeats -> disconnected" watchdog) once this is
        // running against real hardware instead of mocks.
        developer.log(
          'Wi-Fi poll cycle failed',
          name: 'WifiDeviceRepository',
          error: e,
          stackTrace: stackTrace,
          level: 900,
        );
        _consecutivePollFailures++;
        if (_consecutivePollFailures >= _pollFailureThreshold) {
          developer.log(
            'Wi-Fi poll failure threshold reached; marking disconnected',
            name: 'WifiDeviceRepository',
            level: 900,
          );
          _pollTimer?.cancel();
          _pollTimer = null;
          _setState(DeviceConnectionState.disconnected);
        }
      }
    });
  }

  // ---- Live data streams ----

  @override
  Stream<EnvironmentalReading> get environmentalDataStream =>
      _environmentalDataController.stream;

  @override
  Stream<int> get statusFlagsStream => _statusFlagsController.stream;

  @override
  Stream<ActuatorStatusData> get actuatorStatusStream =>
      _actuatorStatusController.stream;

  // ---- Reads ----

  @override
  Future<EnvironmentalReading> readEnvironmentalData() => _guard(() async {
        final json = await _get('/api/data');
        return EnvironmentalReading(
          co2Ppm: json['co2'] as int,
          temperatureC: (json['temp'] as num).toDouble(),
          relativeHumidity: (json['humidity'] as num).toDouble(),
          lightRaw: (json['lux'] as num).round(),
          uptimeMs: 0,
          timestamp: DateTime.now(),
        );
      });

  @override
  Future<ControlTargetsData> readControlTargets() => _guard(() async {
        final json = await _get('/control-targets');
        return _controlTargetsFromJson(json);
      });

  @override
  Future<StageStateData> readStageState() => _guard(() async {
        final json = await _get('/stage-state');
        return _stageStateFromJson(json);
      });

  @override
  Future<int> readStatusFlags() => _guard(() async {
        final json = await _get('/status-flags');
        return json['flags'] as int;
      });

  @override
  Future<ActuatorStatusData?> readActuatorStatus() => _guard(() async {
        final json = await _get('/api/data');
        if (json.isEmpty) return null;
        return ActuatorStatusData(
          lightOn: json['lightRunning'] as bool,
          fanOn: json['fanRunning'] as bool,
          mistOn: json['humidifierOn'] as bool,
          heaterOn: json['tecOn'] as bool,
          fanReasonCode: 0,
          mistReasonCode: 0,
          lightReasonCode: 0,
          heaterReasonCode: 0,
        );
      });

  @override
  Future<void> toggleManualMode() =>
      _guard(() => _postText('/api/manual/toggle'));

  @override
  Future<void> toggleTec() => _guard(() => _postText('/api/manual/tec/toggle'));

  @override
  Future<void> toggleHumidifier() =>
      _guard(() => _postText('/api/manual/humidifier/toggle'));

  @override
  Future<void> setFanPwm(int value) =>
      _guard(() => _get('/api/manual/fan/$value'));

  @override
  Future<void> setLightPwm(int value) =>
      _guard(() => _get('/api/manual/light/$value'));

  // The toggle endpoints return plain "ON/OFF" strings, not JSON.
  // Separate helper so _get/_post don't need to special-case response parsing.
  Future<void> _postText(String path) async {
    final response = await _client.post(_uri(path)).timeout(_requestTimeout);
    _checkStatus(response);
  }

  @override
  Future<StageThresholdsData?> readStageThresholds(
    Species species,
    GrowthStage stage,
  ) =>
      _guard(() async {
        final json = await _get('/stage-thresholds', query: {
          'species': species.id.toString(),
          'stage': stage.id.toString(),
        });
        if (json.isEmpty) return null;
        // StageThresholdsData already has a fromJson in ble_serializer.dart
        return StageThresholdsData.fromJson(json);
      });

  // ---- Writes ----

  @override
  Future<void> writeControlTargets(ControlTargetsData targets) =>
      _guard(() => _post('/control-targets', {
            'tempMin': targets.tempMin,
            'tempMax': targets.tempMax,
            'rhMin': targets.rhMin,
            'co2Max': targets.co2Max,
            'lightMode': targets.lightMode.value,
            'onMinutes': targets.onMinutes,
            'offMinutes': targets.offMinutes,
          }));

  @override
  Future<void> writeStageState(StageStateData state) =>
      _guard(() => _post('/stage-state', {
            'mode': state.mode.id,
            'species': state.species.id,
            'stage': state.stage.id,
            'stageStartTime': state.stageStartTime.toIso8601String(),
            'expectedDays': state.expectedDays,
          }));

  @override
  Future<void> writeOverrideBits(int bits) =>
      _guard(() => _post('/override-bits', {'bits': bits}));

  @override
  Future<bool> writeStageThresholds(StageThresholdsData thresholds) =>
      _guard(() async {
        final response = await _post('/stage-thresholds', thresholds.toJson());
        return response['success'] as bool? ?? true;
      });

  // ---- Lifecycle ----

  @override
  void dispose() {
    _pollTimer?.cancel();
    _connectionStateController.close();
    _environmentalDataController.close();
    _statusFlagsController.close();
    _actuatorStatusController.close();
    _client.close();
  }

  // ---- HTTP + JSON helpers ----

  Uri _uri(String path, [Map<String, String>? query]) {
    if (_host == null) {
      throw DeviceRepositoryException(
        'WifiDeviceRepository.connect() must be called before use',
      );
    }
    return Uri.http('$_host:$_port', path, query);
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    final response =
        await _client.get(_uri(path, query)).timeout(_requestTimeout);
    _checkStatus(response);
    if (response.body.isEmpty) return {};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _client
        .post(
          _uri(path),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);
    _checkStatus(response);
    if (response.body.isEmpty) return {};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void _checkStatus(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DeviceRepositoryException(
        'MushPi controller returned HTTP ${response.statusCode} for '
        '${response.request?.url}',
      );
    }
  }

  ControlTargetsData _controlTargetsFromJson(Map<String, dynamic> json) {
    return ControlTargetsData(
      tempMin: (json['tempMin'] as num).toDouble(),
      tempMax: (json['tempMax'] as num).toDouble(),
      rhMin: (json['rhMin'] as num).toDouble(),
      co2Max: json['co2Max'] as int,
      lightMode: LightMode.fromValue(json['lightMode'] as int),
      onMinutes: json['onMinutes'] as int,
      offMinutes: json['offMinutes'] as int,
    );
  }

  StageStateData _stageStateFromJson(Map<String, dynamic> json) {
    return StageStateData(
      mode: ControlMode.fromId(json['mode'] as int),
      species: Species.fromId(json['species'] as int),
      stage: GrowthStage.fromId(json['stage'] as int),
      stageStartTime: DateTime.parse(json['stageStartTime'] as String),
      expectedDays: json['expectedDays'] as int,
    );
  }

  /// Wraps HTTP/parsing failures into [DeviceRepositoryException] so
  /// callers above this layer can catch one exception type regardless of
  /// which transport is active.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DeviceRepositoryException {
      rethrow;
    } catch (e) {
      throw DeviceRepositoryException('Wi-Fi operation failed', cause: e);
    }
  }
}
