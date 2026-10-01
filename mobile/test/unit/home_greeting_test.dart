import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/home/presentation/screens/home_screen.dart';

void main() {
  test('before noon is a morning greeting', () {
    expect(greetingForHour(0), 'Good morning');
    expect(greetingForHour(8), 'Good morning');
    expect(greetingForHour(11), 'Good morning');
  });

  test('noon through early evening is an afternoon greeting', () {
    expect(greetingForHour(12), 'Good afternoon');
    expect(greetingForHour(15), 'Good afternoon');
    expect(greetingForHour(17), 'Good afternoon');
  });

  test('6pm onward is an evening greeting', () {
    expect(greetingForHour(18), 'Good evening');
    expect(greetingForHour(21), 'Good evening');
    expect(greetingForHour(23), 'Good evening');
  });
}
