import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:developer' as developer;
import 'dart:math' as math;

import '../data/database/app_database.dart';
import '../providers/readings_provider.dart';
import '../providers/current_farm_provider.dart';
import '../providers/farms_provider.dart';

/// Environmental Chart Screen displaying trend data with customizable time range.
///
/// Shows line charts for:
/// - Temperature (°C)
/// - Humidity (%)
/// - CO₂ (ppm)
/// - Light (raw value)
///
/// Automatically loads data for the currently selected monitoring farm.
/// Supports custom date range selection (defaults to last 24 hours).
class EnvironmentalChartScreen extends ConsumerStatefulWidget {
  const EnvironmentalChartScreen({super.key});

  @override
  ConsumerState<EnvironmentalChartScreen> createState() =>
      _EnvironmentalChartScreenState();
}

class _EnvironmentalChartScreenState
    extends ConsumerState<EnvironmentalChartScreen> {
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  bool _useCustomRange = false;

  @override
  Widget build(BuildContext context) {
    final selectedFarmId = ref.watch(selectedMonitoringFarmIdProvider);
    final farmsAsync = ref.watch(activeFarmsProvider);

    // Use custom range provider if custom range is selected, otherwise use 24-hour provider
    final readingsAsync = _useCustomRange &&
            _customStartDate != null &&
            _customEndDate != null &&
            selectedFarmId != null
        ? ref.watch(readingsByPeriodProvider((
            farmId: selectedFarmId,
            start: _customStartDate!,
            end: _customEndDate!,
          )))
        : ref.watch(last24HoursReadingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Environmental Trends'),
        actions: [
          if (_useCustomRange)
            IconButton(
              icon: const Icon(Icons.restore),
              onPressed: () {
                setState(() {
                  _useCustomRange = false;
                  _customStartDate = null;
                  _customEndDate = null;
                });
                ref.invalidate(last24HoursReadingsProvider);
              },
              tooltip: 'Reset to Last 24 Hours',
            ),
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: () => _showDateRangePicker(context),
            tooltip: 'Select Date Range',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              developer.log(
                'Refreshing readings',
                name: 'EnvironmentalChartScreen',
              );
              if (_useCustomRange &&
                  _customStartDate != null &&
                  _customEndDate != null) {
                ref.invalidate(readingsByPeriodProvider((
                  farmId: selectedFarmId!,
                  start: _customStartDate!,
                  end: _customEndDate!,
                )));
              } else {
                ref.invalidate(last24HoursReadingsProvider);
              }
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: farmsAsync.when(
        data: (farms) {
          if (selectedFarmId == null || farms.isEmpty) {
            return _EmptyChartView();
          }

          final selectedFarm = farms.firstWhere(
            (f) => f.id == selectedFarmId,
            orElse: () => farms.first,
          );

          return readingsAsync.when(
            data: (readings) {
              if (readings.isEmpty) {
                return _NoDataView(farmName: selectedFarm.name);
              }

              return RefreshIndicator(
                onRefresh: () async {
                  if (_useCustomRange &&
                      _customStartDate != null &&
                      _customEndDate != null) {
                    ref.invalidate(readingsByPeriodProvider((
                      farmId: selectedFarmId,
                      start: _customStartDate!,
                      end: _customEndDate!,
                    )));
                  } else {
                    ref.invalidate(last24HoursReadingsProvider);
                  }
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FarmHeader(
                        farmName: selectedFarm.name,
                        timeRange: _useCustomRange &&
                                _customStartDate != null &&
                                _customEndDate != null
                            ? '${DateFormat('MMM dd, yyyy').format(_customStartDate!)} - ${DateFormat('MMM dd, yyyy').format(_customEndDate!)}'
                            : 'Last 24 Hours',
                      ),
                      const SizedBox(height: 16),
                      _DataSummary(readings: readings),
                      const SizedBox(height: 24),
                      _EnvironmentalChart(
                        readings: readings,
                        title: 'Temperature',
                        unit: '°C',
                        icon: Icons.thermostat,
                        color: Colors.orange,
                        minValue: 15.0,
                        maxValue: 35.0,
                        getValue: (r) => r.temperatureC,
                      ),
                      const SizedBox(height: 24),
                      _EnvironmentalChart(
                        readings: readings,
                        title: 'Humidity',
                        unit: '%',
                        icon: Icons.water_drop,
                        color: Colors.blue,
                        minValue: 70.0,
                        maxValue: 110.0,
                        getValue: (r) => r.relativeHumidity,
                      ),
                      const SizedBox(height: 24),
                      _EnvironmentalChart(
                        readings: readings,
                        title: 'CO₂',
                        unit: 'ppm',
                        icon: Icons.air,
                        color: Colors.green,
                        minValue: 300.0,
                        maxValue: 4000.0,
                        getValue: (r) => r.co2Ppm.toDouble(),
                      ),
                      const SizedBox(height: 24),
                      _EnvironmentalChart(
                        readings: readings,
                        title: 'Light',
                        unit: 'raw',
                        icon: Icons.light_mode,
                        color: Colors.amber,
                        minValue: 100.0,
                        maxValue: 600.0,
                        getValue: (r) => r.lightRaw.toDouble(),
                      ),
                      const SizedBox(height: 80), // Bottom padding
                    ],
                  ),
                ),
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(),
            ),
            error: (error, stack) {
              developer.log(
                'Error loading readings',
                name: 'EnvironmentalChartScreen',
                error: error,
                stackTrace: stack,
                level: 1000,
              );
              return _ErrorView(error: error.toString());
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => _ErrorView(error: error.toString()),
      ),
    );
  }

  Future<void> _showDateRangePicker(BuildContext context) async {
    final selectedFarmId = ref.read(selectedMonitoringFarmIdProvider);
    if (selectedFarmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a farm first')),
      );
      return;
    }

    final now = DateTime.now();
    final initialStart =
        _customStartDate ?? now.subtract(const Duration(hours: 24));
    final initialEnd = _customEndDate ?? now;

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange:
          _useCustomRange && _customStartDate != null && _customEndDate != null
              ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
              : DateTimeRange(
                  start: initialStart,
                  end: initialEnd,
                ),
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Select Date Range',
      cancelText: 'Cancel',
      confirmText: 'Apply',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Theme.of(context).colorScheme.primary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customStartDate = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
          0,
          0,
          0,
        );
        _customEndDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
        _useCustomRange = true;
      });

      // Invalidate the provider to fetch new data
      ref.invalidate(readingsByPeriodProvider((
        farmId: selectedFarmId,
        start: _customStartDate!,
        end: _customEndDate!,
      )));
    }
  }
}

