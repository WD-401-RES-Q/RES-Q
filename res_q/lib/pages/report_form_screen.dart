import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import '../services/user_session.dart';
import '../services/location_service.dart';
import '../ui/widgets/bottom_nav_bar.dart';
import 'home_page.dart';
import 'emergency_call_screen.dart';

enum LocationSelectionMode { current, pin }

class ReportFormScreen extends StatefulWidget {
  final String incidentType;

  const ReportFormScreen({super.key, required this.incidentType});

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final TextEditingController _informationController = TextEditingController();
  String? _fullName;
  String? _contactNumber;
  late final String _reportDate;

  LocationSelectionMode _locationMode = LocationSelectionMode.current;
  LatLng? _selectedLocation;
  bool _locationLoading = false;
  XFile? _capturedMedia;
  final ImagePicker _picker = ImagePicker();
  bool _submitting = false;
  int _navIndex = 1;

  @override
  void initState() {
    super.initState();
    _reportDate = _formatDate(DateTime.now());
    _loadUserInfo();
  }

  @override
  void dispose() {
    _informationController.dispose();
    super.dispose();
  }

  void _loadUserInfo() {
    final data = UserSession.currentUserData;
    _fullName = data?['fullName'] as String?;
    _contactNumber = data?['contactNumber'] as String?;
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day/${date.year}';
  }

