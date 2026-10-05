import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/features/home/presentation/screens/home_screen.dart';

void main() {
  test('the middle of the night is a night greeting, not morning', () {
    expect(greetingForHour(0), 'Good night');
    expect(greetingForHour(2), 'Good night');
    expect(greetingForHour(4), 'Good night');
  });

  test('early morning through late morning is a morning greeting', () {
    expect(greetingForHour(5), 'Good morning');
    expect(greetingForHour(8), 'Good morning');
    expect(greetingForHour(11), 'Good morning');
  });

  test('noon through late afternoon is an afternoon greeting', () {
    expect(greetingForHour(12), 'Good afternoon');
    expect(greetingForHour(15), 'Good afternoon');
    expect(greetingForHour(17), 'Good afternoon');
  });

  test('evening through late evening is an evening greeting', () {
    expect(greetingForHour(18), 'Good evening');
    expect(greetingForHour(20), 'Good evening');
    expect(greetingForHour(21), 'Good evening');
  });

  test('late night (10pm onward) is a night greeting again', () {
    expect(greetingForHour(22), 'Good night');
    expect(greetingForHour(23), 'Good night');
  });
}
