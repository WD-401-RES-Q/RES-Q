import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
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
  
  // Simulate moving along route
  Timer? _trackingTimer;

  @override
  void initState() {
    super.initState();
    _addSampleMarkers();
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
          
          // Floating action button for current location
          Positioned(
            bottom: 20,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton(
                  backgroundColor: const Color(0xFFAC1B22),
                  onPressed: _goToCurrentLocation,
                  child: const Icon(Icons.my_location, color: Colors.white),
                ),
                const SizedBox(height: 16),
                if (_isTracking)
                  FloatingActionButton(
                    backgroundColor: Colors.blue,
                    onPressed: () {
                      // Simulate emergency stop
                      _stopTracking();
                      _showIncidentInfo('Emergency Stop', 'Emergency responder has stopped en route');
                    },
                    child: const Icon(Icons.emergency, color: Colors.white),
                  ),
              ],
            ),
          ),
          
          // Legend card
          Positioned(
            bottom: 20,
            left: 16,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Legend',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _legendItem(Icons.local_fire_department, Colors.red, 'Fire'),
                    _legendItem(Icons.warning, Colors.orange, 'Road Incident'),
                    _legendItem(Icons.water, Colors.blue, 'Flood'),
                    _legendItem(Icons.medical_services, Colors.yellow, 'Medical'),
                    const Divider(height: 16),
                    _legendItem(Icons.location_on, Colors.blue, 'Your Location'),
                    _legendItem(Icons.flag, Colors.red, 'Destination'),
                    _legendItem(Icons.route, Color(0xFF4285F4), 'Route'),
                  ],
                ),
              ),
            ),
          ),
          
          // Zoom controls
          Positioned(
            bottom: 100,
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

  Widget _legendItem(IconData icon, Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
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
          title: const Text('Set Destination'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Search Location'),
                onTap: () {
                  Navigator.pop(context);
                  // Implement location search
                },
              ),
              ListTile(
                leading: const Icon(Icons.map),
                title: const Text('Tap on Map'),
                subtitle: const Text('Tap anywhere on map to set destination'),
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
                title: const Text('Use Current Location'),
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
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Filter Incidents'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title: const Text('Fire'),
                value: true,
                onChanged: (bool? value) {},
                secondary: const Icon(Icons.local_fire_department, color: Colors.red),
              ),
              CheckboxListTile(
                title: const Text('Flood'),
                value: true,
                onChanged: (bool? value) {},
                secondary: const Icon(Icons.water, color: Colors.blue),
              ),
              CheckboxListTile(
                title: const Text('Medical'),
                value: true,
                onChanged: (bool? value) {},
                secondary: const Icon(Icons.medical_services, color: Colors.yellow),
              ),
              CheckboxListTile(
                title: const Text('Vehicular'),
                value: true,
                onChanged: (bool? value) {},
                secondary: const Icon(Icons.car_crash, color: Colors.purple),
              ),
              CheckboxListTile(
                title: const Text('Road Obstruction'),
                value: true,
                onChanged: (bool? value) {},
                secondary: const Icon(Icons.warning, color: Colors.orange),
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
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }
}