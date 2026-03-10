String resolveIncidentIcon(String incidentType, String priority, String role) {
  final normalizedRole = normalizeIncidentViewerRole(role);
  final normalizedIncident = normalizeIncidentType(incidentType);
  final normalizedPriority = normalizeIncidentPriority(priority);

  final prefix = normalizedRole == 'user'
      ? 'WHITE'
      : (normalizedPriority == 'NONE' ? 'WHITE' : normalizedPriority);

  return 'assets/icons/locations/$prefix-$normalizedIncident-ICON.svg';
}

String normalizeIncidentType(String incidentType) {
  final normalized = incidentType.trim().toUpperCase().replaceAll('_', ' ');
  if (normalized.contains('EARTHQUAKE')) return 'EARTHQUAKE';
  if (normalized.contains('FIRE')) return 'FIRE';
  if (normalized.contains('FLOOD')) return 'FLOOD';
  if (normalized.contains('ROADCRASH') ||
      normalized.contains('ROAD CRASH') ||
      normalized.contains('ROAD ACCIDENT') ||
      normalized.contains('VEHICULAR') ||
      normalized.contains('CAR CRASH')) {
    return 'ROADCRASH';
  }
  return 'OTHERS';
}

String normalizeIncidentPriority(String priority) {
  final normalized = priority.trim().toUpperCase().replaceAll('_', ' ');
  if (normalized == 'HIGH') return 'HIGH';
  if (normalized == 'MEDIUM') return 'MEDIUM';
  if (normalized == 'LOW') return 'LOW';
  return 'NONE';
}

String normalizeIncidentViewerRole(String role) {
  final normalized = role.trim().toLowerCase().replaceAll('_', '');
  if (normalized == 'responder' || normalized == 'semiadmin') {
    return 'responder';
  }
  if (normalized == 'admin') {
    return 'admin';
  }
  return 'user';
}