  Future<void> _capturePhoto() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 60,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (photo != null) {
      setState(() {
        _capturedMedia = photo;
      });
    }
  }

  Future<void> _pickFromGallery() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 60,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (image != null) {
      setState(() {
        _capturedMedia = image;
      });
    }
  }

  void _showMediaOptions() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFFF7F8F3),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Camera Icon
                  Container(
                    width: 90,
                    height: 90,
                    decoration: const BoxDecoration(
                      color: Color(0xFFAC1B22),
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Buttons Column
                  Expanded(
                    child: Column(
                      children: [
                        // Capture Image Button
                        SizedBox(
                          width: double.infinity,
                          height: 36,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _capturePhoto();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFAC1B22),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 2,
                            ),
                            child: const Text(
                              'CAPTURE AN IMAGE',
                              style: TextStyle(
                                fontFamily: 'RobotoCondensed',
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Record Video Button
                        SizedBox(
                          width: double.infinity,
                          height: 36,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _pickFromGallery();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFAC1B22),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 2,
                            ),
                            child: const Text(
                              'RECORD A VIDEO',
                              style: TextStyle(
                                fontFamily: 'RobotoCondensed',
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReport() async {
    final location = await _resolveReportLocation();
    if (location == null) return;

    setState(() => _submitting = true);

    try {
      print('📝 Starting report submission...');
      final now = DateTime.now();

      String? mediaUrl;
      String? mediaType;

      // Upload media only if captured (optional)
      if (_capturedMedia != null) {
        final rawName = (_capturedMedia?.name ?? '').isNotEmpty
            ? _capturedMedia!.name
            : (_capturedMedia!.path.split('/').last);
        final safeName = rawName.isNotEmpty
            ? rawName
            : 'report_${now.millisecondsSinceEpoch}';
        final lowerName = safeName.toLowerCase();
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('reports')
            .child('${now.millisecondsSinceEpoch}_$safeName');

        final isVideo =
            lowerName.endsWith('.mp4') ||
            lowerName.endsWith('.mov') ||
            lowerName.endsWith('.m4v');
        final contentType = isVideo ? 'video/mp4' : 'image/jpeg';

        print('📤 Reading media file...');
        final data = await _capturedMedia!.readAsBytes();
        print('📤 Uploading ${data.length} bytes to Firebase Storage...');

        final uploadSnapshot = await storageRef
            .putData(data, SettableMetadata(contentType: contentType))
            .timeout(const Duration(seconds: 60));

        print('🔗 Getting download URL...');
        mediaUrl = await uploadSnapshot.ref.getDownloadURL().timeout(
          const Duration(seconds: 15),
        );
        mediaType = isVideo ? 'video' : 'photo';
        print('✅ Media uploaded: $mediaUrl');
      } else {
        print('⏭️ Skipping media upload (no media captured)');
      }

      print('💾 Saving to Firestore...');
      final docRef = await FirebaseFirestore.instance
          .collection('reports')
          .add({
            'name': _fullName ?? 'Unknown',
            'contactNumber': _contactNumber ?? 'Unknown',
            'incidentType': widget.incidentType,
            'details': _informationController.text.trim(),
            'reportedAt': Timestamp.fromDate(now),
            'gpsSharingEnabled': _locationMode == LocationSelectionMode.current,
            'locationSource': _locationMode == LocationSelectionMode.current
                ? 'current'
                : 'pin',
            'mediaUrl': mediaUrl,
            'mediaType': mediaType,
            'location': GeoPoint(
              location.latitude,
              location.longitude,
            ),
            'status': 'Pending',
            'greenFlags': 0,
            'redFlags': 0,
          })
          .timeout(const Duration(seconds: 15));

      print('✅ Report saved with ID: ${docRef.id}');

      if (!mounted) return;

      // Show success modal
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 32),
              const SizedBox(width: 12),
              Text(
                'Success!',
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          content: Text(
            'Your ${widget.incidentType} report has been submitted successfully.',
            style: const TextStyle(
              fontFamily: 'RobotoCondensed',
              fontWeight: FontWeight.w400,
              fontSize: 14,
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                final reportData = {
                  'name': _fullName ?? 'Unknown',
                  'contactNumber': _contactNumber ?? 'Unknown',
                  'incidentType': widget.incidentType,
                  'details': _informationController.text.trim(),
                  'mediaUrl': mediaUrl,
                  'mediaType': mediaType,
                  'reportedAt': now,
                  'locationSource':
                      _locationMode == LocationSelectionMode.current
                          ? 'current'
                          : 'pin',
                  'locationLat': location.latitude,
                  'locationLng': location.longitude,
                };
                UserSession.setActiveReport(
                  reportId: docRef.id,
                  reportData: reportData,
                );
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => const MainPage(initialIndex: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFAC1B22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'OK',
                style: TextStyle(
                  fontFamily: 'RobotoCondensed',
                  fontWeight: FontWeight.w400,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    } on TimeoutException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload timed out: ${e.message ?? ''}'.trim()),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit report: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<LatLng?> _resolveReportLocation() async {
    setState(() => _locationLoading = true);
    try {
      if (_locationMode == LocationSelectionMode.current) {
        final position = await LocationService.getCurrentPosition();
        if (position == null) {
          _showLocationError('Unable to get current location');
          return null;
        }
        final point = LatLng(position.latitude, position.longitude);
        if (!_isWithinAngeles(point)) {
          _showLocationError(
            'Location must be inside Angeles City coverage',
          );
          return null;
        }
        _selectedLocation = point;
        return point;
      }
      if (_selectedLocation == null) {
        _showLocationError('Please pin a location to continue');
        return null;
      }
      if (!_isWithinAngeles(_selectedLocation!)) {
        _showLocationError(
          'Pinned location must be inside Angeles City coverage',
        );
        return null;
      }
      return _selectedLocation;
    } finally {
      if (mounted) {
        setState(() => _locationLoading = false);
      }
    }
  }

  bool _isWithinAngeles(LatLng point) {
    const center = LatLng(15.1450, 120.5887);
    const radiusMeters = 6000.0;
    final distance = const Distance().as(
      LengthUnit.Meter,
      center,
      point,
    );
    return distance <= radiusMeters;
  }

  void _showLocationError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Location Issue',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Color(0xFF111827),
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: 'RobotoCondensed',
            fontWeight: FontWeight.w400,
            fontSize: 14,
            color: Color(0xFF4B5563),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFAC1B22),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'OK',
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

  Future<void> _openPinPicker() async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => const _PinPickerPage(),
      ),
    );
    if (picked == null) return;
    setState(() {
      _selectedLocation = picked;
    });
  }

  Widget _buildLocationOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF3F3) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFFAC1B22) : Colors.black26,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'RobotoCondensed',
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: isSelected ? const Color(0xFFAC1B22) : Colors.black87,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F3),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              children: [
                // Logo - Tap to go back to home
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                  },
                  child: SizedBox(
                    height: 50,
                    child: SvgPicture.asset(
                      "assets/icons/RESQ-LOGO.svg",
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.image_not_supported,
                        size: 30,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Incident label (HEADING - Roboto Black)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.incidentType,
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFAC1B22),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Reporter info card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow('Name', _fullName ?? 'Not available'),
                      const SizedBox(height: 8),
                      _infoRow(
                        'Contact Number',
                        _contactNumber ?? 'Not available',
                      ),
                      const SizedBox(height: 8),
                      _infoRow('Date', _reportDate),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Information TextArea
                Container(
                  height: 190,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: TextField(
                    controller: _informationController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontFamily: 'RobotoCondensed',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.black,
                    ),
                    decoration: const InputDecoration(
                      hintText:
                          "Please tell us more about the incident...(Optional)",
                      hintStyle: TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: Colors.black,
                      ),
                      contentPadding: EdgeInsets.all(16),
                      border: InputBorder.none,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Capture Photo/Video Row
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            _capturedMedia == null
                                ? "(Optional) CAPTURE PHOTO/VIDEO"
                                : "✓ Media captured",
                            style: const TextStyle(
                              fontFamily: 'RobotoCondensed',
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: GestureDetector(
                        onTap: _showMediaOptions,
                        child: Container(
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFFAC1B22),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Location selection
                Column(
                  children: [
                    const Text(
                      'Choose Report Location',
                      style: TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLocationOption(
                          label: 'CURRENT LOCATION',
                          isSelected:
                              _locationMode == LocationSelectionMode.current,
                          onTap: () {
                            setState(() {
                              _locationMode = LocationSelectionMode.current;
                            });
                          },
                        ),
                        const SizedBox(width: 12),
                        _buildLocationOption(
                          label: 'PIN LOCATION',
                          isSelected:
                              _locationMode == LocationSelectionMode.pin,
                          onTap: () {
                            setState(() {
                              _locationMode = LocationSelectionMode.pin;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_locationMode == LocationSelectionMode.pin)
                      SizedBox(
                        width: 180,
                        child: OutlinedButton.icon(
                          onPressed: _openPinPicker,
                          icon: const Icon(Icons.location_on_outlined),
                          label: Text(
                            _selectedLocation == null
                                ? 'Pick on map'
                                : 'Update pin',
                            style: const TextStyle(
                              fontFamily: 'RobotoCondensed',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFAC1B22),
                            side: const BorderSide(
                              color: Color(0xFFAC1B22),
                            ),
                          ),
                        ),
                      ),
                    if (_locationMode == LocationSelectionMode.pin &&
                        _selectedLocation != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Pinned: ${_selectedLocation!.latitude.toStringAsFixed(5)}, '
                          '${_selectedLocation!.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontSize: 11,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 14),

                // Confirm Button - Rounded corners, drop shadow
                Container(
                  width: 220,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _locationLoading ? null : _confirmReport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC806),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            "CONFIRM",
                            style: TextStyle(
                              fontFamily: 'RobotoCondensed',
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                // Emergency Call Button - Circular with yellow border and drop shadow
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      print("Emergency call button pressed");
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EmergencyCallScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFAC1B22),
                      shape: const CircleBorder(
                        side: BorderSide(color: Color(0xFFFFC806), width: 6),
                      ),
                      elevation: 0,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Icon(
                      Icons.phone,
                      color: Colors.white,
                      size: 60,
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _navIndex,
        onTap: (index) {
          setState(() {
            _navIndex = index;
          });
          // Navigate back to MainPage
          Navigator.pushReplacementNamed(context, '/main');
        },
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '$label:',
          style: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Colors.black,
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontFamily: 'RobotoCondensed',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }
}

class _PinPickerPage extends StatefulWidget {
  const _PinPickerPage();

  @override
  State<_PinPickerPage> createState() => _PinPickerPageState();
}

class _PinPickerPageState extends State<_PinPickerPage> {
  static const LatLng _center = LatLng(15.1450, 120.5887);
  static const double _radiusMeters = 6000;

  final MapController _mapController = MapController();
  LatLng? _selected;

  bool _isWithinAngeles(LatLng point) {
    final distance = const Distance().as(
      LengthUnit.Meter,
      _center,
      point,
    );
    return distance <= _radiusMeters;
  }

  void _confirmSelection() {
    if (_selected == null) {
      _showPinPickerError('Tap on the map to pin a location');
      return;
    }
    if (!_isWithinAngeles(_selected!)) {
      _showPinPickerError('Pinned location must be inside Angeles City coverage');
      return;
    }
    Navigator.pop(context, _selected);
  }

  void _showPinPickerError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Location Issue',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Color(0xFF111827),
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: 'RobotoCondensed',
            fontWeight: FontWeight.w400,
            fontSize: 14,
            color: Color(0xFF4B5563),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFAC1B22),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'OK',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 13.5,
              minZoom: 10,
              maxZoom: 18,
              onTap: (tapPosition, point) {
                setState(() {
                  _selected = point;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.resq.emergency_app',
                maxZoom: 19,
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _center,
                    radius: _radiusMeters,
                    useRadiusInMeter: true,
                    color: const Color(0xFF4CAF50).withOpacity(0.08),
                    borderColor: const Color(0xFF4CAF50).withOpacity(0.55),
                    borderStrokeWidth: 2.0,
                  ),
                ],
              ),
              if (_selected != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selected!,
                      width: 48,
                      height: 48,
                      child: const Icon(
                        Icons.location_on,
                        color: Color(0xFFAC1B22),
                        size: 40,
                      ),
                    ),
                  ],
                ),
            ],
          ),
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
                        'PIN LOCATION',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _confirmSelection,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFC806),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('Confirm'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
