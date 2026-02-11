import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/services/location_service.dart';
import '../../../common/services/user_session.dart';

enum WeatherState { none, sunny, cloudy, rainy }

class AdminMapPage extends StatefulWidget {
  const AdminMapPage({super.key});

  @override
  State<AdminMapPage> createState() => _AdminMapPageState();
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

class _AdminMapPageState extends State<AdminMapPage>
    with AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _dispatchNotificationChannel =
      AndroidNotificationChannel(
        'resq_dispatch',
        'RES-Q Dispatch',
        description: 'Deployment and status updates for responders',
        importance: Importance.high,
      );
  WeatherState _weatherState = WeatherState.none;
  bool _showWeatherCard = false;
  bool _isWeatherLoading = false;
  String? _weatherError;
  _WeatherData? _weatherData;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reportsSubscription;
  StreamSubscription<Position>? _responderLocationSub;
  String? _activeReportId;
  String? _autoAssignedReportId;
  String? _lastPresenceStatus;
  bool? _lastPresenceAvailability;
  bool _localNotificationsReady = false;
  final Map<String, String> _lastKnownStatusByReportId = {};
  bool _showInAppDispatchBubble = false;
  String _dispatchBubbleTitle = '';
  String _dispatchBubbleMessage = '';
  Timer? _dispatchBubbleTimer;

  // Default location (Angeles City, Central Luzon, Philippines)
  final LatLng _initialCenter = const LatLng(15.1450, 120.5887);
  final double _initialZoom = 14.0;
  static const LatLng _angelesCityCenter = LatLng(15.1450, 120.5887);
  static const double _angelesCityRadiusMeters = 6000;

  // Sample incident markers
  final List<Marker> _incidentMarkers = [];
  final List<Marker> _reporterMarkers = [];
  final Map<String, Marker> _incidentMarkerById = {};
  final Map<String, Marker> _reporterMarkerById = {};
  final Map<String, int> _incidentMarkerSignatureById = {};
  final Map<String, int> _reporterMarkerSignatureById = {};
  final Map<String, Map<String, dynamic>> _reportCacheById = {};
  final Map<String, Map<String, dynamic>> _resolvedReportEntryById = {};
  final Map<String, String> _assignedStatusByReportId = {};
  static const Duration _resolvedRetention = Duration(hours: 1);
  final Map<String, Timer> _resolvedRemovalTimers = {};
  List<Map<String, dynamic>> _resolvedReports = [];
  QuerySnapshot<Map<String, dynamic>>? _latestReportSnapshot;
  static const Distance _distanceCalculator = Distance();

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
  bool _isMapReady = false;

  @override
  void initState() {
    super.initState();
    _subscribeToReportsRealtime();
    unawaited(_ensureFirestoreAuthSession());
    // Initialize with user location (simulated)
    _userLocation = _initialCenter;
    _syncUserLocation();
    _startResponderLocationSharing();
    unawaited(_initializeDispatchNotifications());
    unawaited(_syncOwnPresence(status: 'available', isAvailable: true));
  }