/// Farm header showing the selected farm name
class _FarmHeader extends StatelessWidget {
  final String farmName;
  final String timeRange;

  const _FarmHeader({required this.farmName, this.timeRange = 'Last 24 Hours'});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              Icons.agriculture,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    farmName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    timeRange,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.show_chart,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Data summary showing count and time range
class _DataSummary extends StatelessWidget {
  final List<Reading> readings;

  const _DataSummary({required this.readings});

  @override
  Widget build(BuildContext context) {
    final earliest = readings.first.timestamp;
    final latest = readings.last.timestamp;
    final timeFormat = DateFormat('MMM dd, HH:mm');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.dataset,
                  size: 20,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${readings.length} Data Points',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${timeFormat.format(earliest)} → ${timeFormat.format(latest)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable environmental chart widget
class _EnvironmentalChart extends StatelessWidget {
  final List<Reading> readings;
  final String title;
  final String unit;
  final IconData icon;
  final Color color;
  final double minValue;
  final double maxValue;
  final double Function(Reading) getValue;

  const _EnvironmentalChart({
    required this.readings,
    required this.title,
    required this.unit,
    required this.icon,
    required this.color,
    required this.minValue,
    required this.maxValue,
    required this.getValue,
  });

  @override
  Widget build(BuildContext context) {
    final spots = _createSpots(readings, getValue, minValue, maxValue);

    return _ChartCard(
      title: title,
      unit: unit,
      icon: icon,
      color: color,
      minValue: minValue,
      maxValue: maxValue,
      spots: spots,
      readings: readings,
    );
  }
}

/// Generic chart card widget
class _ChartCard extends StatefulWidget {
  final String title;
  final String unit;
  final IconData icon;
  final Color color;
  final double minValue;
  final double maxValue;
  final List<FlSpot> spots;
  final List<Reading> readings;

  const _ChartCard({
    required this.title,
    required this.unit,
    required this.icon,
    required this.color,
    required this.minValue,
    required this.maxValue,
    required this.spots,
    required this.readings,
  });

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  // Scroll position, as an ABSOLUTE epoch-millisecond value (this is used
  // directly as the chart's minX in _buildChartData, and directly as the
  // Slider's value below) - NOT a relative offset from the earliest
  // reading. This distinction matters: past bugs here came from treating
  // it as relative in one place while every other place treated it as
  // absolute.
  double _scrollOffset = 0;

  // Visible window size (in milliseconds) - default to 6 hours
  static const double _defaultWindowMs = 6 * 60 * 60 * 1000; // 6 hours
  double _visibleWindowMs = _defaultWindowMs;

  @override
  void initState() {
    super.initState();
    // Start by showing the most recent data
    if (widget.spots.isNotEmpty) {
      final earliestTime = widget.spots.first.x;
      final latestTime = widget.spots.last.x;
      _scrollOffset = latestTime - _visibleWindowMs;
      // Lower bound must be the first reading's timestamp, NOT 0 (epoch,
      // i.e. the year 1970). Clamping to 0 here rarely mattered for this
      // particular initial value, but the same wrong lower bound is what
      // broke the Slider elsewhere - see the bounds below.
      if (_scrollOffset < earliestTime) _scrollOffset = earliestTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    final avgValue = widget.spots.isEmpty
        ? 0.0
        : widget.spots.map((s) => s.y).reduce((a, b) => a + b) /
            widget.spots.length;

    if (widget.spots.isEmpty) {
      return _buildEmptyCard(context, avgValue);
    }

    final minTime = widget.spots.first.x;
    final maxTime = widget.spots.last.x;
    final totalDuration = maxTime - minTime;

    // Recompute bounds every build (not just during pan/zoom gestures).
    // New readings can shrink `maxTime` if the latest sample gets filtered
    // out by _createSpots (out-of-range value), which would otherwise leave
    // a stale _scrollOffset greater than the new Slider max and crash.
    final maxScrollOffset =
        (maxTime - _visibleWindowMs).clamp(minTime, double.infinity);
    if (_scrollOffset > maxScrollOffset) {
      _scrollOffset = maxScrollOffset;
    }
    // FIX: the lower bound must be minTime, not 0/epoch. _scrollOffset is
    // an absolute epoch-ms value, so a Slider with `min: 0` mapped most of
    // its track to a time window from 1970 up to just before your real
    // data - i.e. a window with no points in it. That's why dragging the
    // Slider showed a blank chart, while panning looked fine (a drag
    // gesture can never realistically travel far enough to get anywhere
    // near epoch 0, so it stayed within the real data range by accident).
    if (_scrollOffset < minTime) {
      _scrollOffset = minTime;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, avgValue),
            const SizedBox(height: 16),
            // Zoom controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.zoom_out),
                  onPressed: () {
                    setState(() {
                      // Increase visible window (zoom out). Guard against
                      // totalDuration being shorter than _defaultWindowMs
                      // (e.g. sparse data), which would otherwise make the
                      // clamp's upperLimit < lowerLimit and throw.
                      final lowerBound = _defaultWindowMs;
                      final upperBound = totalDuration > lowerBound
                          ? totalDuration
                          : lowerBound;
                      _visibleWindowMs = (_visibleWindowMs * 1.5)
                          .clamp(lowerBound, upperBound);
                    });
                  },
                  tooltip: 'Zoom Out',
                ),
                Flexible(
                  child: Text(
                    _getTimeRangeLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_in),
                  onPressed: () {
                    setState(() {
                      // Decrease visible window (zoom in). Same guard as
                      // zoom out: upperLimit must never be less than
                      // lowerLimit or clamp() throws.
                      const double lowerBound =
                          60 * 60 * 1000; // Minimum 1 hour
                      final upperBound = totalDuration > lowerBound
                          ? totalDuration
                          : lowerBound;
                      _visibleWindowMs = (_visibleWindowMs / 1.5)
                          .clamp(lowerBound, upperBound);
                    });
                  },
                  tooltip: 'Zoom In',
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Horizontal scrollable chart
            SizedBox(
              height: 200,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Pick how many time-axis labels to show based on the
                  // actual rendered width, so labels never sit closer than
                  // ~64px apart. On narrow (mobile) screens this naturally
                  // reduces the label count; on wide (web) screens it stays
                  // at the same 5-6 labels as before.
                  const minLabelSpacingPx = 64.0;
                  final maxLabels = (constraints.maxWidth / minLabelSpacingPx)
                      .floor()
                      .clamp(2, 6);
                  final bottomInterval = _visibleWindowMs / maxLabels;

                  return GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        // Pan the chart
                        final sensitivity =
                            _visibleWindowMs / 200; // Adjust sensitivity
                        _scrollOffset -= details.delta.dx * sensitivity;
                        // FIX: lower bound is minTime, not 0 - see notes
                        // above. Previously this only "worked" because a
                        // drag gesture can't physically travel far enough
                        // to reach epoch 0.
                        _scrollOffset =
                            _scrollOffset.clamp(minTime, maxScrollOffset);
                      });
                    },
                    child: LineChart(
                      _buildChartData(
                          context, minTime, maxTime, bottomInterval),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // Time navigation slider
            if (totalDuration > _visibleWindowMs)
              Slider(
                value: _scrollOffset,
                // FIX: was `min: 0` (epoch/1970). _scrollOffset is an
                // absolute epoch-ms value, so the Slider's minimum must be
                // minTime (the earliest reading) - otherwise almost the
                // entire track corresponds to a time window with no data
                // in it at all, which is why dragging the slider showed a
                // blank chart.
                min: minTime,
                max: maxScrollOffset,
                onChanged: (value) {
                  setState(() {
                    _scrollOffset = value;
                  });
                },
                label: _getScrollPositionLabel(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard(BuildContext context, double avgValue) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, avgValue),
            const SizedBox(height: 16),
            const SizedBox(
              height: 200,
              child: Center(
                child: Text('No data available'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, double avgValue) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(widget.icon, color: widget.color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Avg: ${avgValue.toStringAsFixed(1)} ${widget.unit}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              // Show data range instead of fixed Y-axis range
              Text(
                _getDataRangeLabel(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Computes Y-axis bounds from the given spots so the plotted line fills
  /// roughly 80%+ of the chart's vertical space, similar to ThingSpeak's
  /// auto-scaling behaviour, instead of using a fixed min/max range that
  /// can leave sparse-range data (e.g. Light) squeezed into a sliver.
  ///
  /// Also returns a "nice" (1/2/5 x 10^n) interval and snaps min/max to
  /// multiples of it. Without this, an interval-based gridline can land
  /// a fraction of a unit away from the axis boundary, causing its label
  /// to render almost exactly on top of the boundary's own label (the
  /// "64 / 63" overlap seen at the top of the chart).
  (double, double, double) _computeYAxisBounds(List<FlSpot> spotsInView) {
    if (spotsInView.isEmpty) {
      final interval = _niceInterval((widget.maxValue - widget.minValue) / 4);
      return (widget.minValue, widget.maxValue, interval);
    }

    var dataMin = spotsInView.first.y;
    var dataMax = spotsInView.first.y;
    for (final s in spotsInView) {
      if (s.y < dataMin) dataMin = s.y;
      if (s.y > dataMax) dataMax = s.y;
    }

    var range = dataMax - dataMin;
    if (range <= 0) {
      // Flat line (all same value) - fabricate a small range so the axis
      // isn't degenerate.
      final fallback = dataMax.abs() * 0.1;
      range = fallback > 0 ? fallback : 1.0;
      dataMin -= range / 2;
      dataMax += range / 2;
    }

    // 10% padding on each side => data occupies ~1/1.2 ≈ 83% of the height.
    final padding = range * 0.1;
    var minY = dataMin - padding;
    var maxY = dataMax + padding;

    // Sensor quantities here (temp/humidity/CO2/light) are never negative;
    // avoid padding below zero when the data itself never goes negative.
    final allowNegative = dataMin < 0;
    if (!allowNegative && minY < 0) minY = 0;

    // Snap to a nice interval so gridlines/labels land on clean numbers
    // and the last tick coincides with the axis edge instead of sitting
    // a hair's breadth away from it.
    final interval = _niceInterval((maxY - minY) / 4);
    minY = (minY / interval).floorToDouble() * interval;
    maxY = (maxY / interval).ceilToDouble() * interval;
    if (!allowNegative && minY < 0) minY = 0;
    if (maxY - minY < interval) maxY = minY + interval;

    return (minY, maxY, interval);
  }

  /// Rounds a raw axis interval up to the nearest "nice" step (1, 2, or 5
  /// times a power of 10), the same approach most charting libraries use
  /// to avoid ugly/colliding tick values.
  double _niceInterval(double rawInterval) {
    if (rawInterval <= 0) return 1.0;
    final exponent = (math.log(rawInterval) / math.ln10).floor();
    final magnitude = math.pow(10, exponent).toDouble();
    final residual = rawInterval / magnitude;
    double niceResidual;
    if (residual <= 1.0) {
      niceResidual = 1.0;
    } else if (residual <= 2.0) {
      niceResidual = 2.0;
    } else if (residual <= 5.0) {
      niceResidual = 5.0;
    } else {
      niceResidual = 10.0;
    }
    return niceResidual * magnitude;
  }

  String _getDataRangeLabel() {
    if (widget.spots.isEmpty) {
      return 'Y-axis: ${widget.minValue.toStringAsFixed(0)} - ${widget.maxValue.toStringAsFixed(0)}';
    }
    final dataMin =
        widget.spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final dataMax =
        widget.spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    return 'Data: ${dataMin.toStringAsFixed(1)} - ${dataMax.toStringAsFixed(1)}';
  }

  LineChartData _buildChartData(BuildContext context, double minTime,
      double maxTime, double bottomInterval) {
    final visibleMinX = _scrollOffset;
    final visibleMaxX = _scrollOffset + _visibleWindowMs;

    final visibleSpots = widget.spots
        .where((s) => s.x >= visibleMinX && s.x <= visibleMaxX)
        .toList();
    final (minY, maxY, yInterval) = _computeYAxisBounds(
      visibleSpots.isNotEmpty ? visibleSpots : widget.spots,
    );

    // Tracks the x-value (ms) of the last bottom-axis label actually
    // rendered during this chart build, so we can suppress any tick that
    // lands too close to it. fl_chart generates ticks by stepping from a
    // rounded starting point at `bottomInterval` spacing rather than
    // anchoring on maxX/"now", so the final tick nearest the current time
    // can fall closer to its neighbor than minLabelSpacingPx guarantees -
    // this is what was causing the overlapping/doubled label at the right
    // edge. Declared here (fresh on every _buildChartData call) so it
    // resets on every rebuild/zoom/pan instead of leaking state.
    double? lastRenderedLabelX;

    return LineChartData(
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: yInterval,
        verticalInterval: _visibleWindowMs / 6, // Show ~6 vertical grid lines
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.3),
            strokeWidth: 1,
          );
        },
        getDrawingVerticalLine: (value) {
          return FlLine(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.3),
            strokeWidth: 1,
            dashArray: [5, 5],
          );
        },
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: yInterval,
            getTitlesWidget: (value, meta) {
              return Text(
                value.toStringAsFixed(0),
                style: Theme.of(context).textTheme.bodySmall,
              );
            },
          ),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            // Slightly taller reserved area to make room for the tilted
            // labels below (they take up a bit more vertical space than
            // flat horizontal text).
            reservedSize: 38,
            interval: bottomInterval, // Responsive - avoids label collision
            getTitlesWidget: (value, meta) {
              // Skip this tick entirely if it would land too close to the
              // previously rendered label. This is what actually fixes the
              // collision at the right edge: fl_chart's automatic tick
              // generation doesn't guarantee the final tick (nearest "now")
              // is a full `bottomInterval` away from its neighbor, so
              // without this check the last two labels can render on top
              // of each other right at the chart border.
              final minSpacingMs = bottomInterval * 0.6;
              if (lastRenderedLabelX != null &&
                  (value - lastRenderedLabelX!).abs() < minSpacingMs) {
                return const SizedBox.shrink();
              }
              lastRenderedLabelX = value;

              final dateTime =
                  DateTime.fromMillisecondsSinceEpoch(value.toInt());
              final timeFormat = _visibleWindowMs > 12 * 60 * 60 * 1000
                  ? DateFormat('MMM dd HH:mm') // Show date if > 12 hours
                  : DateFormat('HH:mm'); // Just time if <= 12 hours

              // Tilt the label so consecutive/edge labels no longer collide
              // or get visually clipped against the chart border (e.g. the
              // rightmost "now" label overlapping the axis edge). Rotating
              // around the top-right corner makes the label swing up and
              // to the left as it tilts, away from the right border, while
              // still reading naturally left-to-right.
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Transform.rotate(
                  angle: -0.45, // ~-26 degrees
                  alignment: Alignment.topRight,
                  child: Text(
                    timeFormat.format(dateTime),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                        ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
          left: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
          right: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      minX: visibleMinX,
      maxX: visibleMaxX,
      // Auto-scaled Y-axis: fills ~80%+ of the chart height around the
      // data currently in view, ThingSpeak-style, instead of a fixed range.
      minY: minY,
      maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: widget.spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: widget.color,
          barWidth: 3,
          dotData: FlDotData(
            show: _visibleWindowMs <
                3 * 60 * 60 * 1000, // Show dots if zoomed in (< 3 hours)
          ),
          belowBarData: BarAreaData(
            show: true,
            color: widget.color.withValues(alpha: 0.1),
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final dateTime =
                  DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
              final timeFormat = DateFormat('MMM dd, HH:mm:ss');
              return LineTooltipItem(
                '${spot.y.toStringAsFixed(1)} ${widget.unit}\n${timeFormat.format(dateTime)}',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  String _getTimeRangeLabel() {
    final hours = _visibleWindowMs / (60 * 60 * 1000);
    if (hours < 1) {
      final minutes = _visibleWindowMs / (60 * 1000);
      return '${minutes.toStringAsFixed(0)}m view';
    } else if (hours < 24) {
      return '${hours.toStringAsFixed(1)}h view';
    } else {
      final days = hours / 24;
      return '${days.toStringAsFixed(1)}d view';
    }
  }

  /// FIX: _scrollOffset is already an ABSOLUTE epoch-ms value (see the
  /// field doc comment above), so it must be converted to a DateTime
  /// directly. The previous version added `minTime` to it again
  /// (`_scrollOffset + minTime`), which double-counted the offset and
  /// showed the wrong time in the Slider's drag label.
  String _getScrollPositionLabel() {
    final currentTime =
        DateTime.fromMillisecondsSinceEpoch(_scrollOffset.toInt());
    return DateFormat('MMM dd, HH:mm').format(currentTime);
  }
}

/// Helper function to create FlSpot list from readings with timestamp-based x-axis
/// Filters out zero/negative values (sensor error reads). Upper/lower
/// "normal" bounds (minValue/maxValue) are no longer used to drop points -
/// the chart's Y-axis now scales dynamically to whatever data is present,
/// so a legitimate reading outside the old fixed display range (e.g. a low
/// Light value) is kept and simply reflected in the auto-scaled axis.
List<FlSpot> _createSpots(
  List<Reading> readings,
  double Function(Reading) getValue,
  double minValue,
  double maxValue,
) {
  return readings
      .map((reading) {
        final value = getValue(reading);
        // Filter out zero/negative values only - these indicate a sensor
        // error/dropout rather than a real (if unusually low) reading.
        if (value <= 0) return null;
        // Use milliseconds since epoch as x-value to show accurate time gaps
        return FlSpot(
          reading.timestamp.millisecondsSinceEpoch.toDouble(),
          value,
        );
      })
      .whereType<FlSpot>()
      .toList();
}

/// Empty state when no farm is selected
class _EmptyChartView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: 80,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No Farm Selected',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Please select a farm from the Monitoring screen to view charts.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// No data state when readings are empty
class _NoDataView extends StatelessWidget {
  final String farmName;

  const _NoDataView({required this.farmName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.data_usage,
              size: 80,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No Data Available',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'No sensor readings found for $farmName in the last 24 hours.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Text(
              'Charts will appear once data is collected.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Error state
class _ErrorView extends StatelessWidget {
  final String error;

  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 80,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              'Error Loading Charts',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              error,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
