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

  @override
  void initState() {
    super.initState();
    _addSampleMarkers();
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
              // Navigate to incident details
            },
            child: const Text('View Details'),
          ),
        ],
      ),
    );
  }

  void _goToCurrentLocation() {
    _mapController.move(_initialCenter, _initialZoom);
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
            ),
            children: [
              // Map tiles from OpenStreetMap
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.resq.emergency_app',
                maxZoom: 19,
              ),
              
              // Incident markers
              MarkerLayer(
                markers: _incidentMarkers,
              ),
              
              // Attribution (required for OSM)
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () {}, // Link to OSM copyright
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
                color: const Color(0xFF004FC6),
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
          
          // Floating action button for current location
          Positioned(
            bottom: 20,
            right: 16,
            child: FloatingActionButton(
              backgroundColor: const Color(0xFF004FC6),
              onPressed: _goToCurrentLocation,
              child: const Icon(Icons.my_location, color: Colors.white),
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