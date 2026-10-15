import '../../tasks/domain/item.dart';

/// Uses UTC only to recover after restart, then advances using monotonic time.
class FocusClock {
  final DateTime Function() utcNow;
  final Duration Function() monotonicNow;
  String? _key;
  int _baseline = 0;
  Duration _started = Duration.zero;
  FocusClock({DateTime Function()? utcNow, Duration Function()? monotonicNow})
    : utcNow = utcNow ?? (() => DateTime.now().toUtc()),
      monotonicNow = monotonicNow ?? _stopwatchReader();
  static Duration Function() _stopwatchReader() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  int elapsed(Item session) {
    final stored = session.data['elapsed_seconds'] as int? ?? 0;
    final duration = session.data['duration_seconds'] as int;
    if (session.data['state'] != 'running') return stored.clamp(0, duration);
    final anchor = session.data['anchor'] as String?;
    final key = '${session.id}/$anchor/$stored';
    if (_key != key) {
      _key = key;
      _baseline =
          stored +
          (anchor == null
              ? 0
              : utcNow()
                    .difference(DateTime.parse(anchor))
                    .inSeconds
                    .clamp(0, duration));
      _started = monotonicNow();
    }
    return (_baseline + (monotonicNow() - _started).inSeconds).clamp(
      0,
      duration,
    );
  }
}
