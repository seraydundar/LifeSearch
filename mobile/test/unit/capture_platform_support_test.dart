import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/capture/presentation/widgets/capture_platform_support.dart';

void main() {
  // Faz 11, madde 6c (masaüstü/web istemci — see docs/roadmap.md): which
  // capture tiles are disabled on which platform, and why. These take
  // isWeb as a plain argument rather than reading kIsWeb directly so
  // every platform combination is deterministically testable regardless
  // of which machine actually runs `flutter test` — kIsWeb is always
  // false in a VM test run.
  group('fileCaptureSupportedFor', () {
    // P3 (docs/requirements-audit-2026-09-13.md, "Platformlar"):
    // file_picker natively supports bytes on web — the old blanket web
    // exclusion here was really about uploadFile()'s path-based queuing,
    // fixed by uploadFileBytes() instead. No platform excludes this any
    // more.
    test('supported on web — file_picker gives bytes, no path needed', () {
      expect(fileCaptureSupportedFor(isWeb: true), isTrue);
    });

    test('supported everywhere else (mobile, macOS, Windows, Linux)', () {
      expect(fileCaptureSupportedFor(isWeb: false), isTrue);
    });
  });

  group('cameraSupportedFor', () {
    test('unsupported on web — CameraScreen still relies on a real file path', () {
      expect(cameraSupportedFor(isWeb: true), isFalse);
    });

    // P3 (docs/requirements-audit-2026-09-13.md, "Platformlar"):
    // CameraScreen now routes macOS through camera_macos (a separate
    // AVKit-based plugin) instead of excluding it — the `camera`
    // package's own lack of a macOS backend no longer matters here.
    test('supported everywhere native, including macOS', () {
      expect(cameraSupportedFor(isWeb: false), isTrue);
    });
  });

  group('audioRecordingSupportedFor', () {
    test('unsupported on web — AudioRecorderScreen still relies on path_provider', () {
      expect(audioRecordingSupportedFor(isWeb: true), isFalse);
    });

    test('supported everywhere else', () {
      expect(audioRecordingSupportedFor(isWeb: false), isTrue);
    });
  });

  group('fileCaptureUnavailableReasonFor', () {
    test('gives no reason on web any more', () {
      expect(fileCaptureUnavailableReasonFor(isWeb: true), isNull);
    });

    test('gives no reason when actually supported', () {
      expect(fileCaptureUnavailableReasonFor(isWeb: false), isNull);
    });
  });

  group('cameraUnavailableReasonFor', () {
    test('gives a reason on web', () {
      expect(cameraUnavailableReasonFor(isWeb: true), isNotNull);
    });

    test('gives no reason when actually supported, including on macOS', () {
      expect(cameraUnavailableReasonFor(isWeb: false), isNull);
    });
  });

  group('audioRecordingUnavailableReasonFor', () {
    test('gives a reason on web', () {
      expect(audioRecordingUnavailableReasonFor(isWeb: true), isNotNull);
    });

    test('gives no reason when actually supported', () {
      expect(audioRecordingUnavailableReasonFor(isWeb: false), isNull);
    });
  });
}
