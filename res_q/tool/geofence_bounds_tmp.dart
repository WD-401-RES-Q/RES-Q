import 'package:res_q/common/services/angeles_geofence_service.dart';

void main() {
  final pts = AngelesGeofenceService.angelesCityPolygon;
  var minLat = double.infinity;
  var maxLat = -double.infinity;
  var minLng = double.infinity;
  var maxLng = -double.infinity;
  for (final p in pts) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }
  print('lat: $minLat .. $maxLat');
  print('lng: $minLng .. $maxLng');
  print('count: ${pts.length}');
}
