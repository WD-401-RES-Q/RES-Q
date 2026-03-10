import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../common/services/angeles_geofence_service.dart';
import '../../../common/services/frame_timing_service.dart';
import '../../../common/services/route_weather_cache_service.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/services/location_service.dart';
import '../../../common/services/user_session.dart';
import '../../../common/utils/incident_icon_resolver.dart';

void _debugLog(Object? message) {
  if (kDebugMode) {
    debugPrint('$message');
  }
}

enum WeatherState { none, sunny, cloudy, rainy }

class ResponderMapPage extends StatefulWidget {
  const ResponderMapPage({super.key, this.initialReportId});

  final String? initialReportId;

  @override
  State<ResponderMapPage> createState() => _ResponderMapPageState();
}

class AdminComment {
  final String id;
  final String text;
  final String author;
  final DateTime timestamp;
  final LatLng position;
  final String? reportId;

  AdminComment({
    required this.id,
    required this.text,
    required this.author,
    required this.timestamp,
    required this.position,
    this.reportId,
  });
}

class _ResponderIdentity {
  const _ResponderIdentity({
    required this.phone,
    required this.normalizedName,
    required this.authUid,
  });

  final String phone;
  final String normalizedName;
  final String authUid;

  bool get isEmpty =>
      phone.isEmpty && normalizedName.isEmpty && authUid.isEmpty;
}

