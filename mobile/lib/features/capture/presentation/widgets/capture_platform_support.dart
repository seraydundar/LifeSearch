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

/// `Choose Image`/`Upload Document` go through `file_picker`, which
/// supports web natively via `PlatformFile.bytes` (there's no real
/// filesystem path on web for `PlatformFile.path` to return, so
/// `OfflineItemRepository.uploadFileBytes()` uploads those bytes
/// directly instead of persisting/queuing a local file path the way
/// `uploadFile()` does for every other platform — P3, docs/requirements-
/// audit-2026-09-13.md, "Platformlar"). No platform excludes this any
/// more; kept as a named function (rather than inlined `true`) for the
/// same reason [cameraSupportedFor]/[audioRecordingSupportedFor] are —
/// a single place to change if some future platform ever needs to.
bool fileCaptureSupportedFor({required bool isWeb}) => true;

/// The `camera` plugin has no macOS implementation at all — its own
/// `pubspec.yaml` declares only android/ios/web — so "Take Photo" needs
/// its own check. It *does* declare web support (via `camera_web`), but
/// `CameraScreen`'s use of `XFile.path` (a blob: URL on web, not usable
/// with `dart:io.File`) is a separate, unaddressed gap — checked
/// directly against `isWeb` here rather than composed from
/// [fileCaptureSupportedFor] (which no longer excludes web at all) for
/// exactly that reason.
bool cameraSupportedFor({required bool isWeb, required bool isMacOS}) =>
    !isWeb && !isMacOS;

/// `Record Audio` needs its own check for the same reason `Take Photo`
/// does: `AudioRecorderScreen` asks `path_provider` for a real directory
/// to write the recording into before handing it to the `record`
/// plugin, which web has no equivalent of — a separate, unaddressed gap
/// from the `file_picker`-based flows [fileCaptureSupportedFor] covers.
bool audioRecordingSupportedFor({required bool isWeb}) => !isWeb;

/// `null` means "supported, don't show a reason" — for a tile disabled
/// only transiently (an upload already in progress), not because of
/// the platform.
String? fileCaptureUnavailableReasonFor({required bool isWeb}) {
  return fileCaptureSupportedFor(isWeb: isWeb) ? null : 'Web\'de henüz desteklenmiyor';
}

String? cameraUnavailableReasonFor({required bool isWeb, required bool isMacOS}) {
  if (isWeb) return 'Web\'de henüz desteklenmiyor';
  return cameraSupportedFor(isWeb: isWeb, isMacOS: isMacOS) ? null : 'Bu platformda desteklenmiyor';
}

String? audioRecordingUnavailableReasonFor({required bool isWeb}) {
  return audioRecordingSupportedFor(isWeb: isWeb) ? null : 'Web\'de henüz desteklenmiyor';
}
