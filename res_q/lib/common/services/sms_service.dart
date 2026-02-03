import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Service for sending SMS notifications to users
///
/// Note: This requires integration with an SMS provider API like:
/// - Semaphore (Philippines)
/// - Twilio
/// - AWS SNS
/// - or any other SMS gateway
class SmsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Send SMS notification when account is approved
  ///
  /// This should be called when an admin approves a user account.
  /// It sends an SMS to the user's registered phone number.
  static Future<void> sendAccountApprovedSms(
    String phoneNumber,
    String displayName,
  ) async {
    // TODO: Replace with your SMS provider credentials
    // Example using Semaphore API (Philippines)

    const String apiKey =
        'YOUR_SEMAPHORE_API_KEY'; // Replace with actual API key
    const String senderId = 'RESQ'; // Your sender name

    final message =
        'Hi $displayName! Your RES-Q account has been approved by our admin. '
        'You can now create your PIN and login to the app. '
        'Click "Account Approved? Create PIN here" on the login page to get started.';

    try {
      // Example for Semaphore API (Philippines)
      final response = await http.post(
        Uri.parse('https://api.semaphore.co/api/v4/messages'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'apikey': apiKey,
          'number': phoneNumber,
          'message': message,
          'sendername': senderId,
        },
      );

      if (response.statusCode == 200) {
        print('✅ SMS sent successfully to $phoneNumber');

        // Log the SMS in Firestore for tracking
        await _firestore.collection('sms_logs').add({
          'phoneNumber': phoneNumber,
          'displayName': displayName,
          'message': message,
          'status': 'sent',
          'sentAt': FieldValue.serverTimestamp(),
        });
      } else {
        print('❌ Failed to send SMS: ${response.body}');

        // Log failed attempt
        await _firestore.collection('sms_logs').add({
          'phoneNumber': phoneNumber,
          'displayName': displayName,
          'message': message,
          'status': 'failed',
          'error': response.body,
          'sentAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('❌ Error sending SMS: $e');

      // Log error
      await _firestore.collection('sms_logs').add({
        'phoneNumber': phoneNumber,
        'displayName': displayName,
        'message': message,
        'status': 'error',
        'error': e.toString(),
        'sentAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Alternative implementation using Twilio (international)
  static Future<void> sendAccountApprovedSmsTwilio(
    String phoneNumber,
    String displayName,
  ) async {
    // TODO: Replace with your Twilio credentials
    const String accountSid = 'YOUR_TWILIO_ACCOUNT_SID';
    const String authToken = 'YOUR_TWILIO_AUTH_TOKEN';
    const String fromNumber = 'YOUR_TWILIO_PHONE_NUMBER';

    final message =
        'Hi $displayName! Your RES-Q account has been approved. '
        'Create your PIN now to login.';

    try {
      final credentials = base64Encode(utf8.encode('$accountSid:$authToken'));

      final response = await http.post(
        Uri.parse(
          'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json',
        ),
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'From': fromNumber, 'To': phoneNumber, 'Body': message},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ SMS sent successfully via Twilio to $phoneNumber');
      } else {
        print('❌ Failed to send SMS via Twilio: ${response.body}');
      }
    } catch (e) {
      print('❌ Error sending SMS via Twilio: $e');
    }
  }

  /// Approve user and send notification SMS
  ///
  /// Call this method when admin approves a user.
  /// It moves the user from pending_users to approved_users
  /// and sends an SMS notification.
  static Future<void> approveUserAndNotify(String userId) async {
    try {
      // Get user data from pending_users
      final pendingDoc = await _firestore
          .collection('pending_users')
          .doc(userId)
          .get();

      if (!pendingDoc.exists) {
        throw Exception('Pending user not found');
      }

      final userData = pendingDoc.data()!;
      final phoneNumber = userData['contactNumber'] as String;
      final displayName =
          (userData['fullName'] as String?) ??
          (userData['contactNumber'] as String?) ??
          'User';

      // Move to approved_users
      userData['accountStatus'] = 'approved';
      userData['approvedAt'] = FieldValue.serverTimestamp();

      // Remove PIN if it exists (user will create new one)
      userData.remove('pin');

      await _firestore.collection('approved_users').doc(userId).set(userData);

      // Delete from pending_users
      await _firestore.collection('pending_users').doc(userId).delete();

      // Send SMS notification
      await sendAccountApprovedSms(phoneNumber, displayName);

      print('✅ User $displayName approved and notified via SMS');
    } catch (e) {
      print('❌ Error approving user: $e');
      rethrow;
    }
  }
}
