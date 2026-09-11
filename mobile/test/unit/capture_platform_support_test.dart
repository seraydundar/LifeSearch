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
    test('unsupported on web — no real filesystem for path_provider', () {
      expect(fileCaptureSupportedFor(isWeb: true), isFalse);
    });

    test('supported everywhere else (mobile, macOS, Windows, Linux)', () {
      expect(fileCaptureSupportedFor(isWeb: false), isTrue);
    });
  });

  group('cameraSupportedFor', () {
    test('unsupported on web (inherits the file-capture restriction)', () {
      expect(cameraSupportedFor(isWeb: true, isMacOS: false), isFalse);
    });

    test('unsupported on macOS — the camera plugin has no macOS backend', () {
      expect(cameraSupportedFor(isWeb: false, isMacOS: true), isFalse);
    });

    test('supported on a native, non-macOS platform (mobile, Windows, Linux)', () {
      expect(cameraSupportedFor(isWeb: false, isMacOS: false), isTrue);
    });
  });

  group('fileCaptureUnavailableReasonFor', () {
    test('gives a reason on web', () {
      expect(fileCaptureUnavailableReasonFor(isWeb: true), isNotNull);
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
}
