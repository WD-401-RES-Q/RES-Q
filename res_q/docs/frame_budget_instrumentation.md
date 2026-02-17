# Frame Budget Instrumentation (16ms Target)

This project now includes app-level frame timing instrumentation for debug/profile builds.

## What Is Instrumented

- Global frame timing collector:
  - `lib/common/services/frame_timing_service.dart`
- Route-level screen tracking:
  - `lib/common/navigation/performance_route_observer.dart`
- Explicit screen tagging for heavy pages:
  - `lib/features/community/pages/community_page.dart`
  - `lib/features/map/pages/map_page.dart`
  - `lib/features/reports/pages/report_map_page.dart`
  - `lib/features/semi_admin/pages/semi_admin_map_page.dart`

## How To Run

- Start in profile mode with tracing:
  - `.\tool\perf_checks.ps1 -Task run-profile-trace -DeviceId <device-id>`
- Optional performance overlay:
  - `flutter run --profile -d <device-id> --dart-define=RESQ_SHOW_PERF_OVERLAY=true`

## How To Read Output

- Open logs filtered by `res_q.performance`.
- Slow-frame logs appear when build or raster exceeds `16.0ms`.
- Summary logs appear every 5 seconds per current screen with:
  - slow build percentage
  - slow raster percentage
  - worst build/raster times

## Fix Rule

- If build or raster repeatedly exceeds `16ms` on a screen:
  - move heavy work out of `build()`
  - reduce repaint area (`RepaintBoundary`)
  - reduce simultaneous animations and map camera updates
  - throttle repeated async work and writes during navigation/interaction
