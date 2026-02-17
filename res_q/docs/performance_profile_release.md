# Performance Check Workflow (Profile/Release Only)

Use this workflow to avoid misleading performance numbers from debug mode.

## Commands

- Profile runtime on a device:
  - `.\tool\perf_checks.ps1 -Task run-profile -DeviceId <device-id>`
- Profile runtime with Skia tracing (for DevTools frame analysis):
  - `.\tool\perf_checks.ps1 -Task run-profile-trace -DeviceId <device-id>`
- Build profile APK:
  - `.\tool\perf_checks.ps1 -Task build-profile-apk`
- Build release APK (size + symbols):
  - `.\tool\perf_checks.ps1 -Task build-release-apk`
- Build both profile and release APK:
  - `.\tool\perf_checks.ps1 -Task all`

## Rules

- Do not benchmark in `flutter run` debug mode.
- Use `flutter run --profile` for frame/FPS and interaction checks.
- Use release APK for final UX validation and APK size checks.
- Compare screens only when tested on the same device and build mode.
