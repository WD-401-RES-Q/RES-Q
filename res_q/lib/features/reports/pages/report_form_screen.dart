import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:io';
import '../../../common/services/user_session.dart';
import '../../../common/services/location_service.dart';
import '../../../common/services/shell_navigation_service.dart';
import '../../../common/theme/app_theme.dart';
import '../../../common/utils/phone_utils.dart';
import '../../../common/widgets/bottom_nav_bar.dart';
import '../../../common/widgets/app_buttons.dart';
import '../../../common/widgets/app_snackbar.dart';
import '../../emergency/pages/emergency_call_screen.dart';

void _debugLog(Object? message) {
  if (kDebugMode) {
    debugPrint('$message');
  }
}

enum LocationSelectionMode { current, pin }

enum CapturedMediaType { photo, video }

Future<void> _showReportThemedDialog({
  required BuildContext context,
  required String title,
  required String message,
  String primaryLabel = 'OK',
  VoidCallback? onPrimaryPressed,
  String? secondaryLabel,
  VoidCallback? onSecondaryPressed,
  IconData icon = Icons.info_outline_rounded,
  Color iconColor = AppTheme.appRed,
  bool barrierDismissible = true,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.52),
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.appOffWhite,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: AppTheme.appOffYellow.withValues(alpha: 0.45),
            width: 1.4,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4A000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.appOffYellow.withValues(alpha: 0.78),
                        width: 1.8,
                      ),
                    ),
                    child: Icon(icon, color: iconColor, size: 23),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        color: AppTheme.appBlack,
                        height: 1.05,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(
                  fontFamily: 'RobotoCondensed',
                  fontWeight: FontWeight.w400,
                  fontSize: 16,
                  color: AppTheme.appBlack,
                  height: 1.22,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (secondaryLabel != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          onSecondaryPressed?.call();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.appRed,
                          side: BorderSide(
                            color: AppTheme.appRed.withValues(alpha: 0.65),
                            width: 1.4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        child: Text(
                          secondaryLabel,
                          style: const TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        onPrimaryPressed?.call();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.appRed,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      child: Text(
                        primaryLabel,
                        style: const TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
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
}

class _VehicleInvolved {
  _VehicleInvolved();

  final TextEditingController plateController = TextEditingController();
  String? bodyType;
  String? color;

  void dispose() {
    plateController.dispose();
  }
}

class ReportFormScreen extends StatefulWidget {
  final String incidentType;

  const ReportFormScreen({super.key, required this.incidentType});

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final TextEditingController _informationController = TextEditingController();
  final TextEditingController _barangayController = TextEditingController();
  final TextEditingController _otherIncidentController =
      TextEditingController();
  String? _fullName;
  String? _contactNumber;
  late final String _reportDate;
  String? _mediaError;
  String? _otherIncidentError;
  String? _barangayError;
  String? _fireTypeError;
  String? _fireType;

  LocationSelectionMode _locationMode = LocationSelectionMode.current;
  LatLng? _selectedLocation;
  bool _locationLoading = false;
  XFile? _capturedMedia;
  CapturedMediaType? _capturedMediaType;
  final ImagePicker _picker = ImagePicker();
  bool _submitting = false;
  int _navIndex = 0;
  int _injuredCount = 0;
  bool _needsAmbulance = false;
  final List<_VehicleInvolved> _vehicles = <_VehicleInvolved>[];

  @override
  void initState() {
    super.initState();
    _reportDate = _formatDate(DateTime.now());
    _loadUserInfo();
    if (_isVehicularIncident()) {
      _vehicles.add(_VehicleInvolved());
    }
  }

  @override
  void dispose() {
    _informationController.dispose();
    _barangayController.dispose();
    _otherIncidentController.dispose();
    for (final vehicle in _vehicles) {
      vehicle.dispose();
    }
    super.dispose();
  }

  void _loadUserInfo() {
    final data = UserSession.currentUserData;
    final rawFullName = (data?['fullName'] ?? data?['displayName']) as String?;
    final normalizedFullName = rawFullName?.trim();
    _fullName = normalizedFullName != null && normalizedFullName.isNotEmpty
        ? normalizedFullName
        : null;
    _contactNumber = data?['contactNumber'] as String?;
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day/${date.year}';
  }

  bool _isLikelyVideoPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.webm');
  }

  String _capturedMediaDisplayText() {
    if (_capturedMedia == null) return 'CAPTURE PHOTO/VIDEO *';
    final fallbackName = _fileNameFromPath(_capturedMedia!.path);
    final fileName = (_capturedMedia!.name).isNotEmpty
        ? _capturedMedia!.name
        : fallbackName;
    final isVideo =
        _capturedMediaType == CapturedMediaType.video ||
        _isLikelyVideoPath(_capturedMedia!.path);
    final typeLabel = isVideo ? 'Video' : 'Photo';
    return '[OK] $typeLabel captured: $fileName';
  }

  String _fileNameFromPath(String path) {
    final segments = path.split(RegExp(r'[\\/]'));
    return segments.isEmpty ? path : segments.last;
  }

  Future<void> _capturePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 60,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (photo != null) {
        setState(() {
          _capturedMedia = photo;
          _capturedMediaType = CapturedMediaType.photo;
          _mediaError = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Failed to capture photo: $e',
        type: AppSnackBarType.error,
      );
    }
  }

  Future<void> _captureVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 10),
      );
      if (video != null) {
        setState(() {
          _capturedMedia = video;
          _capturedMediaType = CapturedMediaType.video;
          _mediaError = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Failed to capture video: $e',
        type: AppSnackBarType.error,
      );
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
                              'CAPTURE A VIDEO (10s max)',
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
      _barangayError = null;
      _fireTypeError = null;
    });

    if (_isVehicularIncident()) {
      if (_vehicles.isEmpty) {
        _vehicles.add(_VehicleInvolved());
      }
      for (int i = 0; i < _vehicles.length; i++) {
        final vehicle = _vehicles[i];
        final plateNumber = vehicle.plateController.text.trim();
        final plateLimit = _plateLimitForBodyType(vehicle.bodyType);
        if (plateNumber.isEmpty ||
            vehicle.bodyType == null ||
            vehicle.color == null) {
          AppSnackBar.show(
            context,
            'Please complete all details for vehicle ${i + 1}.',
            type: AppSnackBarType.error,
          );
          return;
        }
        if (plateNumber.length > plateLimit) {
          AppSnackBar.show(
            context,
            'Vehicle ${i + 1} plate number exceeds the limit of $plateLimit characters.',
            type: AppSnackBarType.error,
          );
          return;
        }
      }
    }

    if (_isFireIncident() && (_fireType == null || _fireType!.trim().isEmpty)) {
      setState(() => _fireTypeError = 'Type of fire is required');
      AppSnackBar.show(
        context,
        'Please select the type of fire.',
        type: AppSnackBarType.error,
      );
      return;
    }
    final barangay = _barangayController.text.trim();
    if (barangay.isEmpty) {
      setState(() => _barangayError = 'Barangay is required');
      AppSnackBar.show(
        context,
        'Please enter the barangay.',
        type: AppSnackBarType.error,
      );
      return;
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
      _debugLog('Starting report submission...');
      await _ensureStorageAuthSession();
      final now = DateTime.now();

      String? mediaUrl;
      String? mediaType;

      // Upload media only if captured (required by validation above)
      if (_capturedMedia != null) {
        final rawName = (_capturedMedia?.name ?? '').isNotEmpty
            ? _capturedMedia!.name
            : _fileNameFromPath(_capturedMedia!.path);
        final isVideo =
            _capturedMediaType == CapturedMediaType.video ||
            _isLikelyVideoPath(_capturedMedia!.path);
        final defaultExt = isVideo ? '.mp4' : '.jpg';
        final safeName = rawName.isNotEmpty
            ? rawName
            : 'report_${now.millisecondsSinceEpoch}$defaultExt';
        final lowerName = safeName.toLowerCase();
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('reports')
            .child('${now.millisecondsSinceEpoch}_$safeName');

        final contentType = isVideo
            ? (lowerName.endsWith('.mov') ? 'video/quicktime' : 'video/mp4')
            : 'image/jpeg';
        final metadata = SettableMetadata(contentType: contentType);

        _debugLog(
          'Uploading ${isVideo ? 'video' : 'photo'} to Firebase Storage...',
        );
        final uploadTimeout = isVideo
            ? const Duration(seconds: 120)
            : const Duration(seconds: 60);
        final mediaPath = _capturedMedia!.path;
        if (mediaPath.isEmpty) {
          throw Exception('Captured media path is empty.');
        }
        final UploadTask uploadTask;
        if (kIsWeb) {
          // Web runtime does not support dart:io File APIs.
          final mediaBytes = await _capturedMedia!.readAsBytes();
          uploadTask = storageRef.putData(mediaBytes, metadata);
        } else {
          uploadTask = storageRef.putFile(File(mediaPath), metadata);
        }

        final uploadSnapshot = await uploadTask.timeout(uploadTimeout);

        mediaUrl = await uploadSnapshot.ref.getDownloadURL().timeout(
          const Duration(seconds: 20),
        );
        mediaType = isVideo ? 'video' : 'photo';

        // Verify that the object exists in Storage and is readable.
        await uploadSnapshot.ref.getMetadata().timeout(
          const Duration(seconds: 10),
        );
        _debugLog('Media uploaded successfully: $mediaUrl');
      } else {
        _debugLog('Skipping media upload (no media captured)');
      }

      _debugLog('Saving report to Firestore...');

      // Generate a unique report ID for easier tracking
      final reportId = _generateReportId();
      _debugLog('Generated Report ID: $reportId');
      final incidentTypeValue = _incidentTypeForStorage();
      final vehiclesPayload = _isVehicularIncident()
          ? _buildVehiclesPayload()
          : <Map<String, dynamic>>[];
      final firstVehicle = _isVehicularIncident() && vehiclesPayload.isNotEmpty
          ? vehiclesPayload.first
          : null;

      // Get user ID safely
      final userId = UserSession.getUserId();
      if (userId.isEmpty) {
        throw Exception(
          'Phone number is required to submit a report. Please update your profile.',
        );
      }

      // Validate userId matches contact number
      final sanitizedContactNumber = PhoneUtils.sanitize(_contactNumber);
      if (sanitizedContactNumber.isEmpty) {
        throw Exception('Contact number is required to submit a report.');
      }
      if (userId != sanitizedContactNumber) {
        _debugLog(
          '[ERROR] Contact number mismatch: profile=$userId, form=$sanitizedContactNumber',
        );

        FirebaseAnalytics.instance.logEvent(
          name: 'report_contact_mismatch',
          parameters: {
            'profile_phone_length': userId.length,
            'form_phone_length': sanitizedContactNumber.length,
          },
        );

        throw Exception(
          'The contact number you entered does not match your registered phone number. '
          'You must use your own phone number ($userId) to ensure accountability. '
          'If you need to update your registered number, please go to Settings.',
        );
      }

      final docRef = await FirebaseFirestore.instance
          .collection('reports')
          .add({
            'reportId': reportId, // Custom readable report ID
            'userId': userId, // User ID for tracking
            'name': _fullName ?? 'Unknown',
            'contactNumber': _contactNumber ?? 'Unknown',
            'incidentType': incidentTypeValue,
            'details': _informationController.text.trim(),
            if (_isVehicularIncident()) ...{
              // Legacy first-vehicle fields for backward compatibility.
              'vehiclePlateNumber': firstVehicle?['plateNumber'],
              'vehicleBodyType': firstVehicle?['bodyType'],
              'vehicleColor': firstVehicle?['color'],
              // New multi-vehicle fields.
              'vehicleCount': vehiclesPayload.length,
              'vehicles': vehiclesPayload,
            },
            if (_isFireIncident()) 'fireType': _fireType,
            'barangay': _barangayController.text.trim(),
            'injuredCount': _injuredCount,
            'needsAmbulance': _isFloodIncident() ? false : _needsAmbulance,
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
            // Keep incident pin immutable for maps/admin even when user shares
            // live location updates later.
            'location': GeoPoint(location.latitude, location.longitude),
            'incidentLocation': GeoPoint(location.latitude, location.longitude),
            if (_locationMode == LocationSelectionMode.current) ...{
              'reporterLocation': GeoPoint(
                location.latitude,
                location.longitude,
              ),
              'reporterLocationUpdatedAt': Timestamp.fromDate(now),
            },
            'status': 'Pending',
            'greenFlags': 0,
            'redFlags': 0,
          })
          .timeout(const Duration(seconds: 15));

      _debugLog('Report saved with ID: ${docRef.id}');

      if (!mounted) return;

      await _showReportThemedDialog(
        context: context,
        barrierDismissible: false,
        title: 'Success',
        message:
            'Your ${widget.incidentType} report has been submitted successfully.',
        icon: Icons.check_circle_rounded,
        iconColor: const Color(0xFF00A458),
        primaryLabel: 'OK',
        onPrimaryPressed: () {
          final reportData = {
            'name': _fullName ?? 'Unknown',
            'contactNumber': _contactNumber ?? 'Unknown',
            'incidentType': incidentTypeValue,
            'details': _informationController.text.trim(),
            if (_isVehicularIncident()) ...{
              'vehiclePlateNumber': firstVehicle?['plateNumber'],
              'vehicleBodyType': firstVehicle?['bodyType'],
              'vehicleColor': firstVehicle?['color'],
              'vehicleCount': vehiclesPayload.length,
              'vehicles': vehiclesPayload,
            },
            if (_isFireIncident()) 'fireType': _fireType,
            'barangay': _barangayController.text.trim(),
            'injuredCount': _injuredCount,
            'needsAmbulance': _isFloodIncident() ? false : _needsAmbulance,
            if (_isOthersIncident()) ...{
              'otherIncidentType': _otherIncidentController.text.trim(),
            },
            'mediaUrl': mediaUrl,
            'mediaType': mediaType,
            'reportedAt': now,
            'locationSource': _locationMode == LocationSelectionMode.current
                ? 'current'
                : 'pin',
            if (_locationMode == LocationSelectionMode.current) ...{
              'reporterLocationLat': location.latitude,
              'reporterLocationLng': location.longitude,
            },
            'incidentLocationLat': location.latitude,
            'incidentLocationLng': location.longitude,
            'locationLat': location.latitude,
            'locationLng': location.longitude,
          };
          UserSession.addActiveReport(
            reportId: docRef.id,
            reportData: reportData,
          );
          MainShellNavigationService.popToRootAndOpenTab(context, 2);
        },
      );
    } on TimeoutException {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Media upload timed out. Please retry with a shorter/clearer capture.',
        type: AppSnackBarType.error,
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final code = e.code.toLowerCase().trim();
      final message = code == 'unauthorized' || code == 'unauthenticated'
          ? 'Upload blocked by Firebase Storage permissions. '
                'Please log in again and verify Storage rules are deployed.'
          : 'Firebase Storage upload failed (${e.code}). '
                'Please check your connection and Storage rules/quota.';
      AppSnackBar.show(context, message, type: AppSnackBarType.error);
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Failed to submit report: $e',
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _ensureStorageAuthSession() async {
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser != null) {
        return;
      }
      await auth.signInAnonymously();
      _debugLog('Firebase anonymous auth restored for report upload.');
    } on FirebaseAuthException catch (e) {
      final code = e.code.toLowerCase().trim();
      // Project has anonymous auth disabled; continue and rely on Storage rules.
      if (code == 'admin-restricted-operation' ||
          code == 'operation-not-allowed') {
        _debugLog(
          'Anonymous Firebase auth is disabled ($code). Continuing upload with Storage rules.',
        );
        return;
      }
      _debugLog(
        'Failed to establish Firebase auth session for upload (${e.code}): ${e.message}',
      );
      rethrow;
    } catch (e) {
      _debugLog('Failed to establish Firebase auth session for upload: $e');
      rethrow;
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
        _fullName ??
        (UserSession.currentUserData?['fullName'] as String?) ??
        (UserSession.currentUserData?['displayName'] as String?);

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
        _debugLog(
          '[WARN] No valid identifier (contactNumber or name) for duplicate check',
        );
        // Use document ID query with impossible value (empty string is always invalid)
        query = query.where(FieldPath.documentId, isEqualTo: '');
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
      _debugLog('[WARN] Could not check report limit: $e');
      return UserSession.activeReportCount >= 2;
    }
  }

  Future<void> _showReportLimitDialog() async {
    await _showReportThemedDialog(
      context: context,
      title: 'Active Report Limit',
      message:
          'You already have 2 active reports. Please wait for them to be resolved before submitting a new one.',
      icon: Icons.error_outline_rounded,
      primaryLabel: 'OK',
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
    unawaited(
      _showReportThemedDialog(
        context: context,
        title: 'Location Issue',
        message: message,
        icon: Icons.location_on_rounded,
        primaryLabel: 'OK',
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
        bottom: false,
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
                      const ResqBackButton(),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: SizedBox(
                            height: 40,
                            child: Align(
                              alignment: Alignment.center,
                              child: SvgPicture.asset(
                                "assets/icons/logo/RES-Q_LOGO.svg",
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
                      const SizedBox(width: 44),
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

                  _buildBarangayField(),
                  if (_barangayError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _barangayError!,
                          style: const TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontSize: 12,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  if (_isFireIncident()) _buildFireTypeField(),

                  if (_isFireIncident()) const SizedBox(height: 16),

                  _buildInjuredCounterField(),

                  const SizedBox(height: 16),

                  if (!_isFloodIncident()) _buildAmbulanceField(),

                  if (!_isFloodIncident()) const SizedBox(height: 16),

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
                                  _capturedMediaDisplayText(),
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
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
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
          MainShellNavigationService.popToRootAndOpenTab(context, index);
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

  static const List<String> _vehicleBodies = [
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

  static const List<String> _vehicleColors = [
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

  static const Map<String, Color> _colorSwatches = {
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

  bool _isVehicularIncident() {
    final incident = widget.incidentType.toUpperCase().trim();
    return incident == 'VEHICULAR' ||
        incident == 'ROAD CRASH' ||
        incident == 'ROADCRASH';
  }

  bool _isFireIncident() {
    return widget.incidentType.toUpperCase().trim() == 'FIRE';
  }

  String _incidentTypeForStorage() {
    if (_isVehicularIncident()) return 'VEHICULAR';
    return widget.incidentType;
  }

  bool _isFloodIncident() {
    return widget.incidentType.toUpperCase() == 'FLOOD';
  }

  bool _isOthersIncident() {
    return widget.incidentType.toUpperCase() == 'OTHERS';
  }

  Widget _buildInjuredCounterField() {
    return _buildLabeledField(
      label: 'How many injured? *',
      child: Row(
        children: [
          IconButton(
            onPressed: _injuredCount > 0
                ? () => setState(() => _injuredCount -= 1)
                : null,
            icon: const Icon(Icons.remove_circle_outline),
            color: const Color(0xFFAC1B22),
          ),
          Expanded(
            child: Text(
              _injuredCount.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'RobotoCondensed',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
          IconButton(
            onPressed: _injuredCount < 999
                ? () => setState(() => _injuredCount += 1)
                : null,
            icon: const Icon(Icons.add_circle_outline),
            color: const Color(0xFFAC1B22),
          ),
        ],
      ),
    );
  }

  Widget _buildAmbulanceField() {
    return _buildLabeledField(
      label: 'Need ambulance?',
      child: CheckboxListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        value: _needsAmbulance,
        onChanged: (value) {
          setState(() => _needsAmbulance = value ?? false);
        },
        activeColor: const Color(0xFFAC1B22),
        title: const Text(
          'Request ambulance response',
          style: TextStyle(
            fontFamily: 'RobotoCondensed',
            fontSize: 12,
            color: Colors.black,
          ),
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

  bool _isMotorcycleBodyType(String? bodyType) {
    if (bodyType == null) return false;
    return bodyType.toLowerCase().contains('motorcycle');
  }

  int _plateLimitForBodyType(String? bodyType) {
    return _isMotorcycleBodyType(bodyType) ? 6 : 7;
  }

  String _plateHintForBodyType(String? bodyType) {
    return _isMotorcycleBodyType(bodyType)
        ? 'Max 6 chars (motorcycle)'
        : 'Max 7 chars (car old/new)';
  }

  void _addVehicle() {
    setState(() => _vehicles.add(_VehicleInvolved()));
  }

  void _removeVehicleAt(int index) {
    if (_vehicles.length <= 1) return;
    final removed = _vehicles.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  List<Map<String, dynamic>> _buildVehiclesPayload() {
    return _vehicles
        .map(
          (vehicle) => {
            'plateNumber': vehicle.plateController.text.trim(),
            'bodyType': vehicle.bodyType,
            'color': vehicle.color,
            'vehicleClass': _isMotorcycleBodyType(vehicle.bodyType)
                ? 'motorcycle'
                : 'car',
          },
        )
        .toList();
  }

  Widget _buildFireTypeField() {
    const fireTypes = [
      'Residential Fire',
      'Grass Fire',
      'Electrical Fire',
      'Vehicular Fire',
      'Commercial Fire',
      'Industrial Fire',
      'Forest Fire',
      'Other Fire Type',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabeledField(
          label: 'Type of Fire *',
          borderColor: _fireTypeError != null ? Colors.red : Colors.black,
          child: DropdownButtonHideUnderline(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButton<String>(
                value: _fireType,
                hint: const Text(
                  'Select fire type',
                  style: TextStyle(
                    fontFamily: 'RobotoCondensed',
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                isExpanded: true,
                isDense: true,
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Color(0xFFAC1B22),
                ),
                items: fireTypes
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
                  setState(() {
                    _fireType = value;
                    _fireTypeError = null;
                  });
                },
              ),
            ),
          ),
        ),
        if (_fireTypeError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _fireTypeError!,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(_vehicles.length, (index) {
          final vehicle = _vehicles[index];
          final plateLimit = _plateLimitForBodyType(vehicle.bodyType);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_vehicles.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Vehicle ${index + 1}',
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFAC1B22),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: _buildLabeledField(
                      label: 'Plate Number *',
                      child: TextField(
                        controller: vehicle.plateController,
                        textCapitalization: TextCapitalization.characters,
                        textAlignVertical: TextAlignVertical.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9-]'),
                          ),
                          LengthLimitingTextInputFormatter(plateLimit),
                        ],
                        style: const TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Colors.black,
                        ),
                        decoration: InputDecoration(
                          hintText: _plateHintForBodyType(vehicle.bodyType),
                          hintStyle: const TextStyle(
                            fontFamily: 'RobotoCondensed',
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: Colors.black54,
                          ),
                          border: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: const EdgeInsets.symmetric(
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
                            value: vehicle.bodyType,
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
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Color(0xFFAC1B22),
                            ),
                            dropdownColor: Colors.white,
                            items: _vehicleBodies
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
                              setState(() {
                                vehicle.bodyType = value;
                                final limit = _plateLimitForBodyType(value);
                                final text = vehicle.plateController.text;
                                if (text.length > limit) {
                                  vehicle.plateController.text = text.substring(
                                    0,
                                    limit,
                                  );
                                  vehicle
                                      .plateController
                                      .selection = TextSelection.collapsed(
                                    offset: vehicle.plateController.text.length,
                                  );
                                }
                              });
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
                            value: vehicle.color,
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
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Color(0xFFAC1B22),
                            ),
                            selectedItemBuilder: (context) {
                              return _vehicleColors.map((value) {
                                final color =
                                    _colorSwatches[value] ?? Colors.transparent;
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
                            items: _vehicleColors
                                .map(
                                  (value) => DropdownMenuItem<String>(
                                    value: value,
                                    child: Row(
                                      children: [
                                        _buildColorSwatch(
                                          _colorSwatches[value] ??
                                              Colors.transparent,
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
                              setState(() => vehicle.color = value);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (index != _vehicles.length - 1) const SizedBox(height: 12),
            ],
          );
        }),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (_vehicles.length > 1)
                _buildVehicleActionButton(
                  label: 'Remove Vehicle',
                  icon: Icons.remove_circle_outline,
                  onPressed: () => _removeVehicleAt(_vehicles.length - 1),
                  destructive: true,
                ),
              _buildVehicleActionButton(
                label: 'Add Another Vehicle',
                icon: Icons.add,
                onPressed: _addVehicle,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool destructive = false,
  }) {
    final color = destructive
        ? const Color(0xFFD32F2F)
        : const Color(0xFFAC1B22);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(
          fontFamily: 'RobotoCondensed',
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color, width: 1.2),
        backgroundColor: color.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ),
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
      borderColor: _barangayError != null ? Colors.red : Colors.black,
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
          if (_barangayError != null) {
            setState(() => _barangayError = null);
          }
        },
        fieldViewBuilder:
            (context, textEditingController, focusNode, onFieldSubmitted) {
              return TextField(
                controller: textEditingController,
                focusNode: focusNode,
                textCapitalization: TextCapitalization.words,
                onChanged: (value) {
                  _barangayController.text = value;
                  if (_barangayError != null && value.trim().isNotEmpty) {
                    setState(() => _barangayError = null);
                  }
                },
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
          final filteredOptions = options.toList(growable: false);
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              shadowColor: Colors.black.withValues(alpha: 0.18),
              child: Container(
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: AppTheme.appOffWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.appRed.withValues(alpha: 0.28),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemBuilder: (context, index) {
                      final option = filteredOptions[index];
                      return InkWell(
                        splashColor: AppTheme.appRed.withValues(alpha: 0.08),
                        highlightColor: AppTheme.appRed.withValues(alpha: 0.05),
                        hoverColor: AppTheme.appRed.withValues(alpha: 0.05),
                        onTap: () => onSelected(option),
                        child: Container(
                          color: AppTheme.appOffWhite,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Text(
                            option,
                            style: const TextStyle(
                              fontFamily: 'RobotoCondensed',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.appBlack,
                            ),
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, index) => Divider(
                      height: 1,
                      color: AppTheme.appBlack.withValues(alpha: 0.1),
                    ),
                    itemCount: filteredOptions.length,
                  ),
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
  static const double _reporterRadiusMeters = 500;

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
          _debugLog('Location stream error: $e');
        },
      );
    } catch (e) {
      _debugLog('Error starting location tracking: $e');
    }
  }

  void _showOutsideAreaError() {
    unawaited(
      _showReportThemedDialog(
        context: context,
        barrierDismissible: false,
        title: 'Outside Coverage Area',
        message:
            'Your current location is outside the Angeles City area. You can still pin a location within the coverage area to submit your report.',
        icon: Icons.warning_amber_rounded,
        primaryLabel: 'I Understand',
      ),
    );
  }

  bool _isWithinAngeles(LatLng point) {
    final distance = const Distance().as(LengthUnit.Meter, _center, point);
    return distance <= _radiusMeters;
  }

  double? _distanceFromReporterMeters() {
    if (_selected == null || _currentLocation == null) {
      return null;
    }
    return const Distance().as(LengthUnit.Meter, _currentLocation!, _selected!);
  }

  void _confirmSelection() {
    // Validate both incident location AND user's current location
    // Incident location: Must be within Angeles City coverage
    // User location: Must be within Angeles City (ensures firsthand reporting with captured media)
    if (_selected == null) {
      _showPinPickerError(
        'Please tap on the map to select the incident location',
      );
      return;
    }

    // Check if the incident location is within Angeles City
    if (!_isWithinAngeles(_selected!)) {
      FirebaseAnalytics.instance.logEvent(
        name: 'report_incident_location_invalid',
        parameters: {
          'incident_lat': _selected!.latitude,
          'incident_lng': _selected!.longitude,
        },
      );
      _showPinPickerError(
        'The incident location must be within Angeles City coverage area.',
      );
      return;
    }

    // Check if the user's current location is within Angeles City
    // Required to ensure users are physically present in coverage area
    // to prevent fraud and ensure timely, firsthand reports with captured media
    if (_currentLocation == null || !_isWithinAngeles(_currentLocation!)) {
      FirebaseAnalytics.instance.logEvent(
        name: 'report_user_location_invalid',
        parameters: {
          'user_lat': _currentLocation?.latitude ?? 0,
          'user_lng': _currentLocation?.longitude ?? 0,
          'has_location': _currentLocation != null,
        },
      );
      _showUserLocationError();
      return;
    }

    final reporterDistanceMeters = _distanceFromReporterMeters();
    if (reporterDistanceMeters == null ||
        reporterDistanceMeters > _reporterRadiusMeters) {
      FirebaseAnalytics.instance.logEvent(
        name: 'report_pin_outside_reporter_radius',
        parameters: {
          'distance_meters': reporterDistanceMeters?.round() ?? -1,
          'max_distance_meters': _reporterRadiusMeters.toInt(),
          'incident_lat': _selected!.latitude,
          'incident_lng': _selected!.longitude,
          'user_lat': _currentLocation!.latitude,
          'user_lng': _currentLocation!.longitude,
        },
      );
      _showPinPickerError(
        'Pinned location must be within 500 meters of your current location. '
        'Move closer to the incident or pin inside the blue radius.',
      );
      return;
    }

    Navigator.pop(context, _selected);
  }

  // RESTORED: Show error when user is outside Angeles City
  void _showUserLocationError() {
    unawaited(
      _showReportThemedDialog(
        context: context,
        barrierDismissible: false,
        title: 'Location Issue',
        message:
            'You cannot submit a report because your current location appears to be outside Angeles City. '
            'To submit a report, you must be physically present within the Angeles City coverage area.\n\n'
            'If you believe this is a GPS error, please:\n'
            '- Ensure location services are enabled\n'
            '- Move to an open area for better GPS signal\n'
            '- Wait a moment for GPS to stabilize',
        icon: Icons.location_off_rounded,
        primaryLabel: 'OK',
      ),
    );
  }

  void _showPinPickerError(String message) {
    unawaited(
      _showReportThemedDialog(
        context: context,
        title: 'Location Issue',
        message: message,
        icon: Icons.location_on_rounded,
        primaryLabel: 'OK',
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
              if (_currentLocation != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _currentLocation!,
                      radius: _reporterRadiusMeters,
                      useRadiusInMeter: true,
                      color: const Color(0xFF1565C0).withValues(alpha: 0.12),
                      borderColor: const Color(
                        0xFF1565C0,
                      ).withValues(alpha: 0.65),
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
          Positioned(
            top: MediaQuery.of(context).padding.top + 72,
            left: 16,
            right: 16,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.radio_button_checked,
                      color: Color(0xFF1565C0),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentLocation == null
                            ? 'Locating you... Pin selection is limited to a 500m radius from your location.'
                            : 'Blue radius = your 500m allowed pin area. Pin inside this circle.',
                        style: const TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF111827),
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (_distanceFromReporterMeters() != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${_distanceFromReporterMeters()!.round()}m',
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
