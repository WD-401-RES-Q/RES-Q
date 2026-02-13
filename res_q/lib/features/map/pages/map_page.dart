import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../../common/theme/app_theme.dart';

enum WeatherState { none, sunny, cloudy, rainy }

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reportsSubscription;

  // Weather cache (shared across instances, 15 min TTL)
  static _WeatherData? _cachedWeatherData;
  static DateTime? _weatherCacheTime;
  static Future<_WeatherData>? _weatherRequestInFlight;
  static const Duration _weatherCacheDuration = Duration(minutes: 15);
  bool _showWeatherCard = false;
  bool _isWeatherLoading = false;
  String? _weatherError;
  _WeatherData? _weatherData;
  final bool _allowDestinationSelection = false;

  // Default location (Angeles City, Central Luzon, Philippines)
  final LatLng _initialCenter = const LatLng(15.1450, 120.5887);
  final double _initialZoom = 14.0;
  static const LatLng _angelesCityCenter = LatLng(15.1450, 120.5887);
  static const double _angelesCityRadiusMeters = 6000;

  // Sample incident markers
  final List<Marker> _incidentMarkers = [];
  static const Duration _resolvedRetention = Duration(hours: 1);
  final Map<String, Timer> _resolvedRemovalTimers = {};
  List<Map<String, dynamic>> _resolvedReports = [];
  QuerySnapshot<Map<String, dynamic>>? _latestReportSnapshot;
  static const int _reportFetchLimit = 100;
  bool _hasShownReportLimitNotice = false;
  bool _hasShownIndexWarning = false;

  bool _showEarthquake = true;
  bool _showFlood = true;
  bool _showFire = true;
  bool _showVehicular = true;
  bool _showOthers = true;

  // Route related variables
  LatLng? _userLocation;
  LatLng? _destination;
  List<LatLng> _routePoints = [];
  List<Marker> _routeMarkers = [];
  List<Polyline> _routePolylines = [];
  bool _isRouting = false;
  bool _isTracking = false;
  String _routeInstructions = '';
  double _estimatedDistance = 0.0;
  String _estimatedTime = '';
  int _currentStepIndex = 0;

  // Simulate moving along route
  Timer? _trackingTimer;

  @override
  void initState() {
    super.initState();
    // Initialize with user location (simulated)
    _userLocation = _initialCenter;
    _subscribeToReports();
  }

  @override
  void dispose() {
    _reportsSubscription?.cancel();
    _trackingTimer?.cancel();
    for (final timer in _resolvedRemovalTimers.values) {
      timer.cancel();
    }
    _weatherCardOffset.dispose();
    super.dispose();
  }

  void _showIncidentInfo(Map<String, dynamic> data) {
    final incidentType = data['incidentType'] as String? ?? 'Unknown';
    final reporter = data['name'] as String? ?? 'Unknown';
    final description =
        data['details'] as String? ?? data['description'] as String? ?? '';
    final contactNumber = data['contactNumber'] as String? ?? 'Unknown';
    final reportedAt = data['reportedAt'];
    String? reportedAtLabel;
    if (reportedAt is Timestamp) {
      final date = reportedAt.toDate();
      reportedAtLabel =
          '${date.month}/${date.day}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    final mediaUrl = data['mediaUrl'] as String?;
    final mediaType = (data['mediaType'] as String?)?.toLowerCase();
    final status = _normalizeStatusLabel(
      data['status'] as String? ?? 'Unverified',
    );

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFAC1B22),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.report,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          incidentType.toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFAC1B22),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3F3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFAC1B22)),
                    ),
                    child: Text(
                      'Status: $status',
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFAC1B22),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Report Details',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2933),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Reported by $reporter',
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1F2933),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Contact: $contactNumber',
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 12,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                  if (reportedAtLabel != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Reported at: $reportedAtLabel',
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 12,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 13,
                        height: 1.4,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  if (mediaUrl != null && mediaUrl.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: mediaType == 'photo'
                          ? CachedNetworkImage(
                              imageUrl: mediaUrl,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                height: 200,
                                color: const Color(0xFFF3F4F6),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) {
                                debugPrint(
                                  'Failed to load image: $url, error: $error',
                                );
                                return Container(
                                  height: 200,
                                  color: const Color(0xFFF3F4F6),
                                  child: const Center(
                                    child: Icon(
                                      Icons.error_outline,
                                      color: Colors.grey,
                                    ),
                                  ),
                                );
                              },
                            )
                          : Container(
                              height: 200,
                              width: double.infinity,
                              color: const Color(0xFFF3F4F6),
                              child: const Center(
                                child: Text(
                                  'Video attached',
                                  style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFAC1B22),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'CLOSE',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _normalizeStatusLabel(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'flagged' || normalized == 'unverified') {
      return 'FLAGGED';
    }
    if (normalized == 'on-scene') {
      return 'ON SCENE';
    }
    return status.toUpperCase();
  }

  Future<void> _calculateRoute() async {
    if (_userLocation == null || _destination == null) return;

    setState(() {
      _isRouting = true;
      _routeInstructions = 'Calculating route...';
      _routePoints.clear();
      _routeMarkers.clear();
      _routePolylines.clear();
    });

    try {
      final osrmRoute = await _fetchRouteFromOsrm(
        _userLocation!,
        _destination!,
      );
      if (osrmRoute != null && osrmRoute.points.isNotEmpty) {
        _routePoints = osrmRoute.points;
        _estimatedDistance = osrmRoute.distanceMeters / 1000;
        _estimatedTime = _formatDurationFromSeconds(osrmRoute.durationSeconds);
      } else {
        _routePoints = _generateSimulatedRoute(_userLocation!, _destination!);
        final distance = _calculateDistance(_routePoints);
        _estimatedDistance = distance;
        _estimatedTime = _calculateEstimatedTime(distance);
      }

      // Add markers
      _routeMarkers.addAll([
        Marker(
          point: _userLocation!,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: Colors.blue, size: 40),
        ),
        Marker(
          point: _destination!,
          width: 40,
          height: 40,
          child: const Icon(Icons.flag, color: Colors.red, size: 40),
        ),
      ]);

      // Add route polylines with subtle casing for visibility
      _routePolylines.addAll([
        Polyline(
          points: _routePoints,
          color: AppColors.appOffWhite.withOpacity(0.9),
          strokeWidth: 8.0,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        Polyline(
          points: _routePoints,
          color: AppColors.appGreen.withOpacity(0.95),
          strokeWidth: 4.5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      ]);

      // Generate route instructions
      _generateRouteInstructions();

      // Zoom to fit route
      _zoomToRoute();
    } catch (e) {
      debugPrint('Error calculating route: $e');
      _routeInstructions = 'Failed to calculate route';
    } finally {
      setState(() {
        _isRouting = false;
      });
    }
  }

  List<LatLng> _generateSimulatedRoute(LatLng start, LatLng end) {
    // Generate a simple curved route
    final points = <LatLng>[];
    const segments = 20;

    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      final lat = start.latitude + (end.latitude - start.latitude) * t;
      final lng = start.longitude + (end.longitude - start.longitude) * t;

      // Add slight curve
      final curve = 0.001 * sin(t * pi);
      points.add(LatLng(lat + curve, lng + curve));
    }

    return points;
  }

  Future<_RouteResult?> _fetchRouteFromOsrm(LatLng start, LatLng end) async {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};'
      '${end.longitude},${end.latitude}'
      '?overview=simplified&geometries=geojson',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      return null;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      return null;
    }
    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>?;
    final coords = geometry?['coordinates'] as List<dynamic>?;
    if (coords == null || coords.isEmpty) {
      return null;
    }
    final points = coords
        .map(
          (coord) => LatLng(
            (coord[1] as num).toDouble(),
            (coord[0] as num).toDouble(),
          ),
        )
        .toList();
    final distanceMeters = (route['distance'] as num?)?.toDouble() ?? 0.0;
    final durationSeconds = (route['duration'] as num?)?.toDouble() ?? 0.0;
    return _RouteResult(
      points: points,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }

  double _calculateDistance(List<LatLng> points) {
    double totalDistance = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      totalDistance += const Distance().as(
        LengthUnit.Kilometer,
        points[i],
        points[i + 1],
      );
    }
    return totalDistance;
  }

  String _calculateEstimatedTime(double distanceKm) {
    // Assume average speed of 40 km/h
    final hours = distanceKm / 40.0;
    if (hours < 1) {
      final minutes = (hours * 60).round();
      return '$minutes mins';
    }
    return '${hours.toStringAsFixed(1)} hours';
  }

  String _formatDurationFromSeconds(double seconds) {
    final duration = Duration(seconds: seconds.round());
    if (duration.inHours >= 1) {
      final hours = duration.inMinutes / 60;
      return '${hours.toStringAsFixed(1)} hours';
    }
    return '${duration.inMinutes} mins';
  }

  void _generateRouteInstructions() {
    _routeInstructions =
        '''
📏 Distance: ${_estimatedDistance.toStringAsFixed(2)} km
⏱️ Estimated Time: $_estimatedTime
''';
    _currentStepIndex = 0;
  }

  void _zoomToRoute() {
    if (_routePoints.isEmpty) return;

    double minLat = _routePoints.first.latitude;
    double maxLat = _routePoints.first.latitude;
    double minLng = _routePoints.first.longitude;
    double maxLng = _routePoints.first.longitude;

    for (final point in _routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

    // Calculate zoom level based on bounds
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = max(latDiff, lngDiff);
    final zoom = 14 - maxDiff.abs() * 10;

    _mapController.move(center, zoom.clamp(10.0, 16.0).toDouble());
  }

  void _startTracking() {
    if (_routePoints.isEmpty || _userLocation == null) return;

    setState(() {
      _isTracking = true;
      _currentStepIndex = 0;
    });

    int pointIndex = 0;

    _trackingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (pointIndex < _routePoints.length - 1) {
        setState(() {
          _userLocation = _routePoints[pointIndex];
          pointIndex++;

          // Update current step
          if (pointIndex % 5 == 0 && _currentStepIndex < 3) {
            _currentStepIndex++;
          }

          // Move map to follow user
          _mapController.move(_userLocation!, _mapController.camera.zoom);
        });
      } else {
        _stopTracking();
        setState(() {
          _routeInstructions = '🎉 Arrived at destination!';
          _currentStepIndex = 3;
        });
      }
    });
  }

  Future<void> _toggleWeatherCard() async {
    if (_showWeatherCard) {
      setState(() {
        _showWeatherCard = false;
      });
      return;
    }
    setState(() {
      _showWeatherCard = true;
      _isWeatherLoading = true;
      _weatherError = null;
    });
    _weatherCardOffset.value = Offset.zero;
    try {
      final data = await _fetchWeatherForAngeles();
      if (!mounted) return;
      setState(() {
        _weatherData = data;
        _isWeatherLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _weatherError = 'Unable to load weather';
        _isWeatherLoading = false;
      });
    }
  }

  IconData _weatherIcon(WeatherState state) {
    switch (state) {
      case WeatherState.sunny:
        return Icons.wb_sunny_outlined;
      case WeatherState.cloudy:
        return Icons.cloud_outlined;
      case WeatherState.rainy:
        return Icons.grain;
      case WeatherState.none:
        return Icons.cloud_outlined;
    }
  }

  void _stopTracking() {
    _trackingTimer?.cancel();
    setState(() {
      _isTracking = false;
    });
  }

  void _clearRoute() {
    setState(() {
      _destination = null;
      _routePoints.clear();
      _routeMarkers.clear();
      _routePolylines.clear();
      _routeInstructions = '';
      _isTracking = false;
      _currentStepIndex = 0;
    });
    _trackingTimer?.cancel();
  }

  void _goToCurrentLocation() {
    if (_userLocation != null) {
      _mapController.move(_userLocation!, _initialZoom);
    } else {
      _mapController.move(_initialCenter, _initialZoom);
    }
  }

  Widget _buildTopBarAction({
    required IconData icon,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(isActive ? 0.28 : 0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.35), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  void _subscribeToReports() {
    _reportsSubscription?.cancel();
    _reportsSubscription = FirebaseFirestore.instance
        .collection('reports')
        .orderBy('reportedAt', descending: true)
        .limit(_reportFetchLimit) // Limit most recent reports for performance
        .snapshots()
        .listen(
          (snapshot) {
            _applyReportSnapshot(snapshot);
          },
          onError: (error) {
            debugPrint('❌ Failed to subscribe to reports: $error');
            if (!_hasShownIndexWarning &&
                error is FirebaseException &&
                error.code == 'failed-precondition') {
              _hasShownIndexWarning = true;
              if (kDebugMode) {
                debugPrint(
                  'Firestore reports query failed due to missing index. Falling back to simpler query configuration.',
                );
              }
            }
          },
        );
  }

  Marker? _createIncidentMarker({
    required String reportId,
    required Map<String, dynamic> data,
  }) {
    final location = data['location'] as GeoPoint?;
    if (location == null) {
      return null;
    }
    final incidentType = data['incidentType'] as String? ?? 'Unknown';
    if (!_shouldShowIncidentType(incidentType)) {
      return null;
    }
    final statusLower = (data['status'] as String? ?? '').toLowerCase();
    final isResolved =
        statusLower == 'resolved' || statusLower == 'incident resolved';
    final isFlagged = statusLower == 'flagged' || statusLower == 'unverified';
    final isInactive = isResolved || isFlagged;

    final markerSize = isInactive ? 56.0 : 72.0;
    final badge = _buildStatusBadge(statusLower, markerSize);
    final baseContent = GestureDetector(
      onTap: () => _showIncidentInfo(data),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _buildIncidentAsset(
            _getMarkerAssetForIncidentType(incidentType),
            width: markerSize,
            height: markerSize,
          ),
          if (badge != null) Positioned(right: -2, top: -2, child: badge),
        ],
      ),
    );
    return Marker(
      key: ValueKey('incident-$reportId'),
      point: LatLng(location.latitude, location.longitude),
      width: markerSize,
      height: markerSize,
      child: isInactive
          ? Opacity(
              opacity: 0.45,
              child: IgnorePointer(ignoring: true, child: baseContent),
            )
          : baseContent,
    );
  }

  void _applyReportSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    _latestReportSnapshot = snapshot;
    _incidentMarkers.clear();
    final resolvedReports = <Map<String, dynamic>>[];
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final location = data['location'] as GeoPoint?;
      if (location != null) {
        final reportId = doc.id;
        final status = (data['status'] as String? ?? '').toLowerCase();
        final incidentType = data['incidentType'] as String? ?? 'Unknown';
        final shouldShowType = _shouldShowIncidentType(incidentType);
        final resolvedAt = _parseResolvedAt(data);
        final flaggedAt = _parseFlaggedAt(data) ?? _parseReportedAt(data);
        final isResolved =
            status == 'resolved' || status == 'incident resolved';
        final isFlagged = status == 'flagged' || status == 'unverified';
        final isInactive = isResolved || isFlagged;
        if (isInactive) {
          final inactiveAt = isResolved ? resolvedAt : flaggedAt;
          final shouldKeep = _shouldKeepResolved(reportId, inactiveAt);
          if (!shouldKeep) {
            continue;
          }
          if (isResolved && shouldShowType) {
            resolvedReports.add({'id': reportId, 'data': data});
          }
        } else {
          _cancelResolvedRemoval(reportId);
        }
        final marker = _createIncidentMarker(reportId: reportId, data: data);
        if (marker != null) {
          _incidentMarkers.add(marker);
        }
      }
    }

    if (mounted) {
      setState(() {
        _resolvedReports = resolvedReports;
      });
    }
    debugPrint('✅ Loaded ${snapshot.docs.length} reports from Firestore');
    if (!_hasShownReportLimitNotice &&
        snapshot.docs.length >= _reportFetchLimit) {
      _hasShownReportLimitNotice = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Showing latest $_reportFetchLimit reports. Older reports are not displayed.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  bool _shouldShowIncidentType(String incidentType) {
    final normalized = incidentType.trim().toLowerCase();
    if (normalized.contains('earthquake')) {
      return _showEarthquake;
    }
    if (normalized.contains('flood')) {
      return _showFlood;
    }
    if (normalized.contains('fire')) {
      return _showFire;
    }
    if (normalized.contains('vehicular') ||
        normalized.contains('road accident') ||
        normalized.contains('car crash') ||
        normalized.contains('vehicle')) {
      return _showVehicular;
    }
    return _showOthers;
  }

  DateTime? _parseResolvedAt(Map<String, dynamic> data) {
    final resolvedAtRaw = data['resolvedAt'];
    if (resolvedAtRaw is Timestamp) {
      return resolvedAtRaw.toDate();
    }
    if (resolvedAtRaw is DateTime) {
      return resolvedAtRaw;
    }
    return null;
  }

  DateTime? _parseFlaggedAt(Map<String, dynamic> data) {
    final flaggedAtRaw = data['flaggedAt'];
    if (flaggedAtRaw is Timestamp) {
      return flaggedAtRaw.toDate();
    }
    if (flaggedAtRaw is DateTime) {
      return flaggedAtRaw;
    }
    return null;
  }

  DateTime? _parseReportedAt(Map<String, dynamic> data) {
    final reportedAtRaw = data['reportedAt'];
    if (reportedAtRaw is Timestamp) {
      return reportedAtRaw.toDate();
    }
    if (reportedAtRaw is DateTime) {
      return reportedAtRaw;
    }
    return null;
  }

  bool _shouldKeepResolved(String reportId, DateTime? resolvedAt) {
    if (resolvedAt == null) {
      return false;
    }
    final elapsed = DateTime.now().difference(resolvedAt);
    if (elapsed >= _resolvedRetention) {
      _cancelResolvedRemoval(reportId);
      return false;
    }
    _scheduleResolvedRemoval(reportId, resolvedAt, elapsed);
    return true;
  }

  void _scheduleResolvedRemoval(
    String reportId,
    DateTime resolvedAt,
    Duration elapsed,
  ) {
    if (_resolvedRemovalTimers.containsKey(reportId)) {
      return;
    }
    final remaining = _resolvedRetention - elapsed;
    if (remaining <= Duration.zero) {
      _removeIncidentMarker(reportId);
      return;
    }
    _resolvedRemovalTimers[reportId] = Timer(remaining, () {
      _removeIncidentMarker(reportId);
    });
  }

  void _cancelResolvedRemoval(String reportId) {
    final timer = _resolvedRemovalTimers.remove(reportId);
    timer?.cancel();
  }

  void _removeIncidentMarker(String reportId) {
    if (!mounted) return;
    setState(() {
      _incidentMarkers.removeWhere(
        (marker) => marker.key == ValueKey('incident-$reportId'),
      );
    });
    _cancelResolvedRemoval(reportId);
  }

  Widget? _buildStatusBadge(String statusLower, double markerSize) {
    final isResolved =
        statusLower == 'resolved' || statusLower == 'incident resolved';
    final isFlagged = statusLower == 'flagged' || statusLower == 'unverified';
    final isAttention =
        statusLower == 'pending' ||
        statusLower == 'on scene' ||
        statusLower == 'responding';

    if (!isResolved && !isAttention && !isFlagged) return null;

    final badgeSize = markerSize <= 60 ? 14.0 : 16.0;
    final iconSize = markerSize <= 60 ? 10.0 : 12.0;
    final color = isResolved
        ? const Color(0xFF00A458)
        : isFlagged
        ? const Color(0xFFDC2626)
        : const Color(0xFFAC1B22);
    final icon = isResolved
        ? Icons.check
        : isFlagged
        ? Icons.close
        : Icons.priority_high;

    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }

  String _formatResolvedTimestamp(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$month/$day/${date.year} $hour:$minute';
  }

  void _openResolvedReportsSheet() {
    if (_resolvedReports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No resolved reports available.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Resolved Reports (Last Hour)',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _resolvedReports.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = _resolvedReports[index];
                    final data = entry['data'] as Map<String, dynamic>? ?? {};
                    final incidentType =
                        data['incidentType'] as String? ?? 'Incident';
                    final resolvedAt = _parseResolvedAt(data);
                    final resolvedLabel = resolvedAt != null
                        ? _formatResolvedTimestamp(resolvedAt)
                        : 'Resolved recently';

                    return ListTile(
                      title: Text(
                        incidentType,
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Resolved: $resolvedLabel',
                        style: const TextStyle(fontFamily: 'RobotoCondensed'),
                      ),
                      trailing: const Icon(Icons.info_outline),
                      onTap: () {
                        Navigator.pop(context);
                        _showIncidentInfo(data);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherButton() {
    return GestureDetector(
      onTap: _toggleWeatherCard,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFAC1B22),
              Color(0xFFE34B3F),
              Color(0xFFFFC806),
              Color(0xFFFFE6A8),
            ],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.7), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          _weatherIcon(_weatherData?.state ?? WeatherState.cloudy),
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  // Track weather card drag offset for swipe-to-dismiss
  final ValueNotifier<Offset> _weatherCardOffset = ValueNotifier(Offset.zero);

  Widget _buildWeatherCard() {
    if (!_showWeatherCard) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: 76,
      left: 16,
      right: 16,
      child: GestureDetector(
        onPanUpdate: (details) {
          _weatherCardOffset.value = _weatherCardOffset.value + details.delta;
        },
        onPanEnd: (details) {
          final currentOffset = _weatherCardOffset.value;
          // Dismiss if dragged far enough horizontally or upward
          final horizontalThreshold = 80.0;
          final verticalThreshold = -50.0; // Negative because up is negative Y

          if (currentOffset.dx.abs() > horizontalThreshold ||
              currentOffset.dy < verticalThreshold) {
            setState(() {
              _showWeatherCard = false;
            });
            _weatherCardOffset.value = Offset.zero;
          } else {
            // Snap back if not dismissed
            _weatherCardOffset.value = Offset.zero;
          }
        },
        child: ValueListenableBuilder<Offset>(
          valueListenable: _weatherCardOffset,
          builder: (context, offset, child) {
            return AnimatedContainer(
              duration: offset == Offset.zero
                  ? const Duration(milliseconds: 200)
                  : Duration.zero,
              transform: Matrix4.translationValues(
                offset.dx,
                offset.dy.clamp(-100.0, 20.0), // Limit vertical drag
                0,
              ),
              child: Opacity(
                opacity: (1 - (offset.distance / 150)).clamp(0.3, 1.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.35),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: _buildWeatherCardContent(),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWeatherCardContent() {
    if (_isWeatherLoading) {
      return const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Loading weather...',
            style: TextStyle(
              fontFamily: 'RobotoCondensed',
              fontWeight: FontWeight.w400,
              color: Color(0xFF4B5563),
            ),
          ),
        ],
      );
    }
    if (_weatherError != null) {
      return Text(
        _weatherError!,
        style: const TextStyle(
          fontFamily: 'RobotoCondensed',
          fontWeight: FontWeight.w400,
          color: Color(0xFFB42318),
        ),
      );
    }
    final data = _weatherData;
    if (data == null) {
      return const Text(
        'Weather unavailable',
        style: TextStyle(
          fontFamily: 'RobotoCondensed',
          fontWeight: FontWeight.w400,
          color: Color(0xFF4B5563),
        ),
      );
    }
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F7FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_weatherIcon(data.state), color: const Color(0xFF2563EB)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Angeles City',
                style: TextStyle(
                  fontFamily: 'RobotoCondensed',
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.description,
                style: const TextStyle(
                  fontFamily: 'RobotoCondensed',
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${data.temperature.round()}°',
              style: const TextStyle(
                fontFamily: 'RobotoCondensed',
                fontWeight: FontWeight.w400,
                fontSize: 20,
                color: Color(0xFF111827),
              ),
            ),
            Text(
              'H ${data.max.round()}°  L ${data.min.round()}°',
              style: const TextStyle(
                fontFamily: 'RobotoCondensed',
                fontWeight: FontWeight.w400,
                fontSize: 11,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<_WeatherData> _fetchWeatherForAngeles() async {
    // Return cached data if still valid
    if (_cachedWeatherData != null && _weatherCacheTime != null) {
      final elapsed = DateTime.now().difference(_weatherCacheTime!);
      if (elapsed < _weatherCacheDuration) {
        return _cachedWeatherData!;
      }
    }

    if (_weatherRequestInFlight != null) {
      return _weatherRequestInFlight!;
    }

    final request = _requestWeatherFromApi();
    _weatherRequestInFlight = request;
    try {
      final weatherData = await request;
      _cachedWeatherData = weatherData;
      _weatherCacheTime = DateTime.now();
      return weatherData;
    } catch (_) {
      _cachedWeatherData = null;
      _weatherCacheTime = null;
      rethrow;
    } finally {
      _weatherRequestInFlight = null;
    }
  }

  Future<_WeatherData> _requestWeatherFromApi() async {
    const lat = 15.1450;
    const lon = 120.5887;
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&current_weather=true'
      '&daily=temperature_2m_max,temperature_2m_min,weathercode'
      '&timezone=auto',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Weather request failed');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final current = json['current_weather'] as Map<String, dynamic>?;
    final daily = json['daily'] as Map<String, dynamic>?;
    if (current == null || daily == null) {
      throw Exception('Weather data missing');
    }
    final temperature = (current['temperature'] as num).toDouble();
    final max = (daily['temperature_2m_max'] as List<dynamic>).first as num;
    final min = (daily['temperature_2m_min'] as List<dynamic>).first as num;
    final code = (daily['weathercode'] as List<dynamic>).first as num;
    final state = _mapWeatherState(code.toInt());
    final description = _mapWeatherDescription(code.toInt());

    return _WeatherData(
      temperature: temperature,
      max: max.toDouble(),
      min: min.toDouble(),
      state: state,
      description: description,
    );
  }

  WeatherState _mapWeatherState(int code) {
    if (code == 0) return WeatherState.sunny;
    if (code == 1 || code == 2 || code == 3 || code == 45 || code == 48) {
      return WeatherState.cloudy;
    }
    return WeatherState.rainy;
  }

  String _mapWeatherDescription(int code) {
    switch (code) {
      case 0:
        return 'Clear';
      case 1:
        return 'Mostly clear';
      case 2:
        return 'Partly cloudy';
      case 3:
        return 'Overcast';
      case 45:
      case 48:
        return 'Foggy';
      case 51:
      case 53:
      case 55:
        return 'Drizzle';
      case 61:
      case 63:
      case 65:
        return 'Rain';
      case 71:
      case 73:
      case 75:
        return 'Snow';
      case 80:
      case 81:
      case 82:
        return 'Showers';
      case 95:
      case 96:
      case 99:
        return 'Thunderstorm';
      default:
        return 'Cloudy';
    }
  }

  Future<void> _loadReportsFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('reports')
          .orderBy('reportedAt', descending: true)
          .limit(_reportFetchLimit)
          .get();
      _applyReportSnapshot(snapshot);
    } catch (e) {
      debugPrint('❌ Failed to load reports: $e');
    }
  }

  String _getMarkerAssetForIncidentType(String type) {
    switch (type.toUpperCase()) {
      case 'FIRE':
        return 'assets/icons/locations/LOC-FIRE.svg';
      case 'FLOOD':
        return 'assets/icons/locations/LOC-FLOOD.svg';
      case 'EARTHQUAKE':
        return 'assets/icons/locations/LOC-EARTHQUAKE.svg';
      case 'VEHICULAR':
        return 'assets/icons/locations/LOC-CRASH.svg';
      case 'ROAD OBSTRUCTION':
        return 'assets/icons/locations/LOC-OTHERS.svg';
      default:
        return 'assets/icons/locations/LOC-OTHERS.svg';
    }
  }

  Widget _buildIncidentAsset(
    String assetPath, {
    required double width,
    required double height,
  }) {
    if (assetPath.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        assetPath,
        width: width,
        height: height,
        fit: BoxFit.contain,
      );
    }

    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // OpenStreetMap (full screen)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
              minZoom: 5,
              maxZoom: 18,
              onTap: _allowDestinationSelection
                  ? (position, latlng) {
                      if (!_isRouting) {
                        _destination = latlng;
                        _calculateRoute();
                      }
                    }
                  : null,
            ),
            children: [
              // Map tiles from OpenStreetMap
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.resq.emergency_app',
                maxZoom: 19,
              ),

              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _angelesCityCenter,
                    radius: _angelesCityRadiusMeters,
                    useRadiusInMeter: true,
                    color: AppColors.appGreen.withOpacity(0.07),
                    borderColor: AppColors.appGreen.withOpacity(0.45),
                    borderStrokeWidth: 2.0,
                  ),
                ],
              ),

              // Route polyline
              if (_routePolylines.isNotEmpty)
                PolylineLayer(polylines: _routePolylines),

              // Incident markers
              MarkerLayer(markers: _incidentMarkers),

              // Route markers (user location and destination)
              if (_routeMarkers.isNotEmpty) MarkerLayer(markers: _routeMarkers),

              // User location marker when tracking
              if (_userLocation != null && _isTracking)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userLocation!,
                      width: 50,
                      height: 50,
                      child: const Icon(
                        Icons.navigation,
                        color: Colors.blue,
                        size: 40,
                      ),
                    ),
                  ],
                ),

              // Attribution (required for OSM)
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),

          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.1,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.08),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFF6FBF6).withOpacity(0.25),
                      Colors.transparent,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Custom Navigation Bar at the top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFAC1B22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        height: 34,
                        child: SvgPicture.asset(
                          'assets/icons/logo/RES-Q_LOGO.svg',
                          fit: BoxFit.contain,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                          placeholderBuilder: (context) => const Text(
                            'RES-Q',
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'Roboto',
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_allowDestinationSelection) ...[
                              _buildTopBarAction(
                                icon: _isTracking ? Icons.stop : Icons.route,
                                isActive: _isTracking,
                                onTap: () {
                                  if (_isTracking) {
                                    _stopTracking();
                                  } else if (_routePoints.isNotEmpty) {
                                    _startTracking();
                                  } else {
                                    _showRouteDialog();
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                            ],
                            _buildTopBarAction(
                              icon: Icons.filter_list,
                              onTap: _showFilterDialog,
                            ),
                            const SizedBox(width: 8),
                            _buildTopBarAction(
                              icon: Icons.refresh,
                              onTap: _loadReportsFromFirestore,
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

          // Responder route information card
          if (_routeInstructions.isNotEmpty && !_isRouting)
            Positioned(
              top: 80,
              right: 16,
              left: 16,
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFAC1B22),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.directions,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'RESPONDER ROUTE',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: Color(0xFFAC1B22),
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: _clearRoute,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3F3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFAC1B22)),
                        ),
                        child: Text(
                          'ETA (Responder \u2192 You): $_estimatedTime',
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFAC1B22),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Live location is updating as the responder moves.',
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 13,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _routeInstructions,
                        style: const TextStyle(fontSize: 15),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      if (_currentStepIndex > 0)
                        LinearProgressIndicator(
                          value: _currentStepIndex / 3,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).primaryColor,
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (!_isTracking)
                        ElevatedButton(
                          onPressed: _startTracking,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFAC1B22),
                            minimumSize: const Size(double.infinity, 40),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.navigation,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'START NAVIGATION',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        )
                      else
                        ElevatedButton(
                          onPressed: _stopTracking,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            minimumSize: const Size(double.infinity, 40),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.stop, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'STOP TRACKING',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

          // Floating action button for current location
          Positioned(
            bottom: 24,
            left: 16,
            child: Column(
              children: [
                _buildWeatherButton(),
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  heroTag: 'resolved_reports',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFAC1B22),
                  onPressed: _resolvedReports.isEmpty
                      ? null
                      : _openResolvedReportsSheet,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.history),
                      if (_resolvedReports.isNotEmpty)
                        Positioned(
                          right: -6,
                          top: -6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFAC1B22),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${_resolvedReports.length}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  backgroundColor: const Color(0xFFAC1B22),
                  onPressed: _goToCurrentLocation,
                  child: const Icon(Icons.my_location, color: Colors.white),
                ),
                if (_isTracking) ...[
                  const SizedBox(height: 16),
                  FloatingActionButton.small(
                    backgroundColor: Colors.blue,
                    onPressed: () {
                      // Simulate emergency stop
                      _stopTracking();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Route tracking stopped'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: const Icon(Icons.emergency, color: Colors.white),
                  ),
                ],
              ],
            ),
          ),

          _buildWeatherCard(),

          // Zoom controls
          Positioned(
            bottom: 24,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom_in',
                  backgroundColor: Colors.white,
                  onPressed: () {
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(
                      _mapController.camera.center,
                      currentZoom + 1,
                    );
                  },
                  child: const Icon(Icons.add, color: Color(0xFF004FC6)),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_out',
                  backgroundColor: Colors.white,
                  onPressed: () {
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(
                      _mapController.camera.center,
                      currentZoom - 1,
                    );
                  },
                  child: const Icon(Icons.remove, color: Color(0xFF004FC6)),
                ),
              ],
            ),
          ),

          // Loading overlay for route calculation
          if (_isRouting)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showRouteDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Set Destination', style: AppText.subheading),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.search),
                title: Text('Search Location', style: AppText.body),
                onTap: () {
                  Navigator.pop(context);
                  // Implement location search
                },
              ),
              ListTile(
                leading: const Icon(Icons.map),
                title: Text('Tap on Map', style: AppText.body),
                subtitle: Text(
                  'Tap anywhere on map to set destination',
                  style: AppText.caption,
                ),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tap on map to set destination'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.my_location),
                title: Text('Use Current Location', style: AppText.body),
                onTap: () {
                  Navigator.pop(context);
                  // Set destination to current location
                  _destination = _userLocation ?? _initialCenter;
                  _calculateRoute();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showFilterDialog() {
    bool showEarthquake = _showEarthquake;
    bool showFlood = _showFlood;
    bool showFire = _showFire;
    bool showVehicular = _showVehicular;
    bool showOthers = _showOthers;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget buildFilterRow({
              required String label,
              required String assetPath,
              required bool value,
              required ValueChanged<bool?> onChanged,
            }) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.appRed.withOpacity(0.15)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _buildIncidentAsset(assetPath, width: 34, height: 34),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label, style: AppText.body)),
                    Checkbox(
                      value: value,
                      onChanged: onChanged,
                      activeColor: AppTheme.appRed,
                      checkColor: Colors.white,
                    ),
                  ],
                ),
              );
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              backgroundColor: AppTheme.appOffWhite,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.appRed,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.tune,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('Filter Incidents', style: AppText.subheading),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose which incident types to display.',
                      style: AppText.caption,
                    ),
                    const SizedBox(height: 12),
                    buildFilterRow(
                      label: 'Earthquake',
                      assetPath:
                          'assets/icons/buttons/FINAL-EARTHQUAKE-ICON.svg',
                      value: showEarthquake,
                      onChanged: (value) {
                        setDialogState(() => showEarthquake = value ?? false);
                      },
                    ),
                    buildFilterRow(
                      label: 'Flood',
                      assetPath: 'assets/icons/buttons/FINAL-FLOOD-ICON.svg',
                      value: showFlood,
                      onChanged: (value) {
                        setDialogState(() => showFlood = value ?? false);
                      },
                    ),
                    buildFilterRow(
                      label: 'Fire',
                      assetPath: 'assets/icons/buttons/FINAL-FIRE-ICON.svg',
                      value: showFire,
                      onChanged: (value) {
                        setDialogState(() => showFire = value ?? false);
                      },
                    ),
                    buildFilterRow(
                      label: 'Vehicular',
                      assetPath: 'assets/icons/buttons/FINAL-CRASH-ICON.svg',
                      value: showVehicular,
                      onChanged: (value) {
                        setDialogState(() => showVehicular = value ?? false);
                      },
                    ),
                    buildFilterRow(
                      label: 'Others',
                      assetPath: 'assets/icons/buttons/FINAL-OTHERS-ICON.svg',
                      value: showOthers,
                      onChanged: (value) {
                        setDialogState(() => showOthers = value ?? false);
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.appRed,
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() {
                                _showEarthquake = showEarthquake;
                                _showFlood = showFlood;
                                _showFire = showFire;
                                _showVehicular = showVehicular;
                                _showOthers = showOthers;
                              });

                              final snapshot = _latestReportSnapshot;
                              if (snapshot != null) {
                                _applyReportSnapshot(snapshot);
                              } else {
                                _loadReportsFromFirestore();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.appRed,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _RouteResult {
  const _RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
}

class _WeatherData {
  const _WeatherData({
    required this.temperature,
    required this.max,
    required this.min,
    required this.state,
    required this.description,
  });

  final double temperature;
  final double max;
  final double min;
  final WeatherState state;
  final String description;
}
