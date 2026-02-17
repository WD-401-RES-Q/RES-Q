import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../services/frame_timing_service.dart';

class PerformanceRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _track(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _track(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _track(newRoute);
  }

  void _track(Route<dynamic>? route) {
    if (kReleaseMode || route == null) {
      return;
    }

    final name = _routeName(route);
    if (name == null) {
      return;
    }
    FrameTimingService.instance.setCurrentScreen(name);
  }

  String? _routeName(Route<dynamic> route) {
    final routeName = route.settings.name;
    if (routeName != null && routeName.trim().isNotEmpty) {
      return routeName;
    }
    return route.runtimeType.toString();
  }
}
