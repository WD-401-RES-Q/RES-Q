import 'dart:convert';

import 'package:crypto/crypto.dart';

class SecurityHash {
  static String sha256Hex(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }
}
