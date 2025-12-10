import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

  AdminComment({
    required this.id,
    required this.text,
    required this.author,
    required this.timestamp,
    required this.position,
  });
}

class _AdminMapPageState extends State<AdminMapPage> {
  final MapController _mapController = MapController();
  
  // Default location (Angeles City, Central Luzon, Philippines)
  final LatLng _initialCenter = const LatLng(15.1450, 120.5887);
  final double _initialZoom = 14.0;

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
  bool _showComments = true;
  
  // Simulate moving along route
  Timer? _trackingTimer;
  bool _isMapReady = false;

  @override
  void initState() {
    super.initState();
    _addSampleMarkers();
    _addSampleComments();
    // Initialize with user location (simulated)
    _userLocation = _initialCenter;
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    super.dispose();
  }

  void _addSampleMarkers() {
    _incidentMarkers.addAll([
      Marker(
        point: const LatLng(15.1450, 120.5887),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _showIncidentInfo('Fire Incident', 'Reported 10 mins ago'),
          child: const Icon(
            Icons.local_fire_department,
            color: Colors.red,
            size: 40,
          ),
        ),
      ),
      Marker(
        point: const LatLng(15.1500, 120.5950),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _showIncidentInfo('Road Obstruction', 'Reported 25 mins ago'),
          child: const Icon(
            Icons.warning,
            color: Colors.orange,
            size: 40,
          ),
        ),
      ),
      Marker(
        point: const LatLng(15.1400, 120.5800),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _showIncidentInfo('Medical Emergency', 'Reported 5 mins ago'),
          child: const Icon(
            Icons.medical_services,
            color: Colors.yellow,
            size: 40,
          ),
        ),
      ),
      Marker(
        point: const LatLng(15.1550, 120.5850),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _showIncidentInfo('Flood Warning', 'Reported 1 hour ago'),
          child: const Icon(
            Icons.water,
            color: Colors.blue,
            size: 40,
          ),
        ),
      ),
    ]);
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

  void _showIncidentInfo(String title, String subtitle) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle),
            const SizedBox(height: 16),
            const Text('Tap for more details or to navigate to location.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Set this incident as destination
              _setDestinationFromIncident(title);
            },
            child: const Text('Navigate'),
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
      // Simulated route points (in real app, use OSRM or Google Directions API)
      _routePoints = _generateSimulatedRoute(_userLocation!, _destination!);
      
      // Calculate distance
      final distance = _calculateDistance(_routePoints);
      _estimatedDistance = distance;
      _estimatedTime = _calculateEstimatedTime(distance);
      
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
      
      // Add route polyline
      _routePolylines.add(Polyline(
        points: _routePoints,
        color: const Color(0xFF4285F4),
        strokeWidth: 5.0,
        isDotted: false,
      ));
      
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

  double _calculateDistance(List<LatLng> points) {
    double totalDistance = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      totalDistance += const Distance().as(LengthUnit.Kilometer, points[i], points[i + 1]);
    }
    return totalDistance;
  }

  String _calculateEstimatedTime(double distanceKm) {
    // Assume average speed of 40 km/h
    final hours = distanceKm / 40;
    if (hours < 1) {
      final minutes = (hours * 60).round();
      return '$minutes mins';
    }
    return '${hours.toStringAsFixed(1)} hours';
  }

  void _generateRouteInstructions() {
    _routeInstructions = '''
Route calculated successfully!

📏 Distance: ${_estimatedDistance.toStringAsFixed(2)} km
⏱️ Estimated Time: $_estimatedTime

🚦 Directions:
1. Head north on MacArthur Highway
2. Turn right onto Friendship Highway
3. Continue straight for 2 km
4. Destination will be on your left
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
    
    final center = LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );
    
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
          if (_isMapReady) {
            _mapController.move(_userLocation!, _mapController.camera.zoom);
          }
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

  void _showAdminCommentDialog() {
    final TextEditingController commentController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Color(0xFFAC1B22)),
              SizedBox(width: 8),
              Text('Responder Comment'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Leave a comment for the admins:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Enter your comment here...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This comment will appear on the map at the center of your current view.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFAC1B22),
              ),
              onPressed: () {
                if (commentController.text.trim().isNotEmpty && _isMapReady) {
                  setState(() {
                    _adminComments.add(
                      AdminComment(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        text: commentController.text.trim(),
                        author: 'Admin User', // In real app, get from auth
                        timestamp: DateTime.now(),
                        position: _mapController.camera.center,
                      ),
                    );
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Comment added successfully'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('Post Comment', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showAllCommentsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.comment, color: Color(0xFFAC1B22)),
              SizedBox(width: 8),
              Text('All Admin Comments'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: _adminComments.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'No comments yet',
                      style: TextStyle(fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _adminComments.length,
                    itemBuilder: (context, index) {
                      final comment = _adminComments[_adminComments.length - 1 - index];
                      final timeAgo = _getTimeAgo(comment.timestamp);
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFAC1B22),
                            child: Icon(Icons.person, color: Colors.white, size: 20),
                          ),
                          title: Text(
                            comment.text,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            '${comment.author} • $timeAgo',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.location_on, size: 20),
                            onPressed: () {
                              Navigator.pop(context);
                              if (_isMapReady) {
                                _mapController.move(comment.position, 16);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
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
              ),
              
              // Route polyline
              if (_routePolylines.isNotEmpty)
                PolylineLayer(
                  polylines: _routePolylines,
                ),
              
              // Incident markers
              MarkerLayer(
                markers: _incidentMarkers,
              ),
              
              // Route markers (user location and destination)
              if (_routeMarkers.isNotEmpty)
                MarkerLayer(
                  markers: _routeMarkers,
                ),
              
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
          
          // Admin comment markers floating on map
          if (_showComments && _isMapReady)
            ..._adminComments.map((comment) {
              try {
                // Get screen position for this comment
                final point = _mapController.camera.latLngToScreenPoint(comment.position);
                
                return Positioned(
                  left: point.x - 120, // Center the card
                  top: point.y - 60,
                  child: GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xFFAC1B22),
                                radius: 16,
                                child: Icon(Icons.person, color: Colors.white, size: 16),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                comment.author,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(comment.text),
                              const SizedBox(height: 8),
                              Text(
                                _getTimeAgo(comment.timestamp),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      width: 240,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xFFAC1B22),
                                radius: 12,
                                child: Icon(Icons.admin_panel_settings, color: Colors.white, size: 14),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  comment.author,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                _getTimeAgo(comment.timestamp),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            comment.text,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              } catch (e) {
                // If there's an error with map controller, don't show the comment marker
                print('Error showing comment marker: $e');
                return const SizedBox.shrink();
              }
            }).toList(),
          
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'LIVE MAP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          // Admin comment button
                          Stack(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.admin_panel_settings,
                                  color: Colors.white,
                                ),
                                onPressed: _showAdminCommentDialog,
                                tooltip: 'Add Admin Comment',
                              ),
                              if (_adminComments.isNotEmpty)
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.orange,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '${_adminComments.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          // View all comments button
                          IconButton(
                            icon: const Icon(Icons.comment, color: Colors.white),
                            onPressed: _showAllCommentsDialog,
                            tooltip: 'View All Comments',
                          ),
                          // Route button
                          IconButton(
                            icon: Icon(
                              _isTracking ? Icons.stop : Icons.route,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              if (_isTracking) {
                                _stopTracking();
                              } else if (_routePoints.isNotEmpty) {
                                _startTracking();
                              } else {
                                _showRouteDialog();
                              }
                            },
                          ),
                          // Filter button
                          IconButton(
                            icon: const Icon(Icons.filter_list, color: Colors.white),
                            onPressed: () {
                              _showFilterDialog();
                            },
                          ),
                          // Refresh button
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.white),
                            onPressed: () {
                              setState(() {
                                _incidentMarkers.clear();
                                _addSampleMarkers();
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
          
          // Route information card (top right)
          if (_routeInstructions.isNotEmpty && !_isRouting)
            Positioned(
              top: 80,
              right: 16,
              left: 16,
              child: Card(
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Route to Destination',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: _clearRoute,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_estimatedDistance.toStringAsFixed(2)} km • $_estimatedTime',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _routeInstructions,
                        style: const TextStyle(fontSize: 14),
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
                              Icon(Icons.navigation, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text('START NAVIGATION', style: TextStyle(color: Colors.white)),
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
                              Text('STOP TRACKING', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Current location button (bottom right)
          Positioned(
            bottom: 20,
            right: 16,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFAC1B22),
              elevation: 4,
              onPressed: _goToCurrentLocation,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}