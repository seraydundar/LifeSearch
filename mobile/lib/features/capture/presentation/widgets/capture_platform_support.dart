/// Which capture tiles work on which platform (Faz 11, madde 6c — see
/// docs/roadmap.md: web + macOS desktop support). Pulled out of
/// `capture_sheet.dart` as pure functions, taking `isWeb`/`isMacOS`
/// as plain booleans instead of reading `kIsWeb`/`Platform.isMacOS`
/// directly, so a test can exercise every platform combination
/// deterministically — `flutter test` itself always runs with
/// `kIsWeb == false` and `Platform.isMacOS` reflecting whatever
/// machine happens to run the test, neither of which a test could
/// otherwise control.
library;

/// Every capture path (`Choose Image`/`Upload Document`/`Take Photo`/
/// `Record Audio`) ends up calling `OfflineItemRepository.uploadFile()`,
/// which persists the picked/captured file with `dart:io`'s `File` —
/// unsupported on web (no real filesystem for `path_provider` to hand
/// back a path to in a browser).
bool fileCaptureSupportedFor({required bool isWeb}) => !isWeb;

/// The `camera` plugin has no macOS implementation at all — its own
/// `pubspec.yaml` declares only android/ios/web — so "Take Photo" needs
/// its own, narrower check on top of [fileCaptureSupportedFor].
bool cameraSupportedFor({required bool isWeb, required bool isMacOS}) =>
    fileCaptureSupportedFor(isWeb: isWeb) && !isMacOS;

/// `null` means "supported, don't show a reason" — for a tile disabled
/// only transiently (an upload already in progress), not because of
/// the platform.
String? fileCaptureUnavailableReasonFor({required bool isWeb}) {
  return fileCaptureSupportedFor(isWeb: isWeb) ? null : 'Web\'de henüz desteklenmiyor';
}

String? cameraUnavailableReasonFor({required bool isWeb, required bool isMacOS}) {
  if (!fileCaptureSupportedFor(isWeb: isWeb)) return 'Web\'de henüz desteklenmiyor';
  if (!cameraSupportedFor(isWeb: isWeb, isMacOS: isMacOS)) return 'Bu platformda desteklenmiyor';
  return null;
}