  Future<bool> _ensureFirestoreAuthSession() async {
    if (FirebaseAuth.instance.currentUser != null) {
      return true;
    }
    try {
      final credential = await FirebaseAuth.instance.signInAnonymously();
      return credential.user != null;
    } catch (e) {
      debugPrint('Failed to create Firebase Auth session for responder: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _dispatchBubbleTimer?.cancel();
    _reportsSubscription?.cancel();
    _responderLocationSub?.cancel();
    for (final timer in _resolvedRemovalTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _initializeDispatchNotifications() async {
    try {
      const initializationSettingsAndroid = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initializationSettingsIOS = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _localNotificationsPlugin.initialize(initializationSettings);
      final androidPlugin = _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        _dispatchNotificationChannel,
      );
      await androidPlugin?.requestNotificationsPermission();
      await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      _localNotificationsReady = true;
    } catch (e) {
      debugPrint('Failed to initialize dispatch notifications: $e');
    }
  }

  Future<void> _notifyResponderEvent({
    required String title,
    required String message,
    String? payload,
  }) async {
    _showDispatchBubble(title: title, message: message);
    if (!_localNotificationsReady) return;

    try {
      const androidDetails = AndroidNotificationDetails(
        'resq_dispatch',
        'RES-Q Dispatch',
        channelDescription: 'Deployment and status updates for responders',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        icon: '@mipmap/ic_launcher',
        color: Color(0xFFAC1B22),
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
        title,
        message,
        details,
        payload: payload ?? 'dispatch',
      );
    } catch (e) {
      debugPrint('Failed to show dispatch notification: $e');
    }
  }

  void _showDispatchBubble({required String title, required String message}) {
    _dispatchBubbleTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _dispatchBubbleTitle = title;
      _dispatchBubbleMessage = message;
      _showInAppDispatchBubble = true;
    });
    _dispatchBubbleTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _showInAppDispatchBubble = false;
      });
    });
  }

  void _announceResponderStatusChange({
    required String reportId,
    required String statusLabel,
  }) {
    _lastKnownStatusByReportId[reportId] = statusLabel;
    unawaited(
      _notifyResponderEvent(
        title: 'Status updated',
        message: 'Report $reportId is now $statusLabel.',
        payload: 'status:$reportId:$statusLabel',
      ),
    );
  }

  void _syncAssignedStatusNotifications(
    Map<String, String> assignedStatusByReportId,
  ) {
    final staleReportIds = _lastKnownStatusByReportId.keys
        .where((id) => !assignedStatusByReportId.containsKey(id))
        .toList();
    for (final id in staleReportIds) {
      _lastKnownStatusByReportId.remove(id);
    }

    for (final entry in assignedStatusByReportId.entries) {
      final reportId = entry.key;
      final nextStatus = entry.value;
      final previousStatus = _lastKnownStatusByReportId[reportId];
      if (previousStatus == null) {
        _lastKnownStatusByReportId[reportId] = nextStatus;
        continue;
      }
      if (previousStatus == nextStatus) {
        continue;
      }
      _announceResponderStatusChange(
        reportId: reportId,
        statusLabel: nextStatus,
      );
    }
  }

  Widget _buildIncidentMarker({
    required String assetPath,
    required Map<String, dynamic> data,
    required String reportId,
    required LatLng position,
    bool interactive = true,
    double size = 72,
    double opacity = 1,
    bool animate = true,
  }) {
    final statusLower = (data['status'] as String? ?? '')
        .toString()
        .toLowerCase();
    final badge = _buildStatusBadge(statusLower, size);
    final marker = _buildBouncyPin(
      animate: animate,
      child: GestureDetector(
        onTap: () {
          unawaited(
            _navigateToReportDestination(
              reportId: reportId,
              position: position,
            ),
          );
          _showIncidentInfo(
            _reportCacheById[reportId] ?? data,
            reportId,
            position,
          );
        },
        child: Container(
          decoration: const BoxDecoration(shape: BoxShape.circle),
          child: Opacity(
            opacity: opacity,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Image.asset(
                  assetPath,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                ),
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
          .get();
      _applyReportSnapshot(snapshot);
    } catch (e) {
      debugPrint('Failed to load reports: $e');
    }
  }

  void _applyReportSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    _latestReportSnapshot = snapshot;
    _reportCacheById
      ..clear()
      ..addEntries(
        snapshot.docs.map(
          (doc) => MapEntry(doc.id, Map<String, dynamic>.from(doc.data())),
        ),
      );
    _rebuildResponderViewFromCache();
    debugPrint('Loaded ${snapshot.docs.length} reports from Firestore');
  }

  void _applyReportChanges(QuerySnapshot<Map<String, dynamic>> snapshot) {
    _latestReportSnapshot = snapshot;
    if (snapshot.docChanges.isEmpty) {
      return;
    }

    final userData = UserSession.currentUserData;
    final responderPhone = _normalizePhoneValue(
      userData?['contactNumber'] ?? userData?['phoneNumber'],
    );
    final responderName = (userData?['fullName'] ?? userData?['username'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();

    var hasViewChanges = false;
    for (final change in snapshot.docChanges) {
      final reportId = change.doc.id;
      if (change.type == DocumentChangeType.removed) {
        _reportCacheById.remove(reportId);
        hasViewChanges = _removeReportFromView(reportId) || hasViewChanges;
        continue;
      }

      final data = change.doc.data();
      if (data == null) {
        _reportCacheById.remove(reportId);
        hasViewChanges = _removeReportFromView(reportId) || hasViewChanges;
        continue;
      }

      _reportCacheById[reportId] = Map<String, dynamic>.from(data);
      hasViewChanges =
          _upsertReportIntoView(
            reportId: reportId,
            data: _reportCacheById[reportId]!,
            responderPhone: responderPhone,
            responderName: responderName,
            authUid: authUid,
          ) ||
          hasViewChanges;
    }

    if (hasViewChanges) {
      _commitReportViewState();
    }
    _syncAssignedStatusNotifications(_assignedStatusByReportId);
    _syncAutoAssignedReport();
  }

  void _rebuildResponderViewFromCache() {
    final userData = UserSession.currentUserData;
    final responderPhone = _normalizePhoneValue(
      userData?['contactNumber'] ?? userData?['phoneNumber'],
    );
    final responderName = (userData?['fullName'] ?? userData?['username'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();

    _incidentMarkerById.clear();
    _reporterMarkerById.clear();
    _incidentMarkerSignatureById.clear();
    _reporterMarkerSignatureById.clear();
    _resolvedReportEntryById.clear();
    _assignedStatusByReportId.clear();

    for (final entry in _reportCacheById.entries) {
      _upsertReportIntoView(
        reportId: entry.key,
        data: entry.value,
        responderPhone: responderPhone,
        responderName: responderName,
        authUid: authUid,
      );
    }

    _commitReportViewState();
    _syncAssignedStatusNotifications(_assignedStatusByReportId);
    _syncAutoAssignedReport();
  }

  bool _upsertReportIntoView({
    required String reportId,
    required Map<String, dynamic> data,
    required String responderPhone,
    required String responderName,
    required String authUid,
  }) {
    var changed = false;
    final responderStatus = _normalizeStatusLabel(
      data['responderStatus'] as String? ?? data['status'] as String? ?? '',
    );
    final isAssigned =
        !_isClosedIncidentStatus(responderStatus) &&
        _matchesCurrentResponderAssignment(
          data: data,
          responderPhone: responderPhone,
          responderName: responderName,
          authUid: authUid,
        );

    if (!isAssigned) {
      return _removeReportFromView(reportId);
    }
    _assignedStatusByReportId[reportId] = responderStatus;

    final incidentPoint =
        _latLngFromDynamic(data['incidentLocation']) ??
        _latLngFromDynamic(data['location']);
    if (incidentPoint == null) {
      return _removeReportFromView(reportId);
    }

    final status = (data['status'] as String? ?? '').toLowerCase();
    final incidentType = data['incidentType'] as String? ?? 'Unknown';
    final shouldShowType = _shouldShowIncidentType(incidentType);
    final resolvedAt = _parseResolvedAt(data);
    final flaggedAt = _parseFlaggedAt(data) ?? _parseReportedAt(data);
    final isResolved = status == 'resolved' || status == 'incident resolved';
    final isFlagged = status == 'flagged' || status == 'unverified';
    final isInactive = isResolved || isFlagged;
    final incidentMarkerSignature = _buildIncidentMarkerSignature(
      incidentPoint: incidentPoint,
      incidentType: incidentType,
      statusLower: status,
      shouldShowType: shouldShowType,
    );

    if (isInactive) {
      final inactiveAt = isResolved ? resolvedAt : flaggedAt;
      final shouldKeep = _shouldKeepResolved(reportId, inactiveAt);
      if (!shouldKeep) {
        return _removeReportFromView(reportId);
      }
      if (isResolved && shouldShowType) {
        _resolvedReportEntryById[reportId] = {'id': reportId, 'data': data};
        changed = true;
      } else if (_resolvedReportEntryById.remove(reportId) != null) {
        changed = true;
      }
    } else {
      _cancelResolvedRemoval(reportId);
      if (_resolvedReportEntryById.remove(reportId) != null) {
        changed = true;
      }
    }

    if (!shouldShowType) {
      if (_incidentMarkerById.remove(reportId) != null) {
        changed = true;
      }
      if (_incidentMarkerSignatureById.remove(reportId) != null) {
        changed = true;
      }
      if (_reporterMarkerById.remove(reportId) != null) {
        changed = true;
      }
      if (_reporterMarkerSignatureById.remove(reportId) != null) {
        changed = true;
      }
      return changed;
    }

    final previousIncidentSignature = _incidentMarkerSignatureById[reportId];
    if (previousIncidentSignature != incidentMarkerSignature ||
        !_incidentMarkerById.containsKey(reportId)) {
      final markerSize = isInactive ? 56.0 : 72.0;
      _incidentMarkerById[reportId] = Marker(
        key: ValueKey('incident-$reportId'),
        point: incidentPoint,
        width: markerSize,
        height: markerSize,
        child: _buildIncidentMarker(
          assetPath: _getMarkerAssetForIncidentType(incidentType),
          data: data,
          reportId: reportId,
          position: incidentPoint,
          interactive: !isInactive,
          size: markerSize,
          opacity: isInactive ? 0.45 : 1,
          animate: false,
        ),
      );
      _incidentMarkerSignatureById[reportId] = incidentMarkerSignature;
      changed = true;
    }

    final reporterPoint = _latLngFromDynamic(data['reporterLocation']);
    if (reporterPoint != null) {
      final reporterMarkerSignature = _buildReporterMarkerSignature(
        reporterPoint: reporterPoint,
      );
      final previousReporterSignature = _reporterMarkerSignatureById[reportId];
      if (previousReporterSignature != reporterMarkerSignature ||
          !_reporterMarkerById.containsKey(reportId)) {
        _reporterMarkerById[reportId] = _createReporterMarker(
          reportId: reportId,
          reporterPoint: reporterPoint,
        );
        _reporterMarkerSignatureById[reportId] = reporterMarkerSignature;
        changed = true;
      }
    } else if (_reporterMarkerById.remove(reportId) != null) {
      changed = true;
      _reporterMarkerSignatureById.remove(reportId);
    } else if (_reporterMarkerSignatureById.remove(reportId) != null) {
      changed = true;
    }

    return changed;
  }

  int _buildIncidentMarkerSignature({
    required LatLng incidentPoint,
    required String incidentType,
    required String statusLower,
    required bool shouldShowType,
  }) {
    return Object.hash(
      incidentPoint.latitude.toStringAsFixed(6),
      incidentPoint.longitude.toStringAsFixed(6),
      incidentType.trim().toLowerCase(),
      statusLower,
      shouldShowType,
    );
  }

  int _buildReporterMarkerSignature({required LatLng reporterPoint}) {
    return Object.hash(
      reporterPoint.latitude.toStringAsFixed(6),
      reporterPoint.longitude.toStringAsFixed(6),
    );
  }

  Marker _createReporterMarker({
    required String reportId,
    required LatLng reporterPoint,
  }) {
    return Marker(
      key: ValueKey('reporter-$reportId'),
      point: reporterPoint,
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () {
          final latestData = _reportCacheById[reportId];
          final incidentPoint =
              _latLngFromDynamic(latestData?['incidentLocation']) ??
              _latLngFromDynamic(latestData?['location']) ??
              _latLngFromDynamic(latestData?['reporterLocation']) ??
              reporterPoint;
          _showIncidentInfo(
            latestData ?? const <String, dynamic>{},
            reportId,
            incidentPoint,
          );
        },
        child: const Icon(
          Icons.person_pin_circle,
          color: Color(0xFF2563EB),
          size: 30,
        ),
      ),
    );
  }

  bool _removeReportFromView(String reportId) {
    final removedIncident = _incidentMarkerById.remove(reportId) != null;
    final removedReporter = _reporterMarkerById.remove(reportId) != null;
    final removedIncidentSignature =
        _incidentMarkerSignatureById.remove(reportId) != null;
    final removedReporterSignature =
        _reporterMarkerSignatureById.remove(reportId) != null;
    final removedResolved = _resolvedReportEntryById.remove(reportId) != null;
    final removedStatus = _assignedStatusByReportId.remove(reportId) != null;
    _cancelResolvedRemoval(reportId);
    return removedIncident ||
        removedReporter ||
        removedIncidentSignature ||
        removedReporterSignature ||
        removedResolved ||
        removedStatus;
  }

  void _commitReportViewState() {
    final orderedIncidentEntries = _incidentMarkerById.entries.toList(
      growable: false,
    )..sort((a, b) => a.key.compareTo(b.key));
    final orderedReporterEntries = _reporterMarkerById.entries.toList(
      growable: false,
    )..sort((a, b) => a.key.compareTo(b.key));
    final orderedResolvedReports =
        _resolvedReportEntryById.values.toList(growable: false)..sort((a, b) {
          final aData = (a['data'] as Map<String, dynamic>? ?? const {});
          final bData = (b['data'] as Map<String, dynamic>? ?? const {});
          final aTime =
              (_parseResolvedAt(aData) ??
                      _parseFlaggedAt(aData) ??
                      _parseReportedAt(aData))
                  ?.millisecondsSinceEpoch ??
              0;
          final bTime =
              (_parseResolvedAt(bData) ??
                      _parseFlaggedAt(bData) ??
                      _parseReportedAt(bData))
                  ?.millisecondsSinceEpoch ??
              0;
          return bTime.compareTo(aTime);
        });

    if (!mounted) {
      _incidentMarkers
        ..clear()
        ..addAll(orderedIncidentEntries.map((entry) => entry.value));
      _reporterMarkers
        ..clear()
        ..addAll(orderedReporterEntries.map((entry) => entry.value));
      _resolvedReports = orderedResolvedReports;
      return;
    }

    setState(() {
      _incidentMarkers
        ..clear()
        ..addAll(orderedIncidentEntries.map((entry) => entry.value));
      _reporterMarkers
        ..clear()
        ..addAll(orderedReporterEntries.map((entry) => entry.value));
      _resolvedReports = orderedResolvedReports;
    });
  }

  String _normalizePhoneValue(Object? raw) {
    return (raw?.toString() ?? '').replaceAll(RegExp(r'\D'), '');
  }

  bool _isClosedIncidentStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'resolved' ||
        normalized == 'incident resolved' ||
        normalized == 'flagged' ||
        normalized == 'unverified';
  }

  bool _matchesCurrentResponderAssignment({
    required Map<String, dynamic> data,
    required String responderPhone,
    required String responderName,
    required String authUid,
  }) {
    final assignedId = (data['responderId'] as String? ?? '').trim();
    final assignedIdPhone = _normalizePhoneValue(assignedId);
    final assignedContactPhone = _normalizePhoneValue(
      data['responderContactNumber'] ?? data['responderPhone'],
    );
    final assignedName = (data['responderName'] as String? ?? '')
        .trim()
        .toLowerCase();

    final matchesPhone =
        responderPhone.isNotEmpty &&
        (assignedIdPhone == responderPhone ||
            assignedContactPhone == responderPhone);
    final matchesUid =
        authUid.isNotEmpty && assignedId.isNotEmpty && assignedId == authUid;
    final matchesName =
        responderName.isNotEmpty &&
        assignedName.isNotEmpty &&
        assignedName == responderName;

    return matchesPhone || matchesUid || matchesName;
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
      await FirebaseFirestore.instance
          .collection('semi_admins')
          .doc(docId)
          .set({
            'isLoggedIn': true,
            'status': normalizedStatus,
            'isAvailable': isAvailable,
            'lastSeenAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      _lastPresenceStatus = normalizedStatus;
      _lastPresenceAvailability = isAvailable;
    } catch (e) {
      debugPrint('Failed to sync responder presence: $e');
    }
  }

  void _syncAutoAssignedReport() {
    final userData = UserSession.currentUserData;
    final responderPhone = _normalizePhoneValue(
      userData?['contactNumber'] ?? userData?['phoneNumber'],
    );
    final responderName = (userData?['fullName'] ?? userData?['username'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();

    if ((responderPhone.isEmpty && responderName.isEmpty) && authUid.isEmpty) {
      return;
    }

    final previousAutoAssignedReportId = _autoAssignedReportId;
    String? matchedReportId;
    LatLng? matchedDestination;
    String matchedStatusLabel = 'PENDING';
    String matchedIncidentType = 'incident';
    DateTime latestAssignedAt = DateTime.fromMillisecondsSinceEpoch(0);

    for (final entry in _reportCacheById.entries) {
      final reportId = entry.key;
      final data = entry.value;
      final status =
          (data['responderStatus'] as String? ??
                  data['status'] as String? ??
                  '')
              .toLowerCase();
      if (_isClosedIncidentStatus(status)) {
        continue;
      }

      if (!_matchesCurrentResponderAssignment(
        data: data,
        responderPhone: responderPhone,
        responderName: responderName,
        authUid: authUid,
      )) {
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
      matchedReportId = reportId;
      matchedDestination = incidentPoint;
      matchedStatusLabel = _normalizeStatusLabel(
        data['responderStatus'] as String? ?? data['status'] as String? ?? '',
      );
      matchedIncidentType = (data['incidentType'] as String? ?? 'incident')
          .toString()
          .trim();
    }

    if (matchedReportId == null || matchedDestination == null) {
      _autoAssignedReportId = null;
      _activeReportId = null;
      if (mounted) {
        final hasActiveRoute =
            _destination != null ||
            _routePoints.isNotEmpty ||
            _routeMarkers.isNotEmpty ||
            _routePolylines.isNotEmpty ||
            _isTracking;
        if (hasActiveRoute) {
          _clearRoute();
        }
      } else {
        _destination = null;
        _routePoints.clear();
        _routeMarkers.clear();
        _routePolylines.clear();
        _routeInstructions = '';
        _isTracking = false;
        _currentStepIndex = 0;
        _trackingTimer?.cancel();
      }
      unawaited(_syncOwnPresence(status: 'available', isAvailable: true));
      return;
    }

    final assignmentChanged = previousAutoAssignedReportId != matchedReportId;

    final shouldRefreshRoute =
        _autoAssignedReportId != matchedReportId ||
        _activeReportId != matchedReportId ||
        _destination == null ||
        _distanceCalculator.as(
              LengthUnit.Meter,
              _destination!,
              matchedDestination,
            ) >
            20;

    _autoAssignedReportId = matchedReportId;
    _lastKnownStatusByReportId[matchedReportId] = matchedStatusLabel;
    if (assignmentChanged) {
      unawaited(
        _notifyResponderEvent(
          title: 'New deployment',
          message:
              'You were deployed to ${matchedIncidentType.toUpperCase()} (Report $matchedReportId).',
          payload: 'deploy:$matchedReportId',
        ),
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

    _calculateRoute();
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
                    final reportId = entry['id']?.toString() ?? '';
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
                        final location = data['location'];
                        if (location is GeoPoint) {
                          _showIncidentInfo(
                            data,
                            reportId,
                            LatLng(location.latitude, location.longitude),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Location not available.'),
                            ),
                          );
                        }
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

  Widget _buildBouncyPin({required Widget child, bool animate = true}) {
    return child;
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.35)),
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
              '${data.temperature.round()} deg',
              style: const TextStyle(
                fontFamily: 'RobotoCondensed',
                fontWeight: FontWeight.w400,
                fontSize: 20,
                color: Color(0xFF111827),
              ),
            ),
            Text(
              'H ${data.max.round()} deg  L ${data.min.round()} deg',
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

  String _getMarkerAssetForIncidentType(String type) {
    switch (type.toUpperCase()) {
      case 'FIRE':
        return 'assets/icons/locations/LOC-FIRE.png';
      case 'FLOOD':
        return 'assets/icons/locations/LOC-FLOOD.png';
      case 'EARTHQUAKE':
        return 'assets/icons/locations/LOC-EARTHQUAKE.png';
      case 'VEHICULAR':
        return 'assets/icons/locations/LOC-CRASH.png';
      case 'ROAD OBSTRUCTION':
        return 'assets/icons/locations/LOC-OTHERS.png';
      default:
        return 'assets/icons/locations/LOC-OTHERS.png';
    }
  }

  void _addSampleComments() {
    _adminComments.addAll([
      AdminComment(
        id: '1',
        text: 'Unit 3 dispatched to this location',
        author: 'Admin John',
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        position: const LatLng(15.1460, 120.5900),
      ),
      AdminComment(
        id: '2',
        text: 'Road closure on MacArthur Highway',
        author: 'Admin Sarah',
        timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
        position: const LatLng(15.1480, 120.5920),
      ),
    ]);
  }

  Future<void> _postAdminComment({
    required String reportId,
    required String text,
    required LatLng position,
    String? author,
    bool showSuccessToast = true,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final hasAuth = await _ensureFirestoreAuthSession();
    if (!hasAuth) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in again to post comments.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final commentAuthor = author?.trim().isNotEmpty == true
        ? author!.trim()
        : (UserSession.currentUserData?['fullName'] as String? ??
              UserSession.currentUserData?['username'] as String? ??
              'Responder');

    try {
      final commentPayload = <String, dynamic>{
        'text': trimmed,
        'author': commentAuthor,
        'type': 'admin',
        'role': 'responder',
        'timestamp': Timestamp.now(),
      };
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .collection('comments')
          .add(commentPayload);

      // Keep legacy report-level mirror fields best-effort only.
      // Primary source of truth is reports/{reportId}/comments.
      try {
        await FirebaseFirestore.instance
            .collection('reports')
            .doc(reportId)
            .update({
              'responderComments': FieldValue.arrayUnion([commentPayload]),
              'latestResponderCommentText': trimmed,
              'latestResponderCommentBy': commentAuthor,
              'latestResponderCommentAt': commentPayload['timestamp'],
            });
      } catch (mirrorError) {
        debugPrint(
          'Failed to mirror responder comment on report: $mirrorError',
        );
      }

      if (!mounted) return;
      setState(() {
        _adminComments.add(
          AdminComment(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: trimmed,
            author: commentAuthor,
            timestamp: DateTime.now(),
            position: position,
            reportId: reportId,
          ),
        );
      });

      if (showSuccessToast) {
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
      }
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
      final hasAuth = await _ensureFirestoreAuthSession();
      if (!hasAuth) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Responder is not authenticated. Please sign in again.',
        );
      }
      final statusLower = status.trim().toLowerCase();
      final now = Timestamp.now();
      final responderName =
          UserSession.currentUserData?['fullName'] as String? ??
          UserSession.currentUserData?['username'] as String? ??
          'Semi-Admin';

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
        _announceResponderStatusChange(
          reportId: reportId,
          statusLabel: 'FLAGGED',
        );
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
        _announceResponderStatusChange(
          reportId: reportId,
          statusLabel: 'RESPONDING',
        );
        await _postStatusUpdateComment(
          reportId: reportId,
          statusLabel: 'RESPONDING',
          responderName: responderName,
        );
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
        _announceResponderStatusChange(
          reportId: reportId,
          statusLabel: 'ON SCENE',
        );
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
      _announceResponderStatusChange(
        reportId: reportId,
        statusLabel: normalizedStatus,
      );
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

  LatLng _resolveReportPosition(String reportId) {
    final snapshot = _latestReportSnapshot;
    if (snapshot != null) {
      for (final doc in snapshot.docs) {
        if (doc.id != reportId) continue;
        final data = doc.data();
        final incidentPoint =
            _latLngFromDynamic(data['incidentLocation']) ??
            _latLngFromDynamic(data['location']);
        if (incidentPoint != null) {
          return incidentPoint;
        }
      }
    }
    return _destination ?? _userLocation ?? _initialCenter;
  }

  Future<void> _postStatusUpdateComment({
    required String reportId,
    required String statusLabel,
    required String responderName,
  }) async {
    final normalized = statusLabel.trim().toUpperCase();
    String? message;
    if (normalized == 'RESPONDING') {
      message =
          '$responderName is now responding and heading to your location.';
    } else if (normalized == 'ON SCENE') {
      message = '$responderName has arrived on scene.';
    } else if (normalized == 'RESOLVED') {
      message = '$responderName marked this report as resolved.';
    }
    if (message == null) {
      return;
    }

    await _postAdminComment(
      reportId: reportId,
      text: message,
      position: _resolveReportPosition(reportId),
      author: responderName,
      showSuccessToast: false,
    );
  }

  Future<bool> _markIncidentResolved(String reportId) async {
    final resolvedTime = DateTime.now();
    final resolvedAt = Timestamp.fromDate(resolvedTime);
    final responderName =
        UserSession.currentUserData?['fullName'] as String? ??
        UserSession.currentUserData?['username'] as String? ??
        'Semi-Admin';
    try {
      final hasAuth = await _ensureFirestoreAuthSession();
      if (!hasAuth) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Responder is not authenticated. Please sign in again.',
        );
      }
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
      _announceResponderStatusChange(
        reportId: reportId,
        statusLabel: 'RESOLVED',
      );
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
    final removedIncident = _incidentMarkerById.remove(reportId) != null;
    final removedReporter = _reporterMarkerById.remove(reportId) != null;
    final removedIncidentSignature =
        _incidentMarkerSignatureById.remove(reportId) != null;
    final removedReporterSignature =
        _reporterMarkerSignatureById.remove(reportId) != null;
    final removedResolved = _resolvedReportEntryById.remove(reportId) != null;
    final removedStatus = _assignedStatusByReportId.remove(reportId) != null;
    _cancelResolvedRemoval(reportId);
    if (removedIncident ||
        removedReporter ||
        removedIncidentSignature ||
        removedReporterSignature ||
        removedResolved ||
        removedStatus) {
      _commitReportViewState();
    }
  }

  Future<void> _startResponderLocationSharing() async {
    final hasPermission = await LocationService.requestLocationPermission();
    if (!hasPermission) return;
    _responderLocationSub?.cancel();
    _responderLocationSub =
        LocationService.getPositionStream(distanceFilterMeters: 5).listen((
          position,
        ) {
          final point = LatLng(position.latitude, position.longitude);
          final previousPoint = _userLocation;
          if (previousPoint != null) {
            final movedMeters = _distanceCalculator.as(
              LengthUnit.Meter,
              previousPoint,
              point,
            );
            if (movedMeters < 2) {
              return;
            }
          }
          if (!mounted) return;
          setState(() {
            _userLocation = point;
          });
          final reportId = _activeReportId;
          if (reportId == null) return;
          unawaited(_syncResponderLocationForActiveReport(reportId, point));
        });
  }

  Future<void> _syncResponderLocationForActiveReport(
    String reportId,
    LatLng point,
  ) async {
    final hasAuth = await _ensureFirestoreAuthSession();
    if (!hasAuth) {
      return;
    }
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
    } catch (e) {
      debugPrint('Failed to sync responder location for $reportId: $e');
    }
  }

  void _subscribeToReportsRealtime() {
    _reportsSubscription?.cancel();
    _reportsSubscription = FirebaseFirestore.instance
        .collection('reports')
        .snapshots()
        .listen(
          _applyReportChanges,
          onError: (error) {
            debugPrint('Failed to subscribe to report updates: $error');
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
    final incidentUpper = incidentType.toUpperCase();
    final isVehicular = incidentUpper == 'VEHICULAR';
    final isFireOrFlood = incidentUpper == 'FIRE' || incidentUpper == 'FLOOD';
    _activeReportId = reportId;
    _destination = position;
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
                                  return SizedBox(
                                    width: 126,
                                    child: OutlinedButton(
                                      onPressed: () async {
                                        final confirm =
                                            await _confirmStatusChange(option);
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
                                        side: BorderSide(
                                          color: isActive
                                              ? const Color(0xFFAC1B22)
                                              : const Color(0xFFE5E7EB),
                                        ),
                                        backgroundColor: isActive
                                            ? const Color(0xFFFFF3F3)
                                            : Colors.white,
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
                                          color: isActive
                                              ? const Color(0xFFAC1B22)
                                              : const Color(0xFF4B5563),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
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
                                ? Image.network(
                                    mediaUrl,
                                    height: 200,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
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
                                          '${comment.author} - ${_getTimeAgo(comment.timestamp)}',
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
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await _navigateToReportDestination(
                                    reportId: reportId,
                                    position: position,
                                  );
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
      debugPrint('Failed to load admin comments: $e');
    }
  }

  String _normalizeStatusLabel(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'PENDING';
    }
    if (normalized == 'flagged' || normalized == 'unverified') {
      return 'FLAGGED';
    }
    if (normalized == 'on scene' || normalized == 'on-scene') {
      return 'ON SCENE';
    }
    if (normalized == 'incident resolved') {
      return 'RESOLVED';
    }
    return status.toUpperCase();
  }

  Future<bool?> _confirmStatusChange(String status) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Status', style: AppText.subheading),
        content: Text('Set incident status to $status?', style: AppText.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFC806),
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _setDestinationFromIncident(String incidentType) {
    LatLng destination;

    switch (incidentType) {
      case 'Fire Incident':
        destination = const LatLng(15.1450, 120.5887);
        break;
      case 'Road Obstruction':
        destination = const LatLng(15.1500, 120.5950);
        break;
      case 'Medical Emergency':
        destination = const LatLng(15.1400, 120.5800);
        break;
      case 'Flood Warning':
        destination = const LatLng(15.1550, 120.5850);
        break;
      default:
        destination = const LatLng(15.1450, 120.5887);
    }

    _destination = destination;
    _calculateRoute();
  }

  Future<void> _navigateToReportDestination({
    required String reportId,
    required LatLng position,
  }) async {
    if (mounted) {
      setState(() {
        _activeReportId = reportId;
        _destination = position;
      });
    } else {
      _activeReportId = reportId;
      _destination = position;
    }

    _mapController.move(position, 16.0);
    try {
      await _calculateRoute();
    } catch (e) {
      debugPrint('Failed to calculate route for $reportId: $e');
      _ensureDirectRouteFallback(position);
    }

    if ((_routePoints.isEmpty || _routeMarkers.isEmpty) &&
        mounted &&
        _destination != null) {
      _ensureDirectRouteFallback(_destination!);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to build route right now. Showing destination pin.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _syncUserLocation() async {
    try {
      final position = await LocationService.getCurrentPosition();
      if (position == null) return;
      if (!mounted) return;
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      debugPrint('Failed to get responder location for routing: $e');
    }
  }

  void _ensureDirectRouteFallback(LatLng destination) {
    void applyFallback() {
      final origin = _userLocation ?? _initialCenter;
      _routePoints = [origin, destination];
      _routeMarkers
        ..clear()
        ..addAll([
          Marker(
            point: origin,
            width: 40,
            height: 40,
            child: const Icon(Icons.location_on, color: Colors.blue, size: 40),
          ),
          Marker(
            point: destination,
            width: 40,
            height: 40,
            child: const Icon(Icons.flag, color: Colors.red, size: 40),
          ),
        ]);
      _routePolylines
        ..clear()
        ..addAll([
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
      final fallbackDistance = _calculateDistance(_routePoints);
      _estimatedDistance = fallbackDistance;
      _estimatedTime = _calculateEstimatedTime(fallbackDistance);
      _generateRouteInstructions();
    }

    if (mounted) {
      setState(applyFallback);
    } else {
      applyFallback();
    }
    _zoomToRoute();
  }

  Future<void> _calculateRoute() async {
    if (_destination == null) return;
    await _syncUserLocation();
    final origin = _userLocation ?? _initialCenter;
    final destination = _destination!;
    if (_userLocation == null && mounted) {
      setState(() {
        _userLocation = origin;
      });
    } else if (_userLocation == null) {
      _userLocation = origin;
    }

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

      if (_routePoints.isEmpty) {
        _routePoints = [origin, destination];
        final distance = _calculateDistance(_routePoints);
        _estimatedDistance = distance;
        _estimatedTime = _calculateEstimatedTime(distance);
      }

      // Add markers
      _routeMarkers.addAll([
        Marker(
          point: origin,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: Colors.blue, size: 40),
        ),
        Marker(
          point: destination,
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
      print('Error calculating route: $e');
      _routePoints = _generateSimulatedRoute(origin, destination);
      if (_routePoints.isEmpty) {
        _routePoints = [origin, destination];
      }
      final distance = _calculateDistance(_routePoints);
      _estimatedDistance = distance;
      _estimatedTime = _calculateEstimatedTime(distance);
      _routeMarkers
        ..clear()
        ..addAll([
          Marker(
            point: origin,
            width: 40,
            height: 40,
            child: const Icon(Icons.location_on, color: Colors.blue, size: 40),
          ),
          Marker(
            point: destination,
            width: 40,
            height: 40,
            child: const Icon(Icons.flag, color: Colors.red, size: 40),
          ),
        ]);
      _routePolylines
        ..clear()
        ..add(
          Polyline(
            points: _routePoints,
            color: AppColors.appGreen.withOpacity(0.95),
            strokeWidth: 4.5,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
      _generateRouteInstructions();
      _zoomToRoute();
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
      totalDistance += _distanceCalculator.as(
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
Distance: ${_estimatedDistance.toStringAsFixed(2)} km
Estimated Time: $_estimatedTime
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
                    Image.asset(
                      assetPath,
                      width: 34,
                      height: 34,
                      fit: BoxFit.contain,
                    ),
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
                          'assets/icons/buttons/FINAL-EARTHQUAKE-ICON.png',
                      value: showEarthquake,
                      onChanged: (value) {
                        setDialogState(() => showEarthquake = value ?? false);
                      },
                    ),
                    buildFilterRow(
                      label: 'Flood',
                      assetPath: 'assets/icons/buttons/FINAL-FLOOD-ICON.png',
                      value: showFlood,
                      onChanged: (value) {
                        setDialogState(() => showFlood = value ?? false);
                      },
                    ),
                    buildFilterRow(
                      label: 'Fire',
                      assetPath: 'assets/icons/buttons/FINAL-FIRE-ICON.png',
                      value: showFire,
                      onChanged: (value) {
                        setDialogState(() => showFire = value ?? false);
                      },
                    ),
                    buildFilterRow(
                      label: 'Vehicular',
                      assetPath: 'assets/icons/buttons/FINAL-CRASH-ICON.png',
                      value: showVehicular,
                      onChanged: (value) {
                        setDialogState(() => showVehicular = value ?? false);
                      },
                    ),
                    buildFilterRow(
                      label: 'Others',
                      assetPath: 'assets/icons/buttons/FINAL-OTHERS-ICON.png',
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

  Widget _buildDispatchBubbleOverlay(BuildContext context) {
    final routeCardVisible = _routeInstructions.isNotEmpty && !_isRouting;
    final topOffset =
        MediaQuery.of(context).padding.top + (routeCardVisible ? 188 : 72);
    return Positioned(
      top: topOffset,
      left: 16,
      right: 16,
      child: IgnorePointer(
        ignoring: true,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: _showInAppDispatchBubble
              ? Offset.zero
              : const Offset(0, -0.25),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: _showInAppDispatchBubble ? 1 : 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF111827).withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1F2937)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.notifications_active,
                      color: Color(0xFFFBBF24),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _dispatchBubbleTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _dispatchBubbleMessage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFD1D5DB),
                            fontSize: 12,
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
              onMapReady: () {
                setState(() {
                  _isMapReady = true;
                });
              },
              onTap: (position, latlng) {
                // Allow setting destination by tapping on map
                if (!_isRouting) {
                  _destination = latlng;
                  _calculateRoute();
                }
              },
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

              // Reporter location markers (shared live location)
              if (_reporterMarkers.isNotEmpty)
                MarkerLayer(markers: _reporterMarkers),

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
                                _incidentMarkers.clear();
                                _loadReportsFromFirestore();
                              });
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

          _buildDispatchBubbleOverlay(context),

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
                      Text(
                        '${_estimatedDistance.toStringAsFixed(2)} km \u2022 $_estimatedTime',
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFAC1B22),
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
