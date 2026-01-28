import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../common/theme/app_theme.dart';

import '../../../common/services/location_service.dart';
import '../../../common/services/user_session.dart';
import '../../../common/widgets/bottom_nav_bar.dart';
import '../../home/pages/home_page.dart';

enum WeatherState { none, sunny, cloudy, rainy }

class ReportMapPage extends StatefulWidget {
  const ReportMapPage({
    super.key,
    required this.reportId,
    required this.reportData,
    this.showBottomNav = true,
  });

  final String reportId;
  final Map<String, dynamic> reportData;
  final bool showBottomNav;

  @override
  State<ReportMapPage> createState() => _ReportMapPageState();
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

class _ReportMapPageState extends State<ReportMapPage>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  final MapController _mapController = MapController();
  late final AnimationController _pinBounceController;
  WeatherState _weatherState = WeatherState.none;
  bool _showWeatherCard = false;
  bool _isWeatherLoading = false;
  String? _weatherError;
  _WeatherData? _weatherData;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _reportSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _commentsSubscription;
  bool _commentsInitialized = false;
  List<Map<String, dynamic>> _responderCommentsFallback = [];
  Map<String, dynamic>? _liveReportData;
  LatLng? _responderLocation;
  bool _resolvedDialogShown = false;
  bool _flaggedDialogShown = false;
  List<Polyline> _responderRoutePolylines = [];
  Timer? _routeDebounce;
  LatLng? _lastRouteOrigin;
  LatLng? _lastRouteDestination;
  double? _responderRouteDistanceKm;
  String? _responderRouteEta;

  // Default location (Angeles City, Central Luzon, Philippines)
  final LatLng _initialCenter = const LatLng(15.1450, 120.5887);
  final double _initialZoom = 14.0;
  static const LatLng _angelesCityCenter = LatLng(15.1450, 120.5887);
  static const double _angelesCityRadiusMeters = 6000;

  LatLng? _userLocation;
  bool _locationShared = false;
  bool _showSuccessCard = false;
  bool _showReportCard = false;
  int _navIndex = 2;

