import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class FrameTimingService {
  FrameTimingService._();

  static final FrameTimingService instance = FrameTimingService._();

  static const double frameBudgetMs = 16.0;
  static const Duration _summaryInterval = Duration(seconds: 5);
  static const Duration _slowFrameLogThrottle = Duration(seconds: 2);

  bool _isStarted = false;
  String _currentScreen = 'unknown';

  DateTime? _windowStartedAt;
  DateTime? _lastSlowFrameLogAt;
  int _windowFrameCount = 0;
  int _windowSlowBuildCount = 0;
  int _windowSlowRasterCount = 0;
  double _windowWorstBuildMs = 0;
  double _windowWorstRasterMs = 0;

  final Map<String, _FrameBudgetStats> _statsByScreen = {};

  void start() {
    if (_isStarted || kReleaseMode) {
      return;
    }

    _isStarted = true;
    _windowStartedAt = DateTime.now();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    developer.log(
      'Frame timing instrumentation enabled (budget: ${frameBudgetMs.toStringAsFixed(1)}ms)',
      name: 'res_q.performance',
    );
  }

  void setCurrentScreen(String screenName) {
    if (!_isStarted || kReleaseMode) {
      return;
    }
    if (screenName.trim().isEmpty || _currentScreen == screenName) {
      return;
    }
    _currentScreen = screenName;
    developer.log(
      'Tracking frame timings for $_currentScreen',
      name: 'res_q.performance',
    );
  }

  String dumpSummary() {
    if (_statsByScreen.isEmpty) {
      return 'No frame data recorded yet.';
    }

    final buffer = StringBuffer();
    final entries = _statsByScreen.entries.toList()
      ..sort(
        (a, b) => b.value.slowestFrameMs.compareTo(a.value.slowestFrameMs),
      );

    for (final entry in entries) {
      final stats = entry.value;
      final slowBuildRate = stats.frameCount == 0
          ? 0.0
          : (stats.slowBuildFrames / stats.frameCount) * 100;
      final slowRasterRate = stats.frameCount == 0
          ? 0.0
          : (stats.slowRasterFrames / stats.frameCount) * 100;
      buffer.writeln(
        '${entry.key}: frames=${stats.frameCount}, '
        'avgBuild=${stats.avgBuildMs.toStringAsFixed(2)}ms, '
        'avgRaster=${stats.avgRasterMs.toStringAsFixed(2)}ms, '
        'worst=${stats.slowestFrameMs.toStringAsFixed(2)}ms, '
        'slowBuild=${slowBuildRate.toStringAsFixed(1)}%, '
        'slowRaster=${slowRasterRate.toStringAsFixed(1)}%',
      );
    }
    return buffer.toString().trimRight();
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (kReleaseMode) {
      return;
    }

    final stats = _statsByScreen.putIfAbsent(
      _currentScreen,
      _FrameBudgetStats.new,
    );

    for (final timing in timings) {
      final buildMs = timing.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;
      final frameMs = buildMs + rasterMs;

      final slowBuild = buildMs > frameBudgetMs;
      final slowRaster = rasterMs > frameBudgetMs;
      final isSlowFrame = slowBuild || slowRaster;

      stats.frameCount += 1;
      stats.totalBuildMs += buildMs;
      stats.totalRasterMs += rasterMs;
      if (slowBuild) {
        stats.slowBuildFrames += 1;
      }
      if (slowRaster) {
        stats.slowRasterFrames += 1;
      }
      if (frameMs > stats.slowestFrameMs) {
        stats.slowestFrameMs = frameMs;
      }

      _windowFrameCount += 1;
      if (slowBuild) {
        _windowSlowBuildCount += 1;
      }
      if (slowRaster) {
        _windowSlowRasterCount += 1;
      }
      if (buildMs > _windowWorstBuildMs) {
        _windowWorstBuildMs = buildMs;
      }
      if (rasterMs > _windowWorstRasterMs) {
        _windowWorstRasterMs = rasterMs;
      }

      if (isSlowFrame) {
        _maybeLogSlowFrame(
          buildMs: buildMs,
          rasterMs: rasterMs,
          frameMs: frameMs,
        );
      }
    }

    _maybeLogWindowSummary();
  }

  void _maybeLogSlowFrame({
    required double buildMs,
    required double rasterMs,
    required double frameMs,
  }) {
    final now = DateTime.now();
    final lastLogAt = _lastSlowFrameLogAt;
    if (lastLogAt != null &&
        now.difference(lastLogAt) < _slowFrameLogThrottle) {
      return;
    }

    _lastSlowFrameLogAt = now;
    developer.log(
      'Slow frame on $_currentScreen '
      '(build=${buildMs.toStringAsFixed(2)}ms, '
      'raster=${rasterMs.toStringAsFixed(2)}ms, '
      'total=${frameMs.toStringAsFixed(2)}ms)',
      name: 'res_q.performance',
    );
  }

  void _maybeLogWindowSummary() {
    final startedAt = _windowStartedAt;
    if (startedAt == null) {
      _windowStartedAt = DateTime.now();
      return;
    }

    final now = DateTime.now();
    if (now.difference(startedAt) < _summaryInterval ||
        _windowFrameCount == 0) {
      return;
    }

    final slowBuildRate = (_windowSlowBuildCount / _windowFrameCount) * 100;
    final slowRasterRate = (_windowSlowRasterCount / _windowFrameCount) * 100;
    developer.log(
      'Summary[$_currentScreen] frames=$_windowFrameCount '
      'slowBuild=${slowBuildRate.toStringAsFixed(1)}% '
      'slowRaster=${slowRasterRate.toStringAsFixed(1)}% '
      'worstBuild=${_windowWorstBuildMs.toStringAsFixed(2)}ms '
      'worstRaster=${_windowWorstRasterMs.toStringAsFixed(2)}ms',
      name: 'res_q.performance',
    );

    _windowStartedAt = now;
    _windowFrameCount = 0;
    _windowSlowBuildCount = 0;
    _windowSlowRasterCount = 0;
    _windowWorstBuildMs = 0;
    _windowWorstRasterMs = 0;
  }
}

class _FrameBudgetStats {
  int frameCount = 0;
  int slowBuildFrames = 0;
  int slowRasterFrames = 0;
  double totalBuildMs = 0;
  double totalRasterMs = 0;
  double slowestFrameMs = 0;

  double get avgBuildMs => frameCount == 0 ? 0 : totalBuildMs / frameCount;
  double get avgRasterMs => frameCount == 0 ? 0 : totalRasterMs / frameCount;
}
