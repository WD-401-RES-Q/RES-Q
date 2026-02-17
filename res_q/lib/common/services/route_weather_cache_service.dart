import 'package:http/http.dart' as http;

import 'json_parsing_service.dart';

class RouteWeatherCacheService {
  RouteWeatherCacheService._();

  static const Duration _weatherCacheTtl = Duration(minutes: 15);
  static const Duration _routeCacheTtl = Duration(minutes: 2);

  static final Map<String, _JsonCacheEntry> _weatherCache =
      <String, _JsonCacheEntry>{};
  static final Map<String, Future<Map<String, dynamic>>> _weatherInFlight =
      <String, Future<Map<String, dynamic>>>{};

  static final Map<String, _JsonCacheEntry> _routeCache =
      <String, _JsonCacheEntry>{};
  static final Map<String, Future<Map<String, dynamic>?>> _routeInFlight =
      <String, Future<Map<String, dynamic>?>>{};

  static Future<Map<String, dynamic>> fetchWeatherJson(
    Uri uri, {
    Duration ttl = _weatherCacheTtl,
  }) async {
    final key = uri.toString();
    final cached = _weatherCache[key];
    if (cached != null && !cached.isExpired) {
      return cached.json;
    }

    final inFlight = _weatherInFlight[key];
    if (inFlight != null) {
      return inFlight;
    }

    final request = _requestWeatherJson(uri, ttl: ttl);
    _weatherInFlight[key] = request;
    try {
      return await request;
    } finally {
      _weatherInFlight.remove(key);
    }
  }

  static Future<Map<String, dynamic>> fetchAngelesWeatherJson() {
    const lat = 15.1450;
    const lon = 120.5887;
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&current_weather=true'
      '&daily=temperature_2m_max,temperature_2m_min,weathercode'
      '&timezone=auto',
    );
    return fetchWeatherJson(uri);
  }

  static Future<Map<String, dynamic>?> fetchRouteJson(
    Uri uri, {
    Duration ttl = _routeCacheTtl,
  }) async {
    final key = uri.toString();
    final cached = _routeCache[key];
    if (cached != null && !cached.isExpired) {
      return cached.json;
    }

    final inFlight = _routeInFlight[key];
    if (inFlight != null) {
      return inFlight;
    }

    final request = _requestRouteJson(uri, ttl: ttl);
    _routeInFlight[key] = request;
    try {
      return await request;
    } finally {
      _routeInFlight.remove(key);
    }
  }

  static Future<Map<String, dynamic>> _requestWeatherJson(
    Uri uri, {
    required Duration ttl,
  }) async {
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Weather request failed');
    }
    final json = await parseJsonObject(response.body);
    _weatherCache[uri.toString()] = _JsonCacheEntry(json: json, ttl: ttl);
    return json;
  }

  static Future<Map<String, dynamic>?> _requestRouteJson(
    Uri uri, {
    required Duration ttl,
  }) async {
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      return null;
    }
    final json = await parseJsonObject(response.body);
    _routeCache[uri.toString()] = _JsonCacheEntry(json: json, ttl: ttl);
    return json;
  }
}

class _JsonCacheEntry {
  _JsonCacheEntry({required this.json, required Duration ttl})
    : expiresAt = DateTime.now().add(ttl);

  final Map<String, dynamic> json;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
