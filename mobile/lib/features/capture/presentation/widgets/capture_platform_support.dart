/// Per-platform capture support as plain functions of `isWeb`, so tests can exercise every platform combination deterministically.
library;

/// Always true; kept as a function in case a future platform needs to differ.
bool fileCaptureSupportedFor({required bool isWeb}) => true;

/// False on web — `camera`'s `XFile.path` is a blob: URL there, not usable with `dart:io.File`.
bool cameraSupportedFor({required bool isWeb}) => !isWeb;

/// False on web — `path_provider` has no real directory there for `record` to write into.
bool audioRecordingSupportedFor({required bool isWeb}) => !isWeb;

/// `null` means supported — don't show a reason.
String? fileCaptureUnavailableReasonFor({required bool isWeb}) {
  return fileCaptureSupportedFor(isWeb: isWeb) ? null : 'Web\'de henüz desteklenmiyor';
}

String? cameraUnavailableReasonFor({required bool isWeb}) {
  return cameraSupportedFor(isWeb: isWeb) ? null : 'Web\'de henüz desteklenmiyor';
}

String? audioRecordingUnavailableReasonFor({required bool isWeb}) {
  return audioRecordingSupportedFor(isWeb: isWeb) ? null : 'Web\'de henüz desteklenmiyor';
}
