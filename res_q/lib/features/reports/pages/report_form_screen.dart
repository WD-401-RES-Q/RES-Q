import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import '../../../common/services/user_session.dart';
import '../../../common/services/location_service.dart';
import '../../../common/widgets/bottom_nav_bar.dart';
import '../../home/pages/home_page.dart';
import '../../emergency/pages/emergency_call_screen.dart';

enum LocationSelectionMode { current, pin }

class ReportFormScreen extends StatefulWidget {
  final String incidentType;

  const ReportFormScreen({super.key, required this.incidentType});

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final TextEditingController _informationController = TextEditingController();
  final TextEditingController _plateNumberController = TextEditingController();
  final TextEditingController _barangayController = TextEditingController();
  final TextEditingController _otherIncidentController =
      TextEditingController();
  String? _fullName;
  String? _contactNumber;
  late final String _reportDate;
  String? _vehicleBodyType;
  String? _vehicleColor;
  String? _mediaError;
  String? _otherIncidentError;

  LocationSelectionMode _locationMode = LocationSelectionMode.current;
  LatLng? _selectedLocation;
  bool _locationLoading = false;
  XFile? _capturedMedia;
  final ImagePicker _picker = ImagePicker();
  bool _submitting = false;
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    _reportDate = _formatDate(DateTime.now());
    _loadUserInfo();
  }

  @override
  void dispose() {
    _informationController.dispose();
    _plateNumberController.dispose();
    _barangayController.dispose();
    _otherIncidentController.dispose();
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
        _mediaError = null;
      });
    }
  }

  Future<void> _captureVideo() async {
    final XFile? video = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(seconds: 30),
    );
    if (video != null) {
      setState(() {
        _capturedMedia = video;
        _mediaError = null;
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
                              _captureVideo();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFAC1B22),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 2,
                            ),
                            child: const Text(
                              'CAPTURE A VIDEO',
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
    // Clear previous errors
    setState(() {
      _mediaError = null;
      _otherIncidentError = null;
    });

    if (_isVehicularIncident()) {
      final plateNumber = _plateNumberController.text.trim();
      if (plateNumber.isEmpty ||
          _vehicleBodyType == null ||
          _vehicleColor == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please complete all vehicle details.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    if (_isFireOrFloodIncident()) {
      final barangay = _barangayController.text.trim();
      if (barangay.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter the barangay.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    if (_isOthersIncident()) {
      final otherIncident = _otherIncidentController.text.trim();
      if (otherIncident.isEmpty) {
        setState(
          () => _otherIncidentError = 'Please specify the incident type',
        );
        return;
      }
    }
    // Validate required media
    if (_capturedMedia == null) {
      setState(() => _mediaError = 'Photo or video is required');
      return;
    }

    final hasReachedLimit = await _hasReachedReportLimit();
    if (hasReachedLimit) {
      if (!mounted) return;
      await _showReportLimitDialog();
      return;
    }
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

      // Generate a unique report ID for easier tracking
      final reportId = _generateReportId();
      print('🆔 Generated Report ID: $reportId');

      // Get user ID safely
      final userId = UserSession.getUserId();
      if (userId == null || userId.isEmpty) {
        throw Exception(
          'Phone number is required to submit a report. Please update your profile.',
        );
      }

      // Validate userId matches contact number
      final sanitizedContactNumber = _contactNumber?.replaceAll(
        RegExp(r'\D'),
        '',
      );
      if (sanitizedContactNumber == null || sanitizedContactNumber.isEmpty) {
        throw Exception('Contact number is required to submit a report.');
      }
      if (userId != sanitizedContactNumber) {
        throw Exception(
          'Contact number mismatch. Your profile phone ($userId) does not match the form contact number ($sanitizedContactNumber).',
        );
      }

      final docRef = await FirebaseFirestore.instance
          .collection('reports')
          .add({
            'reportId': reportId, // Custom readable report ID
            'userId': userId, // User ID for tracking
            'name': _fullName ?? 'Unknown',
            'contactNumber': _contactNumber ?? 'Unknown',
            'incidentType': widget.incidentType,
            'details': _informationController.text.trim(),
            if (_isVehicularIncident()) ...{
              'vehiclePlateNumber': _plateNumberController.text.trim(),
              'vehicleBodyType': _vehicleBodyType,
              'vehicleColor': _vehicleColor,
            },
            if (_isFireOrFloodIncident()) ...{
              'barangay': _barangayController.text.trim(),
            },
            if (_isOthersIncident()) ...{
              'otherIncidentType': _otherIncidentController.text.trim(),
            },
            'reportedAt': Timestamp.fromDate(now),
            'gpsSharingEnabled': _locationMode == LocationSelectionMode.current,
            'locationSource': _locationMode == LocationSelectionMode.current
                ? 'current'
                : 'pin',
            'mediaUrl': mediaUrl,
            'mediaType': mediaType,
            'location': GeoPoint(location.latitude, location.longitude),
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
                  if (_isVehicularIncident()) ...{
                    'vehiclePlateNumber': _plateNumberController.text.trim(),
                    'vehicleBodyType': _vehicleBodyType,
                    'vehicleColor': _vehicleColor,
                  },
                  if (_isFireOrFloodIncident()) ...{
                    'barangay': _barangayController.text.trim(),
                  },
                  if (_isOthersIncident()) ...{
                    'otherIncidentType': _otherIncidentController.text.trim(),
                  },
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
                UserSession.addActiveReport(
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

  Future<bool> _hasReachedReportLimit() async {
    if (UserSession.activeReportCount >= 2) {
      return true;
    }

    final contactNumber =
        _contactNumber ??
        (UserSession.currentUserData?['contactNumber'] as String?);
    final fallbackName =
        _fullName ?? (UserSession.currentUserData?['fullName'] as String?);

    if (contactNumber == null && fallbackName == null) {
      return false;
    }

    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
        'reports',
      );

      // Primary: Check by contact number
      if (contactNumber != null && contactNumber.isNotEmpty) {
        query = query.where('contactNumber', isEqualTo: contactNumber);
      } else if (fallbackName != null && fallbackName.isNotEmpty) {
        // Fallback: Check by name (less reliable)
        query = query.where('name', isEqualTo: fallbackName);
      } else {
        // No valid identifier - return no results
        query = query.where(
          'contactNumber',
          isEqualTo: '__INVALID_NO_IDENTIFIER__',
        );
        print(
          '⚠️ Warning: No valid identifier (contactNumber or name) for duplicate check',
        );
      }

      final snapshot = await query.get();
      var activeCount = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final status = (data['status'] as String? ?? '').toLowerCase();
        final resolvedAt = data['resolvedAt'];
        final isResolved =
            status == 'resolved' || status == 'incident resolved';
        final isFlagged = status == 'flagged' || status == 'unverified';
        if (!isResolved && !isFlagged && resolvedAt == null) {
          activeCount += 1;
        }
      }

      return activeCount >= 2;
    } catch (e) {
      debugPrint('⚠️ Could not check report limit: $e');
      return UserSession.activeReportCount >= 2;
    }
  }

  Future<void> _showReportLimitDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFAC1B22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.error_outline, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Active Report Limit',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'You already have 2 active reports. Please wait for them to be resolved before submitting a new one.',
          style: TextStyle(
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
          _showLocationError('Location must be inside Angeles City coverage');
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
    final distance = const Distance().as(LengthUnit.Meter, center, point);
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
    final picked = await Navigator.of(
      context,
    ).push<LatLng>(MaterialPageRoute(builder: (_) => const _PinPickerPage()));
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
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  // Back button + logo row
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Color(0xFFAC1B22),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: SizedBox(
                            height: 50,
                            child: Align(
                              alignment: Alignment.center,
                              child: SvgPicture.asset(
                                "assets/icons/RES-Q_LOGO.svg",
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                      Icons.image_not_supported,
                                      size: 30,
                                      color: Colors.blue,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
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

                  if (_isVehicularIncident()) _buildVehicleDetailsRow(),

                  if (_isVehicularIncident()) const SizedBox(height: 16),

                  if (_isFireOrFloodIncident()) _buildBarangayField(),

                  if (_isFireOrFloodIncident()) const SizedBox(height: 16),

                  if (_isOthersIncident()) _buildOtherIncidentField(),

                  if (_isOthersIncident()) const SizedBox(height: 16),

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
                      maxLength: 256,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      inputFormatters: [LengthLimitingTextInputFormatter(256)],
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
                        counterStyle: TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontSize: 11,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Capture Photo/Video Row (Required)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Container(
                              height: 64,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _mediaError != null
                                      ? Colors.red
                                      : Colors.black,
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  _capturedMedia == null
                                      ? "CAPTURE PHOTO/VIDEO *"
                                      : "✓ Media captured",
                                  style: TextStyle(
                                    fontFamily: 'RobotoCondensed',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    color: _capturedMedia == null
                                        ? (_mediaError != null
                                              ? Colors.red
                                              : Colors.black)
                                        : const Color(0xFF22C55E),
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
                      if (_mediaError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _mediaError!,
                            style: const TextStyle(
                              fontFamily: 'RobotoCondensed',
                              fontSize: 12,
                              color: Colors.red,
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
                          child: ElevatedButton.icon(
                            onPressed: _openPinPicker,
                            icon: const Icon(
                              Icons.location_on,
                              color: Colors.white,
                              size: 20,
                            ),
                            label: Text(
                              _selectedLocation == null
                                  ? 'PIN ON MAP'
                                  : 'UPDATE PIN',
                              style: const TextStyle(
                                fontFamily: 'RobotoCondensed',
                                fontWeight: FontWeight.w500,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFAC1B22),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
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
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _navIndex,
        onTap: (index) {
          setState(() {
            _navIndex = index;
          });
          // Navigate back to MainPage with selected tab
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => MainPage(initialIndex: index)),
          );
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

  /// Generate a unique report ID for easier tracking
  /// Format: RPT-YYYYMMDD-UUID (e.g., RPT-20260203-A1B2C3D4E5F6)
  /// Uses UUID v4 for cryptographically secure, collision-free IDs
  String _generateReportId() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    // Use UUID for guaranteed uniqueness (16 chars for better collision resistance)
    final uuid = const Uuid()
        .v4()
        .replaceAll('-', '')
        .substring(0, 16)
        .toUpperCase();

    return 'RPT-$dateStr-$uuid';
  }

  bool _isVehicularIncident() {
    return widget.incidentType.toUpperCase() == 'VEHICULAR';
  }

  bool _isFireOrFloodIncident() {
    final incident = widget.incidentType.toUpperCase();
    return incident == 'FIRE' || incident == 'FLOOD';
  }

  bool _isOthersIncident() {
    return widget.incidentType.toUpperCase() == 'OTHERS';
  }

  Widget _buildOtherIncidentField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabeledField(
          label: 'Specific Incident Type *',
          borderColor: _otherIncidentError != null ? Colors.red : Colors.black,
          child: TextField(
            controller: _otherIncidentController,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_otherIncidentError != null) {
                setState(() => _otherIncidentError = null);
              }
            },
            style: const TextStyle(
              fontFamily: 'RobotoCondensed',
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Colors.black,
            ),
            decoration: const InputDecoration(
              hintText: 'e.g., Medical Emergency, Crime, etc.',
              hintStyle: TextStyle(
                fontFamily: 'RobotoCondensed',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.black54,
              ),
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
            ),
          ),
        ),
        if (_otherIncidentError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _otherIncidentError!,
              style: const TextStyle(
                fontFamily: 'RobotoCondensed',
                fontSize: 12,
                color: Colors.red,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVehicleDetailsRow() {
    const vehicleBodies = [
      'Sedan',
      'SUV',
      'Hatchback',
      'Pickup',
      'Van',
      'Motorcycle',
      'Bus',
      'Truck',
      'Other',
    ];
    const vehicleColors = [
      'Black',
      'White',
      'Gray',
      'Red',
      'Orange',
      'Yellow',
      'Green',
      'Blue',
      'Purple',
    ];
    const colorSwatches = {
      'Black': Colors.black,
      'White': Colors.white,
      'Gray': Color(0xFF9CA3AF),
      'Red': Color(0xFFDC2626),
      'Orange': Color(0xFFF97316),
      'Yellow': Color(0xFFFACC15),
      'Green': Color(0xFF22C55E),
      'Blue': Color(0xFF2563EB),
      'Purple': Color(0xFF7C3AED),
    };
    return Row(
      children: [
        Expanded(
          child: _buildLabeledField(
            label: 'Plate Number *',
            child: TextField(
              controller: _plateNumberController,
              textCapitalization: TextCapitalization.characters,
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(
                fontFamily: 'RobotoCondensed',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.black,
              ),
              decoration: const InputDecoration(
                hintText: 'ABC123',
                hintStyle: TextStyle(
                  fontFamily: 'RobotoCondensed',
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.black54,
                ),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildLabeledField(
            label: 'Body Type *',
            child: DropdownButtonHideUnderline(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButton<String>(
                  value: _vehicleBodyType,
                  hint: const Text(
                    'Select',
                    style: TextStyle(
                      fontFamily: 'RobotoCondensed',
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                  isExpanded: true,
                  isDense: true,
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: Color(0xFFAC1B22),
                  ),
                  dropdownColor: Colors.white,
                  items: vehicleBodies
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value,
                            style: const TextStyle(
                              fontFamily: 'RobotoCondensed',
                              fontSize: 12,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _vehicleBodyType = value);
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildLabeledField(
            label: 'Color *',
            child: DropdownButtonHideUnderline(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButton<String>(
                  value: _vehicleColor,
                  hint: const Text(
                    'Select',
                    style: TextStyle(
                      fontFamily: 'RobotoCondensed',
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                  isExpanded: true,
                  isDense: true,
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: Color(0xFFAC1B22),
                  ),
                  selectedItemBuilder: (context) {
                    return vehicleColors.map((value) {
                      final color = colorSwatches[value] ?? Colors.transparent;
                      return Row(
                        children: [
                          _buildColorSwatch(color),
                          const SizedBox(width: 8),
                          Text(
                            value,
                            style: const TextStyle(
                              fontFamily: 'RobotoCondensed',
                              fontSize: 12,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      );
                    }).toList();
                  },
                  items: vehicleColors
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Row(
                            children: [
                              _buildColorSwatch(
                                colorSwatches[value] ?? Colors.transparent,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                value,
                                style: const TextStyle(
                                  fontFamily: 'RobotoCondensed',
                                  fontSize: 12,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _vehicleColor = value);
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColorSwatch(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.black12, width: 1),
      ),
    );
  }

  Widget _buildBarangayField() {
    const barangays = [
      'Agapito del Rosario',
      'Amsic',
      'Anunas',
      'Balibago',
      'Capaya',
      'Claro M. Recto',
      'Cuayan',
      'Cutcut',
      'Cutud',
      'Lourdes North West',
      'Lourdes Sur',
      'Lourdes Sur East',
      'Malabanias',
      'Margot',
      'Marisol',
      'Mining',
      'Ninoy Aquino',
      'Pampang',
      'Pandan',
      'Poblacion',
      'Pulungbulu',
      'Pulung Cacutud',
      'Pulung Maragul',
      'Salapungan',
      'San Jose',
      'San Nicolas',
      'Santa Teresita',
      'Santa Trinidad',
      'Santo Cristo',
      'Santo Domingo',
      'Santo Rosario',
      'Sapalibutad',
      'Sula',
      'Tabun',
      'Virgen delos Remedios',
    ];
    return _buildLabeledField(
      label: 'Barangay *',
      child: Autocomplete<String>(
        initialValue: TextEditingValue(text: _barangayController.text),
        optionsBuilder: (TextEditingValue value) {
          final query = value.text.trim().toLowerCase();
          if (query.isEmpty) {
            return const Iterable<String>.empty();
          }
          return barangays.where(
            (option) => option.toLowerCase().contains(query),
          );
        },
        onSelected: (selection) {
          _barangayController.text = selection;
        },
        fieldViewBuilder:
            (context, textEditingController, focusNode, onFieldSubmitted) {
              return TextField(
                controller: textEditingController,
                focusNode: focusNode,
                textCapitalization: TextCapitalization.words,
                onChanged: (value) => _barangayController.text = value,
                style: const TextStyle(
                  fontFamily: 'RobotoCondensed',
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.black,
                ),
                decoration: const InputDecoration(
                  hintText: 'Enter barangay',
                  hintStyle: TextStyle(
                    fontFamily: 'RobotoCondensed',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Colors.black54,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              );
            },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return ListTile(
                      dense: true,
                      title: Text(
                        option,
                        style: const TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontSize: 12,
                        ),
                      ),
                      onTap: () => onSelected(option),
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemCount: options.length,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLabeledField({
    required String label,
    required Widget child,
    Color borderColor = Colors.black,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'RobotoCondensed',
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: child,
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
  LatLng? _currentLocation;
  bool _locationChecked = false;
  StreamSubscription<Position>? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
    try {
      // Get initial position
      final position = await LocationService.getCurrentPosition();
      if (position != null && mounted) {
        final currentPos = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentLocation = currentPos;
        });

        // Check if user is outside Angeles City (only show once)
        if (!_locationChecked && !_isWithinAngeles(currentPos)) {
          _locationChecked = true;
          _showOutsideAreaError();
        }
      }

      // Start listening to location updates
      _locationSubscription = LocationService.getPositionStream().listen(
        (position) {
          if (mounted) {
            final newPos = LatLng(position.latitude, position.longitude);
            setState(() {
              _currentLocation = newPos;
            });

            // Check if user moved outside Angeles City
            if (!_locationChecked && !_isWithinAngeles(newPos)) {
              _locationChecked = true;
              _showOutsideAreaError();
            }
          }
        },
        onError: (e) {
          debugPrint('Location stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('Error starting location tracking: $e');
    }
  }

  void _showOutsideAreaError() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFAC1B22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Outside Coverage Area',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Your current location is outside the Angeles City area. You can still pin a location within the coverage area to submit your report.',
          style: TextStyle(
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
              'I Understand',
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

  bool _isWithinAngeles(LatLng point) {
    final distance = const Distance().as(LengthUnit.Meter, _center, point);
    return distance <= _radiusMeters;
  }

  void _confirmSelection() {
    if (_selected == null) {
      _showPinPickerError(
        'Please tap on the map to select the incident location',
      );
      return;
    }

    // Check if the incident location is within Angeles City
    if (!_isWithinAngeles(_selected!)) {
      _showPinPickerError(
        'The incident location must be within Angeles City coverage area.',
      );
      return;
    }

    // RESTORED: Check if the user's current location is within Angeles City
    // This prevents users outside Angeles from submitting reports
    if (_currentLocation == null || !_isWithinAngeles(_currentLocation!)) {
      _showUserLocationError();
      return;
    }

    Navigator.pop(context, _selected);
  }

  // RESTORED: Show error when user is outside Angeles City
  void _showUserLocationError() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFAC1B22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.location_off, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Location Issue',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'You cannot submit a report because your current location is outside Angeles City. Please move within the Angeles City coverage area to submit a report.',
          style: TextStyle(
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
              // Current location marker (blue)
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation!,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              // Selected pin marker (red)
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
