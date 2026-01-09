import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';
import '../services/user_session.dart';
import '../widgets/bottom_nav_bar.dart';
import 'home_page.dart';
import 'emergency_call_screen.dart';

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

  bool _enableGpsSharing = false;
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
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
    if (!_enableGpsSharing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enable GPS sharing to continue'),
          backgroundColor: const Color(0xFFAC1B22),
        ),
      );
      return;
    }

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
            'gpsSharingEnabled': _enableGpsSharing,
            'mediaUrl': mediaUrl,
            'mediaType': mediaType,
            'location': null, // Will be updated from map page
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

                // GPS Checkbox - Center aligned
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Checkbox(
                        value: _enableGpsSharing,
                        onChanged: (value) {
                          setState(() {
                            _enableGpsSharing = value ?? false;
                          });
                        },
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        side: const BorderSide(color: Colors.black, width: 2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "CHECK TO ENABLE GPS SHARING LOCATION",
                      style: const TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Confirm Button - Rounded corners, drop shadow
                Container(
                  width: 230,
                  height: 56,
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
                    onPressed: _confirmReport,
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

                const SizedBox(height: 25),

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
