import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/features/pomodoro/domain/focus_clock.dart';
import 'package:mindflow/features/tasks/domain/item.dart';

void main() {
  test('restart recovery then monotonic time ignores wall clock jumps', () {
    var utc = DateTime.utc(2026, 10, 13, 12, 5);
    var monotonic = Duration.zero;
    final clock = FocusClock(utcNow: () => utc, monotonicNow: () => monotonic);
    final session = Item('focus', 'focus_session', 1, {
      'state': 'running',
      'started_at': '2026-10-13T12:00:00Z',
      'anchor': '2026-10-13T12:00:00Z',
      'elapsed_seconds': 0,
      'duration_seconds': 1500,
    });
    expect(clock.elapsed(session), 300);
    utc = utc.add(const Duration(days: 2));
    monotonic = const Duration(seconds: 60);
    expect(clock.elapsed(session), 360);
    monotonic = const Duration(hours: 1);
    expect(clock.elapsed(session), 1500);
  });
  test('pause preserves elapsed and resume captures a fresh anchor', () {
    var utc = DateTime.utc(2026, 10, 13, 12, 5);
    final clock = FocusClock(
      utcNow: () => utc,
      monotonicNow: () => Duration.zero,
    );
    final paused = Item('focus', 'focus_session', 1, {
      'state': 'paused',
      'anchor': null,
      'elapsed_seconds': 120,
      'duration_seconds': 1500,
    });
    expect(clock.elapsed(paused), 120);
    utc = utc.add(const Duration(days: 1));
    expect(clock.elapsed(paused), 120);
    final resumed = Item('focus', 'focus_session', 1, {
      ...paused.data,
      'state': 'running',
      'anchor': utc.toIso8601String(),
    });
    expect(clock.elapsed(resumed), 120);
  });
}