class _ResponderMapPageState extends State<ResponderMapPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();
  final ValueNotifier<LatLng?> _trackingUserLocationNotifier =
      ValueNotifier<LatLng?>(null);
  final ValueNotifier<Offset> _weatherCardOffset = ValueNotifier(Offset.zero);
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
  _prioritySubscriptions = {};
  late final AnimationController _pinBounceController;
  bool _showWeatherCard = false;
  bool _isWeatherLoading = false;
  String? _weatherError;
  _WeatherData? _weatherData;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reportsSubscription;
  StreamSubscription<Position>? _responderLocationSub;
  Timer? _responderLocationFallbackTimer;
  String? _activeReportId;
  String? _autoAssignedReportId;
  String? _lastPresenceStatus;
  bool? _lastPresenceAvailability;
  bool _hasPrimedAssignmentAlert = false;
  String? _lastAssignmentAlertKey;
  Timer? _assignmentAlertTimer;
  bool _showAssignmentAlert = false;
  String? _assignmentAlertReportId;
  String _assignmentAlertIncidentType = 'INCIDENT';
  String _assignmentAlertBarangay = 'Angeles City';
  String _assignmentAlertDeployedBy = 'admin';

  // Default location (Angeles City, Central Luzon, Philippines)
  final LatLng _initialCenter = const LatLng(15.1450, 120.5887);
  final double _initialZoom = 14.0;

  // Sample incident markers
  final List<Marker> _incidentMarkers = [];
  final List<Marker> _reporterMarkers = [];
  final Map<String, Map<String, dynamic>> _reportsById = {};
  final Map<String, Marker> _incidentMarkerCache = {};
  final Map<String, Marker> _reporterMarkerCache = {};
  static const Duration _resolvedRetention = Duration(minutes: 10);
  final Map<String, Timer> _resolvedRemovalTimers = {};
  static const int _reportFetchLimit = 150;

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

  // Admin comments
  final List<AdminComment> _adminComments = [];

  // Simulate moving along route
  Timer? _trackingTimer;
  Timer? _viewportRefreshDebounce;
  Timer? _routeRecalcDebounce;
  bool _routeCalcInFlight = false;
  bool _routeCalcQueued = false;
  String? _pendingFocusReportId;
  bool _isOpeningPendingReport = false;
  DateTime? _lastRouteCalcAt;
  LatLng? _lastRouteCalcOrigin;
  LatLng? _lastRouteCalcDestination;
  static const Duration _routeRecalcDebounceDuration = Duration(
    milliseconds: 220,
  );
  static const Duration _routeRecalcMinInterval = Duration(milliseconds: 900);
  static const double _routeRecalcMinMoveMeters = 8.0;
  static const Duration _responderLocationWriteMinInterval = Duration(
    seconds: 2,
  );
  static const double _responderLocationWriteMinMoveMeters = 10.0;
  static const double _autoOnSceneDistanceMeters = 25.0;
  DateTime? _lastResponderLocationWriteAt;
  LatLng? _lastResponderLocationWritePoint;
  String? _lastResponderLocationWriteReportId;
  bool _isResponderLocationWriteInFlight = false;
  LatLng? _pendingResponderLocationWritePoint;
  String? _pendingResponderLocationWriteReportId;
  final Set<String> _autoOnSceneInFlightReportIds = <String>{};
  late final String _viewerRole;

  @override
  void initState() {
    super.initState();
    FrameTimingService.instance.setCurrentScreen('ResponderMapPage');
    _viewerRole = normalizeIncidentViewerRole(
      (UserSession.currentUserData?['role'] ?? 'responder').toString(),
    );
    _pendingFocusReportId = widget.initialReportId?.trim();
    _subscribeToReportsRealtime();
    // Initialize with user location (simulated)
    _userLocation = _initialCenter;
    _trackingUserLocationNotifier.value = _initialCenter;
    _syncUserLocation();
    _pinBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _startResponderLocationSharing();
    unawaited(_syncOwnPresence(status: 'available', isAvailable: true));
  }

  @override
  void didUpdateWidget(covariant ResponderMapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialReportId != oldWidget.initialReportId) {
      final nextReportId = widget.initialReportId?.trim();
      _pendingFocusReportId = (nextReportId == null || nextReportId.isEmpty)
          ? null
          : nextReportId;
      unawaited(_tryOpenPendingReport());
    }
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _viewportRefreshDebounce?.cancel();
    _routeRecalcDebounce?.cancel();
    _reportsSubscription?.cancel();
    for (final subscription in _prioritySubscriptions.values) {
      subscription.cancel();
    }
    _prioritySubscriptions.clear();
    _responderLocationSub?.cancel();
    _responderLocationFallbackTimer?.cancel();
    _assignmentAlertTimer?.cancel();
    for (final timer in _resolvedRemovalTimers.values) {
      timer.cancel();
    }
    _trackingUserLocationNotifier.dispose();
    _weatherCardOffset.dispose();
    _pinBounceController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Widget _buildIncidentMarker({
    required String assetPath,
    required Map<String, dynamic> data,
    required String reportId,
    required LatLng position,
    bool interactive = true,
    double size = 72,
    double opacity = 1,
  }) {
    final statusLower = (data['status'] as String? ?? '')
        .toString()
        .toLowerCase();
    final badge = _buildStatusBadge(statusLower, size);
    final marker = _buildBouncyPin(
      child: GestureDetector(
        onTap: () => _showIncidentInfo(data, reportId, position),
        child: Container(
          decoration: const BoxDecoration(shape: BoxShape.circle),
          child: Opacity(
            opacity: opacity,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _buildIncidentAsset(assetPath, width: size, height: size),
                if (badge != null) Positioned(right: -2, top: -2, child: badge),
              ],
            ),
          ),
        ),
      ),
    );

    if (interactive) {
      return marker;
    }

    return IgnorePointer(ignoring: true, child: marker);
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
        placeholderBuilder: (_) =>
            SizedBox(width: width, height: height, child: _missingIcon()),
      );
    }

    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => _missingIcon(),
    );
  }

  Widget _missingIcon() {
    return const Icon(
      Icons.warning_amber_rounded,
      color: Colors.white,
      size: 24,
    );
  }

  LatLng? _latLngFromDynamic(Object? raw) {
    if (raw is GeoPoint) {
      return LatLng(raw.latitude, raw.longitude);
    }
    if (raw is Map) {
      final lat = raw['latitude'] ?? raw['lat'];
      final lng = raw['longitude'] ?? raw['lng'];
      if (lat is num && lng is num) {
        return LatLng(lat.toDouble(), lng.toDouble());
      }
    }
    return null;
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
      _debugLog('Failed to load reports: $e');
    }
  }

  void _applyReportSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.docChanges.isEmpty && _reportsById.isEmpty) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        _reportsById[doc.id] = data;
        _updateMarkersForReport(reportId: doc.id, data: data);
      }
    } else {
      for (final change in snapshot.docChanges) {
        final reportId = change.doc.id;
        final data = change.doc.data();
        if (change.type == DocumentChangeType.removed || data == null) {
          _reportsById.remove(reportId);
          _incidentMarkerCache.remove(reportId);
          _cancelResolvedRemoval(reportId);
          continue;
        }
        _reportsById[reportId] = data;
        _updateMarkersForReport(reportId: reportId, data: data);
      }
    }

    _syncPriorityFieldListeners();

    if (!mounted) return;
    setState(_refreshMarkerLists);
    _syncAutoAssignedReport(snapshot);
    unawaited(_tryOpenPendingReport());
    _debugLog('Loaded ${_reportsById.length} reports from Firestore');
  }

  String _priorityValueFromReport(Map<String, dynamic> data) {
    final candidates = <Object?>[
      data['priority'],
      data['deploymentPriority'],
      data['priorityLabel'],
      data['verdictPriority'],
      data['severity'],
    ];

    for (final candidate in candidates) {
      if (candidate == null) continue;
      final normalized = normalizeIncidentPriority(candidate.toString());
      if (normalized != 'NONE') {
        return normalized;
      }
    }
    return 'NONE';
  }

  String _resolveIncidentIconForReport({
    required String incidentType,
    required Map<String, dynamic> data,
  }) {
    return resolveIncidentIcon(
      incidentType,
      _priorityValueFromReport(data),
      _viewerRole,
    );
  }

  bool get _usesPriorityDrivenIcons => _viewerRole != 'user';

  void _syncPriorityFieldListeners() {
    final reportIds = _reportsById.entries
        .where((entry) => _isAssignedToCurrentResponder(entry.value))
        .map((entry) => entry.key)
        .toSet();
    final staleIds = _prioritySubscriptions.keys
        .where((id) => !reportIds.contains(id))
        .toList();

    for (final id in staleIds) {
      _prioritySubscriptions.remove(id)?.cancel();
    }

    if (!_usesPriorityDrivenIcons) {
      for (final subscription in _prioritySubscriptions.values) {
        subscription.cancel();
      }
      _prioritySubscriptions.clear();
      return;
    }

    for (final id in reportIds) {
      _prioritySubscriptions[id] ??= FirebaseFirestore.instance
          .collection('reports')
          .doc(id)
          .snapshots()
          .listen(
            (snapshot) {
              if (!mounted) return;

              final data = snapshot.data();
              if (data == null) {
                _reportsById.remove(id);
                _incidentMarkerCache.remove(id);
                _reporterMarkerCache.remove(id);
                _prioritySubscriptions.remove(id)?.cancel();
                setState(_refreshMarkerLists);
                return;
              }

              final existing = _reportsById[id];
              if (existing == null) return;

              final previousPriority = _priorityValueFromReport(existing);
              final nextPriority = _priorityValueFromReport(data);
              if (previousPriority == nextPriority) {
                return;
              }

              _reportsById[id] = data;
              _updateMarkersForReport(reportId: id, data: data);
              setState(_refreshMarkerLists);
            },
            onError: (error) {
              _debugLog('Priority listener failed for report $id: $error');
            },
          );
    }
  }

  Future<void> _tryOpenPendingReport() async {
    final reportId = _pendingFocusReportId;
    if (!mounted ||
        _isOpeningPendingReport ||
        reportId == null ||
        reportId.isEmpty) {
      return;
    }

    final data = _reportsById[reportId];
    if (data == null || !_isAssignedToCurrentResponder(data)) {
      return;
    }

    final incidentPoint =
        _latLngFromDynamic(data['incidentLocation']) ??
        _latLngFromDynamic(data['location']);
    if (incidentPoint == null) {
      _pendingFocusReportId = null;
      return;
    }

    _isOpeningPendingReport = true;
    _pendingFocusReportId = null;

    try {
      _activeReportId = reportId;
      _destination = incidentPoint;
      _scheduleRouteCalculation();
      try {
        final targetZoom = _mapController.camera.zoom < 15
            ? 15.0
            : _mapController.camera.zoom;
        _mapController.move(incidentPoint, targetZoom);
      } catch (_) {}

      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      await _showIncidentInfo(data, reportId, incidentPoint);
    } finally {
      _isOpeningPendingReport = false;
    }
  }

  void _updateMarkersForReport({
    required String reportId,
    required Map<String, dynamic> data,
  }) {
    if (!_isAssignedToCurrentResponder(data)) {
      _incidentMarkerCache.remove(reportId);
      _reporterMarkerCache.remove(reportId);
      return;
    }

    final incidentPoint =
        _latLngFromDynamic(data['incidentLocation']) ??
        _latLngFromDynamic(data['location']);
    if (incidentPoint == null) {
      _incidentMarkerCache.remove(reportId);
      _reporterMarkerCache.remove(reportId);
      return;
    }

    final status = (data['status'] as String? ?? '').toLowerCase();
    final incidentType = data['incidentType'] as String? ?? 'Unknown';
    final shouldShowType = _shouldShowIncidentType(incidentType);
    final resolvedAt = _parseResolvedAt(data);
    final approvedAt = _parseApprovedAt(data);
    final isResolved = _isResolvedStatus(status);
    final isApproved = _isApprovedStatus(status);
    final isFlagged = _isFlaggedStatus(status);

    if (isResolved || isApproved) {
      final inactiveAt =
          (isResolved ? resolvedAt : approvedAt) ?? _parseReportedAt(data);
      final shouldKeep = _shouldKeepResolved(reportId, inactiveAt);
      if (!shouldKeep) {
        _incidentMarkerCache.remove(reportId);
        _reporterMarkerCache.remove(reportId);
        return;
      }
    } else {
      _cancelResolvedRemoval(reportId);
    }

    if (!shouldShowType) {
      _incidentMarkerCache.remove(reportId);
      _reporterMarkerCache.remove(reportId);
      return;
    }

    final isCheckStatus = isResolved || isApproved || isFlagged;
    final markerSize = isCheckStatus ? 56.0 : 72.0;
    _incidentMarkerCache[reportId] = Marker(
      key: ValueKey('incident-$reportId'),
      point: incidentPoint,
      width: markerSize,
      height: markerSize,
      child: _buildIncidentMarker(
        assetPath: _resolveIncidentIconForReport(
          incidentType: incidentType,
          data: data,
        ),
        data: data,
        reportId: reportId,
        position: incidentPoint,
        interactive: true,
        size: markerSize,
        opacity: isCheckStatus ? 0.82 : 1,
      ),
    );
    _reporterMarkerCache.remove(reportId);
  }

  void _rebuildMarkersFromCache() {
    _incidentMarkerCache.clear();
    _reporterMarkerCache.clear();
    for (final entry in _reportsById.entries) {
      _updateMarkersForReport(reportId: entry.key, data: entry.value);
    }
    _refreshMarkerLists();
  }

  void _refreshMarkerLists() {
    final visibleBounds = _safeVisibleBounds();
    _incidentMarkers
      ..clear()
      ..addAll(
        _incidentMarkerCache.values.where(
          (marker) => _isMarkerVisible(marker, visibleBounds),
        ),
      );
    _reporterMarkers.clear();
  }

  LatLngBounds? _safeVisibleBounds() {
    try {
      return _mapController.camera.visibleBounds;
    } catch (_) {
      return null;
    }
  }

  bool _isMarkerVisible(Marker marker, LatLngBounds? bounds) {
    if (bounds == null) {
      return true;
    }
    return bounds.contains(marker.point);
  }

  void _scheduleViewportMarkerRefresh() {
    _viewportRefreshDebounce?.cancel();
    _viewportRefreshDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(_refreshMarkerLists);
    });
  }

  String _normalizePhoneValue(Object? raw) {
    return (raw?.toString() ?? '').replaceAll(RegExp(r'\D'), '');
  }

  _ResponderIdentity _currentResponderIdentity() {
    final userData = UserSession.currentUserData;
    final phone = _normalizePhoneValue(
      userData?['contactNumber'] ?? userData?['phoneNumber'],
    );
    final normalizedName =
        (userData?['fullName'] ?? userData?['username'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();

    return _ResponderIdentity(
      phone: phone,
      normalizedName: normalizedName,
      authUid: authUid,
    );
  }

  bool _isAssignedToCurrentResponder(Map<String, dynamic> data) {
    final identity = _currentResponderIdentity();
    if (identity.isEmpty) {
      return false;
    }

    final assignedId = (data['responderId'] as String? ?? '').trim();
    final assignedIdPhone = _normalizePhoneValue(assignedId);
    final assignedContactPhone = _normalizePhoneValue(
      data['responderContactNumber'] ?? data['responderPhone'],
    );
    final assignedName = (data['responderName'] as String? ?? '')
        .trim()
        .toLowerCase();

    final matchesPhone =
        identity.phone.isNotEmpty &&
        (assignedIdPhone == identity.phone ||
            assignedContactPhone == identity.phone);
    final matchesUid =
        identity.authUid.isNotEmpty && assignedId == identity.authUid;
    final matchesName =
        identity.normalizedName.isNotEmpty &&
        assignedName.isNotEmpty &&
        assignedName == identity.normalizedName;

    return matchesPhone || matchesUid || matchesName;
  }

  String _normalizeStatusKey(String status) {
    return status
        .trim()
        .toLowerCase()
        .replaceAll('-', ' ')
        .replaceAll('_', ' ');
  }

  bool _isFlaggedStatus(String status) {
    final normalized = _normalizeStatusKey(status);
    return normalized == 'flagged' ||
        normalized == 'unverified' ||
        normalized == 'admin flagged';
  }

  bool _isResolvedStatus(String status) {
    final normalized = _normalizeStatusKey(status);
    return normalized == 'resolved' || normalized == 'incident resolved';
  }

  bool _isApprovedStatus(String status) {
    final normalized = _normalizeStatusKey(status);
    return normalized == 'approved';
  }

  bool _isClosedIncidentStatus(String status) {
    return _isResolvedStatus(status) ||
        _isFlaggedStatus(status) ||
        _isApprovedStatus(status);
  }

  bool _isVerdictLockedStatus(String status) {
    return _isResolvedStatus(status) ||
        _isFlaggedStatus(status) ||
        _isApprovedStatus(status);
  }

  DateTime _parseSortTimestamp(Object? raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _syncOwnPresence({
    required String status,
    required bool isAvailable,
  }) async {
    final normalizedStatus = status.trim().toLowerCase();
    if (_lastPresenceStatus == normalizedStatus &&
        _lastPresenceAvailability == isAvailable) {
      return;
    }

    final userData = UserSession.currentUserData;
    final docId =
        (userData?['id'] ?? userData?['contactNumber'])?.toString().trim() ??
        '';
    if (docId.isEmpty) {
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('responders').doc(docId).set({
        'isLoggedIn': true,
        'status': normalizedStatus,
        'isAvailable': isAvailable,
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _lastPresenceStatus = normalizedStatus;
      _lastPresenceAvailability = isAvailable;
    } catch (e) {
      _debugLog('Failed to sync responder presence: $e');
    }
  }

  void _syncAutoAssignedReport(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final identity = _currentResponderIdentity();
    if (identity.isEmpty) {
      return;
    }

    String? matchedReportId;
    LatLng? matchedDestination;
    Map<String, dynamic>? matchedData;
    DateTime latestAssignedAt = DateTime.fromMillisecondsSinceEpoch(0);

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status =
          (data['responderStatus'] as String? ??
                  data['status'] as String? ??
                  '')
              .toLowerCase();
      if (_isClosedIncidentStatus(status)) {
        continue;
      }

      if (!_isAssignedToCurrentResponder(data)) {
        continue;
      }

      final incidentPoint =
          _latLngFromDynamic(data['incidentLocation']) ??
          _latLngFromDynamic(data['location']);
      if (incidentPoint == null) {
        continue;
      }

      final assignedAt = _parseSortTimestamp(
        data['responderAssignedAt'] ??
            data['deployedAt'] ??
            data['respondingAt'] ??
            data['reportedAt'],
      );
      if (assignedAt.isBefore(latestAssignedAt)) {
        continue;
      }

      latestAssignedAt = assignedAt;
      matchedReportId = doc.id;
      matchedDestination = incidentPoint;
      matchedData = data;
    }

    if (matchedReportId == null || matchedDestination == null) {
      _autoAssignedReportId = null;
      _activeReportId = null;
      if (!_hasPrimedAssignmentAlert) {
        _hasPrimedAssignmentAlert = true;
      }
      if (_destination != null ||
          _routeMarkers.isNotEmpty ||
          _routePolylines.isNotEmpty ||
          _routePoints.isNotEmpty) {
        if (mounted) {
          setState(() {
            _destination = null;
            _routeMarkers.clear();
            _routePolylines.clear();
            _routePoints.clear();
            _routeInstructions = '';
            _estimatedDistance = 0;
            _estimatedTime = '';
          });
        } else {
          _destination = null;
          _routeMarkers.clear();
          _routePolylines.clear();
          _routePoints.clear();
          _routeInstructions = '';
          _estimatedDistance = 0;
          _estimatedTime = '';
        }
      }
      unawaited(_syncOwnPresence(status: 'available', isAvailable: true));
      return;
    }

    final shouldRefreshRoute =
        _autoAssignedReportId != matchedReportId ||
        _activeReportId != matchedReportId ||
        _destination == null ||
        const Distance().as(
              LengthUnit.Meter,
              _destination!,
              matchedDestination,
            ) >
            20;

    _autoAssignedReportId = matchedReportId;
    if (matchedData != null) {
      _maybeShowAssignmentAlert(
        reportId: matchedReportId,
        data: matchedData,
        assignedAt: latestAssignedAt,
      );
    }
    unawaited(_syncOwnPresence(status: 'busy', isAvailable: false));
    if (!shouldRefreshRoute) {
      return;
    }

    if (mounted) {
      setState(() {
        _activeReportId = matchedReportId;
        _destination = matchedDestination;
      });
    } else {
      _activeReportId = matchedReportId;
      _destination = matchedDestination;
    }

    _scheduleRouteCalculation();
  }

  String _buildAssignmentAlertKey({
    required String reportId,
    required DateTime assignedAt,
  }) {
    return '$reportId|${assignedAt.millisecondsSinceEpoch}';
  }

  Future<void> _playAssignmentAlertCue() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  void _dismissAssignmentAlert() {
    if (!mounted) {
      _showAssignmentAlert = false;
      return;
    }
    setState(() {
      _showAssignmentAlert = false;
    });
  }

  void _openAssignmentReportFromBubble() {
    final reportId = _assignmentAlertReportId;
    if (reportId == null || reportId.isEmpty) {
      return;
    }
    _pendingFocusReportId = reportId;
    _dismissAssignmentAlert();
    unawaited(_tryOpenPendingReport());
  }

  void _maybeShowAssignmentAlert({
    required String reportId,
    required Map<String, dynamic> data,
    required DateTime assignedAt,
  }) {
    final alertKey = _buildAssignmentAlertKey(
      reportId: reportId,
      assignedAt: assignedAt,
    );

    if (!_hasPrimedAssignmentAlert) {
      _hasPrimedAssignmentAlert = true;
      _lastAssignmentAlertKey = alertKey;
      return;
    }
    if (_lastAssignmentAlertKey == alertKey) {
      return;
    }
    _lastAssignmentAlertKey = alertKey;

    final incidentType = (data['incidentType'] as String? ?? 'Incident').trim();
    final barangay = (data['barangay'] as String? ?? 'Angeles City').trim();
    final deployedBy = (data['deployedBy'] as String? ?? 'Admin').trim();

    _assignmentAlertTimer?.cancel();
    if (mounted) {
      setState(() {
        _assignmentAlertReportId = reportId;
        _assignmentAlertIncidentType = incidentType.toUpperCase();
        _assignmentAlertBarangay = barangay.isEmpty ? 'Angeles City' : barangay;
        _assignmentAlertDeployedBy = deployedBy.isEmpty ? 'Admin' : deployedBy;
        _showAssignmentAlert = true;
      });
    } else {
      _assignmentAlertReportId = reportId;
      _assignmentAlertIncidentType = incidentType.toUpperCase();
      _assignmentAlertBarangay = barangay.isEmpty ? 'Angeles City' : barangay;
      _assignmentAlertDeployedBy = deployedBy.isEmpty ? 'Admin' : deployedBy;
      _showAssignmentAlert = true;
    }

    unawaited(_playAssignmentAlertCue());
    _assignmentAlertTimer = Timer(const Duration(seconds: 9), () {
      _dismissAssignmentAlert();
    });
  }

  Widget _buildAssignmentAlertBubble() {
    if (!_showAssignmentAlert || _assignmentAlertReportId == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 84,
      left: 14,
      right: 14,
      child: AnimatedOpacity(
        opacity: _showAssignmentAlert ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _openAssignmentReportFromBubble,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.appOffWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.appOffYellow, width: 1.3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4E9EA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: AppColors.appRed,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.appRed,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _assignmentAlertIncidentType,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Roboto',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Assigned report received',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w700,
                            color: AppColors.appBlack,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Deployed by $_assignmentAlertDeployedBy · $_assignmentAlertBarangay',
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 13,
                            color: AppColors.appBlack,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _dismissAssignmentAlert,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.appBlack,
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

  DateTime? _parseDateTimeValue(Object? raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  DateTime? _parseResolvedAt(Map<String, dynamic> data) {
    return _parseDateTimeValue(data['resolvedAt']) ??
        _parseDateTimeValue(data['responderStatusUpdatedAt']) ??
        _parseDateTimeValue(data['statusUpdatedAt']) ??
        _parseDateTimeValue(data['updatedAt']);
  }

  DateTime? _parseApprovedAt(Map<String, dynamic> data) {
    return _parseDateTimeValue(data['approvedAt']) ??
        _parseDateTimeValue(data['statusUpdatedAt']) ??
        _parseDateTimeValue(data['updatedAt']) ??
        _parseDateTimeValue(data['responderStatusUpdatedAt']);
  }

  DateTime? _parseReportedAt(Map<String, dynamic> data) {
    return _parseDateTimeValue(data['reportedAt']) ??
        _parseDateTimeValue(data['createdAt']);
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

  Widget? _buildStatusBadge(String statusLower, double markerSize) {
    final normalized = _normalizeStatusKey(statusLower);
    final isResolved = _isResolvedStatus(statusLower);
    final isApproved = _isApprovedStatus(statusLower);
    final isFlagged = _isFlaggedStatus(statusLower);
    final isAttention =
        normalized == 'pending' ||
        normalized == 'on scene' ||
        normalized == 'responding';

    if (!isResolved && !isApproved && !isAttention && !isFlagged) return null;

    final badgeSize = markerSize <= 60 ? 14.0 : 16.0;
    final iconSize = markerSize <= 60 ? 10.0 : 12.0;
    final color = (isResolved || isApproved)
        ? const Color(0xFF00A458)
        : isFlagged
        ? const Color(0xFFDC2626)
        : const Color(0xFFAC1B22);
    final icon = (isResolved || isApproved)
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

  Widget _buildBouncyPin({required Widget child}) {
    return AnimatedBuilder(
      animation: _pinBounceController,
      child: child,
      builder: (context, child) {
        final eased = Curves.easeInOut.transform(_pinBounceController.value);
        final offset = sin(eased * pi) * 4;
        return Transform.translate(offset: Offset(0, -offset), child: child);
      },
    );
  }

  Future<void> _toggleWeatherCard() async {
    if (_showWeatherCard) {
      setState(() {
        _showWeatherCard = false;
      });
      _weatherCardOffset.value = Offset.zero;
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
          const horizontalThreshold = 80.0;
          const verticalThreshold = -50.0;

          if (currentOffset.dx.abs() > horizontalThreshold ||
              currentOffset.dy < verticalThreshold) {
            setState(() {
              _showWeatherCard = false;
            });
          }
          _weatherCardOffset.value = Offset.zero;
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
                offset.dy.clamp(-100.0, 20.0),
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
    final json = await RouteWeatherCacheService.fetchAngelesWeatherJson();
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

  Future<void> _postAdminComment({
    required String reportId,
    required String text,
    required LatLng position,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final responderName =
        (UserSession.currentUserData?['fullName'] ??
                UserSession.currentUserData?['username'] ??
                'Responder')
            .toString()
            .trim();

    try {
      final commentPayload = {
        'text': trimmed,
        'author': responderName,
        'type': 'admin',
        'role': 'responder',
        'timestamp': Timestamp.now(),
      };
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .add(commentPayload);

      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .update({
            'responderComments': FieldValue.arrayUnion([commentPayload]),
          });

      if (!mounted) return;
      setState(() {
        _adminComments.add(
          AdminComment(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: trimmed,
            author: responderName,
            timestamp: DateTime.now(),
            position: position,
            reportId: reportId,
          ),
        );
      });

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
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'Comment posted on this incident',
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to post comment: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _updateIncidentStatus(String reportId, String status) async {
    try {
      final statusLower = status.trim().toLowerCase();
      final latestDoc = await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .get();
      final latestData = latestDoc.data();
      final latestStatusRaw =
          (latestData?['responderStatus'] ?? latestData?['status'] ?? '')
              .toString();
      if (_isVerdictLockedStatus(latestStatusRaw)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(
                'Status is locked by final verdict and can no longer be changed.',
              ),
              backgroundColor: Color(0xFF6B7280),
            ),
          );
        }
        return false;
      }

      if (_isDuplicateStatusWrite(reportId, statusLower)) {
        return true;
      }
      final now = Timestamp.now();
      final responderName =
          UserSession.currentUserData?['fullName'] as String? ??
          UserSession.currentUserData?['username'] as String? ??
          'Responder';

      if (statusLower == 'resolved' || statusLower == 'incident resolved') {
        return _markIncidentResolved(reportId);
      }
      if (statusLower == 'flagged' || statusLower == 'unverified') {
        await FirebaseFirestore.instance
            .collection('reports')
            .doc(reportId)
            .update({
              'status': 'FLAGGED',
              'responderStatus': 'FLAGGED',
              'flaggedAt': now,
              'flaggedBy': responderName,
              'resolvedAt': FieldValue.delete(),
              'resolvedBy': FieldValue.delete(),
              'responderStatusUpdatedAt': now,
              'responderStatusUpdatedBy': responderName,
            });
        _cancelResolvedRemoval(reportId);
        _scheduleResolvedRemoval(reportId, DateTime.now(), Duration.zero);
        return true;
      }

      if (statusLower == 'responding') {
        await FirebaseFirestore.instance
            .collection('reports')
            .doc(reportId)
            .update({
              'status': 'RESPONDING',
              'responderStatus': 'RESPONDING',
              'respondingAt': now,
              'respondingBy': responderName,
              'responderStatusUpdatedAt': now,
              'responderStatusUpdatedBy': responderName,
              'resolvedAt': FieldValue.delete(),
              'resolvedBy': FieldValue.delete(),
              'flaggedAt': FieldValue.delete(),
              'flaggedBy': FieldValue.delete(),
            });
        _cancelResolvedRemoval(reportId);
        return true;
      }

      if (statusLower == 'on scene' || statusLower == 'on-scene') {
        await FirebaseFirestore.instance
            .collection('reports')
            .doc(reportId)
            .update({
              'status': 'ON SCENE',
              'responderStatus': 'ON SCENE',
              'arrivedAt': now,
              'arrivedBy': responderName,
              'responderStatusUpdatedAt': now,
              'responderStatusUpdatedBy': responderName,
              'resolvedAt': FieldValue.delete(),
              'resolvedBy': FieldValue.delete(),
              'flaggedAt': FieldValue.delete(),
              'flaggedBy': FieldValue.delete(),
            });
        _cancelResolvedRemoval(reportId);
        return true;
      }

      final normalizedStatus = _normalizeStatusLabel(status);
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .update({
            'status': normalizedStatus,
            'responderStatus': normalizedStatus,
            'responderStatusUpdatedAt': now,
            'responderStatusUpdatedBy': responderName,
            'resolvedAt': FieldValue.delete(),
            'resolvedBy': FieldValue.delete(),
            'flaggedAt': FieldValue.delete(),
            'flaggedBy': FieldValue.delete(),
          });
      _cancelResolvedRemoval(reportId);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _markIncidentResolved(String reportId) async {
    final resolvedTime = DateTime.now();
    final resolvedAt = Timestamp.fromDate(resolvedTime);
    final responderName =
        UserSession.currentUserData?['fullName'] as String? ??
        UserSession.currentUserData?['username'] as String? ??
        'Responder';
    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .update({
            'status': 'RESOLVED',
            'responderStatus': 'RESOLVED',
            'resolvedAt': resolvedAt,
            'resolvedBy': responderName,
            'flaggedAt': FieldValue.delete(),
            'flaggedBy': FieldValue.delete(),
            'responderStatusUpdatedAt': resolvedAt,
            'responderStatusUpdatedBy': responderName,
          });
      _cancelResolvedRemoval(reportId);
      _scheduleResolvedRemoval(reportId, resolvedTime, Duration.zero);
      if (_activeReportId == reportId) {
        _activeReportId = null;
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to resolve incident: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  void _removeIncidentMarker(String reportId) {
    if (!mounted) return;
    setState(() {
      _incidentMarkerCache.remove(reportId);
      _reporterMarkerCache.remove(reportId);
      _refreshMarkerLists();
    });
    _cancelResolvedRemoval(reportId);
  }

  Future<void> _startResponderLocationSharing() async {
    final hasPermission = await LocationService.requestLocationPermission();
    if (!hasPermission) return;
    _responderLocationSub?.cancel();
    _responderLocationFallbackTimer?.cancel();
    try {
      _responderLocationSub =
          LocationService.getPositionStream(distanceFilterMeters: 5).listen(
            _handleResponderLocationPosition,
            onError: (Object error, StackTrace stackTrace) {
              _debugLog('Responder location stream error: $error');
              _startResponderLocationPollingFallback();
            },
            onDone: _startResponderLocationPollingFallback,
          );
    } catch (e) {
      _debugLog('Failed to start responder location stream: $e');
      _startResponderLocationPollingFallback();
    }
  }

  void _handleResponderLocationPosition(Position position) {
    final point = LatLng(position.latitude, position.longitude);
    _userLocation = point;
    _trackingUserLocationNotifier.value = point;
    final reportId = _activeReportId;
    if (reportId == null) return;
    _scheduleResponderLocationWrite(reportId: reportId, point: point);
    _evaluateAutoOnSceneProximity(reportId: reportId, point: point);
  }

  void _evaluateAutoOnSceneProximity({
    required String reportId,
    required LatLng point,
  }) {
    final reportData = _reportsById[reportId];
    if (reportData == null) {
      return;
    }
    if (!_isAssignedToCurrentResponder(reportData)) {
      return;
    }
    final statusRaw =
        (reportData['responderStatus'] ?? reportData['status'] ?? '')
            .toString();
    if (_isClosedIncidentStatus(statusRaw)) {
      return;
    }
    if (_normalizeStatusKey(statusRaw) == 'on scene') {
      return;
    }
    if (_autoOnSceneInFlightReportIds.contains(reportId)) {
      return;
    }

    final incidentPoint =
        _latLngFromDynamic(reportData['incidentLocation']) ??
        _latLngFromDynamic(reportData['location']);
    if (incidentPoint == null) {
      return;
    }

    final distanceMeters = const Distance().as(
      LengthUnit.Meter,
      point,
      incidentPoint,
    );
    if (distanceMeters > _autoOnSceneDistanceMeters) {
      return;
    }

    reportData['status'] = 'ON SCENE';
    reportData['responderStatus'] = 'ON SCENE';
    _autoOnSceneInFlightReportIds.add(reportId);
    unawaited(
      _updateIncidentStatus(reportId, 'ON SCENE').whenComplete(() {
        _autoOnSceneInFlightReportIds.remove(reportId);
      }),
    );
  }

  void _startResponderLocationPollingFallback() {
    _responderLocationFallbackTimer?.cancel();
    _responderLocationFallbackTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) async {
        final position = await LocationService.getCurrentPosition();
        if (position == null) {
          return;
        }
        if (!mounted) return;
        _handleResponderLocationPosition(position);
      },
    );
  }

  void _scheduleResponderLocationWrite({
    required String reportId,
    required LatLng point,
  }) {
    _pendingResponderLocationWriteReportId = reportId;
    _pendingResponderLocationWritePoint = point;
    if (_isResponderLocationWriteInFlight) {
      return;
    }
    unawaited(_flushResponderLocationWrite());
  }

  Future<void> _flushResponderLocationWrite() async {
    final reportId = _pendingResponderLocationWriteReportId;
    final point = _pendingResponderLocationWritePoint;
    if (reportId == null || point == null) {
      return;
    }

    _pendingResponderLocationWriteReportId = null;
    _pendingResponderLocationWritePoint = null;

    final now = DateTime.now();
    final lastWriteAt = _lastResponderLocationWriteAt;
    final lastPoint = _lastResponderLocationWritePoint;
    final sameReport = _lastResponderLocationWriteReportId == reportId;
    final movedMeters = lastPoint == null
        ? double.infinity
        : const Distance().as(LengthUnit.Meter, lastPoint, point);
    final elapsed = lastWriteAt == null
        ? _responderLocationWriteMinInterval
        : now.difference(lastWriteAt);

    if (sameReport &&
        elapsed < _responderLocationWriteMinInterval &&
        movedMeters < _responderLocationWriteMinMoveMeters) {
      return;
    }

    _isResponderLocationWriteInFlight = true;
    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .update({
            'responderLocation': GeoPoint(point.latitude, point.longitude),
            'responderLocationLat': point.latitude,
            'responderLocationLng': point.longitude,
            'responderLocationUpdatedAt': Timestamp.now(),
          });
      _lastResponderLocationWriteAt = DateTime.now();
      _lastResponderLocationWritePoint = point;
      _lastResponderLocationWriteReportId = reportId;
    } catch (e) {
      _debugLog('Failed to sync responder location: $e');
    } finally {
      _isResponderLocationWriteInFlight = false;
      if (_pendingResponderLocationWriteReportId != null &&
          _pendingResponderLocationWritePoint != null) {
        unawaited(_flushResponderLocationWrite());
      }
    }
  }

  String _canonicalResponderStatus(String status) {
    final normalized = _normalizeStatusKey(status);
    switch (normalized) {
      case 'resolved':
      case 'incident resolved':
        return 'RESOLVED';
      case 'flagged':
      case 'unverified':
      case 'admin flagged':
        return 'FLAGGED';
      case 'responding':
        return 'RESPONDING';
      case 'on scene':
        return 'ON SCENE';
      case 'pending':
        return 'PENDING';
      case 'approved':
        return 'APPROVED';
      default:
        return _normalizeStatusLabel(status);
    }
  }

  bool _isDuplicateStatusWrite(String reportId, String requestedStatus) {
    final reportData = _reportsById[reportId];
    if (reportData == null) {
      return false;
    }
    final currentStatus =
        (reportData['responderStatus'] ?? reportData['status'])?.toString();
    if (currentStatus == null || currentStatus.trim().isEmpty) {
      return false;
    }
    return _canonicalResponderStatus(currentStatus) ==
        _canonicalResponderStatus(requestedStatus);
  }

  void _subscribeToReportsRealtime() {
    _reportsSubscription?.cancel();
    _reportsSubscription = FirebaseFirestore.instance
        .collection('reports')
        .orderBy('reportedAt', descending: true)
        .limit(_reportFetchLimit)
        .snapshots()
        .listen(
          _applyReportSnapshot,
          onError: (error) {
            _debugLog('Failed to subscribe to report updates: $error');
          },
        );
  }

  void _showIncidentCommentDialog(String reportId, LatLng position) {
    final TextEditingController commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                      Icons.comment,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'ADD COMMENT',
                      style: TextStyle(
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
              TextField(
                controller: commentController,
                maxLines: 4,
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Write your update...',
                  hintStyle: const TextStyle(fontFamily: 'Roboto'),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (commentController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a comment')),
                      );
                      return;
                    }
                    Navigator.pop(context);
                    _postAdminComment(
                      reportId: reportId,
                      text: commentController.text,
                      position: position,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAC1B22),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'POST COMMENT',
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
    );
  }

  Future<void> _callReporter(String rawPhoneNumber) async {
    final normalized = _normalizePhoneValue(rawPhoneNumber);
    if (normalized.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reporter contact number is unavailable.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String dialable = rawPhoneNumber.trim();
    if (dialable.isEmpty || dialable.toLowerCase() == 'unknown') {
      if (normalized.length == 10 && normalized.startsWith('9')) {
        dialable = '+63$normalized';
      } else if (normalized.startsWith('63')) {
        dialable = '+$normalized';
      } else {
        dialable = normalized;
      }
    }

    final uri = Uri(scheme: 'tel', path: dialable);
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to start a phone call on this device.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to launch dialer: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showIncidentInfo(
    Map<String, dynamic> data,
    String reportId,
    LatLng position,
  ) async {
    Map<String, dynamic> activeData = data;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .get();
      if (doc.data() != null) {
        activeData = doc.data()!;
      }
    } catch (_) {}

    final incidentType = activeData['incidentType'] as String? ?? 'Unknown';
    final reporter = activeData['name'] as String? ?? 'Unknown';
    final description =
        activeData['details'] as String? ??
        activeData['description'] as String? ??
        '';
    final contactNumber = activeData['contactNumber'] as String? ?? 'Unknown';
    final canCallReporter = _normalizePhoneValue(contactNumber).isNotEmpty;
    final vehiclePlateNumber =
        activeData['vehiclePlateNumber'] as String? ?? 'Not provided';
    final vehicleBodyType =
        activeData['vehicleBodyType'] as String? ?? 'Not provided';
    final vehicleColor =
        activeData['vehicleColor'] as String? ?? 'Not provided';
    final barangay = activeData['barangay'] as String? ?? 'Not provided';
    final incidentLocation =
        _latLngFromDynamic(activeData['incidentLocation']) ??
        _latLngFromDynamic(activeData['location']) ??
        position;
    final reporterLocation = _latLngFromDynamic(activeData['reporterLocation']);
    final responderLocation = _latLngFromDynamic(
      activeData['responderLocation'],
    );
    final reportedAt = activeData['reportedAt'];
    String? reportedAtLabel;
    if (reportedAt is Timestamp) {
      final date = reportedAt.toDate();
      reportedAtLabel =
          '${date.month}/${date.day}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    final mediaUrl = activeData['mediaUrl'] as String?;
    final mediaType = (activeData['mediaType'] as String?)?.toLowerCase();
    const incidentMediaHeight = 140.0;
    final incidentUpper = incidentType.toUpperCase();
    final isVehicular = incidentUpper == 'VEHICULAR';
    final isFireOrFlood = incidentUpper == 'FIRE' || incidentUpper == 'FLOOD';
    _activeReportId = reportId;
    _destination = incidentLocation;
    final initialStatus = _normalizeStatusLabel(
      activeData['responderStatus'] as String? ??
          activeData['status'] as String? ??
          'Pending',
    );
    await _loadAdminComments(reportId, position);
    final incidentComments =
        _adminComments.where((comment) => comment.reportId == reportId).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    String status = initialStatus;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final statusOptions = const [
            'PENDING',
            'RESPONDING',
            'ON SCENE',
            'FLAGGED',
            'RESOLVED',
          ];
          final isStatusLocked = _isVerdictLockedStatus(status);

          return Dialog(
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 560),
                child: SingleChildScrollView(
                  child: GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    behavior: HitTestBehavior.opaque,
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
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: SizedBox(
                              width: 260,
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: statusOptions.map((option) {
                                  final isActive = status == option;
                                  final buttonBorder = isStatusLocked
                                      ? const Color(0xFFD1D5DB)
                                      : isActive
                                      ? const Color(0xFFAC1B22)
                                      : const Color(0xFFE5E7EB);
                                  final buttonBackground = isStatusLocked
                                      ? const Color(0xFFF3F4F6)
                                      : isActive
                                      ? const Color(0xFFFFF3F3)
                                      : Colors.white;
                                  final buttonTextColor = isStatusLocked
                                      ? const Color(0xFF9CA3AF)
                                      : isActive
                                      ? const Color(0xFFAC1B22)
                                      : const Color(0xFF4B5563);
                                  return SizedBox(
                                    width: 126,
                                    child: OutlinedButton(
                                      onPressed: isStatusLocked
                                          ? null
                                          : () async {
                                              final confirm =
                                                  await _confirmStatusChange(
                                                    option,
                                                  );
                                              if (confirm != true) return;
                                              final updated =
                                                  await _updateIncidentStatus(
                                                    reportId,
                                                    option,
                                                  );
                                              if (!updated) return;
                                              setDialogState(() {
                                                status = option;
                                              });
                                            },
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(color: buttonBorder),
                                        backgroundColor: buttonBackground,
                                        disabledForegroundColor: const Color(
                                          0xFF9CA3AF,
                                        ),
                                        disabledBackgroundColor: const Color(
                                          0xFFF3F4F6,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        option,
                                        style: TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: buttonTextColor,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                        if (isStatusLocked)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Status is locked for approved/flagged/resolved reports.',
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9CA3AF),
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
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: canCallReporter
                                ? () => _callReporter(contactNumber)
                                : null,
                            icon: const Icon(Icons.call, size: 16),
                            label: const Text(
                              'Call Reporter',
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFAC1B22),
                              side: const BorderSide(color: Color(0xFFAC1B22)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Report location: ${incidentLocation.latitude.toStringAsFixed(5)}, ${incidentLocation.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 12,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                        if (reporterLocation != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Reporter location: ${reporterLocation.latitude.toStringAsFixed(5)}, ${reporterLocation.longitude.toStringAsFixed(5)}',
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 12,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ],
                        if (responderLocation != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Responder location: ${responderLocation.latitude.toStringAsFixed(5)}, ${responderLocation.longitude.toStringAsFixed(5)}',
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 12,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ],
                        if (isVehicular) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Plate Number: $vehiclePlateNumber',
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 12,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Body Type: $vehicleBodyType',
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 12,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Color: $vehicleColor',
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 12,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ],
                        if (isFireOrFlood) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Barangay: $barangay',
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 12,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ],
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
                                    height: incidentMediaHeight,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      height: incidentMediaHeight,
                                      width: double.infinity,
                                      color: const Color(0xFFF3F4F6),
                                      alignment: Alignment.center,
                                      child: const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.appRed,
                                        ),
                                      ),
                                    ),
                                    memCacheHeight: 400,
                                    maxHeightDiskCache: 400,
                                    errorWidget: (_, __, ___) => Container(
                                      height: 96,
                                      width: double.infinity,
                                      color: const Color(0xFFF3F4F6),
                                      alignment: Alignment.center,
                                      child: const Text(
                                        'Unable to load attachment',
                                        style: TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: 12,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    height: 120,
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
                        const SizedBox(height: 12),
                        const Text(
                          'Admin Comments',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2933),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (incidentComments.isEmpty)
                          const Text(
                            'No comments yet.',
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          )
                        else
                          ...incidentComments
                              .take(3)
                              .map(
                                (comment) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8F8F8),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFE5E7EB),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          comment.text,
                                          style: const TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: 12,
                                            color: Color(0xFF374151),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${comment.author} • ${_getTimeAgo(comment.timestamp)}',
                                          style: const TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: 11,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _activeReportId = reportId;
                                  _destination = incidentLocation;
                                  _lastRouteCalcAt = null;
                                  _lastRouteCalcOrigin = null;
                                  _lastRouteCalcDestination = null;
                                  _scheduleRouteCalculation(immediate: true);
                                },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFFAC1B22),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text(
                                  'NAVIGATE',
                                  style: TextStyle(
                                    fontFamily: 'Roboto',
                                    color: Color(0xFFAC1B22),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showIncidentCommentDialog(
                                    reportId,
                                    position,
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFAC1B22),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text(
                                  'ADD COMMENT',
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadAdminComments(String reportId, LatLng position) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .orderBy('timestamp', descending: true)
          .get();
      final comments = snapshot.docs
          .map((doc) {
            final data = doc.data();
            final type = (data['type'] as String?)?.toLowerCase();
            final role = (data['role'] as String?)?.toLowerCase();
            if (type != null && type == 'user') {
              return null;
            }
            if (role != null && role != 'responder' && type != 'admin') {
              return null;
            }
            final timestamp = data['timestamp'] as Timestamp?;
            return AdminComment(
              id: doc.id,
              text: data['text'] as String? ?? '',
              author: data['author'] as String? ?? 'Admin',
              timestamp: timestamp?.toDate() ?? DateTime.now(),
              position: position,
              reportId: reportId,
            );
          })
          .whereType<AdminComment>()
          .toList();
      if (!mounted) return;
      setState(() {
        _adminComments
          ..removeWhere((c) => c.reportId == reportId)
          ..addAll(comments);
      });
    } catch (e) {
      _debugLog('❌ Failed to load admin comments: $e');
    }
  }

  String _normalizeStatusLabel(String status) {
    final normalized = _normalizeStatusKey(status);
    if (normalized.isEmpty) {
      return 'PENDING';
    }
    if (_isFlaggedStatus(normalized)) {
      return 'FLAGGED';
    }
    if (normalized == 'on scene' || normalized == 'on-scene') {
      return 'ON SCENE';
    }
    if (_isResolvedStatus(normalized)) {
      return 'RESOLVED';
    }
    if (_isApprovedStatus(normalized)) {
      return 'APPROVED';
    }
    return status.toUpperCase();
  }

  Future<bool?> _confirmStatusChange(String status) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.appOffWhite,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.appOffYellow, width: 1.2),
        ),
        title: Text('Update Status', style: AppText.subheading),
        content: Text('Set incident status to $status?', style: AppText.body),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.appRed),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.appOffYellow,
              foregroundColor: AppColors.appBlack,
              elevation: 2,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              'Confirm',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _syncUserLocation() async {
    final position = await LocationService.getCurrentPosition();
    if (position == null) return;
    final next = LatLng(position.latitude, position.longitude);
    _userLocation = next;
    _trackingUserLocationNotifier.value = next;
  }

  void _scheduleRouteCalculation({bool immediate = false}) {
    _routeRecalcDebounce?.cancel();
    if (immediate) {
      unawaited(_calculateRoute());
      return;
    }
    _routeRecalcDebounce = Timer(_routeRecalcDebounceDuration, () {
      if (!mounted) return;
      unawaited(_calculateRoute());
    });
  }

  bool _hasMeaningfulRouteChange(LatLng origin, LatLng destination) {
    final lastOrigin = _lastRouteCalcOrigin;
    final lastDestination = _lastRouteCalcDestination;
    if (lastOrigin == null || lastDestination == null) {
      return true;
    }
    final originMoved = const Distance().as(
      LengthUnit.Meter,
      lastOrigin,
      origin,
    );
    final destinationMoved = const Distance().as(
      LengthUnit.Meter,
      lastDestination,
      destination,
    );
    return originMoved >= _routeRecalcMinMoveMeters ||
        destinationMoved >= _routeRecalcMinMoveMeters;
  }

  Future<void> _calculateRoute() async {
    if (_destination == null) return;

    if (_routeCalcInFlight) {
      _routeCalcQueued = true;
      return;
    }

    await _syncUserLocation();
    final origin = _userLocation;
    final destination = _destination;
    if (origin == null || destination == null) return;

    final now = DateTime.now();
    if (_lastRouteCalcAt != null &&
        now.difference(_lastRouteCalcAt!) < _routeRecalcMinInterval &&
        !_hasMeaningfulRouteChange(origin, destination)) {
      return;
    }

    _routeCalcInFlight = true;
    _lastRouteCalcAt = now;
    _lastRouteCalcOrigin = origin;
    _lastRouteCalcDestination = destination;

    setState(() {
      _isRouting = true;
      _routeInstructions = 'Calculating route...';
      _routePoints.clear();
      _routeMarkers.clear();
      _routePolylines.clear();
    });

    try {
      final osrmRoute = await _fetchRouteFromOsrm(origin, destination);
      if (osrmRoute != null && osrmRoute.points.isNotEmpty) {
        _routePoints = osrmRoute.points;
        _estimatedDistance = osrmRoute.distanceMeters / 1000;
        _estimatedTime = _formatDurationFromSeconds(osrmRoute.durationSeconds);
      } else {
        _routePoints = _generateSimulatedRoute(origin, destination);
        final distance = _calculateDistance(_routePoints);
        _estimatedDistance = distance;
        _estimatedTime = _calculateEstimatedTime(distance);
      }

      // Add destination marker only to avoid extra blue pin overlays.
      _routeMarkers.add(
        Marker(
          point: destination,
          width: 40,
          height: 40,
          child: const Icon(Icons.flag, color: Colors.red, size: 40),
        ),
      );

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
      _debugLog('Error calculating route: $e');
      _routeInstructions = 'Failed to calculate route';
    } finally {
      _routeCalcInFlight = false;
      if (mounted) {
        setState(() {
          _isRouting = false;
        });
      }
      if (_routeCalcQueued) {
        _routeCalcQueued = false;
        _scheduleRouteCalculation(immediate: true);
      }
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
      '?overview=full&geometries=geojson&alternatives=true',
    );
    final data = await RouteWeatherCacheService.fetchRouteJson(uri);
    if (data == null) {
      return null;
    }
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      return null;
    }
    final route = routes.whereType<Map<String, dynamic>>().reduce((
      best,
      current,
    ) {
      final bestDistance =
          (best['distance'] as num?)?.toDouble() ?? double.maxFinite;
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
    // Typical urban response speed for 4-wheeled vehicles
    final hours = distanceKm / 50;
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
    _trackingTimer?.cancel();
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

  String _getTimeAgo(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  void _showRouteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Route Options'),
        content: const Text('Set up route navigation options here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Add route setup logic here
            },
            child: const Text('Set Route'),
          ),
        ],
      ),
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
      builder: (context) {
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
                                _rebuildMarkersFromCache();
                              });
                              if (_reportsById.isEmpty) {
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final routeCardTop = _showAssignmentAlert ? 186.0 : 80.0;
    return Scaffold(
      body: Stack(
        children: [
          // OpenStreetMap (full screen)
          RepaintBoundary(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _initialCenter,
                initialZoom: _initialZoom,
                minZoom: 5,
                maxZoom: 18,
                onPositionChanged: (_, __) {
                  _scheduleViewportMarkerRefresh();
                },
                onTap: (_, __) {},
              ),
              children: [
                // Map tiles from OpenStreetMap
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.resq.emergency_app',
                  maxZoom: 19,
                  tileBuilder: (context, tileWidget, tile) {
                    return ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        1.05,
                        0.03,
                        0.02,
                        0,
                        10,
                        0.03,
                        1.05,
                        0.02,
                        0,
                        10,
                        0.03,
                        0.05,
                        1.02,
                        0,
                        10,
                        0,
                        0,
                        0,
                        1,
                        0,
                      ]),
                      child: tileWidget,
                    );
                  },
                ),

                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: AngelesGeofenceService.angelesCityPolygon,
                      color: AppColors.appGreen.withValues(alpha: 0.07),
                      borderColor: AppColors.appGreen.withValues(alpha: 0.45),
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
                if (_routeMarkers.isNotEmpty)
                  MarkerLayer(markers: _routeMarkers),

                // User location marker when tracking
                _TrackingUserMarkerLayer(
                  userLocationListenable: _trackingUserLocationNotifier,
                  isTracking: _isTracking,
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
                      const Text(
                        "RESPONDER'S MAP",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'RobotoCondensed',
                        ),
                      ),
                      Row(
                        children: [
                          // Route button
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
                          // Filter button
                          _buildTopBarAction(
                            icon: Icons.filter_list,
                            onTap: _showFilterDialog,
                          ),
                          const SizedBox(width: 8),
                          // Refresh button
                          _buildTopBarAction(
                            icon: Icons.refresh,
                            onTap: () {
                              setState(() {
                                _reportsById.clear();
                                _incidentMarkerCache.clear();
                                _reporterMarkerCache.clear();
                                _refreshMarkerLists();
                              });
                              _loadReportsFromFirestore();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          _buildAssignmentAlertBubble(),

          // Responder route information card
          if (_routeInstructions.isNotEmpty && !_isRouting)
            Positioned(
              top: routeCardTop,
              right: 16,
              left: 16,
              child: Card(
                color: AppColors.appOffWhite,
                surfaceTintColor: Colors.transparent,
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(
                    color: AppColors.appOffYellow,
                    width: 1.2,
                  ),
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
                                  color: AppColors.appRed,
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
                                  color: AppColors.appRed,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 20,
                              color: AppColors.appBlack,
                            ),
                            onPressed: _clearRoute,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${_estimatedDistance.toStringAsFixed(2)} km \u2022 $_estimatedTime',
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.appRed,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _routeInstructions,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.appBlack,
                        ),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      if (_currentStepIndex > 0)
                        LinearProgressIndicator(
                          value: _currentStepIndex / 3,
                          backgroundColor: AppColors.appBrightWhite,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.appRed,
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (!_isTracking)
                        ElevatedButton(
                          onPressed: _startTracking,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.appRed,
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
                            backgroundColor: AppColors.appRed,
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

          // Current location and weather buttons (bottom left)
          Positioned(
            bottom: 24,
            left: 16,
            child: Column(
              children: [
                _buildWeatherButton(),
                const SizedBox(height: 12),
                FloatingActionButton.small(
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
    );
  }
}

class _TrackingUserMarkerLayer extends StatelessWidget {
  const _TrackingUserMarkerLayer({
    required this.userLocationListenable,
    required this.isTracking,
  });

  final ValueListenable<LatLng?> userLocationListenable;
  final bool isTracking;

  @override
  Widget build(BuildContext context) {
    if (!isTracking) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<LatLng?>(
      valueListenable: userLocationListenable,
      builder: (context, location, _) {
        if (location == null) {
          return const SizedBox.shrink();
        }
        return MarkerLayer(
          markers: [
            Marker(
              point: location,
              width: 50,
              height: 50,
              child: const Icon(Icons.navigation, color: Colors.blue, size: 40),
            ),
          ],
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
