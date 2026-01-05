import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';
import '../widgets/bottom_nav_bar.dart';
import 'home_page.dart';

class ReportMapPage extends StatefulWidget {
  const ReportMapPage({
    super.key,
    required this.reportId,
    required this.reportData,
  });

  final String reportId;
  final Map<String, dynamic> reportData;

  @override
  State<ReportMapPage> createState() => _ReportMapPageState();
}

class _ReportMapPageState extends State<ReportMapPage>
    with AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();

  // Default location (Angeles City, Central Luzon, Philippines)
  final LatLng _initialCenter = const LatLng(15.1450, 120.5887);
  final double _initialZoom = 14.0;

  LatLng? _userLocation;
  bool _locationShared = false;
  bool _showSuccessCard = false;
  bool _showReportCard = false;
  int _navIndex = 2;

  @override
  void initState() {
    super.initState();
    _userLocation = _initialCenter;

    // Show location sharing modal automatically
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLocationSharingModal();
    });
  }

  Future<void> _showLocationSharingModal() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.location_on, color: Color(0xFFAC1B22), size: 28),
            const SizedBox(width: 12),
            Text(
              'Share Location',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          'Please share your location so emergency responders can find you quickly.',
          style: GoogleFonts.poppins(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Skip', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFAC1B22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Share Location',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
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

  Widget _buildReportSheet(ScrollController scrollController) {
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
                    style: GoogleFonts.poppins(
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
                        widget.reportData['mediaUrl'],
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
                      widget.reportData['incidentType'] ?? 'Unknown',
                      style: GoogleFonts.poppins(
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
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _detailRow('Name', widget.reportData['name'] ?? 'Unknown'),
                  const SizedBox(height: 8),
                  _detailRow(
                    'Contact',
                    widget.reportData['contactNumber'] ?? 'Not provided',
                  ),
                  const SizedBox(height: 20),

                  // Date and time
                  Text(
                    'Report Details',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _detailRow(
                    'Date & Time',
                    widget.reportData['reportedAt'] != null
                        ? DateFormat(
                            'MMM dd, yyyy h:mm a',
                          ).format(widget.reportData['reportedAt'])
                        : 'Unknown',
                  ),
                  const SizedBox(height: 8),
                  if (widget.reportData['mediaType'] != null)
                    _detailRow(
                      'Media Type',
                      widget.reportData['mediaType'] == 'video'
                          ? 'Video'
                          : 'Photo',
                    ),
                  const SizedBox(height: 20),

                  // Responder Information
                  if (widget.reportData['responderName'] != null ||
                      widget.reportData['responderStatus'] != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergency Responder',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (widget.reportData['responderName'] != null)
                          _detailRow(
                            'Responder',
                            widget.reportData['responderName'],
                          ),
                        const SizedBox(height: 8),
                        if (widget.reportData['responderStatus'] != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Status',
                                style: GoogleFonts.poppins(
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
                                    widget.reportData['responderStatus'],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  widget.reportData['responderStatus'],
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 20),
                      ],
                    ),

                  // Annotations
                  if (widget.reportData['annotations'] != null &&
                      (widget.reportData['annotations'] as String).isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Responder Notes',
                          style: GoogleFonts.poppins(
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
                                  style: GoogleFonts.poppins(
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
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.reportData['details'],
                          style: GoogleFonts.poppins(
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
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.poppins(
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
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to view details again',
                      style: GoogleFonts.poppins(
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
    final status = widget.reportData['responderStatus']
        ?.toString()
        .toLowerCase();
    if (status == null) return false;

    return status.contains('arrived') ||
        status.contains('on scene') ||
        status.contains('completed') ||
        status.contains('resolved');
  }

  Color _getStatusColor(String? status) {
    if (status == null) return Colors.grey;

    switch (status.toLowerCase()) {
      case 'responding':
      case 'en route':
        return Colors.blue;
      case 'arrived':
      case 'on scene':
        return Colors.orange;
      case 'completed':
      case 'resolved':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return const Color(0xFFAC1B22);
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
              ),

              // User location marker
              if (_userLocation != null && _locationShared)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userLocation!,
                      width: 50,
                      height: 50,
                      child: const Icon(
                        Icons.person_pin_circle,
                        color: Colors.blue,
                        size: 50,
                      ),
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
                      IconButton(
                        icon: const Icon(
                          Icons.my_location,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          if (_userLocation != null) {
                            _mapController.move(_userLocation!, 16.0);
                          }
                        },
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
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Emergency responders will be notified.',
                              style: GoogleFonts.poppins(
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
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _navIndex,
        onTap: (index) {
          if (index != _navIndex) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => MainPage(initialIndex: index)),
            );
          }
        },
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
