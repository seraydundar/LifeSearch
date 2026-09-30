import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/capture/presentation/widgets/capture_platform_support.dart';

void main() {
  // Faz 11, madde 6c (masaüstü/web istemci — see docs/roadmap.md): which
  // capture tiles are disabled on which platform, and why. These take
  // isWeb/isMacOS as plain arguments rather than reading kIsWeb/
  // Platform.isMacOS directly so every platform combination is
  // deterministically testable regardless of which machine actually
  // runs `flutter test` — kIsWeb is always false in a VM test run, and
  // Platform.isMacOS reflects whatever machine happens to run it.
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
      expect(cameraSupportedFor(isWeb: true, isMacOS: false), isFalse);
    });

    test('unsupported on macOS — the camera plugin has no macOS backend', () {
      expect(cameraSupportedFor(isWeb: false, isMacOS: true), isFalse);
    });

    test('supported on a native, non-macOS platform (mobile, Windows, Linux)', () {
      expect(cameraSupportedFor(isWeb: false, isMacOS: false), isTrue);
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
    test('the web reason and the macOS reason are worded differently', () {
      final webReason = cameraUnavailableReasonFor(isWeb: true, isMacOS: false);
      final macReason = cameraUnavailableReasonFor(isWeb: false, isMacOS: true);

      expect(webReason, isNotNull);
      expect(macReason, isNotNull);
      expect(webReason, isNot(equals(macReason)));
    });

    test('gives no reason when actually supported', () {
      expect(cameraUnavailableReasonFor(isWeb: false, isMacOS: false), isNull);
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
