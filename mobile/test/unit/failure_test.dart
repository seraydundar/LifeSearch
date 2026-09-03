import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/error/failure.dart';

void main() {
  group('Failure.toString', () {
    // Regression test: every error snackbar in the app renders
    // `error.toString()` — without an override, Dart's default prints
    // "Instance of 'AuthFailure'" instead of the actual message.
    test('renders the message, not "Instance of \'...\'"', () {
      const failure = AuthFailure('E-posta veya şifre hatalı.');

      expect(failure.toString(), 'E-posta veya şifre hatalı.');
      expect(failure.toString(), isNot(contains('Instance of')));
    });

    test('holds for every Failure subtype', () {
      expect(const NetworkFailure('network down').toString(), 'network down');
      expect(const UnexpectedFailure('unexpected').toString(), 'unexpected');
    });
  });
}