  @override
  void initState() {
    super.initState();
    _userLocation = _initialCenter;
    _pinBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _subscribeToReportUpdates();
    _subscribeToResponderComments();
    _liveReportData = Map<String, dynamic>.from(widget.reportData);

    final source = widget.reportData['locationSource'] as String?;
    final latValue = widget.reportData['locationLat'];
    final lngValue = widget.reportData['locationLng'];
    if (source == 'pin' && latValue is num && lngValue is num) {
      _userLocation = LatLng(latValue.toDouble(), lngValue.toDouble());
      _locationShared = true;
      _showReportCard = true;
      _scheduleResponderRouteUpdate();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_userLocation != null) {
          _mapController.move(_userLocation!, 16.0);
        }
      });
    } else {
      // Show location sharing modal automatically
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showLocationSharingModal();
      });
    }
  }

  @override
  void dispose() {
    _pinBounceController.dispose();
    _reportSubscription?.cancel();
    _commentsSubscription?.cancel();
    _routeDebounce?.cancel();
    super.dispose();
  }

  Future<void> _showLocationSharingModal() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.location_on, color: AppColors.appBlue, size: 28),
            const SizedBox(width: 12),
            Text('Share Location', style: AppText.subheading),
          ],
        ),
        content: Text(
          'Please share your location so emergency responders can find you quickly.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Share Location'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _shareLocation();
    } else {
      // Show report card even if location not shared
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _showReportCard = true;
          });
        }
      });
    }
  }

  Future<void> _shareLocation() async {
    try {
      final position = await LocationService.getCurrentPosition();
      if (position != null) {
        final userLatLng = LatLng(position.latitude, position.longitude);

        // Update Firestore with location
        await FirebaseFirestore.instance
            .collection('reports')
            .doc(widget.reportId)
            .update({
              'location': GeoPoint(position.latitude, position.longitude),
              'locationSharedAt': Timestamp.now(),
            });

        setState(() {
          _userLocation = userLatLng;
          _locationShared = true;
          _showSuccessCard = true;
        });
        _scheduleResponderRouteUpdate();

        // Center map on user location
        _mapController.move(userLatLng, 16.0);

        print('✅ Location shared: ${position.latitude}, ${position.longitude}');

        // Show report details card
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _showReportCard = true;
            });
          }
        });
      }
    } catch (e) {
      print('❌ Failed to share location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showIncidentInfo(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => StreamBuilder<
          DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('reports')
            .doc(widget.reportId)
            .snapshots(),
        builder: (context, snapshot) {
          final live = snapshot.data?.data();
          final merged = {
            ...data,
            if (live != null) ...live,
          };
          final incidentType =
              merged['incidentType'] as String? ?? 'Unknown';
          final reporter = merged['name'] as String? ?? 'Unknown';
          final description =
              merged['details'] as String? ??
              merged['description'] as String? ??
              'No description';
          final status = _normalizeStatusLabel(
            merged['responderStatus'] as String? ??
                merged['status'] as String? ??
                'Unverified',
          );
          final statusColor = _getStatusColor(status);

          return Dialog(
            backgroundColor: Colors.white,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      'Status: $status',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Reported by $reporter',
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1F2933),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFF4B5563),
                    ),
                  ),
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
          );
        },
      ),
    );
  }

  String _normalizeStatusLabel(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'flagged' || normalized == 'unverified') {
      return 'FLAGGED';
    }
    if (normalized == 'pending') {
      return 'PENDING';
    }
    if (normalized == 'responding') {
      return 'RESPONDING';
    }
    if (normalized == 'on scene' || normalized == 'on-scene') {
      return 'ON SCENE';
    }
    if (normalized == 'resolved' || normalized == 'incident resolved') {
      return 'RESOLVED';
    }
    return status.toUpperCase();
  }

  void _scheduleResponderRouteUpdate() {
    if (_responderLocation == null || _userLocation == null) return;
    _routeDebounce?.cancel();
    _routeDebounce = Timer(const Duration(seconds: 2), () {
      _updateResponderRoute();
    });
  }

  Future<void> _updateResponderRoute() async {
    final origin = _responderLocation;
    final destination = _userLocation;
    if (origin == null || destination == null) return;

    if (_lastRouteOrigin != null && _lastRouteDestination != null) {
      final originMoved = const Distance().as(
        LengthUnit.Meter,
        origin,
        _lastRouteOrigin!,
      );
      final destinationMoved = const Distance().as(
        LengthUnit.Meter,
        destination,
        _lastRouteDestination!,
      );
      if (originMoved < 30 && destinationMoved < 5) {
        return;
      }
    }

    _lastRouteOrigin = origin;
    _lastRouteDestination = destination;

    _RouteResult? route = await _fetchRouteFromOsrm(origin, destination);
    List<LatLng> points = route?.points ?? [];
    double? distanceKm =
        route != null ? route.distanceMeters / 1000 : null;
    String? eta = route != null
        ? _formatDurationFromSeconds(route.durationSeconds)
        : null;
    if (points.isEmpty) {
      points = _generateSimulatedRoute(origin, destination);
      distanceKm = _calculateDistance(points);
      eta = _calculateEstimatedTime(distanceKm);
    }

    if (!mounted) return;
    setState(() {
      _responderRoutePolylines = points.isEmpty
          ? []
          : [
              Polyline(
                points: points,
                color: AppColors.appOffWhite.withOpacity(0.85),
                strokeWidth: 6.0,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
              Polyline(
                points: points,
                color: AppColors.appGreen.withOpacity(0.92),
                strokeWidth: 3.5,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ];
      _responderRouteDistanceKm = points.isEmpty ? null : distanceKm;
      _responderRouteEta = points.isEmpty ? null : eta;
    });
  }

  Future<_RouteResult?> _fetchRouteFromOsrm(
    LatLng start,
    LatLng end,
  ) async {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};'
      '${end.longitude},${end.latitude}'
      '?overview=full&geometries=geojson&alternatives=true',
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
    final route = routes
        .whereType<Map<String, dynamic>>()
        .reduce((best, current) {
      final bestDistance = (best['distance'] as num?)?.toDouble() ?? double.maxFinite;
      final currentDistance =
          (current['distance'] as num?)?.toDouble() ?? double.maxFinite;
      return currentDistance < bestDistance ? current : best;
    });
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

  List<LatLng> _generateSimulatedRoute(LatLng start, LatLng end) {
    final points = <LatLng>[];
    const segments = 20;

    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      final lat = start.latitude + (end.latitude - start.latitude) * t;
      final lng = start.longitude + (end.longitude - start.longitude) * t;
      final curve = 0.001 * sin(t * pi);
      points.add(LatLng(lat + curve, lng + curve));
    }

    return points;
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
    const speedKmh = 50.0;
    final hours = distanceKm / speedKmh;
    final minutes = (hours * 60).round();
    return _formatDurationFromMinutes(minutes);
  }

  String _formatDurationFromSeconds(double seconds) {
    final minutes = (seconds / 60).round();
    return _formatDurationFromMinutes(minutes);
  }

  String _formatDurationFromMinutes(int minutes) {
    if (minutes < 60) {
      return '${minutes} min';
    }
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    if (remaining == 0) {
      return '${hours} hr';
    }
    return '${hours} hr ${remaining} min';
  }

  void _subscribeToReportUpdates() {
    _reportSubscription?.cancel();
    _reportSubscription = FirebaseFirestore.instance
        .collection('reports')
        .doc(widget.reportId)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data == null) return;
      if (mounted) {
        setState(() {
          _liveReportData = Map<String, dynamic>.from(data);
        });
      }
      final commentsRaw = data['responderComments'];
      if (commentsRaw is List) {
        final parsed = commentsRaw
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();
        parsed.sort((a, b) {
          final aTime = a['timestamp'];
          final bTime = b['timestamp'];
          final aDate = aTime is Timestamp
              ? aTime.toDate()
              : (aTime is DateTime ? aTime : DateTime.fromMillisecondsSinceEpoch(0));
          final bDate = bTime is Timestamp
              ? bTime.toDate()
              : (bTime is DateTime ? bTime : DateTime.fromMillisecondsSinceEpoch(0));
          return bDate.compareTo(aDate);
        });
        if (mounted) {
          setState(() {
            _responderCommentsFallback = parsed;
          });
        }
      }
      final status = (data['status'] as String? ?? '').toLowerCase();
      if ((status == 'resolved' || status == 'incident resolved') &&
          !_resolvedDialogShown) {
        _resolvedDialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showResolvedDialog();
        });
      }
      if ((status == 'flagged' || status == 'unverified') &&
          !_flaggedDialogShown) {
        _flaggedDialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showFlaggedDialog();
        });
      }
      final responderLoc = data['responderLocation'];
      if (responderLoc is GeoPoint) {
        final point = LatLng(responderLoc.latitude, responderLoc.longitude);
        if (!mounted) return;
        setState(() {
          _responderLocation = point;
        });
        _scheduleResponderRouteUpdate();
      }
    });
  }

  void _subscribeToResponderComments() {
    _commentsSubscription?.cancel();
    _commentsSubscription = FirebaseFirestore.instance
        .collection('reports')
        .doc(widget.reportId)
        .collection('comments')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (!_commentsInitialized) {
        _commentsInitialized = true;
        return;
      }
      if (snapshot.docChanges.isEmpty) return;
      final hasNew = snapshot.docChanges.any((change) {
        if (change.type != DocumentChangeType.added) return false;
        final data = change.doc.data();
        if (data == null) return false;
        final type = (data['type'] as String?)?.toLowerCase();
        final role = (data['role'] as String?)?.toLowerCase();
        return type == 'admin' ||
            role == 'responder' ||
            (type != 'user' && type != null);
      });
      if (!hasNew || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          duration: const Duration(seconds: 2),
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFAC1B22),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              children: [
                Icon(Icons.notifications, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'Responder posted an update',
                  style: TextStyle(
                    fontFamily: 'RobotoCondensed',
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  void _showResolvedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Incident Resolved',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Color(0xFF111827),
          ),
        ),
        content: const Text(
          'The incident has been resolved. THANK YOU',
          style: TextStyle(
            fontFamily: 'RobotoCondensed',
            fontWeight: FontWeight.w400,
            fontSize: 14,
            color: Color(0xFF4B5563),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _handleResolvedNavigation();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFAC1B22),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'RETURN',
              style: TextStyle(
                fontFamily: 'RobotoCondensed',
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFlaggedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'False Report',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Color(0xFF111827),
          ),
        ),
        content: const Text(
          'Your report has been flagged as not valid. Repeated false reports may lead to account suspension or ban.',
          style: TextStyle(
            fontFamily: 'RobotoCondensed',
            fontWeight: FontWeight.w400,
            fontSize: 14,
            color: Color(0xFF4B5563),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _handleResolvedNavigation();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFAC1B22),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'UNDERSTOOD',
              style: TextStyle(
                fontFamily: 'RobotoCondensed',
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleResolvedNavigation() {
    UserSession.removeActiveReport(widget.reportId);
    final nextReport = UserSession.latestActiveReport;
    if (nextReport != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ReportMapPage(
            reportId: nextReport.reportId,
            reportData: nextReport.reportData,
            showBottomNav: false,
          ),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const MainPage(initialIndex: 0),
      ),
    );
  }

  void _showReportSwitcher() {
    final activeReports = UserSession.activeReports;
    if (activeReports.length <= 1) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: activeReports.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final report = activeReports[index];
            final data = report.reportData;
            final title = (data['incidentType'] as String?) ?? 'Incident';
            final isCurrent = report.reportId == widget.reportId;

            return ListTile(
              title: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                report.reportId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'RobotoCondensed',
                ),
              ),
              trailing: isCurrent
                  ? const Icon(Icons.check_circle, color: Color(0xFF00A458))
                  : const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                if (isCurrent) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReportMapPage(
                      reportId: report.reportId,
                      reportData: report.reportData,
                      showBottomNav: false,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
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
    try {
      final data = await _fetchWeatherForAngeles();
      if (!mounted) return;
      setState(() {
        _weatherData = data;
        _weatherState = data.state;
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

  void _goToCurrentLocation() {
    if (_userLocation != null) {
      _mapController.move(_userLocation!, 16.0);
    }
  }

  String _weatherLabel(WeatherState state) {
    switch (state) {
      case WeatherState.sunny:
        return 'Sunny';
      case WeatherState.cloudy:
        return 'Cloudy';
      case WeatherState.rainy:
        return 'Rainy';
      case WeatherState.none:
        return '';
    }
  }

  String _formatReportedAt(Object? value) {
    if (value is Timestamp) {
      return DateFormat('MMM dd, yyyy h:mm a').format(value.toDate());
    }
    if (value is DateTime) {
      return DateFormat('MMM dd, yyyy h:mm a').format(value);
    }
    return 'Unknown';
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

  Widget _buildBouncyPin({required Widget child}) {
    return AnimatedBuilder(
      animation: _pinBounceController,
      child: child,
      builder: (context, child) {
        final eased = Curves.easeInOut.transform(_pinBounceController.value);
        final offset = sin(eased * pi) * 4;
        return Transform.translate(
          offset: Offset(0, -offset),
          child: child,
        );
      },
    );
  }

  Widget _buildResponderCommentsSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('reports')
          .doc(widget.reportId)
          .collection('comments')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Unable to load responder updates.',
              style: TextStyle(
                fontFamily: 'RobotoCondensed',
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Loading responder updates...',
              style: TextStyle(
                fontFamily: 'RobotoCondensed',
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            ),
          );
        }
        final docs = (snapshot.data?.docs ?? []).where((doc) {
          final data = doc.data();
          final type = (data['type'] as String?)?.toLowerCase();
          final role = (data['role'] as String?)?.toLowerCase();
          if (type == 'admin' || role == 'responder') {
            return true;
          }
          if (type == null) {
            return true;
          }
          return type != 'user';
        }).toList();
        final fallback = docs.isEmpty ? _responderCommentsFallback : [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Responder Updates',
              style: TextStyle(
                fontFamily: 'RobotoCondensed',
                fontWeight: FontWeight.w400,
                fontSize: 14,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            if (docs.isEmpty && fallback.isEmpty)
              const Text(
                'No responder updates yet.',
                style: TextStyle(
                  fontFamily: 'RobotoCondensed',
                  fontWeight: FontWeight.w400,
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                ),
              )
            else if (docs.isNotEmpty)
              ...docs.take(5).map((doc) {
                final data = doc.data();
                final text = data['text'] as String? ?? '';
                final timestamp = data['timestamp'] as Timestamp?;
                final timeLabel = timestamp == null
                    ? ''
                    : DateFormat('h:mm a').format(timestamp.toDate());
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: const TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontWeight: FontWeight.w400,
                          fontSize: 13,
                          color: Color(0xFF374151),
                        ),
                      ),
                      if (timeLabel.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          timeLabel,
                          style: const TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontWeight: FontWeight.w400,
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              })
            else
              ...fallback.take(5).map((data) {
                final text = data['text'] as String? ?? '';
                final timestamp = data['timestamp'];
                final date = timestamp is Timestamp
                    ? timestamp.toDate()
                    : (timestamp is DateTime
                        ? timestamp
                        : DateTime.now());
                final timeLabel = DateFormat('h:mm a').format(date);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: const TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontWeight: FontWeight.w400,
                          fontSize: 13,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        timeLabel,
                        style: const TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontWeight: FontWeight.w400,
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildWeatherButton() {
    return GestureDetector(
      onTap: _toggleWeatherCard,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
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
          border: Border.all(
            color: Colors.white.withOpacity(0.7),
            width: 1.2,
          ),
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
        ),
      ),
    );
  }

  Widget _buildWeatherCard() {
    if (!_showWeatherCard) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: 76,
      left: 16,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          child: Icon(
            _weatherIcon(data.state),
            color: const Color(0xFF2563EB),
          ),
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

  Widget _buildReportSheet(ScrollController scrollController) {
    final reportData = _liveReportData ?? widget.reportData;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: ListView(
          controller: scrollController,
          children: [
            // Drag handle to pull sheet up/down
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),

            // Header with close button (only show if responder has arrived/responded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Report Details',
                    style: GoogleFonts.roboto(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // Only show close button if responder has arrived or completed
                  if (_canDismissReport())
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.black87,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _showReportCard = false;
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    )
                  else
                    Tooltip(
                      message: 'Wait for responder to arrive',
                      child: Icon(
                        Icons.info_outline,
                        color: Colors.grey[400],
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Report image/media
                  if (widget.reportData['mediaUrl'] != null &&
                      (widget.reportData['mediaUrl'] as String).isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        reportData['mediaUrl'],
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 200,
                            color: Colors.grey[300],
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 200,
                          color: Colors.grey[300],
                          child: const Center(
                            child: Icon(Icons.image_not_supported),
                          ),
                        ),
                      ),
                    ),
                  if (widget.reportData['mediaUrl'] != null &&
                      (widget.reportData['mediaUrl'] as String).isNotEmpty)
                    const SizedBox(height: 16),

                  // Incident type badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFAC1B22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      reportData['incidentType'] ?? 'Unknown',
                      style: GoogleFonts.roboto(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Reporter details
                  Text(
                    'Reporter Information',
                    style: GoogleFonts.roboto(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _detailRow('Name', reportData['name'] ?? 'Unknown'),
                  const SizedBox(height: 8),
                  _detailRow(
                    'Contact',
                    reportData['contactNumber'] ?? 'Not provided',
                  ),
                  const SizedBox(height: 20),

                  // Date and time
                  Text(
                    'Report Details',
                    style: GoogleFonts.roboto(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _detailRow(
                    'Date & Time',
                    _formatReportedAt(reportData['reportedAt']),
                  ),
                  const SizedBox(height: 8),
                  if (reportData['mediaType'] != null)
                    _detailRow(
                      'Media Type',
                      reportData['mediaType'] == 'video'
                          ? 'Video'
                          : 'Photo',
                    ),
                  if ((reportData['incidentType'] ?? '')
                          .toString()
                          .toUpperCase() ==
                      'VEHICULAR') ...[
                    const SizedBox(height: 8),
                    _detailRow(
                      'Plate Number',
                      reportData['vehiclePlateNumber'] ?? 'Not provided',
                    ),
                    const SizedBox(height: 8),
                    _detailRow(
                      'Body Type',
                      reportData['vehicleBodyType'] ?? 'Not provided',
                    ),
                    const SizedBox(height: 8),
                    _detailRow(
                      'Color',
                      reportData['vehicleColor'] ?? 'Not provided',
                    ),
                  ],
                  if ((reportData['incidentType'] ?? '')
                          .toString()
                          .toUpperCase() ==
                      'FIRE' ||
                      (reportData['incidentType'] ?? '')
                              .toString()
                              .toUpperCase() ==
                          'FLOOD') ...[
                    const SizedBox(height: 8),
                    _detailRow(
                      'Barangay',
                      reportData['barangay'] ?? 'Not provided',
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Responder Information
                  if (reportData['responderName'] != null ||
                      reportData['responderStatus'] != null ||
                      reportData['status'] != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergency Responder',
                          style: GoogleFonts.roboto(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (reportData['responderName'] != null)
                          _detailRow(
                            'Responder',
                            reportData['responderName'],
                          ),
                        const SizedBox(height: 8),
                        if (reportData['responderStatus'] != null ||
                            reportData['status'] != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Status',
                                style: GoogleFonts.roboto(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[700],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(
                                    (reportData['responderStatus'] ??
                                            reportData['status'])
                                        ?.toString(),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  (reportData['responderStatus'] ??
                                          reportData['status'])
                                      ?.toString() ??
                                      '',
                                  style: GoogleFonts.roboto(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (_responderRouteDistanceKm != null ||
                            _responderRouteEta != null) ...[
                          const SizedBox(height: 8),
                          if (_responderRouteDistanceKm != null)
                            _detailRow(
                              'Distance',
                              '${_responderRouteDistanceKm!.toStringAsFixed(1)} km',
                            ),
                          if (_responderRouteEta != null) ...[
                            const SizedBox(height: 8),
                            _detailRow('ETA', _responderRouteEta!),
                          ],
                        ],
                        const SizedBox(height: 20),
                      ],
                    ),

                  _buildResponderCommentsSection(),

                  // Annotations
                  if (widget.reportData['annotations'] != null &&
                      (widget.reportData['annotations'] as String).isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Responder Notes',
                          style: GoogleFonts.roboto(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blue[200]!,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.note_alt,
                                color: Colors.blue[700],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.reportData['annotations'],
                                  style: GoogleFonts.roboto(
                                    fontSize: 14,
                                    color: Colors.grey[800],
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),

                  // Description
                  if (widget.reportData['details'] != null &&
                      (widget.reportData['details'] as String).isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Description',
                          style: GoogleFonts.roboto(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.reportData['details'],
                          style: GoogleFonts.roboto(
                            fontSize: 14,
                            color: Colors.grey[700],
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.roboto(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.roboto(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPeekCard() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _showReportCard = true;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFAC1B22).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.assignment, color: Color(0xFFAC1B22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Your report',
                      style: GoogleFonts.roboto(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to view details again',
                      style: GoogleFonts.roboto(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_up,
                color: Colors.black54,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _canDismissReport() {
    // Can only dismiss if responder has arrived or completed the response
    final source = _liveReportData ?? widget.reportData;
    final status = source['responderStatus']?.toString().toLowerCase() ??
        source['status']?.toString().toLowerCase();
    if (status == null) return false;

    return status.contains('arrived') ||
        status.contains('on scene') ||
        status.contains('completed') ||
        status.contains('resolved');
  }

  Color _getStatusColor(String? status) {
    if (status == null) return Colors.grey;

    final normalized = _normalizeStatusLabel(status);
    switch (normalized) {
      case 'PENDING':
        return const Color(0xFF2563EB);
      case 'RESPONDING':
        return AppColors.appRed;
      case 'ON SCENE':
        return AppColors.appBlue;
      case 'FLAGGED':
        return const Color(0xFFDC2626);
      case 'RESOLVED':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFFAC1B22);
    }
  }

  String _getMarkerAssetForIncidentType(String type) {
    switch (type.toUpperCase()) {
      case 'FIRE':
        return 'assets/icons/LOC-FIRE.png';
      case 'FLOOD':
        return 'assets/icons/LOC-FLOOD.png';
      case 'EARTHQUAKE':
        return 'assets/icons/LOC-EARTHQUAKE.png';
      case 'VEHICULAR':
        return 'assets/icons/LOC-CRASH.png';
      case 'ROAD OBSTRUCTION':
        return 'assets/icons/LOC-ROAD.png';
      default:
        return 'assets/icons/LOC-OTHERS.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // keep state when navigating tabs

    return Scaffold(
      body: Stack(
        children: [
          // OpenStreetMap
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
              minZoom: 5,
              maxZoom: 18,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.resq.emergency_app',
                maxZoom: 19,
                tileBuilder: (context, tileWidget, tile) {
                  return ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      1.05, 0.03, 0.02, 0, 10,
                      0.03, 1.05, 0.02, 0, 10,
                      0.03, 0.05, 1.02, 0, 10,
                      0, 0, 0, 1, 0,
                    ]),
                    child: tileWidget,
                  );
                },
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

              // Responder route polyline
              if (_responderRoutePolylines.isNotEmpty)
                PolylineLayer(polylines: _responderRoutePolylines),

              // User location marker
              if (_userLocation != null && _locationShared)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userLocation!,
                      width: 72,
                      height: 72,
                      child: _buildBouncyPin(
                        child: GestureDetector(
                          onTap: () => _showIncidentInfo(widget.reportData),
                          child: const Icon(
                            Icons.location_on,
                            color: Color(0xFFAC1B22),
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

              if (_responderLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _responderLocation!,
                      width: 48,
                      height: 48,
                      child: _buildBouncyPin(
                        child: const Icon(
                          Icons.directions_car,
                          color: Color(0xFF2563EB),
                          size: 34,
                        ),
                      ),
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'YOUR REPORT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          if (UserSession.activeReports.length > 1)
                            IconButton(
                              icon: const Icon(
                                Icons.swap_horiz,
                                color: Colors.white,
                              ),
                              onPressed: _showReportSwitcher,
                            ),
                          IconButton(
                            icon: const Icon(
                              Icons.my_location,
                              color: Colors.white,
                            ),
                            onPressed: _goToCurrentLocation,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Attribution overlay near the top-left
          Positioned(
            top: 72,
            left: 12,
            child: SafeArea(
              top: true,
              bottom: false,
              child: RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () {},
                  ),
                ],
                alignment: AttributionAlignment.bottomLeft,
              ),
            ),
          ),

          // Draggable report card that sits on the nav bar
          if (_showReportCard)
            Positioned.fill(
              child: DraggableScrollableSheet(
                maxChildSize: 0.92,
                initialChildSize: 0.5,
                minChildSize: 0.15,
                snap: true,
                snapSizes: const [0.15, 0.5, 0.92],
                expand: false,
                builder: (context, scrollController) =>
                    _buildReportSheet(scrollController),
              ),
            ),

          // Local peek card (comes from map page only)
          if (!_showReportCard)
            Positioned(
              left: 16,
              right: 16,
              bottom: 76, // sits just above the bottom nav bar
              child: SafeArea(top: false, child: _buildPeekCard()),
            ),

          // Success card
          if (_showSuccessCard)
            Positioned(
              top: 80,
              left: 16,
              right: 16,
              child: Card(
                elevation: 8,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Your report is posted',
                              style: GoogleFonts.roboto(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Emergency responders will be notified.',
                              style: GoogleFonts.roboto(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          setState(() {
                            _showSuccessCard = false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Positioned(
            bottom: 96,
            right: 16,
            child: Column(
              children: [
                _buildWeatherButton(),
                const SizedBox(height: 12),
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFAC1B22),
                  elevation: 4,
                  onPressed: _goToCurrentLocation,
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),

          _buildWeatherCard(),
        ],
      ),
      bottomNavigationBar: widget.showBottomNav
          ? BottomNavBar(
              currentIndex: _navIndex,
              onTap: (index) {
                if (index != _navIndex) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MainPage(initialIndex: index),
                    ),
                  );
                }
              },
            )
          : null,
    );
  }

  @override
  bool get wantKeepAlive => true;
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
