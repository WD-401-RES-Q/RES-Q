import 'dart:convert';

import 'package:flutter/foundation.dart';

const int _backgroundParseThresholdChars = 48 * 1024;

Future<Map<String, dynamic>> parseJsonObject(
  String rawJson, {
  int thresholdChars = _backgroundParseThresholdChars,
}) async {
  if (kIsWeb || rawJson.length < thresholdChars) {
    return _decodeJsonObject(rawJson);
  }
  try {
    return await compute(_decodeJsonObject, rawJson);
  } catch (_) {
    // Fallback keeps parsing robust when background isolates are unavailable.
    return _decodeJsonObject(rawJson);
  }
}

Map<String, dynamic> _decodeJsonObject(String rawJson) {
  final decoded = jsonDecode(rawJson);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return decoded.cast<String, dynamic>();
  }
  throw const FormatException('Expected a JSON object.');
}
