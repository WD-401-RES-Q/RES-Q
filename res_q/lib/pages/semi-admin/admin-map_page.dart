import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../ui/app_theme.dart';
import '../../services/location_service.dart';

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
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();
  late final AnimationController _pinBounceController;
  WeatherState _weatherState = WeatherState.none;
  bool _showWeatherCard = false;
  bool _isWeatherLoading = false;
  String? _weatherError;
  _WeatherData? _weatherData;
  StreamSubscription<Position>? _responderLocationSub;
  String? _activeReportId;

  // Default location (Angeles City, Central Luzon, Philippines)
  final LatLng _initialCenter = const LatLng(15.1450, 120.5887);
  final double _initialZoom = 14.0;
  static const LatLng _angelesCityCenter = LatLng(15.1450, 120.5887);
  static const double _angelesCityRadiusMeters = 6000;

  // Sample incident markers
  final List<Marker> _incidentMarkers = [];

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
    _loadReportsFromFirestore();
    // Initialize with user location (simulated)
    _userLocation = _initialCenter;
    _syncUserLocation();
    _pinBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _startResponderLocationSharing();
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _responderLocationSub?.cancel();
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
  }) {
    return _buildBouncyPin(
      child: GestureDetector(
        onTap: () => _showIncidentInfo(data, reportId, position),
        child: Container(
          decoration: const BoxDecoration(shape: BoxShape.circle),
          child: Image.asset(
            assetPath,
            width: 72,
            height: 72,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  Future<void> _loadReportsFromFirestore() async {
    try {
      _incidentMarkers.clear();
      final snapshot = await FirebaseFirestore.instance
          .collection('reports')
          .where('location', isNotEqualTo: null)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final location = data['location'] as GeoPoint?;
        if (location == null) continue;

        final status = (data['status'] as String? ?? '').toLowerCase();
        if (status == 'resolved' || status == 'incident resolved') {
          continue;
        }

        final point = LatLng(location.latitude, location.longitude);
        final incidentType = data['incidentType'] as String? ?? 'Unknown';

        _incidentMarkers.add(
          Marker(
            key: ValueKey('incident-${doc.id}'),
            point: point,
            width: 72,
            height: 72,
            child: _buildIncidentMarker(
              assetPath: _getMarkerAssetForIncidentType(incidentType),
              data: data,
              reportId: doc.id,
              position: point,
            ),
          ),
        );
      }

      if (mounted) setState(() {});
      print('✅ Loaded ${snapshot.docs.length} reports from Firestore');
    } catch (e) {
      print('❌ Failed to load reports: $e');
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
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF3A8DFF),
              Color(0xFFE8F2FF),
              Color(0xFFFFD54A),
              Color(0xFFFF8A3D),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          _weatherIcon(_weatherData?.state ?? WeatherState.cloudy),
          color: const Color(0xFF1F2933),
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
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    try {
      final commentPayload = {
        'text': trimmed,
        'author': 'Admin User',
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
            author: 'Admin User',
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

  Future<void> _updateIncidentStatus(
    String reportId,
    String status,
  ) async {
    try {
      if (status.toLowerCase() == 'resolved' ||
          status.toLowerCase() == 'incident resolved') {
        await _markIncidentResolved(reportId);
        return;
      }
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .update({
        'status': status,
        'responderStatus': status,
        'resolvedAt': FieldValue.delete(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _markIncidentResolved(String reportId) async {
    final resolvedTime = DateTime.now();
    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .update({
        'status': 'RESOLVED',
        'responderStatus': 'RESOLVED',
        'resolvedAt': Timestamp.fromDate(resolvedTime),
      });
      _removeIncidentMarker(reportId);
      if (_activeReportId == reportId) {
        _activeReportId = null;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to resolve incident: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _removeIncidentMarker(String reportId) {
    if (!mounted) return;
    setState(() {
      _incidentMarkers.removeWhere(
        (marker) => marker.key == ValueKey('incident-$reportId'),
      );
    });
  }


  Future<void> _startResponderLocationSharing() async {
    final hasPermission = await LocationService.requestLocationPermission();
    if (!hasPermission) return;
    _responderLocationSub?.cancel();
    _responderLocationSub = LocationService.getPositionStream(
      distanceFilterMeters: 5,
    ).listen((position) {
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _userLocation = point;
      });
      final reportId = _activeReportId;
      if (reportId == null) return;
      FirebaseFirestore.instance.collection('reports').doc(reportId).update({
        'responderLocation': GeoPoint(point.latitude, point.longitude),
        'responderLocationUpdatedAt': Timestamp.now(),
      });
    });
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
                        const SnackBar(
                          content: Text('Please enter a comment'),
                        ),
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
    final description = activeData['details'] as String? ??
        activeData['description'] as String? ??
        '';
    final contactNumber = activeData['contactNumber'] as String? ?? 'Unknown';
    final reportedAt = activeData['reportedAt'];
    String? reportedAtLabel;
    if (reportedAt is Timestamp) {
      final date = reportedAt.toDate();
      reportedAtLabel =
          '${date.month}/${date.day}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    final mediaUrl = activeData['mediaUrl'] as String?;
    final mediaType = (activeData['mediaType'] as String?)?.toLowerCase();
    _activeReportId = reportId;
    _destination = position;
    final initialStatus = _normalizeStatusLabel(
      activeData['status'] as String? ?? 'Unverified',
    );
    await _loadAdminComments(reportId, position);
    final incidentComments = _adminComments
        .where((comment) => comment.reportId == reportId)
        .toList()
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
            'RESOLVED',
          ];

          return Dialog(
            backgroundColor: Colors.white,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 560),
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
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: SizedBox(
                        width: 260,
                        child: GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 2.8,
                          children: statusOptions.map((option) {
                            final isActive = status == option;
                            return OutlinedButton(
                              onPressed: () async {
                                final confirm =
                                    await _confirmStatusChange(option);
                                if (confirm != true) return;
                                setDialogState(() {
                                  status = option;
                                });
                                await _updateIncidentStatus(reportId, option);
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
                                  borderRadius: BorderRadius.circular(10),
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
                    ...incidentComments.take(3).map(
                      (comment) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          width: double.infinity,
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
                            _destination = position;
                            _calculateRoute();
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFAC1B22)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
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
                            _showIncidentCommentDialog(reportId, position);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFAC1B22),
                            padding: const EdgeInsets.symmetric(vertical: 12),
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
      final comments = snapshot.docs.map((doc) {
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
      }).whereType<AdminComment>().toList();
      if (!mounted) return;
      setState(() {
        _adminComments
          ..removeWhere((c) => c.reportId == reportId)
          ..addAll(comments);
      });
    } catch (e) {
      debugPrint('❌ Failed to load admin comments: $e');
    }
  }

  String _normalizeStatusLabel(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'flagged' ||
        normalized == 'unverified') {
      return 'PENDING';
    }
    if (normalized == 'on-scene') {
      return 'ON SCENE';
    }
    return status.toUpperCase();
  }

  Future<bool?> _confirmStatusChange(String status) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Status', style: AppText.subheading),
        content: Text(
          'Set incident status to $status?',
          style: AppText.body,
        ),
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

  Future<void> _syncUserLocation() async {
    final position = await LocationService.getCurrentPosition();
    if (position == null) return;
    if (!mounted) return;
    setState(() {
      _userLocation = LatLng(position.latitude, position.longitude);
    });
  }

  Future<void> _calculateRoute() async {
    if (_destination == null) return;
    await _syncUserLocation();
    if (_userLocation == null) return;

    setState(() {
      _isRouting = true;
      _routeInstructions = 'Calculating route...';
      _routePoints.clear();
      _routeMarkers.clear();
      _routePolylines.clear();
    });

    try {
      final osrmRoute =
          await _fetchRouteFromOsrm(_userLocation!, _destination!);
      if (osrmRoute != null && osrmRoute.points.isNotEmpty) {
        _routePoints = osrmRoute.points;
        _estimatedDistance = osrmRoute.distanceMeters / 1000;
        _estimatedTime =
            _formatDurationFromSeconds(osrmRoute.durationSeconds);
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
      print('Error calculating route: $e');
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

  Future<_RouteResult?> _fetchRouteFromOsrm(
    LatLng start,
    LatLng end,
  ) async {
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
          width: 46,
          height: 46,
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
          child: Icon(icon, color: Colors.white, size: 28),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Incidents'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select incident types to display:'),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('Fire Incidents'),
              value: true,
              onChanged: (value) {},
            ),
            CheckboxListTile(
              title: const Text('Medical Emergencies'),
              value: true,
              onChanged: (value) {},
            ),
            CheckboxListTile(
              title: const Text('Road Obstructions'),
              value: true,
              onChanged: (value) {},
            ),
            CheckboxListTile(
              title: const Text('Flood Warnings'),
              value: true,
              onChanged: (value) {},
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Apply Filters'),
          ),
        ],
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

          // Current location and weather buttons (bottom right)
          Positioned(
            bottom: 24,
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
